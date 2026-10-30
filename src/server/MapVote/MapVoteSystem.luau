--!strict
-- Map vote on the server (piece 33). Players tap a map in the lobby; the server counts. Logic only.
-- The rules live in shared/MapVote/VoteFlow (pure, tested). This file connects players, remotes and the arena.
--
-- For other pieces:
--   MapVoteSystem.setPool(maps)    the second-map piece: the maps that can be picked, { { id, name } } in rotation order.
--   MapVoteSystem.takeWinner()     the arena builder, once, right before it builds the next map. Locks the vote and
--                                  returns the winning map id, or nil if nobody voted (use your own rotation).
--   MapVoteSystem.Locked           Signal(winnerId?) fired once per match when the vote locks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local Signal = require(Shared.Signal)
local VoteBook = require(Shared.MapVote.VoteBook)
local VoteFlow = require(Shared.MapVote.VoteFlow)

local Core = script.Parent.Parent:WaitForChild("Core")
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)

local MapVoteSystem = {}
MapVoteSystem.order = 60 -- after the match flow, before anything that builds the next map
MapVoteSystem.Locked = Signal.new()

local rng = Random.new()
local flow: VoteFlow.Flow = VoteFlow.new({}, function(n: number)
	return rng:NextInteger(1, n)
end)
local dirty = false
local lockedAnnounced = false

local function voterId(player: Player): string
	return Ids.player(player.UserId)
end

local function stateFor(player: Player)
	return flow:state(voterId(player))
end

local function sendTo(player: Player)
	Net.fire("MapVoteState", player, stateFor(player))
end

local function sendAll()
	dirty = false
	for _, player in Players:GetPlayers() do
		sendTo(player)
	end
end

local function announceLock()
	if not lockedAnnounced and flow.locked then
		lockedAnnounced = true
		MapVoteSystem.Locked:fire(flow.nextMapId)
	end
end

function MapVoteSystem.setPool(maps: { VoteBook.MapInfo })
	flow:setPool(maps)
	sendAll()
end

function MapVoteSystem.takeWinner(): string?
	local winner = flow:takeWinner()
	announceLock()
	sendAll()
	return winner
end

-- The arena piece (second map) offers a chooser hook and a rotation list. Both may not exist in older builds,
-- so everything here is looked up safely and the vote simply stays empty without them.
local function connectArena()
	local arenaConfig: any = Config.Arena
	local rotation: any = arenaConfig.rotation
	if type(rotation) == "table" then
		local pool: { VoteBook.MapInfo } = {}
		for _, id in rotation do
			local name = Config.MapVote.names[id]
			table.insert(pool, { id = id, name = if name then name else id })
		end
		MapVoteSystem.setPool(pool)
	end
	local module = script.Parent.Parent:FindFirstChild("Arena")
	local arenaSystem = if module then module:FindFirstChild("ArenaSystem") else nil
	if arenaSystem and arenaSystem:IsA("ModuleScript") then
		local ok, loaded = pcall(require, arenaSystem)
		local hook: any = if ok then (loaded :: any).setChooser else nil
		if type(hook) == "function" then
			hook(function()
				return MapVoteSystem.takeWinner()
			end)
		end
	end
end

function MapVoteSystem.start()
	Net.onRequest("MapVoteRequest", function(player: Player, mapId: string)
		-- Net already checked the shape. The flow checks the window and that the map is in the pool.
		if flow:vote(voterId(player), mapId) then
			dirty = true
			sendTo(player) -- the voter sees it at once; everyone else gets the count on the next tick
		else
			sendTo(player) -- a refused vote snaps the client back to the truth
		end
	end)

	Net.onRequest("MapVoteStateRequest", function(player: Player)
		sendTo(player)
	end)

	MatchContext.PhaseChanged:connect(function(phase: string)
		local before = flow.locked
		flow:onPhase(phase)
		if before and not flow.locked then
			lockedAnnounced = false -- a new window opened
		end
		announceLock()
		sendAll()
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		flow:leave(voterId(player))
		dirty = true
	end)

	-- Counts reach everyone at most once per stateRepeatSeconds, so a burst of taps is one message each.
	task.spawn(function()
		while true do
			task.wait(Config.MapVote.stateRepeatSeconds)
			if dirty then
				sendAll()
			end
		end
	end)

	connectArena()

	-- Do not repeat the map that is on screen when a tie is broken.
	local arena = workspace:FindFirstChild(Config.Workspace.ArenaFolder)
	if arena then
		flow:setCurrentMap(arena:GetAttribute("LayoutName") :: string?)
		arena:GetAttributeChangedSignal("LayoutName"):Connect(function()
			flow:setCurrentMap(arena:GetAttribute("LayoutName") :: string?)
		end)
	end
end

return MapVoteSystem
