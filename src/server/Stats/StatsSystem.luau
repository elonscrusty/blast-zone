--!strict
-- Lifetime stats and the top-wins board (piece 24). Server only; the client just shows what it is sent.
--   * Matches and wins come from MatchSystem.RewardGranted (once per player per match).
--   * Eliminations come from Damage.Eliminated (the killer, if a real player; see StatsRules).
--   * Stats are saved in the profile (piece 17, Profiles.update -> data.stats). Never written per event:
--     Profiles only marks the profile dirty; it saves on its own timer, on leave and on shutdown.
--   * Saved wins are mirrored into an OrderedDataStore (TopWinsStore) for the global board.
-- If the Profile piece is not in this build, stats still count for the session (not saved, not on the board).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local StatsRules = require(Shared.Stats.StatsRules)
local StatsBook = require(Shared.Stats.StatsBook)

local ServerRoot = script.Parent.Parent
local Damage = require(ServerRoot.Core.Damage)
local MatchContext = require(ServerRoot.Core.MatchContext)
local Net = require(ServerRoot.Core.Net)
local MatchSystem = require(ServerRoot.Match.MatchSystem)

local TopWinsStore = require(script.Parent.TopWinsStore)
local TrophyWall = require(script.Parent.TrophyWall)

local StatsSystem = {}
StatsSystem.order = 60 -- after Profiles (10) and MatchSystem (50)

local cfg = Config.Stats
local book: StatsBook.Book

-- Piece 17's door, when it is in the build. Typed loosely so this file builds with or without it.
local Profiles: any = nil
do
	local folder = ServerRoot:FindFirstChild("Profile")
	local module = if folder then folder:FindFirstChild("Profiles") else nil
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			Profiles = result
		else
			warn(`[Stats] Profiles did not load: {result}`)
		end
	end
end

local function send(player: Player, shown: StatsBook.Shown)
	if player.Parent == nil then
		return
	end
	Net.fire("StatsUpdate", player, {
		wins = shown.wins,
		eliminations = shown.eliminations,
		matches = shown.matches,
		saved = shown.saved,
	})
end

-- Adds `delta` to the saved stats inside the profile. Returns the new saved totals, or nil.
local function saveDelta(userId: number, delta: StatsRules.Stats): StatsRules.Stats?
	if Profiles == nil then
		return nil
	end
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return nil
	end
	local result: StatsRules.Stats? = nil
	local ok = Profiles.update(player, function(data: { [string]: any })
		local total = StatsRules.add(StatsRules.read(data[cfg.profileKey]), delta)
		data[cfg.profileKey] = {
			wins = total.wins,
			eliminations = total.eliminations,
			matches = total.matches,
		}
		result = total
		return true
	end)
	if not ok then
		return nil
	end
	return result
end

local function placeBoard(): CFrame
	local board = cfg.board
	for _, inst in CollectionService:GetTagged(board.spotTag) do
		if inst:IsA("BasePart") then
			local ground = inst.Position - Vector3.new(0, inst.Size.Y / 2, 0)
			return CFrame.lookAt(ground, ground + inst.CFrame.LookVector * Vector3.new(1, 0, 1))
		end
	end
	for _, inst in CollectionService:GetTagged("LobbySpawn") do -- same tag MatchSystem uses
		if inst:IsA("BasePart") then
			local top = inst.Position + Vector3.new(0, inst.Size.Y / 2, 0)
			local at = top + Vector3.new(0, 0, -board.lobbyOffset)
			return CFrame.lookAt(at, Vector3.new(top.X, at.Y, top.Z))
		end
	end
	local at = Vector3.new(board.fallback.x, 0, board.fallback.z)
	return CFrame.lookAt(at, at + Vector3.new(0, 0, 1))
end

local function startBoard()
	local wall = TrophyWall.build(placeBoard())
	if Profiles == nil then
		wall.setStatus("Saving is off in this build")
		return
	end
	-- Read first so the board fills fast, then keep writing and reading on their own timers.
	task.spawn(function()
		local sinceWrite = 0
		while true do
			local ok, rows = TopWinsStore.readTop()
			if ok then
				wall.setRows(rows)
			else
				local err = TopWinsStore.lastError() or ""
				wall.setStatus(
					if string.find(err, "403", 1, true)
						then "Board works in the real game"
						else "Board is busy, back soon"
				)
			end
			local waited = 0
			while waited < cfg.board.refreshSeconds do
				task.wait(5)
				waited += 5
				sinceWrite += 5
				if sinceWrite >= cfg.board.writeSeconds then
					sinceWrite = 0
					TopWinsStore.flush()
				end
			end
		end
	end)
	game:BindToClose(function()
		TopWinsStore.flush()
	end)
end

function StatsSystem.start()
	book = StatsBook.new({
		save = saveDelta,
		changed = function(userId: number, shown: StatsBook.Shown)
			local player = Players:GetPlayerByUserId(userId)
			if player then
				send(player, shown)
			end
		end,
		savedWins = function(userId: number, wins: number)
			TopWinsStore.queue(userId, wins)
		end,
	})

	local function onAdded(player: Player)
		book:join(player.UserId)
		if Profiles and Profiles.get(player) ~= nil then
			book:loaded(player.UserId)
		end
	end
	Players.PlayerAdded:Connect(onAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		book:leave(player.UserId)
	end)
	for _, player in Players:GetPlayers() do
		onAdded(player)
	end
	if Profiles then
		Profiles.Loaded:connect(function(player: Player)
			book:loaded(player.UserId)
		end)
	end

	Damage.Eliminated:connect(function(event)
		if not MatchContext:isCurrent(event.matchId) then
			return
		end
		local userId = StatsRules.eliminationCredit(event)
		if userId then
			book:earn(userId, { wins = 0, eliminations = 1, matches = 0 })
		end
	end)

	MatchSystem.RewardGranted:connect(
		function(participantId: string, _amount: number, place: number)
			local userId = if Ids.isPlayer(participantId) then Ids.userIdOf(participantId) else nil
			if userId then
				book:earn(userId, StatsRules.matchDelta(place))
			end
		end
	)

	Net.onRequest("StatsRequest", function(player: Player)
		local shown = book:get(player.UserId)
		if shown then
			send(player, shown)
		end
	end)

	task.spawn(startBoard)
end

return StatsSystem
