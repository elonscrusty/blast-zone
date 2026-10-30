--!strict
-- The ranked ladder on the server (gap 23). The client only asks to flip its switch and to see its standing.
--   * The switch is saved in the profile (data.ranked.enabled). What counts is the switch when the fight BEGINS.
--   * When a ranked fight begins, the last-place loss is taken at once (the stake). It is handed back when the
--     match is scored, so leaving mid-fight keeps the loss.
--   * Scoring comes from MatchSystem.RewardGranted (place, won) plus the server's own books: how many fighters
--     and real players the match had, and each player's eliminations (Damage.Eliminated, real killers only).
--   * Saved through Profiles with once-only keys (a repeat can never score a match twice). With no Profile piece
--     in the build the ladder still works for this session, but nothing is saved.
-- Rules are in shared/Ranked (tested in Lune).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local RankedBook = require(Shared.Ranked.RankedBook)
local RankedRules = require(Shared.Ranked.RankedRules)
local StatsRules = require(Shared.Stats.StatsRules)

local ServerRoot = script.Parent.Parent
local Damage = require(ServerRoot.Core.Damage)
local MatchContext = require(ServerRoot.Core.MatchContext)
local Net = require(ServerRoot.Core.Net)
local MatchSystem = require(ServerRoot.Match.MatchSystem)

local RankedSystem = {}
RankedSystem.order = 62 -- after Profiles (10) and MatchSystem (50)

local cfg = Config.Ranked

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
			warn(`[Ranked] Profiles did not load: {result}`)
		end
	end
end

type Snapshot = {
	field: number, -- fighters, bots too
	humans: number,
	ranked: { [number]: boolean }, -- players whose switch was on when the fight began
	counted: boolean, -- enough fighters for the ladder
	kills: { [number]: number },
	staked: boolean,
}

local snapshots: { [number]: Snapshot } = {}
local book: RankedBook.Book
local memory: { [number]: RankedRules.State } = {} -- used only when there is no Profile piece

local function send(userId: number, payload: any)
	local player = Players:GetPlayerByUserId(userId)
	if player and player.Parent ~= nil then
		Net.fire("RankedUpdate", player, payload)
	end
end

local function readState(userId: number): RankedRules.State?
	if Profiles == nil then
		memory[userId] = memory[userId] or RankedRules.empty()
		return memory[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	local profile = if player then Profiles.get(player) else nil
	if profile == nil then
		return nil
	end
	return RankedRules.read(profile.data[cfg.profileKey])
end

-- Runs `change` on the saved state and saves the answer. Returns the new saved state, or nil and why.
local function writeState(
	userId: number,
	key: string?,
	change: (RankedRules.State) -> RankedRules.State
): (RankedRules.State?, string?)
	if Profiles == nil then
		local before = memory[userId] or RankedRules.empty()
		memory[userId] = change(before)
		return memory[userId], nil
	end
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return nil, "gone"
	end
	local out: RankedRules.State? = nil
	local function apply(data: { [string]: any }): boolean
		local new = change(RankedRules.read(data[cfg.profileKey]))
		data[cfg.profileKey] = RankedRules.toSaved(new)
		out = new
		return true
	end
	local ok: boolean = false
	local reason: string? = nil
	if key ~= nil then
		ok, reason = Profiles.grantOnce(player, key, apply)
	else
		ok, reason = Profiles.update(player, apply)
	end
	if ok then
		return out, nil
	end
	return nil, reason
end

local function receiptKey(matchId: number, tag: string): string
	local base = if Profiles ~= nil
		then Profiles.matchReceiptKey(matchId)
		else `{game.JobId}:{matchId}`
	return `{base}:{tag}`
end

-- ===== one match =====

local function snapshotFor(matchId: number): Snapshot
	local snap = snapshots[matchId]
	if snap == nil then
		snap = { field = 0, humans = 0, ranked = {}, counted = false, kills = {}, staked = false }
		snapshots[matchId] = snap
		for old in snapshots do
			if old < matchId - 3 then
				snapshots[old] = nil
			end
		end
	end
	return snap :: Snapshot
end

-- A moment after the spawns went out the field is complete: decide who is ranked and take the stakes.
local function settle(matchId: number)
	local snap = snapshots[matchId]
	if snap == nil or snap.staked or not MatchContext:isCurrent(matchId) then
		return
	end
	snap.staked = true
	snap.counted = RankedRules.counts(snap.field)
	if not snap.counted then
		return
	end
	for userId in snap.ranked do
		if not book:stake(userId, receiptKey(matchId, "rs")) then
			snap.ranked[userId] = nil -- could not write the stake: this match does not count for them
		end
	end
end

local function onSpawn(participant: any)
	if type(participant) ~= "table" or type(participant.matchId) ~= "number" then
		return
	end
	local snap = snapshotFor(participant.matchId)
	snap.field += 1
	local userId = if Ids.isPlayer(participant.id) then Ids.userIdOf(participant.id) else nil
	if userId then
		snap.humans += 1
		if book:isOn(userId) then
			snap.ranked[userId] = true
		end
	end
	if snap.field == 1 then
		local matchId = participant.matchId
		task.delay(cfg.settleSeconds, function()
			settle(matchId)
		end)
	end
end

local function onReward(
	participantId: string,
	_amount: number,
	place: number,
	matchId: number,
	won: boolean?
)
	local userId = if Ids.isPlayer(participantId) then Ids.userIdOf(participantId) else nil
	local snap = snapshots[matchId]
	if userId == nil or snap == nil or not snap.ranked[userId] then
		return -- not a player, not ranked this match, or already scored
	end
	snap.ranked[userId] = nil -- scored once
	local kills = snap.kills[userId] or 0
	if not snap.counted then
		book:practice(userId, matchId, place, kills)
		return
	end
	book:score(userId, receiptKey(matchId, "rk"), matchId, {
		place = place,
		field = snap.field,
		kills = kills,
		won = won == true,
		humans = snap.humans,
	})
end

function RankedSystem.start()
	book = RankedBook.new({
		read = readState,
		write = writeState,
		changed = send,
	})

	local function onAdded(player: Player)
		book:join(player.UserId)
		if Profiles == nil or Profiles.get(player) ~= nil then
			book:loaded(player.UserId)
		end
	end
	Players.PlayerAdded:Connect(onAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		book:leave(player.UserId)
		memory[player.UserId] = nil
	end)
	for _, player in Players:GetPlayers() do
		onAdded(player)
	end
	if Profiles then
		Profiles.Loaded:connect(function(player: Player)
			book:loaded(player.UserId)
		end)
	end

	MatchSystem.SpawnAssigned:connect(function(participant: any)
		onSpawn(participant)
	end)

	Damage.Eliminated:connect(function(event)
		if not MatchContext:isCurrent(event.matchId) then
			return
		end
		local userId = StatsRules.eliminationCredit(event)
		if userId then
			local snap = snapshotFor(event.matchId)
			snap.kills[userId] = (snap.kills[userId] or 0) + 1
		end
	end)

	MatchSystem.RewardGranted:connect(onReward)

	Net.onRequest("RankedRequest", function(player: Player)
		local payload = book:get(player.UserId)
		if payload then
			send(player.UserId, payload)
		end
	end)

	Net.onRequest("RankedToggle", function(player: Player, on: boolean)
		-- Allowed any time: the fight in progress already took its snapshot, so this only changes the next one.
		if not book:setEnabled(player.UserId, on == true) then
			local payload = book:get(player.UserId) -- snap the client's switch back to the truth
			if payload then
				send(player.UserId, payload)
			end
		end
	end)
end

return RankedSystem
