--!strict
-- Buy / EquipTool / SetSetting / TutorialDone, plus the zone gate prompts. Thin glue: every rule
-- (price, owned, max level, gate order, whitelist) is in Shared/Player/PurchaseRules and is checked
-- again here on the server; a remote only says what the player WANTS.
-- A purchase is one synchronous call (check, spend, apply): no yield in between, so two quick taps
-- can never buy twice with the money for one.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PurchaseRules = require(Shared.Player.PurchaseRules)

local Net = require(script.Parent.Parent.Core.Net)
local PlayerState = require(script.Parent.PlayerState)

local GATE_TAG = "VSGate"
local GATE_REACH_EXTRA = 12 -- studs of slack on top of the prompt's own distance
local GATE_TOAST_GAP = 1.5 -- seconds between "not yet" messages from gates, per player

local PurchaseService = {}

local started = false
local lastGateToast: { [Player]: number } = {}
local hookedGates: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Runs a purchase and tells the player what happened. Returns true when it was bought.
local function doBuy(player: Player, kind: string, id: string | number): boolean
	local state = PlayerState.get(player)
	if state == nil then
		return false
	end
	local result = PurchaseRules.buy(state.profile, kind, id)
	if not result.ok then
		PlayerState.toast(player, result.message, "warn")
		return false
	end
	PlayerState.touch(player, table.unpack(result.keys))
	PlayerState.recompute(player) -- tool, upgrades, zones and Sparks all change the derived numbers
	PlayerState.toast(player, result.message, result.toastKind)
	return true
end

local function onGateTriggered(player: Player, gate: BasePart)
	local state = PlayerState.get(player)
	if state == nil then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp == nil or not hrp:IsA("BasePart") then
		return
	end
	local prompt = gate:FindFirstChild("GatePrompt")
	local reach = if prompt ~= nil and prompt:IsA("ProximityPrompt")
		then prompt.MaxActivationDistance
		else 12
	if
		(hrp.Position - gate.Position).Magnitude
		> reach + gate.Size.Magnitude + GATE_REACH_EXTRA
	then
		return
	end

	local zoneId = gate:GetAttribute("ZoneId")
	local verdict = PurchaseRules.gate(state.profile, zoneId)
	if verdict.state == "buy" then
		doBuy(player, "zone", zoneId :: number)
		return
	end
	local now = os.clock()
	if now - (lastGateToast[player] or -10) < GATE_TOAST_GAP then
		return
	end
	lastGateToast[player] = now
	PlayerState.toast(player, verdict.text, if verdict.state == "open" then "info" else "warn")
end

local function hookGate(gate: Instance)
	if hookedGates[gate] or not gate:IsA("BasePart") then
		return
	end
	hookedGates[gate] = true
	local part: BasePart = gate
	task.spawn(function()
		-- the prompt is a child of the gate; give the world builder a moment if it adds it later
		local prompt = part:WaitForChild("GatePrompt", 15)
		if prompt == nil or not prompt:IsA("ProximityPrompt") then
			warn(`[Purchase] gate {part:GetFullName()} has no GatePrompt`)
			return
		end
		prompt.Triggered:Connect(function(player: Player)
			local ok, err = pcall(onGateTriggered, player, part)
			if not ok then
				warn(`[Purchase] gate prompt failed: {err}`)
			end
		end)
	end)
end

function PurchaseService.init()
	if started then
		return
	end
	started = true

	Net.onRequest("Buy", function(player: Player, kind: string, id: string)
		doBuy(player, kind, id)
	end)

	Net.onRequest("EquipTool", function(player: Player, id: string)
		local state = PlayerState.get(player)
		if state == nil then
			return
		end
		local ok, text = PurchaseRules.equip(state.profile, id)
		if not ok then
			PlayerState.toast(player, text, "warn")
			return
		end
		PlayerState.touch(player, "tool")
		PlayerState.recompute(player) -- reach, power and backpack come from the tool
		PlayerState.toast(player, `{text} ready!`, "info")
	end)

	Net.onRequest("SetSetting", function(player: Player, key: string, value: boolean)
		local state = PlayerState.get(player)
		if state == nil then
			return
		end
		if PurchaseRules.setSetting(state.profile, key, value) then
			PlayerState.touch(player, "settings")
		end
	end)

	Net.onRequest("TutorialDone", function(player: Player)
		local state = PlayerState.get(player)
		if state == nil or state.profile.tutorialDone then
			return
		end
		state.profile.tutorialDone = true
		PlayerState.touch(player, "tutorialDone")
	end)

	-- Gates: now and any added later.
	CollectionService:GetInstanceAddedSignal(GATE_TAG):Connect(hookGate)
	for _, gate in CollectionService:GetTagged(GATE_TAG) do
		hookGate(gate)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastGateToast[player] = nil
	end)
end

return PurchaseService
