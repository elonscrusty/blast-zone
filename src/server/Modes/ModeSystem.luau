--!strict
-- Game modes on the server (piece G24). Players tap a mode in the lobby; the server counts (same rules as the map
-- vote, see shared/MapVote), checks the voter's account level, and when the fight is about to start (Spawning) puts
-- the winning mode's tuning on the config. When the match is over everything is put back. Logic only: the look of
-- the picker comes from Claude Design.
--
-- For other pieces:
--   ModeSystem.current()    the id of the mode being played (or about to be): never nil once a mode is shown.
--   ModeSystem.Chosen       Signal(modeId, matchId): once per match, right after the tuning is applied.
-- Systems that start after this one (everything except the profile) see the changed numbers when they read Config
-- at Spawning or later. This one starts first so its phase listener runs before theirs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local MatchPhase = require(Shared.MatchPhase)
local ModeRules = require(Shared.Modes.ModeRules)
local Signal = require(Shared.Signal)
local VoteFlow = require(Shared.MapVote.VoteFlow)

local Server = script.Parent.Parent
local MatchContext = require(Server.Core.MatchContext)
local Net = require(Server.Core.Net)

local ModeSystem = {}
ModeSystem.order = 8 -- before the arena (10), crates (110), floor loot (150) and the circle (200)
ModeSystem.Chosen = Signal.new()

local rng = Random.new()
local flow: VoteFlow.Flow = VoteFlow.new(ModeRules.pool(), function(n: number)
	return rng:NextInteger(1, n)
end)
local dirty = false
local undo: (() -> ())? = nil
local currentId: string = ""

local function levelOf(player: Player): number
	local ok, level = pcall(function()
		return require(Server.Progression.ProgressionSystem).getAccountLevel(player)
	end)
	return if ok and type(level) == "number" then level else 1
end

local function sendTo(player: Player)
	Net.fire(
		"ModeState",
		player,
		ModeRules.stateFor(flow, Ids.player(player.UserId), levelOf(player))
	)
end

local function sendAll()
	dirty = false
	for _, player in Players:GetPlayers() do
		sendTo(player)
	end
end

local function revert()
	if undo ~= nil then
		undo()
		undo = nil
	end
end

-- Locks the vote (the flow already did, at Spawning) and puts the winner's numbers on the config.
local function applyChosen(matchId: number)
	revert() -- never stack one mode on another
	local def = ModeRules.resolve(flow.nextMapId)
	if def == nil then
		return
	end
	local problem = ModeRules.problem(def.tuning)
	if problem ~= nil then
		warn(`[modes] {def.id} skipped: {problem}`)
		def = ModeRules.default()
		if def == nil or ModeRules.problem(def.tuning) ~= nil then
			return
		end
	end
	undo = ModeRules.apply(Config, def.tuning)
	currentId = def.id
	flow:setCurrentMap(def.id) -- a tie next time does not repeat this mode when there is a choice
	workspace:SetAttribute("ModeId", def.id)
	ModeSystem.Chosen:fire(def.id, matchId)
end

function ModeSystem.current(): string
	return currentId
end

function ModeSystem.start()
	local first = ModeRules.default()
	currentId = if first then first.id else ""
	workspace:SetAttribute("ModeId", if first then first.id else nil)

	Net.onRequest("ModeVoteRequest", function(player: Player, modeId: string)
		-- Net checked the shape. The rules check the mode is shown, the level opens it and the window is open.
		if ModeRules.vote(flow, Ids.player(player.UserId), modeId, levelOf(player)) then
			dirty = true
		end
		sendTo(player) -- the voter sees the truth at once; everyone else gets the count on the next tick
	end)

	Net.onRequest("ModeStateRequest", function(player: Player)
		sendTo(player)
	end)

	MatchContext.PhaseChanged:connect(function(phase: string, _old: string, matchId: number)
		flow:onPhase(phase) -- opens a fresh window after Results, locks at Spawning
		if phase == MatchPhase.Spawning then
			applyChosen(matchId)
		elseif
			phase == MatchPhase.Results
			or phase == MatchPhase.Resetting
			or phase == MatchPhase.Waiting
			or phase == MatchPhase.Countdown
		then
			revert()
		end
		sendAll()
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		flow:leave(Ids.player(player.UserId))
		dirty = true
	end)

	-- Counts reach everyone at most once per stateRepeatSeconds, so a burst of taps is one message each.
	task.spawn(function()
		while true do
			task.wait(Config.Modes.stateRepeatSeconds)
			if dirty then
				sendAll()
			end
		end
	end)
end

return ModeSystem
