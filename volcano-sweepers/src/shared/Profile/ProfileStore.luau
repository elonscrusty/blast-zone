--!strict
-- Loads, saves and releases one player profile in a DataStore, safely. Pure Luau: the DataStore,
-- clock, waiting and retrying are passed in, so Lune tests it with a fake DataStore.
--
-- What it guarantees:
--   * Session lock. A record carries { lock = { jobId, sid, at } }. Another server's fresh lock
--     stops a load ("locked"). A lock older than lockStaleSeconds (a crashed server) can be taken.
--     Every save checks that the lock is still ours (sid); if not, the profile is "lost" and
--     NOTHING more is written for it.
--   * A profile that did not load is never saved. After a failed load the caller may play with
--     ProfileStore.offline(): a fresh profile with `locked = true`. A locked profile can never be
--     written (and its sid matches no lock anyway), so defaults can never overwrite real progress.
--   * Never loads data from a newer game version ("future") or an unreadable record ("corrupt").
--   * Every write goes through UpdateAsync (merge-safe) and SaveRetry (waits longer each time).
--   * Data is repaired (ProfileSchema.sanitize) and checked (Serializable) before each save.
--   * Writes are rationed: one autosave a minute per player (staggered), plus saveSoon merged to one
--     write per minSecondsBetweenWrites.
--   * One profile per player key at a time in this server (a rejoin waits for the old one to release).

local ProfileSchema = require("./ProfileSchema")
local SaveRetry = require("../SaveRetry")
local Receipts = require("./Receipts")
local Serializable = require("./Serializable")
local Types = require("../Types")

local ProfileStore = {}
ProfileStore.__index = ProfileStore

export type Status = "ready" | "lost" | "released"

export type Profile = {
	key: string,
	userId: number,
	sid: string,
	data: Types.Profile, -- the LIVE table other code reads and changes; call markDirty after
	receipts: Receipts.Book,
	isNew: boolean,
	status: Status,
	-- locked = this profile may NEVER be written (the load failed, so it is a stand-in).
	locked: boolean,
	lockReason: string?, -- why the load failed ("locked", "error", "future", "corrupt", ...)
	dirty: boolean,
	wantSave: boolean,
	saving: boolean,
	lastWriteAt: number,
	autosaveAt: number, -- next autosave time (staggered per player)
	saves: number,
	lastError: string?,
}

export type Cfg = {
	autosaveSeconds: number,
	minSecondsBetweenWrites: number,
	lockStaleSeconds: number,
	loadLockTries: number,
	lockRetrySeconds: number,
	receiptsKept: number,
	failRetrySeconds: number, -- after a failed save, try the autosave again this soon
}

-- The numbers the game runs with. Not in Config on purpose (the saving piece owns them).
ProfileStore.DEFAULT_CFG = {
	autosaveSeconds = 60, -- also refreshes the session lock
	minSecondsBetweenWrites = 6, -- DataStore allows one write per key about every 6 s
	lockStaleSeconds = 180, -- a lock older than this belongs to a crashed server
	loadLockTries = 6, -- how many times a load waits for another server to let go
	lockRetrySeconds = 3,
	receiptsKept = 100, -- newest once-only grant keys remembered per player
	failRetrySeconds = 15,
} :: Cfg

export type Deps = {
	-- UpdateAsync: update(key, transform). transform(old) returns the new value (and optional user
	-- ids), or nil to cancel. Errors are thrown, like the real thing.
	update: (key: string, transform: (any) -> (any, { number }?)) -> any,
	jobId: string,
	clock: () -> number, -- seconds, same on every server (os.time)
	wait: (number) -> (),
	-- SaveRetry.run signature
	retry: (
		fn: () -> any,
		wait: (number) -> any,
		onFail: ((number, string) -> ())?,
		tries: number?
	) -> (boolean, any, string?),
	cfg: Cfg,
	log: ((string) -> ())?,
}

export type Store = typeof(setmetatable(
	{} :: { deps: Deps, active: { [string]: boolean }, counter: number },
	ProfileStore
))

function ProfileStore.new(deps: Deps): Store
	return setmetatable({ deps = deps, active = {}, counter = 0 }, ProfileStore)
end

function ProfileStore.keyFor(userId: number): string
	return "profile_" .. tostring(math.floor(userId))
end

-- How many seconds EARLIER than a full interval this player's first autosave falls. Spreads the
-- players of a server over the minute instead of writing them all at once.
function ProfileStore.stagger(userId: number, autosaveSeconds: number): number
	return (math.floor(math.abs(userId)) % 16) / 16 * autosaveSeconds * 0.5
end

local function log(self: Store, text: string)
	if self.deps.log then
		self.deps.log(text)
	end
end

local function lockFor(self: Store, sid: string)
	return { jobId = self.deps.jobId, sid = sid, at = self.deps.clock() }
end

-- Clears our lock without touching the data. Used when a load fails after it took the lock.
local function unlock(self: Store, key: string, sid: string, userId: number)
	local ok = self.deps.retry(function()
		return self.deps.update(key, function(old: any)
			if type(old) ~= "table" or type(old.lock) ~= "table" or old.lock.sid ~= sid then
				return nil, nil
			end
			local rec = Serializable.copy(old)
			rec.lock = nil
			return rec, { userId }
		end)
	end, self.deps.wait, nil, nil)
	if not ok then
		log(self, "could not clear lock for " .. key .. " (it goes stale by itself)")
	end
end

local function newProfile(
	self: Store,
	userId: number,
	sid: string,
	data: Types.Profile,
	receipts: Receipts.Book,
	isNew: boolean
): Profile
	local now = self.deps.clock()
	local cfg = self.deps.cfg
	return {
		key = ProfileStore.keyFor(userId),
		userId = userId,
		sid = sid,
		data = data,
		receipts = receipts,
		isNew = isNew,
		status = "ready",
		locked = false,
		lockReason = nil,
		dirty = false,
		wantSave = false,
		saving = false,
		lastWriteAt = now,
		autosaveAt = now + cfg.autosaveSeconds - ProfileStore.stagger(userId, cfg.autosaveSeconds),
		saves = 0,
		lastError = nil,
	}
end

-- Returns a Profile, or nil and a reason: "locked", "future", "corrupt", "migration", "error",
-- "busy", "noAccess".
function ProfileStore.load(self: Store, userId: number): (Profile?, string?)
	local deps = self.deps
	local key = ProfileStore.keyFor(userId)

	-- A rejoin must wait for this server's previous profile of the same player to finish saving.
	local waited = 0
	while self.active[key] do
		if waited >= 60 then
			return nil, "busy"
		end
		deps.wait(0.5)
		waited += 1
	end
	self.active[key] = true

	self.counter += 1
	local sid = deps.jobId .. "#" .. tostring(self.counter) .. "@" .. tostring(deps.clock())

	local function fail(reason: string, detail: string?): (Profile?, string?)
		self.active[key] = nil
		if detail then
			log(self, "load " .. key .. " failed (" .. reason .. "): " .. detail)
		end
		return nil, reason
	end

	for attempt = 1, deps.cfg.loadLockTries do
		-- The transform can run more than once; it only writes `outcome` and returns a new value.
		local outcome: { kind: string, record: any?, isNew: boolean? } = { kind = "none" }
		local ok, _, err = deps.retry(
			function()
				return deps.update(key, function(old: any)
					local now = deps.clock()
					if old == nil then
						local rec = {
							v = 1,
							lock = lockFor(self, sid),
							data = ProfileSchema.default(),
							receipts = Receipts.newBook(),
							savedAt = now,
							saves = 0,
						}
						outcome = { kind = "ok", record = rec, isNew = true }
						return Serializable.copy(rec), { userId }
					end
					if type(old) ~= "table" or type(old.data) ~= "table" then
						outcome = { kind = "corrupt" }
						return nil, nil
					end
					local lock = old.lock
					if type(lock) == "table" and lock.jobId ~= deps.jobId then
						local at = if type(lock.at) == "number" then lock.at else 0
						if now - at < deps.cfg.lockStaleSeconds then
							outcome = { kind = "locked" }
							return nil, nil
						end
					end
					local version = old.data.version
					if type(version) == "number" and version > ProfileSchema.CURRENT then
						outcome = { kind = "future" }
						return nil, nil
					end
					local rec = Serializable.copy(old)
					rec.lock = lockFor(self, sid)
					outcome = { kind = "ok", record = rec, isNew = false }
					return Serializable.copy(rec), { userId }
				end)
			end,
			deps.wait,
			function(n: number, e: string)
				log(self, "load " .. key .. " try " .. n .. " failed: " .. e)
			end,
			nil
		)

		if not ok then
			-- "noAccess": API access is off / the place is unpublished. It can never load here, so
			-- nobody should keep trying (ProfileManager retries "error", "locked" and "busy").
			return fail(if SaveRetry.isPermanent(err) then "noAccess" else "error", err)
		end
		if outcome.kind == "locked" then
			if attempt < deps.cfg.loadLockTries then
				deps.wait(deps.cfg.lockRetrySeconds)
			end
		elseif outcome.kind == "ok" then
			local record = outcome.record :: any
			local data, why, changed = ProfileSchema.prepare(record.data)
			if data == nil then
				unlock(self, key, sid, userId)
				return fail("migration", tostring(why))
			end
			local receipts = Receipts.clean(record.receipts, deps.cfg.receiptsKept)
			local profile = newProfile(self, userId, sid, data, receipts, outcome.isNew == true)
			profile.dirty = changed
			return profile, nil
		else
			return fail(outcome.kind, nil)
		end
	end
	return fail("locked", "still locked by another server")
end

-- A stand-in for a player whose load failed: a fresh profile to play with, locked so that it is
-- NEVER written. Holds no session lock and no `active` slot. `reason` is the load failure.
function ProfileStore.offline(self: Store, userId: number, reason: string): Profile
	self.counter += 1
	local profile = newProfile(
		self,
		userId,
		self.deps.jobId .. "#offline" .. tostring(self.counter),
		ProfileSchema.default(),
		Receipts.newBook(),
		true
	)
	profile.locked = true
	profile.lockReason = reason
	return profile
end

-- Marks the profile as changed since the last write. Call after changing profile.data.
function ProfileStore.markDirty(_: Store, profile: Profile)
	profile.dirty = true
end

local function finishRelease(self: Store, profile: Profile)
	profile.status = "released"
	self.active[profile.key] = nil
end

-- Writes the profile. With release = true the lock is cleared and the profile is finished.
-- Returns ok, reason ("locked", "lost", "invalid", "error", "busy", "released").
function ProfileStore.save(self: Store, profile: Profile, release: boolean?): (boolean, string?)
	local deps = self.deps
	if profile.status == "released" then
		return false, "released"
	end
	if profile.status == "lost" then
		return false, "lost"
	end
	if profile.locked then
		-- Never writes. A release of a stand-in only finishes it.
		if release then
			finishRelease(self, profile)
		end
		return false, "locked"
	end
	if profile.saving then
		if not release then
			return false, "busy"
		end
		local waited = 0
		while profile.saving and waited < 60 do
			deps.wait(0.25)
			waited += 1
		end
		if profile.saving then
			return false, "busy"
		end
		if profile.status ~= "ready" then
			return false, profile.status
		end
	end
	profile.saving = true

	-- Other code edits profile.data directly, so repair it first: a NaN or an out-of-range number
	-- becomes a legal one instead of blocking every future save.
	local okShape, shapeWhy = ProfileSchema.isValid(profile.data)
	if not okShape then
		log(self, "repairing " .. profile.key .. " before saving: " .. tostring(shapeWhy))
		ProfileSchema.assign(profile.data :: any, ProfileSchema.sanitize(profile.data) :: any)
	end

	local snapshot = Serializable.copy(profile.data)
	local receiptsSnapshot = Serializable.copy(profile.receipts)
	local valid, why = Serializable.check(snapshot)
	if not valid then
		profile.saving = false
		profile.lastError = why
		log(self, "NOT saving " .. profile.key .. ": " .. tostring(why))
		if release then
			unlock(self, profile.key, profile.sid, profile.userId)
			finishRelease(self, profile)
		end
		return false, "invalid"
	end

	profile.dirty = false
	profile.wantSave = false
	local result = "none"
	local ok, _, err = deps.retry(
		function()
			result = "none"
			return deps.update(profile.key, function(old: any)
				local now = deps.clock()
				if
					type(old) ~= "table"
					or type(old.lock) ~= "table"
					or old.lock.sid ~= profile.sid
				then
					result = "lost"
					return nil, nil
				end
				result = "ok"
				local rec = {
					v = 1,
					lock = if release then nil else lockFor(self, profile.sid),
					data = Serializable.copy(snapshot),
					receipts = Serializable.copy(receiptsSnapshot),
					savedAt = now,
					saves = (if type(old.saves) == "number" then old.saves else 0) + 1,
				}
				return rec, { profile.userId }
			end)
		end,
		deps.wait,
		function(n: number, e: string)
			log(self, "save " .. profile.key .. " try " .. n .. " failed: " .. e)
		end,
		nil
	)

	profile.saving = false
	if not ok then
		profile.dirty = true
		profile.lastError = err
		profile.autosaveAt = deps.clock() + deps.cfg.failRetrySeconds
		if release then
			-- Nothing more can be done here; the lock goes stale by itself.
			finishRelease(self, profile)
			log(self, "RELEASE FAILED for " .. profile.key .. ": " .. tostring(err))
		end
		return false, "error"
	end
	if result == "lost" then
		profile.status = "lost"
		profile.lastError = "lock lost"
		self.active[profile.key] = nil
		log(self, "lock lost for " .. profile.key .. ": no more writes")
		return false, "lost"
	end
	local now = deps.clock()
	profile.lastWriteAt = now
	profile.autosaveAt = now + deps.cfg.autosaveSeconds
	profile.saves += 1
	profile.lastError = nil
	if release then
		finishRelease(self, profile)
	end
	return true, nil
end

-- Final save, clears the lock. Safe to call twice.
function ProfileStore.release(self: Store, profile: Profile): (boolean, string?)
	if profile.status == "released" then
		return true, nil
	end
	if profile.status == "lost" then
		self.active[profile.key] = nil
		return false, "lost"
	end
	return self:save(profile, true)
end

-- Ask for a save soon (merged and rationed by `due`).
function ProfileStore.saveSoon(_: Store, profile: Profile)
	profile.dirty = true
	profile.wantSave = true
end

-- Does the autosave loop need to write this profile now?
function ProfileStore.due(self: Store, profile: Profile, now: number): boolean
	if profile.status ~= "ready" or profile.saving or profile.locked then
		return false
	end
	-- Even a clean profile is written once a minute: it refreshes the lock so it never looks stale.
	if now >= profile.autosaveAt then
		return true
	end
	return profile.wantSave and now - profile.lastWriteAt >= self.deps.cfg.minSecondsBetweenWrites
end

local function commit(self: Store, profile: Profile, copy: Types.Profile): (boolean, string?)
	local valid, why = ProfileSchema.isValid(copy)
	if valid then
		valid, why = Serializable.check(copy)
	end
	if not valid then
		log(self, "rejected change for " .. profile.key .. ": " .. tostring(why))
		return false, "invalid"
	end
	ProfileSchema.assign(profile.data :: any, copy :: any) -- same table: others hold it
	profile.dirty = true
	return true, nil
end

-- Runs fn on a copy of the data. Applied only if fn does not error, does not return false, and the
-- result is a valid saveable profile. Returns ok, reason ("notLoaded", "rejected", "error", "invalid").
function ProfileStore.update(
	self: Store,
	profile: Profile?,
	fn: (Types.Profile) -> boolean?
): (boolean, string?)
	if profile == nil or profile.status ~= "ready" then
		return false, "notLoaded"
	end
	local copy = Serializable.copy(profile.data)
	local ok, res = pcall(fn, copy)
	if not ok then
		log(self, "update error for " .. profile.key .. ": " .. tostring(res))
		return false, "error"
	end
	if res == false then
		return false, "rejected"
	end
	return commit(self, profile, copy)
end

-- Like update, but pays only once per receipt key. "duplicate" means it was already paid. The
-- receipt is written in the same save as the change.
function ProfileStore.grantOnce(
	self: Store,
	profile: Profile?,
	key: string,
	fn: (Types.Profile) -> boolean?
): (boolean, string?)
	if profile == nil or profile.status ~= "ready" then
		return false, "notLoaded"
	end
	if not Receipts.isValidKey(key) then
		return false, "badKey"
	end
	if Receipts.has(profile.receipts, key) then
		return false, "duplicate"
	end
	local copy = Serializable.copy(profile.data)
	local ok, res = pcall(fn, copy)
	if not ok then
		log(self, "grant error for " .. profile.key .. ": " .. tostring(res))
		return false, "error"
	end
	if res == false then
		return false, "rejected"
	end
	local committed, why = commit(self, profile, copy)
	if not committed then
		return false, why
	end
	Receipts.add(profile.receipts, key, self.deps.clock(), self.deps.cfg.receiptsKept)
	return true, nil
end

return ProfileStore
