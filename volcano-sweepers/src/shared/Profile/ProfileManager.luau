--!strict
-- The life of every player's profile on this server, by userId: load on join, autosave, save on
-- leave, release on shutdown. Pure Luau (store, spawning, waiting and signals are passed in), so
-- the whole join / leave / outage flow is tested in Lune. The Roblox side is only a thin wrapper
-- (server/Profile/Profiles).
--
-- Status of a player: "loading" | "ready" | "offline" | "lost" ("none" = never joined).
--   ready    Profile loaded, saves allowed.
--   offline  The load failed (DataStore down or API off, another server holds the profile, saved
--            by a newer game, unreadable). The player still plays with a fresh profile, but it is
--            `locked`: it is NEVER written, so real progress in the DataStore is never overwritten.
--   lost     Another server took this profile over. get() is nil and nothing more is written.

local ProfileStore = require("./ProfileStore")
local Types = require("../Types")

local ProfileManager = {}
ProfileManager.__index = ProfileManager

export type Status = "none" | "loading" | "ready" | "offline" | "lost"

type Entry = {
	status: Status,
	profile: ProfileStore.Profile?,
	reason: string?,
	left: boolean,
}

export type Deps = {
	store: ProfileStore.Store,
	spawn: (() -> ()) -> (),
	wait: (number) -> (),
	clock: () -> number,
	newSignal: () -> any,
	cfg: ProfileStore.Cfg & { shutdownSeconds: number },
	log: ((string) -> ())?,
}

export type Manager = typeof(setmetatable(
	{} :: {
		deps: Deps,
		entries: { [number]: Entry },
		pending: number,
		closing: boolean,
		Loaded: any, -- (userId, profile) once per join, ready or offline
		Leaving: any, -- (userId, profile) just before the final save
		Released: any, -- (userId) once per join, after the final save (or after a load for a player who left)
		StatusChanged: any, -- (userId, status, reason?)
	},
	ProfileManager
))

function ProfileManager.new(deps: Deps): Manager
	return setmetatable({
		deps = deps,
		entries = {},
		pending = 0,
		closing = false,
		Loaded = deps.newSignal(),
		Leaving = deps.newSignal(),
		Released = deps.newSignal(),
		StatusChanged = deps.newSignal(),
	}, ProfileManager)
end

local function log(self: Manager, text: string)
	if self.deps.log then
		self.deps.log(text)
	end
end

-- Runs fn in the background and counts it, so shutdown can wait for it.
local function background(self: Manager, fn: () -> ())
	self.pending += 1
	self.deps.spawn(function()
		local ok, err = pcall(fn :: () -> any)
		if not ok then
			log(self, "profile task error: " .. tostring(err))
		end
		self.pending -= 1
	end)
end

local function setStatus(
	self: Manager,
	userId: number,
	entry: Entry,
	status: Status,
	reason: string?
)
	entry.status = status
	entry.reason = reason
	self.StatusChanged:fire(userId, status, reason)
end

local function releaseProfile(self: Manager, userId: number, profile: ProfileStore.Profile)
	self.deps.store:release(profile)
	self.Released:fire(userId)
end

local function runLoad(self: Manager, userId: number, entry: Entry)
	local profile, reason = self.deps.store:load(userId)
	if entry.left or self.closing then
		-- The player left (or the server is closing) while loading: do not keep the lock.
		if profile then
			releaseProfile(self, userId, profile)
		else
			self.Released:fire(userId)
		end
		return
	end
	if profile then
		entry.profile = profile
		setStatus(self, userId, entry, "ready", nil)
		self.Loaded:fire(userId, profile)
	else
		-- Play on with a fresh profile that can never be saved.
		local why = reason or "error"
		log(self, "load for " .. tostring(userId) .. " failed (" .. why .. "): playing offline")
		entry.profile = self.deps.store:offline(userId, why)
		setStatus(self, userId, entry, "offline", why)
		self.Loaded:fire(userId, entry.profile)
	end
end

function ProfileManager.join(self: Manager, userId: number)
	if self.closing then
		return
	end
	local entry: Entry = { status = "loading", profile = nil, reason = nil, left = false }
	self.entries[userId] = entry
	self.StatusChanged:fire(userId, "loading", nil)
	background(self, function()
		runLoad(self, userId, entry)
	end)
end

function ProfileManager.leave(self: Manager, userId: number)
	local entry = self.entries[userId]
	if entry == nil then
		return
	end
	local profile = entry.profile
	if profile and profile.status == "ready" then
		self.Leaving:fire(userId, profile)
	end
	entry.left = true
	self.entries[userId] = nil
	if profile then
		background(self, function()
			releaseProfile(self, userId, profile)
		end)
	end
end

function ProfileManager.status(self: Manager, userId: number): Status
	local entry = self.entries[userId]
	return if entry then entry.status else "none"
end

-- Why the load failed while status is "offline" ("locked", "error", "future", "corrupt",
-- "migration", "busy").
function ProfileManager.failReason(self: Manager, userId: number): string?
	local entry = self.entries[userId]
	return if entry then entry.reason else nil
end

-- The profile to play with: ready or offline. nil while loading, after "lost", or for a stranger.
function ProfileManager.get(self: Manager, userId: number): ProfileStore.Profile?
	local entry = self.entries[userId]
	if
		entry
		and (entry.status == "ready" or entry.status == "offline")
		and entry.profile
		and entry.profile.status == "ready"
	then
		return entry.profile
	end
	return nil
end

-- The live Types.Profile table, or nil. Same rules as get().
function ProfileManager.data(self: Manager, userId: number): Types.Profile?
	local profile = self:get(userId)
	return if profile then profile.data else nil
end

function ProfileManager.isOffline(self: Manager, userId: number): boolean
	local entry = self.entries[userId]
	return entry ~= nil and entry.status == "offline"
end

local function noticeLost(self: Manager, userId: number)
	local entry = self.entries[userId]
	if entry and entry.status == "ready" and entry.profile and entry.profile.status == "lost" then
		setStatus(self, userId, entry, "lost", "lock lost")
	end
end

-- Call after changing the live profile table. Cheap (a flag); the write happens on the autosave
-- timer, on leave, on shutdown or on saveNow.
function ProfileManager.markDirty(self: Manager, userId: number)
	local profile = self:get(userId)
	if profile then
		self.deps.store:markDirty(profile)
	end
end

function ProfileManager.update(
	self: Manager,
	userId: number,
	fn: (Types.Profile) -> boolean?
): (boolean, string?)
	return self.deps.store:update(self:get(userId), fn)
end

function ProfileManager.grantOnce(
	self: Manager,
	userId: number,
	key: string,
	fn: (Types.Profile) -> boolean?
): (boolean, string?)
	return self.deps.store:grantOnce(self:get(userId), key, fn)
end

function ProfileManager.saveSoon(self: Manager, userId: number)
	local profile = self:get(userId)
	if profile then
		self.deps.store:saveSoon(profile)
	end
end

-- Saves now and waits for it (use after a purchase or reward). Nothing to do for an unchanged
-- profile (returns true) and never writes an offline one (returns false). At most one write per
-- minSecondsBetweenWrites: if one just happened this waits out the gap first.
function ProfileManager.saveNow(self: Manager, userId: number): boolean
	local profile = self:get(userId)
	if profile == nil or profile.locked then
		return false
	end
	if not profile.dirty and not profile.wantSave then
		return true
	end
	local gap = self.deps.cfg.minSecondsBetweenWrites - (self.deps.clock() - profile.lastWriteAt)
	if gap > 0 then
		self.deps.wait(gap)
	end
	local ok = self.deps.store:save(profile)
	noticeLost(self, userId)
	return ok
end

-- Called about once a second. Starts a background save for every profile that is due.
function ProfileManager.tick(self: Manager)
	local now = self.deps.clock()
	for userId, entry in self.entries do
		local profile = entry.profile
		if entry.status == "ready" and profile and self.deps.store:due(profile, now) then
			background(self, function()
				self.deps.store:save(profile)
				noticeLost(self, userId)
			end)
		end
	end
end

-- Server closing: release every profile in parallel and wait (up to shutdownSeconds).
function ProfileManager.shutdown(self: Manager)
	self.closing = true
	for userId, entry in self.entries do
		entry.left = true
		local profile = entry.profile
		if profile then
			if profile.status == "ready" then
				self.Leaving:fire(userId, profile)
			end
			background(self, function()
				releaseProfile(self, userId, profile)
			end)
		end
	end
	self.entries = {}
	local started = self.deps.clock()
	while self.pending > 0 and self.deps.clock() - started < self.deps.cfg.shutdownSeconds do
		self.deps.wait(0.1)
	end
	if self.pending > 0 then
		log(self, "shutdown: " .. self.pending .. " profile task(s) did not finish in time")
	end
end

return ProfileManager
