--!strict
-- Saving player progress. The ONLY door to DataStore for player data: other server code never calls
-- DataStoreService. Server only. The rules live in shared/Profile (tested in Lune); this file only
-- connects them to Players, DataStoreService and BindToClose.
--
--   local Profiles = require(script.Parent.Parent.Profile.Profiles)   -- from a sibling server folder
--
--   Profiles.init()                    once, from the bootstrap (safe to call twice). Connect
--                                      onLoaded / onLeaving BEFORE calling it.
--   Profiles.get(player)               -> Types.Profile?  The LIVE table: change it in place, then
--                                      call markDirty. nil while loading, after the player left, or
--                                      if the profile was taken over by another server.
--   Profiles.isOffline(player)         -> boolean. true when the save could not be loaded (DataStore
--                                      down / API off / profile busy elsewhere). The player still
--                                      plays with a fresh profile that is NEVER saved. Show a small
--                                      "progress is not being saved" note, nothing scary.
--   Profiles.onLoaded:Connect(function(player, profile) end)   profile ready (also offline ones).
--   Profiles.onLeaving:Connect(function(player, profile) end)  just before the final save: last
--                                      chance to write stats (playSeconds ...) into the profile.
--   Profiles.onRecovered:Connect(function(player, profile) end) an offline player's REAL profile
--                                      loaded after all (background retries). `profile` is the same
--                                      live table as before, now holding the real data.
--   Profiles.onGaveUp:Connect(function(player, profile) end)   the background retries ended without
--                                      the real profile (another live server still holds it).
--   Profiles.isRetrying(player)        -> boolean. Offline, and still trying to load the real save.
--   Profiles.markDirty(player)         cheap flag: "I changed the profile". Writes are never per change.
--   Profiles.saveNow(player)           -> boolean. YIELDS up to ~6 s (DataStore write spacing): call it
--                                      with task.spawn after a purchase or reward. true = nothing
--                                      left to write or written; false = offline/failed.
--   Profiles.saveSoon(player)          ask for a write as soon as the spacing allows (no yield).
--   Profiles.update(player, fn)        -> ok, reason?  fn(profile) edits a COPY; applied only if it
--                                      does not error, does not return false and stays valid.
--   Profiles.grantOnce(player, key, fn) same, but pays once per key ("duplicate" = already paid).
--                                      Daily reward: key = Profiles.dailyKey(day).
--   Profiles.status(player)            -> "loading" | "ready" | "offline" | "lost" | "none"
--   Profiles.waitForLoad(player, secs) -> Types.Profile?  (yields)
--   Profiles.beforeShutdown(fn)        fn runs first when the server closes, before the final saves.
--
-- Writes happen on the autosave timer (every 60 s per player, staggered), on leave, on server
-- shutdown (BindToClose, all players in parallel) and on saveNow.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SaveRetry = require(Shared.SaveRetry)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local ProfileManager = require(Shared.Profile.ProfileManager)
local ProfileStore = require(Shared.Profile.ProfileStore)
local Receipts = require(Shared.Profile.Receipts)

-- Changing this starts every player from nothing: never rename.
local STORE_NAME = "VolcanoSweepers_v1"
local SHUTDOWN_SECONDS = 25 -- BindToClose allows 30

local Profiles = {}

-- An event that can be used as `event:Connect(fn)` (the Roblox spelling) or `event:connect(fn)`.
export type Connection = { Disconnect: (self: Connection) -> (), connected: boolean }
export type Event = {
	Connect: (self: Event, fn: (Player, Types.Profile) -> ()) -> Connection,
	connect: (self: Event, fn: (Player, Types.Profile) -> ()) -> Connection,
	fire: (self: Event, Player, Types.Profile) -> (),
}

local function newEvent(): Event
	local signal = Signal.new()
	local event: any = {}
	function event.Connect(_: any, fn: (Player, Types.Profile) -> ()): Connection
		local inner = signal:connect(fn)
		local conn: any = { connected = true }
		function conn.Disconnect(c: any)
			c.connected = false
			inner:disconnect()
		end
		return conn
	end
	event.connect = event.Connect
	function event.fire(_: any, player: Player, profile: Types.Profile)
		signal:fire(player, profile)
	end
	return event :: Event
end

Profiles.onLoaded = newEvent()
Profiles.onLeaving = newEvent()
Profiles.onRecovered = newEvent()
Profiles.onGaveUp = newEvent()

-- In Studio JobId is empty; two Studio servers must still look different to the lock.
local jobId: string = if game.JobId ~= ""
	then game.JobId
	else "studio-" .. HttpService:GenerateGUID(false)

local manager: ProfileManager.Manager? = nil
local shutdownHooks: { () -> () } = {}
local known: { [number]: Player } = {} -- by userId, so signals can name the player

local function say(text: string)
	print("[Profile] " .. text)
end

function Profiles.init()
	if manager ~= nil then
		return
	end
	-- Studio with API access off (or an unpublished place) throws on every call, with "403" in the
	-- text. SaveRetry stops at once on that, the load fails, and the player plays offline.
	local okStore, dataStore = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	local function update(key: string, transform: (any) -> (any, { number }?)): any
		if not okStore then
			error("403 no DataStore: " .. tostring(dataStore))
		end
		local ok, result = pcall(function()
			return (dataStore :: DataStore):UpdateAsync(key, transform)
		end)
		if not ok then
			local text = tostring(result)
			-- An unpublished place says "publish" instead of 403; treat it the same: no point waiting.
			if
				string.find(text, "publish", 1, true) or string.find(text, "Studio access", 1, true)
			then
				error("403 " .. text, 0)
			end
			error(text, 0)
		end
		return result
	end

	local cfg = table.clone(ProfileStore.DEFAULT_CFG) :: any
	cfg.shutdownSeconds = SHUTDOWN_SECONDS
	local store = ProfileStore.new({
		update = update,
		jobId = jobId,
		clock = os.time,
		wait = task.wait,
		retry = SaveRetry.run,
		cfg = cfg,
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
		cfg = cfg,
		log = say,
	})
	manager = m

	m.Loaded:connect(function(userId: number, profile: ProfileStore.Profile)
		local player = known[userId]
		if player then
			Profiles.onLoaded:fire(player, profile.data)
		end
	end)
	m.Leaving:connect(function(userId: number, profile: ProfileStore.Profile)
		local player = known[userId]
		if player then
			Profiles.onLeaving:fire(player, profile.data)
		end
	end)
	m.Recovered:connect(function(userId: number, profile: ProfileStore.Profile)
		local player = known[userId]
		if player then
			Profiles.onRecovered:fire(player, profile.data)
		end
	end)
	m.StatusChanged:connect(function(userId: number, status: string)
		local player = known[userId]
		if player == nil then
			return
		end
		if status == "offline" and not m:isRetrying(userId) then
			local data = m:data(userId)
			if data ~= nil then
				Profiles.onGaveUp:fire(player, data)
			end
		end
		if status == "lost" then
			warn(`[Profile] {player.Name}'s progress was opened by another server`)
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
		m:leave(player.UserId) -- fires onLeaving, then saves and releases in the background
		if known[player.UserId] == player then
			known[player.UserId] = nil
		end
	end)

	game:BindToClose(function()
		for _, hook in shutdownHooks do
			local ok, err = pcall(hook)
			if not ok then
				warn(`[Profile] shutdown hook failed: {err}`)
			end
		end
		m:shutdown() -- one task.spawn per player, waits for all (up to SHUTDOWN_SECONDS)
	end)

	task.spawn(function()
		while not m.closing do
			task.wait(1)
			local ok, err = pcall(function()
				m:tick()
			end)
			if not ok then
				warn(`[Profile] autosave tick failed: {err}`)
			end
		end
	end)
end

local function need(): ProfileManager.Manager
	if manager == nil then
		Profiles.init()
	end
	return manager :: ProfileManager.Manager
end

function Profiles.beforeShutdown(fn: () -> ())
	table.insert(shutdownHooks, fn)
end

function Profiles.get(player: Player): Types.Profile?
	return need():data(player.UserId)
end

function Profiles.isOffline(player: Player): boolean
	return need():isOffline(player.UserId)
end

function Profiles.isRetrying(player: Player): boolean
	return need():isRetrying(player.UserId)
end

function Profiles.status(player: Player): string
	return need():status(player.UserId)
end

-- Why the load failed while isOffline: "locked" | "error" | "future" | "corrupt" | "migration" |
-- "busy" | "noAccess".
function Profiles.offlineReason(player: Player): string?
	return need():failReason(player.UserId)
end

function Profiles.markDirty(player: Player)
	need():markDirty(player.UserId)
end

function Profiles.saveSoon(player: Player)
	need():saveSoon(player.UserId)
end

function Profiles.saveNow(player: Player): boolean
	return need():saveNow(player.UserId)
end

function Profiles.update(player: Player, fn: (Types.Profile) -> boolean?): (boolean, string?)
	return need():update(player.UserId, fn)
end

function Profiles.grantOnce(
	player: Player,
	key: string,
	fn: (Types.Profile) -> boolean?
): (boolean, string?)
	return need():grantOnce(player.UserId, key, fn)
end

-- Once-only key for the daily reward of one UTC day (days since 1970).
function Profiles.dailyKey(day: number): string
	return Receipts.dailyKey(day)
end

function Profiles.waitForLoad(player: Player, seconds: number): Types.Profile?
	local m = need()
	local waited = 0
	while m:status(player.UserId) == "loading" and waited < seconds and player.Parent ~= nil do
		task.wait(0.1)
		waited += 0.1
	end
	return m:data(player.UserId)
end

return Profiles
