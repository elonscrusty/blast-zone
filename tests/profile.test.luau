--!strict
-- Saving tests: schema, once-only grants, session lock, failures, and the whole join / leave /
-- retry flow, all against a fake DataStore. No real DataStore is touched.

local Harness = require("./harness")
local Fake = require("./fake_datastore")
local Config = require("../src/shared/Config")
local SaveRetry = require("../src/shared/SaveRetry")
local Signal = require("../src/shared/Signal")
local Serializable = require("../src/shared/Profile/Serializable")
local Receipts = require("../src/shared/Profile/Receipts")
local ProfileSchema = require("../src/shared/Profile/ProfileSchema")
local ProfileStore = require("../src/shared/Profile/ProfileStore")
local ProfileManager = require("../src/shared/Profile/ProfileManager")

local eq, truthy = Harness.eq, Harness.truthy

-- One shared fake clock for every "server" in a test.
local now = 1000
local waited = 0
local function clock(): number
	return now
end
local function wait(s: number)
	waited += s
	now += s -- waiting moves time, like real life
end

local logs: { string } = {}

local function newStore(fake: Fake.FakeStore, jobId: string): ProfileStore.Store
	return ProfileStore.new({
		update = function(key: string, transform: (any) -> (any, { number }?))
			return fake:update(key, transform)
		end,
		jobId = jobId,
		clock = clock,
		wait = wait,
		retry = SaveRetry.run,
		cfg = Config.Profile,
		log = function(t: string)
			table.insert(logs, t)
		end,
	})
end

local function reset()
	now = 1000
	waited = 0
	logs = {}
end

local KEY = ProfileStore.keyFor(7)

local function loadOk(store: ProfileStore.Store, userId: number): ProfileStore.Profile
	local profile, reason = store:load(userId)
	if profile == nil then
		error("load failed: " .. tostring(reason))
	end
	return profile
end

-- ===== pure pieces =====

Harness.test(
	"serializable: accepts plain data, rejects NaN, inf, functions, mixed and looping tables",
	function()
		truthy((Serializable.check({ a = 1, b = { 1, 2, 3 }, c = "hi", d = true })))
		eq((Serializable.check({ a = 0 / 0 })), false)
		eq((Serializable.check({ a = math.huge })), false)
		eq((Serializable.check({ f = function() end })), false)
		eq((Serializable.check({ 1, 2, x = 3 })), false)
		eq((Serializable.check({ [1] = "a", [3] = "c" })), false, "sparse array")
		local loop: { [string]: any } = {}
		loop.me = loop
		eq((Serializable.check(loop)), false)
		local _, why = Serializable.check({ progression = { coins = 0 / 0 } })
		truthy(why and string.find(why, "progression.coins", 1, true), "reason names the field")
	end
)

Harness.test("receipts: has/add, newest kept, valid keys, match key includes the server", function()
	local data: { [string]: any } = { receipts = {} }
	for i = 1, 5 do
		Receipts.add(data, "k" .. i, 100 + i, 3)
	end
	eq(Receipts.has(data, "k5"), true)
	eq(Receipts.has(data, "k3"), true)
	eq(Receipts.has(data, "k2"), false, "oldest forgotten")
	eq(Receipts.has(data, "k1"), false)
	eq(Receipts.isValidKey("m:abc-123:4"), true)
	eq(Receipts.isValidKey(""), false)
	eq(Receipts.isValidKey("bad key!"), false)
	eq(Receipts.isValidKey(string.rep("a", 101)), false)
	eq(
		Receipts.matchKey("job-A", 1) == Receipts.matchKey("job-B", 1),
		false,
		"matchId 1 on two servers differs"
	)
	eq(Receipts.matchKey("job-A", 1), Receipts.matchKey("job-A", 1))
end)

Harness.test("schema: defaults are fresh copies with the version and every section", function()
	local a, b = ProfileSchema.defaults(), ProfileSchema.defaults()
	a.progression.coins = 5
	eq(b.progression.coins, 0)
	eq(a.schemaVersion, ProfileSchema.CURRENT)
	for _, k in { "progression", "loadout", "flags", "receipts" } do
		eq(type(b[k]), "table", k)
	end
end)

Harness.test("schema: missing keys filled, unknown keys and unknown item ids kept", function()
	local data: { [string]: any } = {
		schemaVersion = 1,
		progression = { coins = 50, unlocked = { removed_item = true } },
		extraThing = 9,
	}
	local ok, repairs, changed = ProfileSchema.prepare(data)
	eq(ok, true)
	eq(changed, true)
	eq(#repairs, 0)
	eq(data.progression.coins, 50)
	eq(data.progression.totalEarned, 0)
	eq(data.progression.unlocked.removed_item, true, "unknown id kept")
	eq(data.extraThing, 9)
	eq(type(data.flags), "table")
end)

Harness.test("schema: wrong-typed field repaired and reported", function()
	local data: { [string]: any } = { schemaVersion = 1, progression = { coins = "lots" } }
	local ok, repairs = ProfileSchema.prepare(data)
	eq(ok, true)
	eq(data.progression.coins, 0)
	eq(repairs[1], "progression.coins")
end)

Harness.test(
	"schema: a profile with no version is upgraded; a newer one is refused untouched",
	function()
		local old: { [string]: any } = { progression = { coins = 3 } }
		local ok = ProfileSchema.prepare(old)
		eq(ok, true)
		eq(old.schemaVersion, ProfileSchema.CURRENT)
		eq(old.progression.coins, 3)

		local future: { [string]: any } =
			{ schemaVersion = ProfileSchema.CURRENT + 1, progression = { coins = 9 } }
		local ok2, why = ProfileSchema.prepare(future)
		eq(ok2, false)
		eq(why, "future")
		eq(future.progression.coins, 9)
		eq(future.schemaVersion, ProfileSchema.CURRENT + 1)
	end
)

Harness.test("schema: a migration step runs in order (v1 -> v2 -> v3)", function()
	local data: { [string]: any } = { schemaVersion = 1, order = "" }
	local steps: ProfileSchema.Steps = {
		[1] = function(d)
			d.order ..= "a"
		end,
		[2] = function(d)
			d.order ..= "b"
		end,
	}
	local ok = ProfileSchema.prepare(data, 3, steps, { order = "" })
	eq(ok, true)
	eq(data.order, "ab")
	eq(data.schemaVersion, 3)
	local missing: { [string]: any } = { schemaVersion = 1 }
	local ok2, why = ProfileSchema.prepare(missing, 3, {}, {})
	eq(ok2, false)
	eq(why, "noStep")
end)

Harness.test("schema: item renames move unlocked and equipped ids", function()
	local data: { [string]: any } = {
		schemaVersion = 1,
		progression = { unlocked = { old_skin = true }, equipped = { skin = "old_skin" } },
	}
	local ok = ProfileSchema.prepare(data, 1, nil, nil, { old_skin = "new_skin" })
	eq(ok, true)
	eq(data.progression.unlocked.new_skin, true)
	eq(data.progression.unlocked.old_skin, nil)
	eq(data.progression.equipped.skin, "new_skin")
end)

Harness.test("schema: item ids are stable text", function()
	eq(ProfileSchema.isItemId("crash_dummy"), true)
	eq(ProfileSchema.isItemId("Crash Dummy"), false)
	eq(ProfileSchema.isItemId(3), false)
	eq(ProfileSchema.isItemId(""), false)
end)

-- ===== store =====

Harness.test(
	"store: new player gets defaults, is written with our lock, and is not dirty",
	function()
		reset()
		local fake = Fake.new()
		local store = newStore(fake, "A")
		local p = loadOk(store, 7)
		eq(p.isNew, true)
		eq(p.data.progression.coins, 0)
		eq(p.dirty, false)
		local raw = fake:raw(KEY)
		eq(raw.lock.jobId, "A")
		eq(raw.data.schemaVersion, ProfileSchema.CURRENT)
	end
)

Harness.test("store: saved progress comes back after leave and rejoin", function()
	reset()
	local fake = Fake.new()
	local store = newStore(fake, "A")
	local p = loadOk(store, 7)
	local ok = store:update(p, function(d)
		d.progression.coins = 120
		d.progression.unlocked.crash_dummy = true
		return true
	end)
	eq(ok, true)
	eq(p.dirty, true)
	eq(store:release(p), true)
	eq(p.status, "released")
	eq(fake:raw(KEY).lock, nil, "lock cleared on leave")

	local again = loadOk(store, 7)
	eq(again.isNew, false)
	eq(again.data.progression.coins, 120)
	eq(again.data.progression.unlocked.crash_dummy, true)
end)

Harness.test("store: update is all-or-nothing (error, false and NaN change nothing)", function()
	reset()
	local fake = Fake.new()
	local store = newStore(fake, "A")
	local p = loadOk(store, 7)
	local ok1, r1 = store:update(p, function(d)
		d.progression.coins = 99
		error("boom")
	end)
	eq(ok1, false)
	eq(r1, "error")
	local ok2, r2 = store:update(p, function(d)
		d.progression.coins = 99
		return false
	end)
	eq(ok2, false)
	eq(r2, "rejected")
	local ok3, r3 = store:update(p, function(d)
		d.progression.coins = 0 / 0
		return true
	end)
	eq(ok3, false)
	eq(r3, "invalid")
	eq(p.data.progression.coins, 0)
	eq(p.dirty, false)
end)

Harness.test("store: update on no profile says notLoaded", function()
	reset()
	local store = newStore(Fake.new(), "A")
	local ok, why = store:update(nil, function()
		return true
	end)
	eq(ok, false)
	eq(why, "notLoaded")
end)

Harness.test("store: grantOnce pays once per key, even after save and reload", function()
	reset()
	local fake = Fake.new()
	local store = newStore(fake, "A")
	local p = loadOk(store, 7)
	local key = Receipts.matchKey("A", 1)
	local function pay(d: { [string]: any }): boolean?
		d.progression.coins += 40
		return true
	end
	eq((store:grantOnce(p, key, pay)), true)
	local ok, why = store:grantOnce(p, key, pay)
	eq(ok, false)
	eq(why, "duplicate")
	eq(p.data.progression.coins, 40)
	eq((store:grantOnce(p, Receipts.matchKey("A", 2), pay)), true, "next match pays")
	eq(p.data.progression.coins, 80)
	store:release(p)
	local again = loadOk(store, 7)
	local ok2, why2 = store:grantOnce(again, key, pay)
	eq(ok2, false, "receipt survived the save")
	eq(why2, "duplicate")
	eq(again.data.progression.coins, 80)
end)

Harness.test("store: a refused grant leaves no receipt (can be paid later)", function()
	reset()
	local store = newStore(Fake.new(), "A")
	local p = loadOk(store, 7)
	local ok = store:grantOnce(p, "k1", function()
		return false
	end)
	eq(ok, false)
	eq(Receipts.has(p.data, "k1"), false)
	local ok2 = store:grantOnce(p, "k1", function(d)
		d.progression.coins = 5
		return true
	end)
	eq(ok2, true)
end)

Harness.test("store: grantOnce rejects bad keys", function()
	reset()
	local store = newStore(Fake.new(), "A")
	local p = loadOk(store, 7)
	local ok, why = store:grantOnce(p, "bad key", function()
		return true
	end)
	eq(ok, false)
	eq(why, "badKey")
end)

Harness.test(
	"lock: a second server cannot load a fresh lock and never changes the record",
	function()
		reset()
		local fake = Fake.new()
		local a = newStore(fake, "A")
		local b = newStore(fake, "B")
		local pa = loadOk(a, 7)
		a:update(pa, function(d)
			d.progression.coins = 10
			return true
		end)
		a:save(pa)
		local before = fake:raw(KEY)
		local pb, reason = b:load(7)
		eq(pb, nil)
		eq(reason, "locked")
		eq(waited >= Config.Profile.lockRetrySeconds, true, "it waited and tried again")
		local after = fake:raw(KEY)
		eq(after.data.progression.coins, 10)
		eq(after.lock.jobId, "A")
		eq(after.saves, before.saves, "failed load wrote nothing")
		eq(b.active[KEY], nil)
	end
)

Harness.test("lock: leaving server A lets server B in during B's retries", function()
	reset()
	local fake = Fake.new()
	local a = newStore(fake, "A")
	local pa = loadOk(a, 7)
	a:update(pa, function(d)
		d.progression.coins = 33
		return true
	end)
	-- A lets go while B is waiting: the third wait of B triggers the release.
	local count = 0
	local b = ProfileStore.new({
		update = function(key: string, transform: (any) -> (any, { number }?))
			return fake:update(key, transform)
		end,
		jobId = "B",
		clock = clock,
		wait = function(s: number)
			wait(s)
			count += 1
			if count == 2 then
				a:release(pa)
			end
		end,
		retry = SaveRetry.run,
		cfg = Config.Profile,
	})
	local pb = loadOk(b, 7)
	eq(pb.data.progression.coins, 33)
end)

Harness.test(
	"lock: a stale lock (crashed server) can be taken over; the old owner is then locked out",
	function()
		reset()
		local fake = Fake.new()
		local a = newStore(fake, "A")
		local b = newStore(fake, "B")
		local pa = loadOk(a, 7)
		a:update(pa, function(d)
			d.progression.coins = 5
			return true
		end)
		a:save(pa)
		now += Config.Profile.lockStaleSeconds + 1 -- A stops refreshing (frozen server)
		local pb = loadOk(b, 7)
		eq(pb.data.progression.coins, 5)

		-- A wakes up and tries to save an old state: must NOT overwrite B.
		a:update(pa, function(d)
			d.progression.coins = 9999
			return true
		end)
		local ok, why = a:save(pa)
		eq(ok, false)
		eq(why, "lost")
		eq(pa.status, "lost")
		eq(fake:raw(KEY).data.progression.coins, 5)
		local writesBefore = fake.writes
		eq((a:save(pa)), false)
		eq((a:release(pa)), false)
		eq(fake.writes, writesBefore, "a lost profile writes nothing more")
		eq(fake:raw(KEY).lock.jobId, "B")
	end
)

Harness.test("lock: autosave refreshes the lock so a live server never looks stale", function()
	reset()
	local fake = Fake.new()
	local a = newStore(fake, "A")
	local b = newStore(fake, "B")
	local pa = loadOk(a, 7)
	for _ = 1, 6 do
		now += Config.Profile.autosaveSeconds
		eq(a:due(pa, now), true)
		eq((a:save(pa)), true)
	end
	-- 6 minutes passed in total, but the lock is only seconds old.
	local pb = b:load(7)
	eq(pb, nil)
end)

Harness.test(
	"load: a failed load gives NO profile and writes nothing (defaults never overwrite)",
	function()
		reset()
		local fake = Fake.new()
		local seed = newStore(fake, "A")
		local p = loadOk(seed, 7)
		seed:update(p, function(d)
			d.progression.coins = 777
			return true
		end)
		seed:release(p)
		local writes = fake.writes
		local store = newStore(fake, "B")
		fake:failNext(99)
		local got, reason = store:load(7)
		eq(got, nil)
		eq(reason, "error")
		fake:failNext(0)
		eq(fake.writes, writes)
		eq(fake:raw(KEY).data.progression.coins, 777)
		eq(store.active[KEY], nil)
		-- and loading works again after the outage
		eq(loadOk(store, 7).data.progression.coins, 777)
	end
)

Harness.test("load: a short outage is retried with growing waits and then succeeds", function()
	reset()
	local fake = Fake.new()
	local store = newStore(fake, "A")
	fake:failNext(2)
	local p = loadOk(store, 7)
	eq(p.isNew, true)
	eq(waited, 2 + 4, "waited 2 s then 4 s")
end)

Harness.test("load: API access off (403) stops at once", function()
	reset()
	local fake = Fake.new()
	fake:failNext(99, "403: Studio access to APIs is not allowed")
	local store = newStore(fake, "A")
	local p, reason = store:load(7)
	eq(p, nil)
	eq(reason, "error")
	eq(fake.calls, 1)
end)

Harness.test("load: data from a newer game version is refused and left alone", function()
	reset()
	local fake = Fake.new()
	local original =
		{ v = 1, data = { schemaVersion = ProfileSchema.CURRENT + 1, progression = { coins = 5 } } }
	fake:setRaw(KEY, original)
	local store = newStore(fake, "A")
	local p, reason = store:load(7)
	eq(p, nil)
	eq(reason, "future")
	local raw = fake:raw(KEY)
	eq(raw.lock, nil, "did not even take the lock")
	eq(raw.data.schemaVersion, ProfileSchema.CURRENT + 1)
	eq(fake.writes, 0)
end)

Harness.test("load: an unreadable record is refused and left alone", function()
	reset()
	local fake = Fake.new()
	fake:setRaw(KEY, { v = 1, nonsense = true })
	local store = newStore(fake, "A")
	local p, reason = store:load(7)
	eq(p, nil)
	eq(reason, "corrupt")
	eq(fake.writes, 0)
end)

Harness.test(
	"load: an old version is migrated, marked dirty, and saved on the next write",
	function()
		reset()
		local fake = Fake.new()
		fake:setRaw(KEY, { v = 1, saves = 3, data = { progression = { coins = 40 } } })
		local store = newStore(fake, "A")
		local p = loadOk(store, 7)
		eq(p.isNew, false)
		eq(p.dirty, true)
		eq(p.data.progression.coins, 40)
		eq(p.data.schemaVersion, ProfileSchema.CURRENT)
		store:save(p)
		local raw = fake:raw(KEY)
		eq(raw.data.schemaVersion, ProfileSchema.CURRENT)
		eq(raw.data.progression.totalEarned, 0)
		eq(raw.saves, 4)
	end
)

Harness.test(
	"save: failing writes keep the profile dirty and retry later; data is not lost",
	function()
		reset()
		local fake = Fake.new()
		local store = newStore(fake, "A")
		local p = loadOk(store, 7)
		store:update(p, function(d)
			d.progression.coins = 8
			return true
		end)
		fake:failNext(99)
		local ok, why = store:save(p)
		eq(ok, false)
		eq(why, "error")
		eq(p.dirty, true)
		eq(p.status, "ready")
		fake:failNext(0)
		eq((store:save(p)), true)
		eq(fake:raw(KEY).data.progression.coins, 8)
	end
)

Harness.test(
	"save: bad data blocks the save but the last good copy stays; release still clears the lock",
	function()
		reset()
		local fake = Fake.new()
		local store = newStore(fake, "A")
		local p = loadOk(store, 7)
		store:update(p, function(d)
			d.progression.coins = 4
			return true
		end)
		store:save(p)
		-- Something writes data directly, bypassing update:
		p.data.progression.coins = 0 / 0
		local ok, why = store:save(p)
		eq(ok, false)
		eq(why, "invalid")
		eq(fake:raw(KEY).data.progression.coins, 4)
		truthy(#logs > 0, "reported")
		store:release(p)
		eq(fake:raw(KEY).lock, nil)
		eq(fake:raw(KEY).data.progression.coins, 4)
	end
)

Harness.test("save: writes are rationed (due only after the gap; autosave when quiet)", function()
	reset()
	local store = newStore(Fake.new(), "A")
	local p = loadOk(store, 7)
	eq(store:due(p, now), false)
	store:saveSoon(p)
	eq(store:due(p, now), false, "too soon after the last write")
	eq(store:due(p, now + Config.Profile.minSecondsBetweenWrites), true)
	store:save(p)
	eq(p.wantSave, false)
	eq(store:due(p, now + Config.Profile.autosaveSeconds - 1), false)
	eq(store:due(p, now + Config.Profile.autosaveSeconds), true)
end)

Harness.test(
	"store: two profiles for one player never overlap (a rejoin waits for the release)",
	function()
		reset()
		local fake = Fake.new()
		local store: ProfileStore.Store
		local first: ProfileStore.Profile? = nil
		local released = false
		store = ProfileStore.new({
			update = function(key: string, transform: (any) -> (any, { number }?))
				return fake:update(key, transform)
			end,
			jobId = "A",
			clock = clock,
			wait = function(s: number)
				wait(s)
				-- The old profile finishes saving while the new load is waiting.
				if first and not released then
					released = true
					store:release(first)
				end
			end,
			retry = SaveRetry.run,
			cfg = Config.Profile,
		})
		first = loadOk(store, 7)
		store:update(first, function(d)
			d.progression.coins = 21
			return true
		end)
		local second = store:load(7)
		eq(released, true, "the new load waited")
		truthy(second, "then loaded")
		eq((second :: ProfileStore.Profile).data.progression.coins, 21)
	end
)

-- ===== manager: the whole flow =====

local function newManager(fake: Fake.FakeStore, jobId: string)
	local store = newStore(fake, jobId)
	local manager = ProfileManager.new({
		store = store,
		spawn = function(fn: () -> ())
			fn()
		end,
		wait = wait,
		clock = clock,
		newSignal = Signal.new,
		cfg = Config.Profile,
		log = function(t: string)
			table.insert(logs, t)
		end,
	})
	return manager, store
end

Harness.test("flow: join, earn, leave, rejoin keeps progress", function()
	reset()
	local fake = Fake.new()
	local m = newManager(fake, "A")
	local loaded = 0
	m.Loaded:connect(function()
		loaded += 1
	end)
	eq(m:status(7), "none")
	m:join(7)
	eq(m:status(7), "ready")
	eq(loaded, 1)
	eq((m:update(7, function(d)
		d.progression.coins = 250
		return true
	end)), true)
	local released = 0
	m.Released:connect(function()
		released += 1
	end)
	m:leave(7)
	eq(released, 1)
	eq(m:get(7), nil)
	eq(fake:raw(KEY).lock, nil)
	m:join(7)
	eq(m:get(7).data.progression.coins, 250)
end)

Harness.test(
	"flow: failed load means no profile and every write refused; retry works once the store is back",
	function()
		reset()
		local fake = Fake.new()
		local seed = newStore(fake, "Z")
		local sp = loadOk(seed, 7)
		seed:update(sp, function(d)
			d.progression.coins = 60
			return true
		end)
		seed:release(sp)
		local writes = fake.writes

		local m = newManager(fake, "A")
		local statuses: { string } = {}
		m.StatusChanged:connect(function(_, s: string)
			table.insert(statuses, s)
		end)
		fake:failNext(99)
		m:join(7)
		eq(m:status(7), "failed")
		eq(m:failReason(7), "error")
		eq(m:get(7), nil)
		local ok, why = m:update(7, function(d)
			d.progression.coins = 1
			return true
		end)
		eq(ok, false)
		eq(why, "notLoaded")
		eq((m:setFlag(7, "introSeen", true)), false)
		eq((m:saveNow(7)), false)
		m:tick()
		eq(fake.writes, writes, "nothing written while failed")
		eq(m:retryLoad(7), true)
		fake:failNext(0)
		eq(m:status(7), "failed", "that retry also hit the outage")
		eq(m:retryLoad(7), true)
		eq(m:status(7), "ready")
		eq(m:get(7).data.progression.coins, 60)
		eq(m:retryLoad(7), false, "nothing to retry when ready")
		eq(statuses[1], "loading")
		eq(statuses[2], "failed")
	end
)

Harness.test("flow: 'future' and 'corrupt' loads cannot be retried", function()
	reset()
	local fake = Fake.new()
	fake:setRaw(KEY, { v = 1, data = { schemaVersion = 99 } })
	local m = newManager(fake, "A")
	m:join(7)
	eq(m:status(7), "failed")
	eq(m:failReason(7), "future")
	eq(m:retryLoad(7), false)
end)

Harness.test("flow: locked by another server reports failed 'locked'", function()
	reset()
	local fake = Fake.new()
	local other = newStore(fake, "B")
	loadOk(other, 7)
	local m = newManager(fake, "A")
	m:join(7)
	eq(m:status(7), "failed")
	eq(m:failReason(7), "locked")
	eq(m:retryLoad(7), true)
end)

Harness.test("flow: flags only accept listed names and are saved", function()
	reset()
	local fake = Fake.new()
	local m = newManager(fake, "A")
	m:join(7)
	eq(m:getFlag(7, "introSeen"), false)
	eq((m:setFlag(7, "introSeen", true)), true)
	eq(m:getFlag(7, "introSeen"), true)
	local ok, why = m:setFlag(7, "isAdmin", true)
	eq(ok, false)
	eq(why, "unknownFlag")
	eq(m:flags(7).introSeen, true)
	m:leave(7)
	m:join(7)
	eq(m:getFlag(7, "introSeen"), true, "saved")
	m:setFlag(7, "introSeen", false)
	eq(m:flags(7).introSeen, nil)
end)

Harness.test("flow: tick writes when due, not before (no per-update writes)", function()
	reset()
	local fake = Fake.new()
	local m = newManager(fake, "A")
	m:join(7)
	local writes = fake.writes
	for i = 1, 50 do
		m:update(7, function(d)
			d.progression.coins = i
			return true
		end)
		m:tick()
	end
	eq(fake.writes, writes, "50 updates, no writes yet")
	now += Config.Profile.autosaveSeconds
	m:tick()
	eq(fake.writes, writes + 1, "one autosave")
	eq(fake:raw(KEY).data.progression.coins, 50)
end)

Harness.test("flow: saveNow waits out the write gap and then writes once", function()
	reset()
	local fake = Fake.new()
	local m = newManager(fake, "A")
	m:join(7)
	m:update(7, function(d)
		d.progression.coins = 12
		return true
	end)
	local before = waited
	eq(m:saveNow(7), true)
	truthy(waited - before >= Config.Profile.minSecondsBetweenWrites - 0.001, "waited for the gap")
	eq(fake:raw(KEY).data.progression.coins, 12)
end)

Harness.test(
	"flow: leaving while the load is still running releases the lock afterwards",
	function()
		reset()
		local fake = Fake.new()
		local store = newStore(fake, "A")
		-- A spawn that delays the load until we say so.
		local queued: { () -> () } = {}
		local m = ProfileManager.new({
			store = store,
			spawn = function(fn: () -> ())
				table.insert(queued, fn)
			end,
			wait = wait,
			clock = clock,
			newSignal = Signal.new,
			cfg = Config.Profile,
		})
		local loaded = 0
		m.Loaded:connect(function()
			loaded += 1
		end)
		m:join(7)
		eq(m:status(7), "loading")
		m:leave(7)
		for _, fn in queued do
			fn()
		end
		eq(loaded, 0, "nobody heard a Loaded for a player who left")
		eq(fake:raw(KEY).lock, nil, "lock released")
	end
)

Harness.test(
	"flow: a server taking the profile over kicks the old one (status lost, no more writes)",
	function()
		reset()
		local fake = Fake.new()
		local a = newManager(fake, "A")
		local b = newManager(fake, "B")
		a:join(7)
		a:update(7, function(d)
			d.progression.coins = 5
			return true
		end)
		a:saveNow(7)
		now += Config.Profile.lockStaleSeconds + 1
		b:join(7)
		eq(b:status(7), "ready")
		local lostSeen = false
		a.StatusChanged:connect(function(_, s: string)
			if s == "lost" then
				lostSeen = true
			end
		end)
		a:update(7, function(d)
			d.progression.coins = 1234
			return true
		end)
		a:saveNow(7)
		eq(lostSeen, true)
		eq(a:status(7), "lost")
		eq(a:get(7), nil)
		eq((a:update(7, function()
			return true
		end)), false)
		eq(fake:raw(KEY).data.progression.coins, 5)
	end
)

Harness.test("flow: shutdown saves every profile and clears the locks", function()
	reset()
	local fake = Fake.new()
	local m = newManager(fake, "A")
	for id = 1, 5 do
		m:join(id)
		m:update(id, function(d)
			d.progression.coins = id * 10
			return true
		end)
	end
	m:shutdown()
	for id = 1, 5 do
		local raw = fake:raw(ProfileStore.keyFor(id))
		eq(raw.data.progression.coins, id * 10)
		eq(raw.lock, nil)
	end
	m:join(9)
	eq(m:status(9), "none", "no new joins while closing")
end)

Harness.test("flow: a reward is paid once per match key even if the request repeats", function()
	reset()
	local fake = Fake.new()
	local m = newManager(fake, "A")
	m:join(7)
	local key = Receipts.matchKey("A", 3)
	local paid = 0
	for _ = 1, 4 do
		local ok = m:grantOnce(7, key, function(d)
			d.progression.coins += 30
			d.progression.totalEarned += 30
			return true
		end)
		if ok then
			paid += 1
		end
	end
	eq(paid, 1)
	eq(m:get(7).data.progression.coins, 30)
end)

Harness.test("config: Profile numbers make sense together", function()
	local c = Config.Profile
	truthy(
		c.lockStaleSeconds > c.autosaveSeconds * 2,
		"a live server refreshes well before the lock looks stale"
	)
	truthy(c.minSecondsBetweenWrites >= 6)
	truthy(c.autosaveSeconds >= c.minSecondsBetweenWrites)
	truthy(c.shutdownSeconds < 30, "BindToClose allows 30 s")
	truthy(table.find(c.flags, "introSeen") ~= nil)
end)
