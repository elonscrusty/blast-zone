--!strict
-- The life of every player's profile on this server, by userId: load on join, autosave, save on
-- leave, release on shutdown. Pure Luau (store, spawning, waiting and signals are passed in), so
-- the whole join / leave / retry flow is tested in Lune. The Roblox side is only a thin wrapper
-- (server/Profile/Profiles).
--
-- Status of a player: "loading" | "ready" | "failed" | "lost" ("none" = never joined).
--   ready   Profile loaded, writes allowed.
--   failed  Load did not work. There is NO profile and no fallback: get() is nil, every write
--           returns false ("notLoaded"). retryLoad() may try again (not for "future"/"corrupt").
--   lost    Another server took this profile over. Nothing more is written for it.

local ProfileStore = require("./ProfileStore")

local ProfileManager = {}
ProfileManager.__index = ProfileManager

export type Status = "none" | "loading" | "ready" | "failed" | "lost"

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
		Loaded: any, -- (userId, profile)
		Released: any, -- (userId)
		StatusChanged: any, -- (userId, status, reason?)
	},
	ProfileManager
))

local RETRYABLE: { [string]: boolean } = { locked = true, error = true, busy = true }

function ProfileManager.new(deps: Deps): Manager
	return setmetatable({
		deps = deps,
		entries = {},
		pending = 0,
		closing = false,
		Loaded = deps.newSignal(),
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
		end
		return
	end
	if profile then
		entry.profile = profile
		setStatus(self, userId, entry, "ready", nil)
		self.Loaded:fire(userId, profile)
	else
		setStatus(self, userId, entry, "failed", reason)
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
	entry.left = true
	self.entries[userId] = nil
	local profile = entry.profile
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

-- Why the last load failed ("locked", "error", "future", "corrupt", "migration", "busy").
function ProfileManager.failReason(self: Manager, userId: number): string?
	local entry = self.entries[userId]
	return if entry then entry.reason else nil
end

function ProfileManager.get(self: Manager, userId: number): ProfileStore.Profile?
	local entry = self.entries[userId]
	if entry and entry.status == "ready" and entry.profile and entry.profile.status == "ready" then
		return entry.profile
	end
	return nil
end

-- Try loading again after a temporary failure. Returns true if a new load started.
function ProfileManager.retryLoad(self: Manager, userId: number): boolean
	local entry = self.entries[userId]
	if self.closing or entry == nil or entry.status ~= "failed" then
		return false
	end
	if not RETRYABLE[entry.reason or ""] then
		return false
	end
	setStatus(self, userId, entry, "loading", nil)
	background(self, function()
		runLoad(self, userId, entry)
	end)
	return true
end

local function noticeLost(self: Manager, userId: number)
	local entry = self.entries[userId]
	if entry and entry.status == "ready" and entry.profile and entry.profile.status == "lost" then
		setStatus(self, userId, entry, "lost", "lock lost")
	end
end

function ProfileManager.update(
	self: Manager,
	userId: number,
	fn: ({ [string]: any }) -> boolean?
): (boolean, string?)
	return self.deps.store:update(self:get(userId), fn)
end

function ProfileManager.grantOnce(
	self: Manager,
	userId: number,
	key: string,
	fn: ({ [string]: any }) -> boolean?
): (boolean, string?)
	return self.deps.store:grantOnce(self:get(userId), key, fn)
end

local function isAllowedFlag(self: Manager, name: any): boolean
	return type(name) == "string" and table.find(self.deps.cfg.flags, name) ~= nil
end

function ProfileManager.getFlag(self: Manager, userId: number, name: string): boolean?
	local profile = self:get(userId)
	if profile == nil then
		return nil
	end
	local flags = profile.data.flags
	return type(flags) == "table" and flags[name] == true
end

function ProfileManager.setFlag(
	self: Manager,
	userId: number,
	name: string,
	value: boolean
): (boolean, string?)
	if not isAllowedFlag(self, name) then
		return false, "unknownFlag"
	end
	return self.deps.store:update(self:get(userId), function(data)
		if type(data.flags) ~= "table" then
			data.flags = {}
		end
		data.flags[name] = if value then true else nil
		return true
	end)
end

-- A copy of the flags, or nil when not ready.
function ProfileManager.flags(self: Manager, userId: number): { [string]: boolean }?
	local profile = self:get(userId)
	if profile == nil then
		return nil
	end
	local out: { [string]: boolean } = {}
	local flags = profile.data.flags
	if type(flags) == "table" then
		for k, v in flags do
			if v == true then
				out[k] = true
			end
		end
	end
	return out
end

function ProfileManager.saveSoon(self: Manager, userId: number)
	local profile = self:get(userId)
	if profile then
		self.deps.store:saveSoon(profile)
	end
end

-- Saves now and waits for it (use after a reward or purchase). At most one write per
-- minSecondsBetweenWrites: if one just happened this waits out the gap first.
function ProfileManager.saveNow(self: Manager, userId: number): boolean
	local profile = self:get(userId)
	if profile == nil then
		return false
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
			background(self, function()
				releaseProfile(self, userId, profile)
			end)
		end
	end
	self.entries = {}
	local waited = 0
	while self.pending > 0 and waited < self.deps.cfg.shutdownSeconds * 10 do
		self.deps.wait(0.1)
		waited += 1
	end
	if self.pending > 0 then
		log(self, "shutdown: " .. self.pending .. " profile task(s) did not finish in time")
	end
end

return ProfileManager
