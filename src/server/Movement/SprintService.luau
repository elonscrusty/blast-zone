--!strict
-- The server's sprint (piece 44). The client only says "I want to run" or "I stopped"; the server
-- keeps the breath bar, decides who really runs (alive, in a fight, moving, not just shot), and
-- sets the real walk speed. That walk speed is what the move watch reads, so a faster run is never
-- mistaken for cheating and a client cannot fake one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local SprintRules = require(Shared.Movement.SprintRules)

local Core = script.Parent.Parent.Core
local EffectiveStats = require(Core.EffectiveStats)
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)
local Participants = require(Core.Participants)

local MovementSetup = require("./MovementSetup")
local SlideService = require("./SlideService")

local SprintService = {}

type Entry = {
	state: SprintRules.State,
	sentAt: number,
	sentStamina: number,
	sentRunning: boolean,
	sentLocked: boolean,
}

local entries: { [string]: Entry } = {}

local function entryOf(id: string): Entry
	local entry = entries[id]
	if entry == nil then
		entry = {
			state = SprintRules.new(),
			sentAt = -math.huge,
			sentStamina = -1,
			sentRunning = false,
			sentLocked = false,
		}
		entries[id] = entry
	end
	return entry :: Entry
end

local function humanoidOf(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	return humanoid, root
end

-- A shot ends the run for a moment (called from Firing, players and bots alike).
function SprintService.noteFire(id: string)
	local entry = entries[id]
	if entry then
		SprintRules.noteFire(entry.state, os.clock())
	end
end

function SprintService.isRunning(id: string): boolean
	local entry = entries[id]
	return entry ~= nil and entry.state.running
end

local function sendState(player: Player, entry: Entry, now: number, force: boolean)
	local s = entry.state
	local changed = s.running ~= entry.sentRunning
		or s.locked ~= entry.sentLocked
		or math.abs(s.stamina - entry.sentStamina) >= 0.02
	if not changed or (not force and now - entry.sentAt < Config.Sprint.sendSeconds) then
		return
	end
	entry.sentAt = now
	entry.sentStamina = s.stamina
	entry.sentRunning = s.running
	entry.sentLocked = s.locked
	Net.fire("SprintState", player, { stamina = s.stamina, running = s.running, locked = s.locked })
end

local function stepPlayer(player: Player, dt: number, now: number)
	local id = Ids.player(player.UserId)
	local entry = entryOf(id)
	local humanoid, root = humanoidOf(player)
	if humanoid == nil or root == nil then
		return
	end
	local participant = Participants:get(id)
	local alive = humanoid.Health > 0 and (participant == nil or participant.alive)
	local fight = participant == nil or MatchContext:isCombat()
	local stats = EffectiveStats:get(id)
	local v = root.AssemblyLinearVelocity
	local flat = math.sqrt(v.X * v.X + v.Z * v.Z)
	local moving = flat >= stats.moveSpeed * Config.Sprint.minMoveSpeedShare
	local canRun = Config.Sprint.enabled and alive and fight and not SlideService.isSliding(id)
	local running = SprintRules.step(entry.state, Config.Sprint, dt, now, moving, canRun)
	MovementSetup.setSprintSpeed(humanoid, stats.moveSpeed, running)
	sendState(player, entry, now, false)
end

function SprintService.start()
	Net.onRequest("SprintRequest", function(player: Player, on: boolean)
		local entry = entryOf(Ids.player(player.UserId))
		SprintRules.request(entry.state, Config.Sprint, on == true)
		sendState(player, entry, os.clock(), true)
	end)

	local acc = 0
	local last = os.clock()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		acc += now - last
		last = now
		if acc < Config.Sprint.tickSeconds then
			return
		end
		local dt = acc
		acc = 0
		for _, player in Players:GetPlayers() do
			stepPlayer(player, dt, now)
		end
	end)

	local function fresh(id: string)
		entries[id] = nil
	end
	Participants.Eliminated:connect(function(p)
		fresh(p.id)
	end)
	MatchContext.MatchStarted:connect(function()
		table.clear(entries)
	end)
	Players.PlayerRemoving:Connect(function(player)
		fresh(Ids.player(player.UserId))
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			fresh(Ids.player(player.UserId))
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			fresh(Ids.player(player.UserId))
		end)
	end
end

return SprintService
