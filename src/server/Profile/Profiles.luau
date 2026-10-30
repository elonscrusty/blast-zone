--!strict
-- Saving player progress (piece 17). The ONLY door to DataStore for player data: other pieces
-- never call DataStoreService. Server only. The rules live in shared/Profile (tested in Lune);
-- this file only connects them to Players, DataStoreService, BindToClose and the remotes.
--
--   local Profiles = require(script.Parent.Parent.Profile.Profiles)   -- from a sibling server folder
--
--   Profiles.get(player)                 -> Profile? ({ userId, isNew, data }); nil until loaded or if it failed.
--                                           Do not keep profile.data across waits: call get again.
--   Profiles.getByParticipantId("p123")  -> Profile? (bots have none)
--   Profiles.status(player)              -> "loading" | "ready" | "failed" | "lost" | "none"
--   Profiles.failReason(player)          -> "locked" | "error" | "future" | "corrupt" | "migration" | "busy"?
--   Profiles.update(player, fn)          -> ok, reason?   fn(data) -> boolean?; runs on a copy, applied only
--                                           if it does not error, does not return false, and stays saveable.
--                                           reason: "notLoaded" | "rejected" | "error" | "invalid"
--   Profiles.grantOnce(player, key, fn)  -> ok, reason?   same, but pays once per key ("duplicate" = already paid).
--                                           Use key = Profiles.matchReceiptKey(matchId) for match rewards.
--   Profiles.getFlag / setFlag           small yes/no settings (names listed in Config.Profile.flags)
--   Profiles.saveSoon(player)            merge into the next allowed write
--   Profiles.saveNow(player)             -> boolean. Yields. Use after a reward or purchase.
--   Profiles.retryLoad(player)           -> boolean. After a failed load.
--   Profiles.waitForLoad(player, secs)   -> Profile?
--   Profiles.beforeShutdown(fn)          fn runs first when the server closes, before the final saves (piece 39:
--                                           the match pays out last rewards there). Errors in fn are ignored.
--   Signals: Loaded(player, profile), Released(player), StatusChanged(player, status, reason?)
--
-- Nothing is written per shot or per update: changes only mark the profile dirty. Writes happen on
-- the autosave timer, on leave, on server shutdown (BindToClose) and on saveNow.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local SaveRetry = require(Shared.SaveRetry)
local Signal = require(Shared.Signal)
local ProfileManager = require(Shared.Profile.ProfileManager)
local ProfileStore = require(Shared.Profile.ProfileStore)
local Receipts = require(Shared.Profile.Receipts)

local Net = require(script.Parent.Parent.Core.Net)

local Profiles = {}

export type Profile = ProfileStore.Profile

Profiles.Loaded = Signal.new()
Profiles.Released = Signal.new()
Profiles.StatusChanged = Signal.new()

-- In Studio JobId is empty; two Studio servers must still look different to the lock.
local jobId: string = if game.JobId ~= ""
	then game.JobId
	else "studio-" .. HttpService:GenerateGUID(false)

local manager: ProfileManager.Manager? = nil
local shutdownHooks: { () -> () } = {}
local known: { [number]: Player } = {} -- so Released can name a player who already left

local function say(text: string)
	warn("[Profile] " .. text)
end

local function sendStatus(player: Player)
	local m = manager
	if m == nil or player.Parent == nil then
		return
	end
	local status = m:status(player.UserId)
	local profile = m:get(player.UserId)
	Net.fire("ProfileStatus", player, {
		state = if status == "none" then "loading" else status,
		isNew = profile ~= nil and profile.isNew,
		flags = m:flags(player.UserId) or {},
	})
end

local function need(): ProfileManager.Manager
	return manager :: ProfileManager.Manager
end

function Profiles.init()
	if manager ~= nil then
		return
	end
	local dataStore = DataStoreService:GetDataStore(Config.Profile.storeName)
	local store = ProfileStore.new({
		update = function(key: string, transform: (any) -> (any, { number }?))
			return dataStore:UpdateAsync(key, transform)
		end,
		jobId = jobId,
		clock = os.time,
		wait = task.wait,
		retry = SaveRetry.run,
		cfg = Config.Profile,
		log = say,
	})
	local m = ProfileManager.new({
		store = store,
		spawn = function(fn: () -> ())
			task.spawn(fn)
		end,
		wait = task.wait,
		clock = os.time,
		newSignal = Signal.new,
		cfg = Config.Profile,
		log = say,
	})
	manager = m

	m.Loaded:connect(function(userId: number, profile: Profile)
		local player = known[userId]
		if player then
			print(
				`[Profile] {player.Name} loaded ({if profile.isNew
					then "new player"
					else "saved progress found"})`
			)
			Profiles.Loaded:fire(player, profile)
		end
	end)
	m.Released:connect(function(userId: number)
		local player = known[userId]
		known[userId] = nil
		if player then
			Profiles.Released:fire(player)
		end
	end)
	m.StatusChanged:connect(function(userId: number, status: string, reason: string?)
		local player = known[userId]
		if player == nil then
			return
		end
		if status == "failed" then
			say(`{player.Name} load failed: {reason or "?"}`)
		end
		Profiles.StatusChanged:fire(player, status, reason)
		sendStatus(player)
		if status == "lost" then
			player:Kick("Your progress was opened in another game server. Please rejoin.")
		end
	end)

	local function onAdded(player: Player)
		known[player.UserId] = player
		m:join(player.UserId)
	end
	Players.PlayerAdded:Connect(onAdded)
	for _, player in Players:GetPlayers() do
		onAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		m:leave(player.UserId)
	end)

	Net.onRequest("ProfileStatusRequest", function(player)
		sendStatus(player)
	end)
	Net.onRequest("RetryProfileLoadRequest", function(player)
		m:retryLoad(player.UserId)
		sendStatus(player) -- always answer, so a client that joined late catches up
	end)
	Net.onRequest("SetFlagRequest", function(player, flag: string, value: boolean)
		-- The manager only accepts names listed in Config.Profile.flags.
		m:setFlag(player.UserId, flag, value)
		sendStatus(player)
	end)

	game:BindToClose(function()
		for _, hook in shutdownHooks do
			local ok, err = pcall(hook)
			if not ok then
				warn(`[profiles] shutdown hook failed: {err}`)
			end
		end
		m:shutdown()
	end)
	task.spawn(function()
		local seconds = 0
		while not m.closing do
			task.wait(1)
			seconds += 1
			m:tick()
			-- A client that joined late can miss the first message: keep telling it while loading.
			if seconds % 5 == 0 then
				for _, player in Players:GetPlayers() do
					if m:status(player.UserId) == "loading" then
						sendStatus(player)
					end
				end
			end
		end
	end)
end

function Profiles.beforeShutdown(fn: () -> ())
	table.insert(shutdownHooks, fn)
end

function Profiles.get(player: Player): Profile?
	return need():get(player.UserId)
end

function Profiles.getByParticipantId(participantId: string): Profile?
	local userId = Ids.userIdOf(participantId)
	if userId == nil then
		return nil
	end
	return need():get(userId)
end

function Profiles.status(player: Player): string
	return need():status(player.UserId)
end

function Profiles.failReason(player: Player): string?
	return need():failReason(player.UserId)
end

function Profiles.update(player: Player, fn: ({ [string]: any }) -> boolean?): (boolean, string?)
	return need():update(player.UserId, fn)
end

function Profiles.grantOnce(
	player: Player,
	key: string,
	fn: ({ [string]: any }) -> boolean?
): (boolean, string?)
	return need():grantOnce(player.UserId, key, fn)
end

function Profiles.getFlag(player: Player, name: string): boolean?
	return need():getFlag(player.UserId, name)
end

function Profiles.setFlag(player: Player, name: string, value: boolean): boolean
	local ok = need():setFlag(player.UserId, name, value)
	if ok then
		sendStatus(player)
	end
	return ok
end

function Profiles.saveSoon(player: Player)
	need():saveSoon(player.UserId)
end

function Profiles.saveNow(player: Player): boolean
	return need():saveNow(player.UserId)
end

function Profiles.retryLoad(player: Player): boolean
	return need():retryLoad(player.UserId)
end

function Profiles.waitForLoad(player: Player, seconds: number): Profile?
	local m = need()
	local waited = 0
	while m:status(player.UserId) == "loading" and waited < seconds and player.Parent ~= nil do
		task.wait(0.1)
		waited += 0.1
	end
	return m:get(player.UserId)
end

-- Once-only key for paying one match's reward. matchId restarts at 1 on each server, so the
-- server's JobId is part of the key.
function Profiles.matchReceiptKey(matchId: number): string
	return Receipts.matchKey(jobId, matchId)
end

return Profiles
