--!strict
-- Selling the backpack at the Trade Hut. Two doors, one function:
--   the `Sell` remote (the SELL button / F key), and every ProximityPrompt tagged `VSSellPrompt`.
-- The server checks that the player is alive, ready, close to a sell pad (judged from MoveWatch's
-- trusted position, so teleporting to the hut does not count), and has something to sell, then
-- pays Economy.sellValue (Lucky Coins may double it) and tells the client with `Sold`.
--
--   SellService.init()     once, after SweepService.init (Main calls it)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Rules.Economy)
local Rng = require(Shared.Rng)
local SweepRules = require(Shared.Sweep.SweepRules)
local Types = require(Shared.Types)

local MoveWatch = require(script.Parent.Parent.Core.MoveWatch)
local Net = require(script.Parent.Parent.Core.Net)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)

local PROMPT_TAG = "VSSellPrompt"
local COOLDOWN = 0.25 -- seconds between sells per player
local RANGE_SLACK = 4 -- studs: the server sees you a moment behind your screen
local EMPTY_TOAST_GAP = 1.5
local FAR_TOAST_GAP = 2

local SellService = {}

local started = false
local rng = Rng.new(math.floor(os.time() * 13 + os.clock() * 1000))
local lastSellAt: { [any]: number } = {}
local emptyToastAt: { [any]: number } = {}
local farToastAt: { [any]: number } = {}
local promptConns: { [Instance]: RBXScriptConnection } = {}
local hubX, hubZ = SweepRules.hubXZ(Config.World)

-- The World piece builds the pads; load it lazily so a missing module never breaks selling.
local world: any = nil
local function getWorld(): any
	if world ~= nil then
		return world
	end
	local ok, mod = pcall(function(): any
		local folder = script.Parent.Parent:FindFirstChild("World")
		local inst = if folder then folder:FindFirstChild("World") else nil
		if inst == nil then
			error("World not found")
		end
		return require(inst :: any)
	end)
	if ok and type(mod) == "table" then
		world = mod
	end
	return world
end

-- Is (px, pz) within the sell range of any sell pad? With no pads at all, the hub position from
-- Config stands in for them.
local function nearSellSpot(px: number, pz: number): boolean
	local range = Config.World.sellRange + RANGE_SLACK
	local anyPad = false
	local w = getWorld()
	if w ~= nil and type(w.sellPadPositions) == "function" then
		local ok, pads = pcall(w.sellPadPositions)
		if ok and type(pads) == "table" then
			for _, pad in pads do
				anyPad = true
				if SweepRules.withinRange2D(px, pz, pad.X, pad.Z, range) then
					return true
				end
			end
		end
	end
	if anyPad then
		return false
	end
	return SweepRules.withinRange2D(px, pz, hubX, hubZ, range)
end

local function toast(player: Player, text: string, kind: "info" | "good" | "warn" | "gold")
	Net.fire("Toast", player, { text = text, kind = kind } :: Types.ToastInfo)
end

local function sell(player: Player)
	local state = PlayerState.get(player)
	if state == nil then
		return
	end
	local now = os.clock()
	if not SweepRules.allowEvery(lastSellAt, player, now, COOLDOWN) then
		return
	end
	local char = player.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if hum == nil or hum.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return
	end
	if state.carried <= 0 then
		if SweepRules.allowEvery(emptyToastAt, player, now, EMPTY_TOAST_GAP) then
			toast(player, "Your backpack is empty", "info")
		end
		return
	end
	local pos = MoveWatch.position(player)
	if pos == nil or not (SweepRules.isFinite(pos.X) and SweepRules.isFinite(pos.Z)) then
		return
	end
	if not nearSellSpot(pos.X, pos.Z) then
		if SweepRules.allowEvery(farToastAt, player, now, FAR_TOAST_GAP) then
			toast(player, "Walk to the Trade Hut to sell!", "info")
		end
		return
	end

	local units, value = PlayerState.takeCarried(player)
	if units <= 0 then
		return
	end
	local coins, bonusCoins, luckyDouble = Economy.sellValue(value, state.derived, rng)
	PlayerState.addCoins(player, coins)
	PlayerState.addStat(player, "unitsSold", units)
	PlayerState.addStat(player, "sellCount", 1)
	Net.fire(
		"Sold",
		player,
		{
			units = units,
			coins = coins,
			bonusCoins = bonusCoins,
			luckyDouble = luckyDouble,
		} :: Types.SoldInfo
	)
end

local function hookPrompt(inst: Instance)
	if promptConns[inst] ~= nil or not inst:IsA("ProximityPrompt") then
		return
	end
	local prompt = inst :: ProximityPrompt
	promptConns[inst] = prompt.Triggered:Connect(function(player: Player)
		sell(player)
	end)
end

local function unhookPrompt(inst: Instance)
	local conn = promptConns[inst]
	if conn ~= nil then
		conn:Disconnect()
		promptConns[inst] = nil
	end
end

function SellService.init()
	if started then
		return
	end
	started = true

	Net.onRequest("Sell", function(player: Player)
		sell(player)
	end)

	CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(hookPrompt)
	CollectionService:GetInstanceRemovedSignal(PROMPT_TAG):Connect(unhookPrompt)
	for _, inst in CollectionService:GetTagged(PROMPT_TAG) do
		hookPrompt(inst)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastSellAt[player] = nil
		emptyToastAt[player] = nil
		farToastAt[player] = nil
	end)
end

return SellService
