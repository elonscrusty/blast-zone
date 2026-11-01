--!strict
-- Loads, saves and releases one player profile in a DataStore, safely. Pure Luau: the DataStore,
-- clock, waiting and retrying are passed in, so Lune tests it with a fake DataStore.
--
-- What it guarantees:
--   * Session lock. A record carries { lock = { jobId, sid, at } }. Another server's fresh lock
--     stops a load ("locked"). A lock older than lockStaleSeconds (a crashed server) can be taken.
--     Every save checks that the lock is still ours (sid); if not, the profile is "lost" and
--     NOTHING more is written for it.
--   * A profile that did not load is never saved. There is no "default profile" fallback: a failed
--     load gives no profile at all, so defaults can never overwrite real progress.
--   * Never loads data from a newer game version ("future") or an unreadable record ("corrupt").
--   * Every write goes through UpdateAsync (merge-safe) and SaveRetry (waits longer each time).
--   * Data is checked (Serializable) before each save; a bad value blocks the save and is reported.
--   * Writes are rationed: autosave, plus saveSoon merged to one write per minSecondsBetweenWrites.
--   * One profile per player key at a time in this server (a rejoin waits for the old one to release).

local ProfileSchema = require("./ProfileSchema")
local Receipts = require("./Receipts")
local Serializable = require("./Serializable")

local ProfileStore = {}
ProfileStore.__index = ProfileStore

export type Status = "ready" | "lost" | "released"

export type Profile = {
	key: string,
	userId: number,
	sid: string,
	data: { [string]: any },
	isNew: boolean,
	status: Status,
	dirty: boolean,
	wantSave: boolean,
	saving: boolean,
	lastWriteAt: number,
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
	flags: { string },
}

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

-- Returns a Profile, or nil and a reason: "locked", "future", "corrupt", "migration", "error", "busy".
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
							data = ProfileSchema.defaults(),
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
					local version = old.data.schemaVersion
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
			return fail("error", err)
		end
		if outcome.kind == "locked" then
			if attempt < deps.cfg.loadLockTries then
				deps.wait(deps.cfg.lockRetrySeconds)
			end
		elseif outcome.kind == "ok" then
			local record = outcome.record :: any
			local data = Serializable.copy(record.data) :: { [string]: any }
			local prepared, info, changed = ProfileSchema.prepare(data)
			if not prepared then
				unlock(self, key, sid, userId)
				return fail("migration", tostring(info))
			end
			if #(info :: { string }) > 0 then
				log(self, "repaired fields for " .. key .. ": " .. table.concat(info :: any, ", "))
			end
			local profile: Profile = {
				key = key,
				userId = userId,
				sid = sid,
				data = data,
				isNew = outcome.isNew == true,
				status = "ready",
				dirty = changed,
				wantSave = false,
				saving = false,
				lastWriteAt = deps.clock(),
				saves = 0,
				lastError = nil,
			}
			return profile, nil
		else
			return fail(outcome.kind, nil)
		end
	end
	return fail("locked", "still locked by another server")
end

-- Writes the profile. With release = true the lock is cleared and the profile is finished.
-- Returns ok, reason ("lost", "invalid", "error", "busy", "released").
function ProfileStore.save(self: Store, profile: Profile, release: boolean?): (boolean, string?)
	local deps = self.deps
	if profile.status == "released" then
		return false, "released"
	end
	if profile.status == "lost" then
		return false, "lost"
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

	local snapshot = Serializable.copy(profile.data)
	local valid, why = Serializable.check(snapshot)
	if not valid then
		profile.saving = false
		profile.lastError = why
		log(self, "NOT saving " .. profile.key .. ": " .. tostring(why))
		if release then
			unlock(self, profile.key, profile.sid, profile.userId)
			profile.status = "released"
			self.active[profile.key] = nil
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
		if release then
			-- Nothing more can be done here; the lock goes stale by itself.
			profile.status = "released"
			self.active[profile.key] = nil
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
	profile.lastWriteAt = deps.clock()
	profile.saves += 1
	profile.lastError = nil
	if release then
		profile.status = "released"
		self.active[profile.key] = nil
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
	profile.wantSave = true
end

-- Does the autosave loop need to write this profile now?
function ProfileStore.due(self: Store, profile: Profile, now: number): boolean
	if profile.status ~= "ready" or profile.saving then
		return false
	end
	local cfg = self.deps.cfg
	local since = now - profile.lastWriteAt
	if profile.wantSave and since >= cfg.minSecondsBetweenWrites then
		return true
	end
	-- Even a clean profile is written now and then: it refreshes the lock so it never looks stale.
	return since >= cfg.autosaveSeconds
end

local function commit(self: Store, profile: Profile, copy: { [string]: any }): (boolean, string?)
	local valid, why = Serializable.check(copy)
	if not valid then
		log(self, "rejected change for " .. profile.key .. ": " .. tostring(why))
		return false, "invalid"
	end
	profile.data = copy
	profile.dirty = true
	return true, nil
end

-- Runs fn on a copy of the data. Applied only if fn does not error, does not return false, and the
-- result can be saved. Returns ok, reason ("notLoaded", "rejected", "error", "invalid").
function ProfileStore.update(
	self: Store,
	profile: Profile?,
	fn: ({ [string]: any }) -> boolean?
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

-- Like update, but pays only once per receipt key. "duplicate" means it was already paid.
function ProfileStore.grantOnce(
	self: Store,
	profile: Profile?,
	key: string,
	fn: ({ [string]: any }) -> boolean?
): (boolean, string?)
	if profile == nil or profile.status ~= "ready" then
		return false, "notLoaded"
	end
	if not Receipts.isValidKey(key) then
		return false, "badKey"
	end
	if Receipts.has(profile.data, key) then
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
	Receipts.add(copy, key, self.deps.clock(), self.deps.cfg.receiptsKept)
	return commit(self, profile, copy)
end

return ProfileStore
