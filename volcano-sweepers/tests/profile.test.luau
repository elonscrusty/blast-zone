--!strict
-- Saving tests: schema (defaults, sanitize fuzz, migration), once-only grants, session lock,
-- failures, and the whole join / leave / outage flow, all against a fake DataStore. No real
-- DataStore is touched.

local serde = require("@lune/serde")

local Harness = require("./harness")
local Fake = require("./fake_datastore")
local SaveRetry = require("../src/shared/SaveRetry")
local Signal = require("../src/shared/Signal")
local Rng = require("../src/shared/Rng")
local Serializable = require("../src/shared/Profile/Serializable")
local Receipts = require("../src/shared/Profile/Receipts")
local ProfileSchema = require("../src/shared/Profile/ProfileSchema")
local ProfileStore = require("../src/shared/Profile/ProfileStore")
local ProfileManager = require("../src/shared/Profile/ProfileManager")

local eq, truthy = Harness.eq, Harness.truthy

local CFG = ProfileStore.DEFAULT_CFG
local MANAGER_CFG = {
	autosaveSeconds = CFG.autosaveSeconds,
	minSecondsBetweenWrites = CFG.minSecondsBetweenWrites,
	lockStaleSeconds = CFG.lockStaleSeconds,
	loadLockTries = CFG.loadLockTries,
	lockRetrySeconds = CFG.lockRetrySeconds,
	receiptsKept = CFG.receiptsKept,
	failRetrySeconds = CFG.failRetrySeconds,
	shutdownSeconds = 25,
}

-- One shared fake clock for every "server" in a test.
local now = 1000
local waited = 0
local waits: { number } = {}
local function clock(): number
	return now
end
local function wait(s: number)
	waited += s
	now += s -- waiting moves time, like real life
	table.insert(waits, s)
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
		cfg = CFG,
		log = function(t: string)
			table.insert(logs, t)
		end,
	})
end

local function reset()
	now = 1000
	waited = 0
	waits = {}
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

local function setCoins(store: ProfileStore.Store, p: ProfileStore.Profile, n: number)
	local ok = store:update(p, function(d)
		d.coins = n
		return true
	end)
	if not ok then
		error("setCoins refused")
	end
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
		local _, why = Serializable.check({ stats = { coins = 0 / 0 } })
		truthy(why and string.find(why, "stats.coins", 1, true), "reason names the field")
	end
)

Harness.test("receipts: add/has, newest kept, valid keys, daily key per day", function()
	local book = Receipts.newBook()
	for i = 1, 5 do
		Receipts.add(book, "k" .. i, 100 + i, 3)
	end
	eq(Receipts.has(book, "k5"), true)
	eq(Receipts.has(book, "k3"), true)
	eq(Receipts.has(book, "k2"), false, "oldest forgotten")
	eq(Receipts.has(book, "k1"), false)
	eq(Receipts.isValidKey("daily:20400"), true)
	eq(Receipts.isValidKey(""), false)
	eq(Receipts.isValidKey("bad key!"), false)
	eq(Receipts.isValidKey(string.rep("a", 101)), false)
	eq(Receipts.dailyKey(20400) == Receipts.dailyKey(20401), false)
	eq(Receipts.dailyKey(20400), Receipts.dailyKey(20400.7), "same day")
	local cleaned =
		Receipts.clean({ ok = 5, ["bad key"] = 6, nan = 0 / 0, text = "x", [1] = 3 }, 10)
	eq(cleaned.ok, 5)
	eq(cleaned["bad key"], nil)
	eq(cleaned.nan, nil)
	eq(cleaned.text, nil)
	eq(next(Receipts.clean("junk", 10)), nil)
end)

-- ===== schema: defaults =====

Harness.test("schema: default() is a valid profile with every field and sane values", function()
	local p = ProfileSchema.default()
	local ok, why = ProfileSchema.isValid(p)
	truthy(ok, tostring(why))
	eq(p.version, 1)
	eq(p.version, ProfileSchema.CURRENT)
	eq(p.tool, "twig_broom")
	eq(p.toolsOwned.twig_broom, true)
	eq(p.zones["1"], true)
	eq(p.zones["2"], nil)
	eq(p.daily.lastDay, 0)
	eq(p.daily.streak, 0)
	eq(p.coins, 0)
	eq(p.tutorialDone, false)
	eq(p.settings.music, true)
	eq(p.settings.sfx, true)
	eq(p.settings.autoSweep, false)
	eq(p.settings.shake, true)
	eq(p.settings.vibrate, true)
	for _, k in ProfileSchema.STAT_KEYS do
		eq((p.stats :: any)[k], 0, k)
	end
	-- every field is there, and nothing else
	local count = 0
	for k in p :: any do
		count += 1
		truthy(table.find(ProfileSchema.KEYS, k) ~= nil, "unexpected key " .. tostring(k))
	end
	eq(count, #ProfileSchema.KEYS)
	eq(count, 20)
end)

Harness.test("schema: default() returns a fresh copy each time", function()
	local a, b = ProfileSchema.default(), ProfileSchema.default()
	a.coins = 5
	a.toolsOwned.push_broom = true
	a.zones["2"] = true
	a.stats.ashSwept = 9
	a.settings.music = false
	eq(b.coins, 0)
	eq(b.toolsOwned.push_broom, nil)
	eq(b.zones["2"], nil)
	eq(b.stats.ashSwept, 0)
	eq(b.settings.music, true)
end)

Harness.test("schema: SaveVersion comes from Config", function()
	eq(ProfileSchema.CURRENT, require("../src/shared/Config").Game.SaveVersion)
end)

Harness.test(
	"schema: isValid really rejects bad profiles (the validator is not vacuous)",
	function()
		local function bad(label: string, change: (any) -> ())
			local p: any = ProfileSchema.default()
			change(p)
			eq((ProfileSchema.isValid(p)), false, label)
		end
		eq((ProfileSchema.isValid(nil)), false)
		eq((ProfileSchema.isValid("x")), false)
		bad("nan coins", function(p)
			p.coins = 0 / 0
		end)
		bad("inf coins", function(p)
			p.coins = math.huge
		end)
		bad("negative coins", function(p)
			p.coins = -1
		end)
		bad("huge coins", function(p)
			p.coins = 1e30
		end)
		bad("fractional sparks", function(p)
			p.sparks = 1.5
		end)
		bad("helpers 7", function(p)
			p.helpers = 7
		end)
		bad("upgrade level 51", function(p)
			p.upgrades.power = 51
		end)
		bad("upgrade level fractional", function(p)
			p.upgrades.power = 2.5
		end)
		bad("zone 6", function(p)
			p.zones["6"] = true
		end)
		bad("zone 1 closed", function(p)
			p.zones["1"] = false
		end)
		bad("numeric zone key", function(p)
			p.zones[2] = true
		end)
		bad("unknown top key", function(p)
			p.extra = 1
		end)
		bad("missing key", function(p)
			p.stats = nil
		end)
		bad("missing stat", function(p)
			p.stats.cleared = nil
		end)
		bad("unowned tool", function(p)
			p.tool = "dragon_vac"
		end)
		bad("starter tool missing", function(p)
			p.toolsOwned.twig_broom = nil
		end)
		bad("bad id", function(p)
			p.goalsClaimed["Bad Id!"] = true
		end)
		bad("array in a map", function(p)
			p.finds = { 1, 2, 3 }
		end)
		bad("wrong version", function(p)
			p.version = 2
		end)
		bad("setting not boolean", function(p)
			p.settings.sfx = "yes"
		end)
		bad("daily negative", function(p)
			p.daily.streak = -1
		end)
		bad("too many ids", function(p)
			for i = 1, 101 do
				p.finds["f" .. i] = 1
			end
		end)
	end
)

-- ===== schema: sanitize =====

Harness.test("schema: sanitize leaves a valid profile exactly as it was", function()
	local p = ProfileSchema.default()
	p.coins = 1234.5
	p.runCoins = 99
	p.lifetimeCoins = 5000
	p.sparks = 7
	p.coolDowns = 1
	p.tool = "push_broom"
	p.toolsOwned.push_broom = true
	p.upgrades.power = 12
	p.upgrades.luck = 3
	p.zones["2"] = true
	p.helpers = 2
	p.helperLevel = 4
	p.sparkPerks.start_coins = 2
	p.finds.shell = 5
	p.setsClaimed.beach = true
	p.goalsClaimed.sweep_1k = true
	p.daily.lastDay = 20400
	p.daily.streak = 3
	p.stats.ashSwept = 123456
	p.stats.playSeconds = 7200.25
	p.settings.autoSweep = true
	p.settings.music = false
	p.tutorialDone = true
	local clean = ProfileSchema.sanitize(p)
	truthy(ProfileSchema.equal(p, clean), "unchanged")
	truthy(clean ~= p, "a new table")
	local again = ProfileSchema.sanitize(clean)
	truthy(ProfileSchema.equal(clean, again), "idempotent")
end)

Harness.test("schema: sanitize fixes wrong types, NaN, inf, negatives and huge numbers", function()
	local clean = ProfileSchema.sanitize({
		version = "one",
		coins = 0 / 0,
		runCoins = -50,
		lifetimeCoins = 1e300,
		sparks = math.huge,
		coolDowns = "3",
		tool = 42,
		toolsOwned = { "twig_broom", "push_broom" },
		upgrades = {
			power = 9999,
			speed = -3,
			reach = 2.7,
			walk = "x",
			["Bad Id"] = 3,
			luck = 0 / 0,
		},
		zones = { ["0"] = true, ["1"] = false, ["3"] = true, ["6"] = true, [4] = true },
		helpers = 99,
		helperLevel = -1,
		sparkPerks = "none",
		finds = { shell = 3.9, pearl = math.huge },
		setsClaimed = { beach = 1, forest = true },
		goalsClaimed = { a = "yes", b = true },
		daily = { lastDay = -5, streak = 1e12 },
		stats = { ashSwept = -1, unitsSold = 0 / 0, sellCount = 1e99, playSeconds = "x" },
		settings = { music = "no", sfx = false, autoSweep = 1 },
		tutorialDone = "yes",
		hacked = true,
	})
	local ok, why = ProfileSchema.isValid(clean)
	truthy(ok, tostring(why))
	eq(clean.coins, 0)
	eq(clean.runCoins, 0)
	eq(clean.lifetimeCoins, ProfileSchema.MAX.coins, "huge capped")
	eq(clean.sparks, 0, "inf is not trusted")
	eq(clean.coolDowns, 0)
	eq(clean.tool, "twig_broom")
	eq(clean.toolsOwned.twig_broom, true)
	eq(clean.toolsOwned.push_broom, nil, "array junk dropped")
	eq(clean.upgrades.power, 50, "capped at 50")
	eq(clean.upgrades.speed, nil)
	eq(clean.upgrades.reach, 2, "whole number")
	eq(clean.upgrades.walk, nil)
	eq(clean.upgrades.luck, nil)
	eq(clean.zones["1"], true, "zone 1 always open")
	eq(clean.zones["3"], true)
	eq(clean.zones["6"], nil)
	eq(clean.zones["0"], nil)
	eq(clean.helpers, 6)
	eq(clean.helperLevel, 0)
	eq(next(clean.sparkPerks), nil)
	eq(clean.finds.shell, 3)
	eq(clean.finds.pearl, nil)
	eq(clean.setsClaimed.beach, nil)
	eq(clean.setsClaimed.forest, true)
	eq(clean.goalsClaimed.a, nil)
	eq(clean.goalsClaimed.b, true)
	eq(clean.daily.lastDay, 0)
	eq(clean.daily.streak, ProfileSchema.MAX.streak)
	eq(clean.stats.ashSwept, 0)
	eq(clean.stats.unitsSold, 0)
	eq(clean.stats.sellCount, ProfileSchema.MAX.stat)
	eq(clean.stats.playSeconds, 0)
	eq(clean.settings.music, true, "wrong type -> default")
	eq(clean.settings.sfx, false)
	eq(clean.settings.autoSweep, false)
	eq(clean.tutorialDone, false)
	eq((clean :: any).hacked, nil, "unknown key dropped")
end)

Harness.test("schema: sanitize keeps a real equipped tool, falls back when not owned", function()
	local a = ProfileSchema.sanitize({ tool = "leaf_blower", toolsOwned = { leaf_blower = true } })
	eq(a.tool, "leaf_blower")
	eq(a.toolsOwned.twig_broom, true)
	local b = ProfileSchema.sanitize({ tool = "leaf_blower", toolsOwned = {} })
	eq(b.tool, "twig_broom")
end)

Harness.test(
	"schema: sanitize keeps unknown but id-shaped ids (a removed item stays owned)",
	function()
		local clean = ProfileSchema.sanitize({
			toolsOwned = { retired_tool = true },
			upgrades = { retired_upgrade = 4 },
			goalsClaimed = { retired_goal = true },
		})
		eq(clean.toolsOwned.retired_tool, true)
		eq(clean.upgrades.retired_upgrade, 4)
		eq(clean.goalsClaimed.retired_goal, true)
	end
)

Harness.test("schema: sanitize of a non-table gives the default", function()
	for _, junk in { 5, "x", true, 0 / 0, math.huge } do
		local clean = ProfileSchema.sanitize(junk)
		truthy(ProfileSchema.equal(clean, ProfileSchema.default()))
	end
	truthy(ProfileSchema.equal(ProfileSchema.sanitize(nil), ProfileSchema.default()))
	truthy(ProfileSchema.equal(ProfileSchema.sanitize({}), ProfileSchema.default()))
end)

Harness.test("schema: runtime View fields are not saved", function()
	local clean = ProfileSchema.sanitize({
		coins = 3,
		carried = 40,
		carriedValue = 99,
		derived = { reach = 9 },
		buffs = { party = 1 },
		cleanTotal = 0.5,
	})
	eq(clean.coins, 3)
	eq((clean :: any).carried, nil)
	eq((clean :: any).derived, nil)
	eq((clean :: any).buffs, nil)
	eq((clean :: any).cleanTotal, nil)
end)

-- deterministic junk
local NUMBERS = {
	0 / 0,
	math.huge,
	-math.huge,
	-1,
	0,
	1,
	0.5,
	-0.5,
	1e300,
	-1e300,
	2 ^ 53,
	2 ^ 31,
	6,
	7,
	50,
	51,
	1e15,
	1e16,
	1e-300,
}
local STRINGS = {
	"",
	"twig_broom",
	"push_broom",
	"1",
	"5",
	"6",
	"Bad Id",
	"__proto__",
	"a",
	"power",
	string.rep("x", 200),
	"\255\254",
	"daily:1",
}

local function junkValue(rng: Rng.Rng, depth: number): any
	local r = rng:next()
	if r < 0.28 then
		return rng:pick(NUMBERS)
	elseif r < 0.42 then
		return rng:pick(STRINGS)
	elseif r < 0.5 then
		return rng:chance(0.5)
	elseif r < 0.55 then
		return nil
	elseif r < 0.6 then
		return function() end
	elseif depth < 3 then
		local t: { [any]: any } = {}
		for _ = 1, rng:int(0, 5) do
			local kr = rng:next()
			local k: any
			if kr < 0.6 then
				k = rng:pick(STRINGS)
			elseif kr < 0.85 then
				k = rng:int(-2, 8)
			else
				k = rng:chance(0.5)
			end
			t[k] = junkValue(rng, depth + 1)
		end
		if rng:chance(0.05) then
			t.loop = t -- a table that contains itself
		end
		return t
	end
	return rng:int(0, 10)
end

local function mutate(rng: Rng.Rng, p: any)
	for _ = 1, rng:int(1, 5) do
		local k = rng:pick(ProfileSchema.KEYS)
		local child = p[k]
		if type(child) == "table" and rng:chance(0.6) then
			local sub = rng:pick(STRINGS)
			if next(child) ~= nil and rng:chance(0.5) then
				sub = next(child)
			end
			child[sub] = junkValue(rng, 2)
		elseif rng:chance(0.15) then
			p[k] = nil
		else
			p[k] = junkValue(rng, 1)
		end
	end
	if rng:chance(0.2) then
		p.version = junkValue(rng, 3)
	end
	if rng:chance(0.2) then
		p[rng:pick(STRINGS)] = junkValue(rng, 2)
	end
end

Harness.test("schema fuzz: 1000 junk tables never throw and always come out valid", function()
	local rng = Rng.new(20261101)
	for i = 1, 1000 do
		local junk: any
		if i % 2 == 0 then
			junk = {}
			for _, k in ProfileSchema.KEYS do
				if rng:chance(0.8) then
					junk[k] = junkValue(rng, 0)
				end
			end
			junk[rng:pick(STRINGS)] = junkValue(rng, 0)
		else
			junk = ProfileSchema.default()
			if rng:chance(0.5) then
				junk.coins = 1000
				junk.upgrades.power = 5
				junk.toolsOwned.push_broom = true
			end
			mutate(rng, junk)
		end
		local ok, clean = pcall(ProfileSchema.sanitize, junk)
		if not ok then
			error(`case {i} threw: {clean}`)
		end
		local valid, why = ProfileSchema.isValid(clean)
		if not valid then
			error(`case {i} not valid: {why}`)
		end
		local saveable, whySave = Serializable.check(clean)
		if not saveable then
			error(`case {i} not saveable: {whySave}`)
		end
		if not ProfileSchema.equal(ProfileSchema.sanitize(clean), clean) then
			error(`case {i} not stable`)
		end
	end
end)

Harness.test("schema fuzz: non-table roots and nested loops never throw", function()
	local rng = Rng.new(99)
	for _ = 1, 200 do
		local v = junkValue(rng, 0)
		local ok, clean = pcall(ProfileSchema.sanitize, v)
		truthy(ok, "threw")
		truthy((ProfileSchema.isValid(clean)))
		local ok2 = pcall(ProfileSchema.prepare, v)
		truthy(ok2, "prepare threw")
	end
	local loop: { [string]: any } = { coins = 5 }
	loop.settings = loop
	loop.stats = loop
	loop.upgrades = loop
	local clean = ProfileSchema.sanitize(loop)
	eq(clean.coins, 5)
	truthy((ProfileSchema.isValid(clean)))
end)

Harness.test("schema: a sanitized profile is DataStore safe and survives JSON unchanged", function()
	local p = ProfileSchema.sanitize({
		coins = 12.5,
		zones = { ["1"] = true, ["2"] = true },
		upgrades = { power = 3 },
		finds = { shell = 2 },
	})
	truthy((Serializable.check(p)))
	local text = serde.encode("json", p)
	local back = serde.decode("json", text)
	truthy(ProfileSchema.equal(p, back), "same after JSON")
	truthy((ProfileSchema.isValid(back)))
	-- only string keys and no arrays anywhere
	local function walk(v: any)
		if type(v) == "table" then
			for k, child in v :: { [any]: any } do
				eq(type(k), "string")
				walk(child)
			end
		end
	end
	walk(p)
end)

-- ===== schema: migrate =====

Harness.test("migrate: a fake v0 save is upgraded to the current shape", function()
	local v0: { [string]: any } = {
		money = 250,
		broom = "push_broom",
		tools = { "twig_broom", "push_broom" },
		zones = { ["1"] = true, ["2"] = true },
	}
	local moved, why = ProfileSchema.migrate(v0, 0)
	eq(why, nil)
	local m = moved :: any
	eq(m.version, 1)
	eq(m.coins, 250)
	eq(m.tool, "push_broom")
	eq(m.toolsOwned.push_broom, true)
	eq(m.money, nil)
	eq(v0.money, 250, "the input is never changed")
	eq(v0.version, nil)

	local clean = ProfileSchema.sanitize(v0)
	eq(clean.coins, 250)
	eq(clean.tool, "push_broom")
	eq(clean.toolsOwned.twig_broom, true)
	eq(clean.zones["2"], true)
	truthy((ProfileSchema.isValid(clean)))
end)

Harness.test("migrate: steps run in order from the stored version up (v1 -> v2 -> v3)", function()
	local steps: ProfileSchema.Steps = {
		[1] = function(d)
			d.order ..= "a"
			return d
		end,
		[2] = function(d)
			d.order ..= "b"
			return d
		end,
	}
	local out = ProfileSchema.migrate({ version = 1, order = "" }, 1, 3, steps) :: any
	eq(out.order, "ab")
	eq(out.version, 3)
	local out2 = ProfileSchema.migrate({ version = 2, order = "" }, 2, 3, steps) :: any
	eq(out2.order, "b", "starts at the stored version")
	local none, why = ProfileSchema.migrate({ order = "" }, 1, 3, { [1] = steps[1] })
	eq(none, nil)
	eq(why, "noStep")
	local _, why2 = ProfileSchema.migrate({}, 5, 3, steps)
	eq(why2, "future")
	local _, why3 = ProfileSchema.migrate("x", 0)
	eq(why3, "corrupt")
	local _, why4 = ProfileSchema.migrate({}, 1, 2, {
		[1] = function()
			error("boom")
		end,
	})
	eq(why4, "error")
end)

Harness.test(
	"migrate: current-version data is untouched and v0 data with no version works",
	function()
		local p = ProfileSchema.default()
		p.coins = 77
		local moved = ProfileSchema.migrate(p, ProfileSchema.CURRENT)
		truthy(ProfileSchema.equal(moved, p))
		eq(ProfileSchema.sanitize({ coins = 40 }).coins, 40, "no version stored")
	end
)

Harness.test(
	"prepare: refuses a newer save untouched, reports whether it repaired anything",
	function()
		local future = { version = ProfileSchema.CURRENT + 1, coins = 9 }
		local p, why = ProfileSchema.prepare(future)
		eq(p, nil)
		eq(why, "future")
		eq(future.coins, 9)
		local _, why2 = ProfileSchema.prepare("junk")
		eq(why2, "corrupt")
		local good, _, changed = ProfileSchema.prepare(ProfileSchema.default())
		truthy(good)
		eq(changed, false)
		local _, _, changed2 = ProfileSchema.prepare({ coins = 1 })
		eq(changed2, true)
	end
)

-- ===== store =====

Harness.test(
	"store: new player gets defaults, is written with our lock, and is not dirty",
	function()
		reset()
		local fake = Fake.new()
		local store = newStore(fake, "A")
		local p = loadOk(store, 7)
		eq(p.isNew, true)
		eq(p.data.coins, 0)
		eq(p.dirty, false)
		eq(p.locked, false)
		local raw = fake:raw(KEY)
		eq(raw.lock.jobId, "A")
		eq(raw.data.version, ProfileSchema.CURRENT)
		truthy((ProfileSchema.isValid(raw.data)))
	end
)

Harness.test("store: round trip. Progress comes back after leave and rejoin", function()
	reset()
	local fake = Fake.new()
	local store = newStore(fake, "A")
	local p = loadOk(store, 7)
	local ok = store:update(p, function(d)
		d.coins = 120
		d.upgrades.power = 4
		d.toolsOwned.push_broom = true
		d.tool = "push_broom"
		d.zones["2"] = true
		d.stats.ashSwept = 900
		d.daily.lastDay = 20400
		d.daily.streak = 2
		return true
	end)
	eq(ok, true)
	eq(p.dirty, true)
	eq(store:release(p), true)
	eq(p.status, "released")
	eq(fake:raw(KEY).lock, nil, "lock cleared on leave")

	local again = loadOk(store, 7)
	eq(again.isNew, false)
	eq(again.data.coins, 120)
	eq(again.data.upgrades.power, 4)
	eq(again.data.tool, "push_broom")
	eq(again.data.zones["2"], true)
	eq(again.data.stats.ashSwept, 900)
	eq(again.data.daily.streak, 2)
	eq(again.dirty, false, "nothing was repaired")
end)

Harness.test("store: other code edits the live table, then saves with markDirty", function()
	reset()
	local fake = Fake.new()
	local store = newStore(fake, "A")
	local p = loadOk(store, 7)
	local live = p.data
	live.coins += 50 -- how the game really does it
	live.upgrades.speed = 2
	store:markDirty(p)
	eq(p.dirty, true)
	eq(store:save(p), true)
	eq(p.dirty, false)
	eq(fake:raw(KEY).data.coins, 50)
	eq(fake:raw(KEY).data.upgrades.speed, 2)
	truthy(p.data == live, "same table all along")
end)

Harness.test(
	"store: update is all-or-nothing (error, false, NaN and bad shape change nothing)",
	function()
		reset()
		local fake = Fake.new()
		local store = newStore(fake, "A")
		local p = loadOk(store, 7)
		local live = p.data
		local ok1, r1 = store:update(p, function(d)
			d.coins = 99
			error("boom")
		end)
		eq(ok1, false)
		eq(r1, "error")
		local ok2, r2 = store:update(p, function(d)
			d.coins = 99
			return false
		end)
		eq(ok2, false)
		eq(r2, "rejected")
		local ok3, r3 = store:update(p, function(d)
			d.coins = 0 / 0
			return true
		end)
		eq(ok3, false)
		eq(r3, "invalid")
		local ok4, r4 = store:update(p, function(d)
			d.upgrades.power = 500
			return true
		end)
		eq(ok4, false)
		eq(r4, "invalid")
		eq(p.data.coins, 0)
		eq(p.dirty, false)
		truthy(p.data == live, "table identity kept")
		setCoins(store, p, 5)
		truthy(p.data == live, "still the same table after a good update")
	end
)

Harness.test("store: update on no profile says notLoaded", function()
	reset()
	local store = newStore(Fake.new(), "A")
	local ok, why = store:update(nil, function()
		return true
	end)
	eq(ok, false)
	eq(why, "notLoaded")
end)

Harness.test("receipts: grantOnce pays once per key, even after save and reload", function()
	reset()
	local fake = Fake.new()
	local store = newStore(fake, "A")
	local p = loadOk(store, 7)
	local key = Receipts.dailyKey(20400)
	local function pay(d: any): boolean?
		d.coins += 40
		return true
	end
	eq((store:grantOnce(p, key, pay)), true)
	local ok, why = store:grantOnce(p, key, pay)
	eq(ok, false)
	eq(why, "duplicate")
	eq(p.data.coins, 40)
	eq((store:grantOnce(p, Receipts.dailyKey(20401), pay)), true, "next day pays")
	eq(p.data.coins, 80)
	store:release(p)
	local again = loadOk(store, 7)
	local ok2, why2 = store:grantOnce(again, key, pay)
	eq(ok2, false, "receipt survived the save")
	eq(why2, "duplicate")
	eq(again.data.coins, 80)
	eq((ProfileSchema.isValid(fake:raw(KEY).data)), true, "receipts are not inside the profile")
end)

Harness.test("receipts: a refused grant leaves no receipt (can be paid later)", function()
	reset()
	local store = newStore(Fake.new(), "A")
	local p = loadOk(store, 7)
	local ok = store:grantOnce(p, "k1", function()
		return false
	end)
	eq(ok, false)
	eq(Receipts.has(p.receipts, "k1"), false)
	local bad = store:grantOnce(p, "k2", function(d)
		d.coins = -5
		return true
	end)
	eq(bad, false)
	eq(Receipts.has(p.receipts, "k2"), false, "an invalid result is not paid and not receipted")
	local ok2 = store:grantOnce(p, "k1", function(d)
		d.coins = 5
		return true
	end)
	eq(ok2, true)
end)

Harness.test("receipts: grantOnce rejects bad keys", function()
	reset()
	local store = newStore(Fake.new(), "A")
	local p = loadOk(store, 7)
	local ok, why = store:grantOnce(p, "bad key", function()
		return true
	end)
	eq(ok, false)
	eq(why, "badKey")
end)

Harness.test("receipts: only the newest are kept across saves", function()
	reset()
	local fake = Fake.new()
	local store = newStore(fake, "A")
	local p = loadOk(store, 7)
	for i = 1, CFG.receiptsKept + 20 do
		now += 1
		store:grantOnce(p, "r" .. i, function(d)
			d.coins += 1
			return true
		end)
	end
	store:release(p)
	local n = 0
	for _ in fake:raw(KEY).receipts do
		n += 1
	end
	eq(n, CFG.receiptsKept)
	local again = loadOk(store, 7)
	eq(Receipts.has(again.receipts, "r" .. (CFG.receiptsKept + 20)), true)
	eq(Receipts.has(again.receipts, "r1"), false)
end)

-- ===== session lock =====

Harness.test(
	"lock: a second server cannot load a fresh lock and never changes the record",
	function()
		reset()
		local fake = Fake.new()
		local a = newStore(fake, "A")
		local b = newStore(fake, "B")
		local pa = loadOk(a, 7)
		setCoins(a, pa, 10)
		a:save(pa)
		local before = fake:raw(KEY)
		local pb, reason = b:load(7)
		eq(pb, nil)
		eq(reason, "locked")
		eq(waited >= CFG.lockRetrySeconds, true, "it waited and tried again")
		local after = fake:raw(KEY)
		eq(after.data.coins, 10)
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
	setCoins(a, pa, 33)
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
		cfg = CFG,
	})
	local pb = loadOk(b, 7)
	eq(pb.data.coins, 33)
end)

Harness.test(
	"lock: a stale lock (crashed server) can be taken over; the old owner is then locked out",
	function()
		reset()
		local fake = Fake.new()
		local a = newStore(fake, "A")
		local b = newStore(fake, "B")
		local pa = loadOk(a, 7)
		setCoins(a, pa, 5)
		a:save(pa)
		now += CFG.lockStaleSeconds + 1 -- A stops refreshing (frozen server)
		local pb = loadOk(b, 7)
		eq(pb.data.coins, 5)

		-- A wakes up and tries to save an old state: must NOT overwrite B.
		setCoins(a, pa, 9999)
		local ok, why = a:save(pa)
		eq(ok, false)
		eq(why, "lost")
		eq(pa.status, "lost")
		eq(fake:raw(KEY).data.coins, 5)
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
		now += CFG.autosaveSeconds
		eq(a:due(pa, now), true)
		eq((a:save(pa)), true)
	end
	-- 6 minutes passed in total, but the lock is only seconds old.
	local pb = b:load(7)
	eq(pb, nil)
end)

-- ===== failed loads never overwrite =====

Harness.test("load: a failed load gives NO profile and writes nothing", function()
	reset()
	local fake = Fake.new()
	local seed = newStore(fake, "A")
	local p = loadOk(seed, 7)
	setCoins(seed, p, 777)
	seed:release(p)
	local writes = fake.writes
	local store = newStore(fake, "B")
	fake:failNext(99)
	local got, reason = store:load(7)
	eq(got, nil)
	eq(reason, "error")
	fake:failNext(0)
	eq(fake.writes, writes)
	eq(fake:raw(KEY).data.coins, 777)
	eq(store.active[KEY], nil)
	eq(loadOk(store, 7).data.coins, 777, "loading works again after the outage")
end)

Harness.test("store: an offline stand-in is locked and can never be written", function()
	reset()
	local fake = Fake.new()
	local seed = newStore(fake, "A")
	local p = loadOk(seed, 7)
	setCoins(seed, p, 777)
	seed:release(p)
	local before = fake:raw(KEY)
	local writes, calls = fake.writes, fake.calls

	local store = newStore(fake, "B")
	local off = store:offline(7, "error")
	eq(off.locked, true)
	eq(off.lockReason, "error")
	eq(off.status, "ready", "playable")
	eq(off.data.coins, 0)
	-- the player earns things offline
	setCoins(store, off, 5000)
	eq(off.dirty, true)
	eq(off.data.coins, 5000)
	-- nothing the store offers can write it
	local ok, why = store:save(off)
	eq(ok, false)
	eq(why, "locked")
	eq(store:due(off, now + 100000), false)
	eq((store:release(off)), false)
	eq(fake.writes, writes)
	eq(fake.calls, calls, "not even a read")
	eq(fake:raw(KEY).data.coins, 777)
	eq(fake:raw(KEY).saves, before.saves)
end)

Harness.test(
	"store: even if something clears the locked flag, the stand-in's sid matches no lock",
	function()
		reset()
		local fake = Fake.new()
		local seed = newStore(fake, "A")
		local p = loadOk(seed, 7)
		setCoins(seed, p, 777)
		seed:release(p)
		local store = newStore(fake, "B")
		local off = store:offline(7, "error")
		off.locked = false -- a bug or an exploit
		local ok, why = store:save(off)
		eq(ok, false)
		eq(why, "lost")
		eq(fake:raw(KEY).data.coins, 777)
	end
)

Harness.test(
	"load: a short outage is retried with growing waits (counted) and then succeeds",
	function()
		reset()
		local fake = Fake.new()
		local store = newStore(fake, "A")
		fake:failNext(2)
		local p = loadOk(store, 7)
		eq(p.isNew, true)
		eq(fake.calls, 3, "two failures, then the third try worked")
		eq(#waits, 2)
		eq(waits[1], 2)
		eq(waits[2], 4)
		eq(waited, 2 + 4, "waited 2 s then 4 s")
	end
)

Harness.test("load: a long outage stops after SaveRetry.TRIES and waits 2+4+8", function()
	reset()
	local fake = Fake.new()
	local store = newStore(fake, "A")
	fake:failNext(99)
	local p, reason = store:load(7)
	eq(p, nil)
	eq(reason, "error")
	eq(fake.calls, SaveRetry.TRIES)
	eq(waited, 2 + 4 + 8)
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
	eq(waited, 0)
end)

Harness.test("load: data from a newer game version is refused and left alone", function()
	reset()
	local fake = Fake.new()
	local original = { v = 1, data = { version = ProfileSchema.CURRENT + 1, coins = 5 } }
	fake:setRaw(KEY, original)
	local store = newStore(fake, "A")
	local p, reason = store:load(7)
	eq(p, nil)
	eq(reason, "future")
	local raw = fake:raw(KEY)
	eq(raw.lock, nil, "did not even take the lock")
	eq(raw.data.version, ProfileSchema.CURRENT + 1)
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
	"load: an old v0 save is migrated, marked dirty, and saved on the next write",
	function()
		reset()
		local fake = Fake.new()
		fake:setRaw(KEY, { v = 1, saves = 3, data = { money = 40, broom = "twig_broom" } })
		local store = newStore(fake, "A")
		local p = loadOk(store, 7)
		eq(p.isNew, false)
		eq(p.dirty, true)
		eq(p.data.coins, 40)
		eq(p.data.version, ProfileSchema.CURRENT)
		store:save(p)
		local raw = fake:raw(KEY)
		eq(raw.data.version, ProfileSchema.CURRENT)
		eq(raw.data.coins, 40)
		eq(raw.data.money, nil)
		eq(raw.saves, 4)
	end
)

Harness.test("load: junk fields in a stored profile are repaired on load", function()
	reset()
	local fake = Fake.new()
	fake:setRaw(KEY, {
		v = 1,
		data = { version = 1, coins = "lots", upgrades = { power = 900 }, evil = true },
	})
	local store = newStore(fake, "A")
	local p = loadOk(store, 7)
	eq(p.data.coins, 0)
	eq(p.data.upgrades.power, 50)
	eq((p.data :: any).evil, nil)
	eq(p.dirty, true)
	truthy((ProfileSchema.isValid(p.data)))
end)

-- ===== saving =====

Harness.test(
	"save: failing writes keep the profile dirty and retry later; data is not lost",
	function()
		reset()
		local fake = Fake.new()
		local store = newStore(fake, "A")
		local p = loadOk(store, 7)
		setCoins(store, p, 8)
		fake:failNext(99)
		local calls = fake.calls
		local ok, why = store:save(p)
		eq(ok, false)
		eq(why, "error")
		eq(fake.calls - calls, SaveRetry.TRIES, "tried 4 times")
		eq(p.dirty, true)
		eq(p.status, "ready")
		eq(p.autosaveAt <= now + CFG.failRetrySeconds, true, "tries the autosave again soon")
		fake:failNext(0)
		eq((store:save(p)), true)
		eq(fake:raw(KEY).data.coins, 8)
	end
)

Harness.test(
	"save: retry/backoff on a write counts the waits (2, 4, 8) and then succeeds",
	function()
		reset()
		local fake = Fake.new()
		local store = newStore(fake, "A")
		local p = loadOk(store, 7)
		setCoins(store, p, 3)
		waits = {}
		fake:failNext(3)
		local calls = fake.calls
		eq((store:save(p)), true)
		eq(fake.calls - calls, 4)
		eq(#waits, 3)
		eq(waits[1], 2)
		eq(waits[2], 4)
		eq(waits[3], 8)
		eq(fake:raw(KEY).data.coins, 3)
	end
)

Harness.test(
	"save: a NaN or out-of-range value in the live table is repaired, not saved as is",
	function()
		reset()
		local fake = Fake.new()
		local store = newStore(fake, "A")
		local p = loadOk(store, 7)
		setCoins(store, p, 4)
		store:save(p)
		local live = p.data
		-- Something writes data directly, bypassing update:
		live.coins = 0 / 0
		live.upgrades.power = 70
		live.stats.cleared = -3
		store:markDirty(p)
		local ok = store:save(p)
		eq(ok, true)
		truthy(#logs > 0, "reported")
		local raw = fake:raw(KEY)
		eq(raw.data.coins, 0, "NaN became 0, never reached the DataStore")
		eq(raw.data.upgrades.power, 50)
		eq(raw.data.stats.cleared, 0)
		truthy(p.data == live, "same table")
		eq(live.coins, 0, "live table healed too")
		store:release(p)
		eq(fake:raw(KEY).lock, nil)
	end
)

Harness.test(
	"save: writes are rationed, staggered per player, and a quiet profile still refreshes",
	function()
		reset()
		local store = newStore(Fake.new(), "A")
		local p = loadOk(store, 7)
		eq(store:due(p, now), false)
		store:saveSoon(p)
		eq(store:due(p, now), false, "too soon after the last write")
		eq(store:due(p, now + CFG.minSecondsBetweenWrites), true)
		store:save(p)
		eq(p.wantSave, false)
		eq(store:due(p, now + CFG.autosaveSeconds - 1), false)
		eq(store:due(p, now + CFG.autosaveSeconds), true, "clean profiles refresh the lock too")
	end
)

Harness.test("save: autosave moments are spread over the minute, never all at once", function()
	reset()
	local fake = Fake.new()
	local store = newStore(fake, "A")
	local seen: { [number]: boolean } = {}
	local count = 0
	for id = 1001, 1016 do
		local p = loadOk(store, id)
		local offset = p.autosaveAt - now
		eq(offset > CFG.autosaveSeconds * 0.45, true, "never earlier than half a minute")
		eq(offset <= CFG.autosaveSeconds, true)
		local slot = math.floor(offset)
		if not seen[slot] then
			seen[slot] = true
			count += 1
		end
	end
	truthy(count >= 12, "16 players land on many different seconds, got " .. count)
	eq(ProfileStore.stagger(5, 60), ProfileStore.stagger(5 + 16, 60), "stable per player")
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
			cfg = CFG,
		})
		first = loadOk(store, 7)
		setCoins(store, first, 21)
		local second = store:load(7)
		eq(released, true, "the new load waited")
		truthy(second, "then loaded")
		eq((second :: ProfileStore.Profile).data.coins, 21)
	end
)

Harness.test("config: store numbers make sense together", function()
	truthy(
		CFG.lockStaleSeconds > CFG.autosaveSeconds * 2,
		"a live server refreshes well before the lock looks stale"
	)
	truthy(CFG.minSecondsBetweenWrites >= 6)
	truthy(CFG.autosaveSeconds >= CFG.minSecondsBetweenWrites)
	truthy(MANAGER_CFG.shutdownSeconds < 30, "BindToClose allows 30 s")
end)

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
		cfg = MANAGER_CFG,
		log = function(t: string)
			table.insert(logs, t)
		end,
	})
	return manager, store
end

local function earn(m: ProfileManager.Manager, userId: number, coins: number)
	local data = m:data(userId)
	if data == nil then
		error("no profile to earn on")
	end
	data.coins += coins
	m:markDirty(userId)
end

Harness.test("flow: join, earn, leave, rejoin keeps progress", function()
	reset()
	local fake = Fake.new()
	local m = newManager(fake, "A")
	local loaded = 0
	local leaving = 0
	m.Loaded:connect(function()
		loaded += 1
	end)
	m.Leaving:connect(function(_, profile: ProfileStore.Profile)
		leaving += 1
		profile.data.stats.playSeconds = 300 -- last chance to add stats
	end)
	eq(m:status(7), "none")
	m:join(7)
	eq(m:status(7), "ready")
	eq(m:isOffline(7), false)
	eq(loaded, 1)
	earn(m, 7, 250)
	local released = 0
	m.Released:connect(function()
		released += 1
	end)
	m:leave(7)
	eq(leaving, 1)
	eq(released, 1)
	eq(m:get(7), nil)
	eq(m:data(7), nil)
	eq(fake:raw(KEY).lock, nil)
	eq(fake:raw(KEY).data.stats.playSeconds, 300, "stats written in Leaving were saved")
	m:join(7)
	eq((m:data(7) :: any).coins, 250)
end)

Harness.test("flow: the live table handed out is the one that gets saved", function()
	reset()
	local fake = Fake.new()
	local m = newManager(fake, "A")
	m:join(7)
	local live = m:data(7) :: any
	live.coins = 31
	live.upgrades.power = 2
	m:markDirty(7)
	eq(m:saveNow(7), true)
	eq(fake:raw(KEY).data.coins, 31)
	truthy(m:data(7) == live, "same table")
end)

Harness.test(
	"flow: THE rule. A failed load plays offline and never saves over real data",
	function()
		reset()
		local fake = Fake.new()
		local seed = newStore(fake, "Z")
		local sp = loadOk(seed, 7)
		setCoins(seed, sp, 60)
		seed:release(sp)
		local writes = fake.writes
		local snapshot = fake:raw(KEY)

		local m = newManager(fake, "A")
		local statuses: { string } = {}
		m.StatusChanged:connect(function(_, s: string)
			table.insert(statuses, s)
		end)
		local loadedCount = 0
		m.Loaded:connect(function()
			loadedCount += 1
		end)
		fake:failNext(99)
		m:join(7)
		eq(m:status(7), "offline")
		eq(m:isOffline(7), true)
		eq(m:failReason(7), "error")
		eq(loadedCount, 1, "the game still gets its profile and starts the player")
		local data = m:data(7)
		truthy(data, "a fresh profile to play with")
		eq((data :: any).coins, 0)
		truthy((ProfileSchema.isValid(data)))
		statuses = {}

		-- the player plays a whole session offline
		earn(m, 7, 5000)
		eq(m:saveNow(7), false, "saveNow refuses")
		m:saveSoon(7)
		for _ = 1, 10 do
			now += CFG.autosaveSeconds
			m:tick() -- autosave ticks never write it
		end
		eq(fake.writes, writes, "nothing written while offline")
		-- the DataStore comes back mid-session
		fake:failNext(0)
		for _ = 1, 10 do
			now += CFG.autosaveSeconds
			m:tick()
		end
		eq(m:saveNow(7), false)
		m:leave(7)
		eq(fake.writes, writes, "leaving writes nothing either")
		local after = fake:raw(KEY)
		eq(after.data.coins, 60, "real progress still there")
		eq(after.saves, snapshot.saves)
		eq(after.lock, nil)

		-- and the next visit loads the real thing
		m:join(7)
		eq(m:status(7), "ready")
		eq((m:data(7) :: any).coins, 60)
	end
)

Harness.test("flow: an offline player stays offline through shutdown without writing", function()
	reset()
	local fake = Fake.new()
	local seed = newStore(fake, "Z")
	local sp = loadOk(seed, 7)
	setCoins(seed, sp, 60)
	seed:release(sp)
	local m = newManager(fake, "A")
	fake:failNext(99)
	m:join(7)
	fake:failNext(0)
	earn(m, 7, 1)
	local writes = fake.writes
	m:shutdown()
	eq(fake.writes, writes)
	eq(fake:raw(KEY).data.coins, 60)
end)

Harness.test("flow: locked by another server plays offline, never touches their lock", function()
	reset()
	local fake = Fake.new()
	local other = newStore(fake, "B")
	local po = loadOk(other, 7)
	setCoins(other, po, 41)
	other:save(po)
	local m = newManager(fake, "A")
	m:join(7)
	eq(m:status(7), "offline")
	eq(m:failReason(7), "locked")
	earn(m, 7, 900)
	m:tick()
	m:leave(7)
	local raw = fake:raw(KEY)
	eq(raw.data.coins, 41)
	eq(raw.lock.jobId, "B", "the other server's lock is untouched")
	-- B can keep saving
	setCoins(other, po, 50)
	eq((other:save(po)), true)
end)

Harness.test("flow: 'future' and 'corrupt' saves play offline and are left alone", function()
	reset()
	local fake = Fake.new()
	fake:setRaw(KEY, { v = 1, data = { version = 99, coins = 8 } })
	local m = newManager(fake, "A")
	m:join(7)
	eq(m:status(7), "offline")
	eq(m:failReason(7), "future")
	earn(m, 7, 5)
	m:leave(7)
	eq(fake.writes, 0)
	eq(fake:raw(KEY).data.coins, 8)

	fake:setRaw(KEY, { v = 1, junk = true })
	m:join(7)
	eq(m:failReason(7), "corrupt")
	m:leave(7)
	eq(fake.writes, 0)
end)

Harness.test("flow: no DataStore at all (403) plays offline at once, no waiting", function()
	reset()
	local fake = Fake.new()
	fake:failNext(99, "403: Studio access to APIs is not allowed")
	local m = newManager(fake, "A")
	m:join(7)
	eq(m:status(7), "offline")
	eq(waited, 0)
	eq(fake.calls, 1)
	earn(m, 7, 10)
	m:leave(7)
	eq(fake.calls, 1, "never tried again")
end)

Harness.test("flow: tick writes when due, not before (no per-update writes)", function()
	reset()
	local fake = Fake.new()
	local m = newManager(fake, "A")
	m:join(7)
	local writes = fake.writes
	for i = 1, 50 do
		earn(m, 7, 1)
		m:tick()
		eq(i > 0, true)
	end
	eq(fake.writes, writes, "50 changes, no writes yet")
	now += CFG.autosaveSeconds
	m:tick()
	eq(fake.writes, writes + 1, "one autosave")
	eq(fake:raw(KEY).data.coins, 50)
	m:tick()
	eq(fake.writes, writes + 1, "and not again at once")
end)

Harness.test("flow: many players do not autosave in the same second", function()
	reset()
	local fake = Fake.new()
	local m = newManager(fake, "A")
	for id = 2001, 2016 do
		m:join(id)
	end
	local writes = fake.writes
	local maxInOneSecond = 0
	for _ = 1, CFG.autosaveSeconds + 1 do
		now += 1
		local before = fake.writes
		m:tick()
		maxInOneSecond = math.max(maxInOneSecond, fake.writes - before)
	end
	eq(fake.writes - writes, 16, "each player saved once in the minute")
	truthy(maxInOneSecond <= 3, "spread out, worst second wrote " .. maxInOneSecond)
end)

Harness.test(
	"flow: saveNow waits out the write gap, writes once, and skips a clean profile",
	function()
		reset()
		local fake = Fake.new()
		local m = newManager(fake, "A")
		m:join(7)
		eq(m:saveNow(7), true, "nothing changed: nothing to write")
		eq(fake.writes, 1, "only the first-load write")
		earn(m, 7, 12)
		local before = waited
		eq(m:saveNow(7), true)
		truthy(waited - before >= CFG.minSecondsBetweenWrites - 0.001, "waited for the gap")
		eq(fake:raw(KEY).data.coins, 12)
		eq(fake.writes, 2)
		eq(m:saveNow(7), true)
		eq(fake.writes, 2, "clean again: no second write")
	end
)

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
			cfg = MANAGER_CFG,
		})
		local loaded, released = 0, 0
		m.Loaded:connect(function()
			loaded += 1
		end)
		m.Released:connect(function()
			released += 1
		end)
		m:join(7)
		eq(m:status(7), "loading")
		eq(m:get(7), nil)
		m:leave(7)
		for _, fn in queued do
			fn()
		end
		eq(loaded, 0, "nobody heard a Loaded for a player who left")
		eq(released, 1)
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
		earn(a, 7, 5)
		a:saveNow(7)
		now += CFG.lockStaleSeconds + 1
		b:join(7)
		eq(b:status(7), "ready")
		local lostSeen = false
		a.StatusChanged:connect(function(_, s: string)
			if s == "lost" then
				lostSeen = true
			end
		end)
		earn(a, 7, 1229)
		a:saveNow(7)
		eq(lostSeen, true)
		eq(a:status(7), "lost")
		eq(a:get(7), nil)
		eq(a:saveNow(7), false)
		eq(fake:raw(KEY).data.coins, 5)
	end
)

Harness.test("flow: shutdown saves every profile in parallel and clears the locks", function()
	reset()
	local fake = Fake.new()
	local m = newManager(fake, "A")
	local leaving = 0
	m.Leaving:connect(function()
		leaving += 1
	end)
	for id = 1, 5 do
		m:join(id)
		earn(m, id, id * 10)
	end
	m:shutdown()
	eq(leaving, 5)
	for id = 1, 5 do
		local raw = fake:raw(ProfileStore.keyFor(id))
		eq(raw.data.coins, id * 10)
		eq(raw.lock, nil)
	end
	m:join(9)
	eq(m:status(9), "none", "no new joins while closing")
end)

Harness.test("flow: shutdown waits for saves still pending and returns inside 30 s", function()
	reset()
	local fake = Fake.new()
	local queued: { () -> () } = {}
	local immediate = true
	local m = ProfileManager.new({
		store = newStore(fake, "A"),
		spawn = function(fn: () -> ())
			if immediate then
				fn()
			else
				table.insert(queued, fn)
			end
		end,
		wait = function(s: number)
			wait(s)
			-- every time the manager waits, one more pending save gets to finish
			local fn = table.remove(queued, 1)
			if fn then
				fn()
			end
		end,
		clock = clock,
		newSignal = Signal.new,
		cfg = MANAGER_CFG,
	})
	for id = 1, 3 do
		m:join(id)
		earn(m, id, 7)
	end
	immediate = false
	local startedAt = now
	m:shutdown()
	eq(#queued, 0, "every pending save was waited for")
	truthy(now - startedAt < 30, "returned inside the 30 s BindToClose window")
	for id = 1, 3 do
		eq(fake:raw(ProfileStore.keyFor(id)).data.coins, 7)
		eq(fake:raw(ProfileStore.keyFor(id)).lock, nil)
	end
end)

Harness.test("flow: shutdown gives up after shutdownSeconds if a save never finishes", function()
	reset()
	local fake = Fake.new()
	local immediate = true
	local m = ProfileManager.new({
		store = newStore(fake, "A"),
		spawn = function(fn: () -> ())
			if immediate then
				fn()
			end -- afterwards: never runs, like a hung DataStore call
		end,
		wait = wait,
		clock = clock,
		newSignal = Signal.new,
		cfg = MANAGER_CFG,
		log = function(t: string)
			table.insert(logs, t)
		end,
	})
	m:join(1)
	immediate = false
	local startedAt = now
	m:shutdown()
	truthy(now - startedAt <= MANAGER_CFG.shutdownSeconds + 1)
	truthy(now - startedAt >= MANAGER_CFG.shutdownSeconds)
	truthy(#logs > 0, "reported")
end)

Harness.test(
	"flow: a daily reward is paid once even if the request repeats or two tabs race",
	function()
		reset()
		local fake = Fake.new()
		local m = newManager(fake, "A")
		m:join(7)
		local key = Receipts.dailyKey(20400)
		local paid = 0
		for _ = 1, 4 do
			local ok = m:grantOnce(7, key, function(d)
				d.coins += 30
				d.daily.lastDay = 20400
				d.daily.streak += 1
				return true
			end)
			if ok then
				paid += 1
			end
		end
		eq(paid, 1)
		local data = m:data(7) :: any
		eq(data.coins, 30)
		eq(data.daily.streak, 1)
		m:leave(7)
		m:join(7)
		local again = m:grantOnce(7, key, function(d)
			d.coins += 30
			return true
		end)
		eq(again, false, "still once after a rejoin")
		eq((m:data(7) :: any).coins, 30)
	end
)

Harness.test("flow: update and grantOnce refuse when there is no profile yet", function()
	reset()
	local m = newManager(Fake.new(), "A")
	local ok, why = m:update(7, function()
		return true
	end)
	eq(ok, false)
	eq(why, "notLoaded")
	local ok2, why2 = m:grantOnce(7, "k", function()
		return true
	end)
	eq(ok2, false)
	eq(why2, "notLoaded")
	m:markDirty(7) -- harmless
	eq(m:saveNow(7), false)
end)
