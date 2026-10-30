--!strict
-- Shrinking safe zone (piece 06). The server owns the circle, the warnings and the damage; clients
-- only draw it. Starts the clock when the match turns Active, stops it when the match leaves
-- combat. All numbers are in Config.Zone; the rules are in ZoneModel (tested in Lune).
--
-- For other pieces:
--   ZoneSystem.FinalPressure   Signal (matchId): the last warning began. Piece 05 moves the match
--                              to the FinalPressure phase from here.
--   ZoneSystem.Event           Signal (ZoneModel.Event): WarningStarted, ClosingStarted, ...
--   ZoneSystem.getSample()     the live circle (nil when no zone), for bots and anyone else
--   ZoneSystem.nearestSafePoint(x, z, margin)  where a bot should walk to get back inside

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchPhase = require(Shared.MatchPhase)
local Signal = require(Shared.Signal)

local Core = script.Parent.Parent:WaitForChild("Core")
local Damage = require(Core.Damage)
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)
local Participants = require(Core.Participants)

local ZoneModel = require(script.Parent.ZoneModel)

local STEP_SECONDS = 0.1

local ZoneSystem = {}
ZoneSystem.order = 200 -- after the core services
ZoneSystem.FinalPressure = Signal.new()
ZoneSystem.Event = Signal.new()

local runner: ZoneModel.Runner? = nil
local botModels: { [string]: Model } = {}

local function rootOf(model: Instance?): BasePart?
	if model == nil or not model:IsA("Model") then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return model.PrimaryPart
end

local function isParticipantModel(inst: Instance, id: string): boolean
	return inst:IsA("Model") and inst:GetAttribute(Config.Attributes.ParticipantId) == id
end

-- Bots are found by the ParticipantId attribute on their character (see Config.Attributes). Looks
-- at the top of Workspace and inside Workspace.Participants, then remembers what it found.
local function findBotRoot(id: string): BasePart?
	local cached: Model? = botModels[id]
	if cached ~= nil and cached.Parent ~= nil then
		return rootOf(cached)
	end
	local holders: { Instance } = { workspace }
	local folder = workspace:FindFirstChild("Participants")
	if folder ~= nil then
		table.insert(holders, folder)
	end
	for _, holder in holders do
		for _, child in holder:GetChildren() do
			if isParticipantModel(child, id) then
				botModels[id] = child :: Model
				return rootOf(child)
			end
		end
	end
	return nil
end

local function getTargets(): { ZoneModel.Target }
	local out: { ZoneModel.Target } = {}
	for _, p in Participants:aliveList() do
		local root: BasePart?
		if p.kind == "player" then
			local player = p.player :: Player?
			root = rootOf(if player then player.Character else nil)
		else
			root = findBotRoot(p.id)
		end
		-- No character yet (still spawning) means no position, so no zone damage this tick.
		if root ~= nil then
			local pos = root.Position
			table.insert(out, { id = p.id, x = pos.X, z = pos.Z })
		end
	end
	return out
end

local function applyDamage(id: string, amount: number, _stage: number)
	Damage:apply({
		matchId = MatchContext:getMatchId(),
		targetId = id,
		amount = amount,
		cause = "zone",
		sourceId = nil,
	})
end

local function sendCurrent(player: Player)
	local state = if runner then runner:getState() else nil
	if state ~= nil then
		Net.fire("ZoneState", player, state)
	end
end

local function onPhaseChanged(phase: string, _old: string, matchId: number)
	local r = runner
	if r == nil then
		return
	end
	if phase == MatchPhase.Active then
		r:start(matchId)
	elseif not MatchPhase.isCombat(phase) then
		r:stop()
	end
end

function ZoneSystem.getSample(): ZoneModel.Sample?
	return if runner then runner:getSample() else nil
end

function ZoneSystem.nearestSafePoint(x: number, z: number, margin: number): (number, number)
	local sample = ZoneSystem.getSample()
	if sample == nil then
		return x, z
	end
	return ZoneModel.nearestSafePoint(sample, x, z, margin)
end

function ZoneSystem.start()
	local r = ZoneModel.newRunner({
		config = Config.Zone :: any,
		now = function()
			return workspace:GetServerTimeNow()
		end,
		getTargets = getTargets,
		applyDamage = applyDamage,
		publish = function(state)
			Net.fireAll("ZoneState", state)
		end,
		onEvent = function(event)
			if event.kind == "FinalPressure" then
				ZoneSystem.FinalPressure:fire(event.matchId)
			end
			ZoneSystem.Event:fire(event)
		end,
	})
	runner = r

	MatchContext.PhaseChanged:connect(onPhaseChanged)
	-- The match may already be running if this system started late.
	if MatchContext:getPhase() == MatchPhase.Active then
		r:start(MatchContext:getMatchId())
	end

	Net.onRequest("ZoneStateRequest", sendCurrent)
	Players.PlayerAdded:Connect(function(player)
		task.delay(3, function()
			if player.Parent ~= nil then
				sendCurrent(player)
			end
		end)
	end)
	MatchContext.MatchStarted:connect(function()
		table.clear(botModels)
	end)

	local sinceStep = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceStep += dt
		if sinceStep >= STEP_SECONDS then
			sinceStep = 0
			r:step()
		end
	end)
end

return ZoneSystem
