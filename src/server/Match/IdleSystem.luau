--!strict
-- Idle (AFK) check, piece 39. Server only. The server watches, nobody can opt out or fake it by name:
--   * In a fight: fighters who neither move (a real walk, not jitter) nor shoot, reload, slide, switch guns,
--     grab pickups or choose upgrades get a warning, then are removed from the match (no reward), and
--     go back to the lobby off the queue. Last place among those still standing is decided by the match.
--   * In the lobby (only with Config.Idle.lobbyCheck, off for now): a queued player with no input at all for a
--     long time is taken off the queue. Spectators are never watched: only living fighters are.
-- The numbers live in Config.Idle. The bookkeeping is IdleWatch (tested in Lune). No looks here:
-- warnings use the existing Notice remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local MatchPhase = require(Shared.MatchPhase)
local RemoteDefs = require(Shared.RemoteDefs)
local Remotes = require(Shared.Remotes)

local Core = script.Parent.Parent:WaitForChild("Core")
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)
local Participants = require(Core.Participants)

local IdleWatch = require(script.Parent.IdleWatch)
local MatchSystem = require(script.Parent.MatchSystem)

-- Remotes that prove a fighter is playing. Every other request still proves a lobby player is there.
local FIGHT_REMOTES = {
	"FireRequest",
	"ReloadRequest",
	"SlideRequest",
	"SwitchWeaponRequest",
	"PickupRequest",
	"UpgradeChoose",
}

local IdleSystem = {}
IdleSystem.order = 70 -- after MatchSystem (50)

local cfg = Config.Idle
local fightWatch = IdleWatch.new({
	warnSeconds = cfg.warnSeconds,
	kickSeconds = cfg.kickSeconds,
	moveStuds = cfg.moveStuds,
})
local lobbyWatch = IdleWatch.new({
	warnSeconds = cfg.lobbyWarnSeconds,
	kickSeconds = cfg.lobbyQueuedSeconds,
	moveStuds = cfg.moveStuds,
})

local function playerFor(id: string): Player?
	local userId = Ids.userIdOf(id)
	return if userId then Players:GetPlayerByUserId(userId) else nil
end

local function notice(player: Player, text: string, kind: string)
	Net.fire("Notice", player, { text = text, kind = kind })
end

local function trackFighters()
	fightWatch.clear()
	local now = os.clock()
	for _, p in Participants:list() do
		if p.kind == "player" and p.alive then
			fightWatch.track(p.id, now)
		end
	end
end

local function sampleFighters(now: number)
	for _, p in Participants:list() do
		if p.kind == "player" and p.alive and fightWatch.isTracked(p.id) then
			local player = playerFor(p.id)
			local character = if player then player.Character else nil
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if root and root:IsA("BasePart") then
				local pos = root.Position
				fightWatch.position(p.id, now, pos.X, pos.Y, pos.Z)
			end
		end
	end
end

local function sweepFight(now: number)
	-- Anyone who fell or left is not watched any more.
	for _, p in Participants:list() do
		if p.kind == "player" and not p.alive then
			fightWatch.untrack(p.id)
		end
	end
	sampleFighters(now)
	local result = fightWatch.sweep(now)
	for _, id in result.warn do
		local player = playerFor(id)
		if player then
			local left = math.ceil(
				fightWatch.secondsUntilKick(id, now) or (cfg.kickSeconds - cfg.warnSeconds)
			)
			notice(player, `Still there? Move or shoot, or you are out in {left}s.`, "warn")
		end
	end
	for _, id in result.kick do
		local player = playerFor(id)
		if player then
			if MatchSystem.kickIdle(player) then
				notice(player, "You were removed from the match for being idle.", "warn")
			end
		end
	end
end

local function sweepLobby(now: number)
	local phase = MatchContext:getPhase()
	local waiting = phase == MatchPhase.Waiting or phase == MatchPhase.Countdown
	for _, player in Players:GetPlayers() do
		local id = Ids.player(player.UserId)
		local queued = waiting and MatchSystem.isQueued(player)
		if queued and not lobbyWatch.isTracked(id) then
			lobbyWatch.track(id, now)
		elseif not queued and lobbyWatch.isTracked(id) then
			lobbyWatch.untrack(id)
		end
	end
	local result = lobbyWatch.sweep(now)
	for _, id in result.warn do
		local player = playerFor(id)
		if player then
			notice(player, "Still there? Tap anything or you leave the queue soon.", "warn")
		end
	end
	for _, id in result.kick do
		local player = playerFor(id)
		if player then
			MatchSystem.kickIdle(player)
			notice(player, "You left the queue because you were away. Tap PLAY to rejoin.", "info")
		end
	end
end

function IdleSystem.start()
	-- Proof of play. Net already checked and rate-limited these for the real handlers; here we only note
	-- that the player did something, so a bad argument counts for nothing but also costs nothing.
	for _, name in FIGHT_REMOTES do
		local ev = Remotes.get(name)
		ev.OnServerEvent:Connect(function(player: Player)
			local id = Ids.player(player.UserId)
			fightWatch.activity(id, os.clock())
			lobbyWatch.activity(id, os.clock())
		end)
	end
	for _, def in RemoteDefs.list do
		if def.direction == "toServer" then
			Remotes.get(def.name).OnServerEvent:Connect(function(player: Player)
				lobbyWatch.activity(Ids.player(player.UserId), os.clock())
			end)
		end
	end

	MatchContext.PhaseChanged:connect(function(phase: string)
		if phase == MatchPhase.Active then
			trackFighters() -- the clock starts when the fight does, not during the spawn show
		elseif not MatchPhase.isCombat(phase) then
			fightWatch.clear()
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local id = Ids.player(player.UserId)
		fightWatch.untrack(id)
		lobbyWatch.untrack(id)
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < cfg.sweepSeconds then
			return
		end
		elapsed = 0
		local now = os.clock()
		local ok, err = pcall(function()
			if MatchPhase.isCombat(MatchContext:getPhase()) then
				sweepFight(now)
			end
			if cfg.lobbyCheck then
				sweepLobby(now)
			end
		end)
		if not ok then
			warn(`[idle] sweep failed: {err}`)
		end
	end)
end

return IdleSystem
