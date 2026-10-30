--!strict
-- Gap 23: the ranked ladder (pure parts).
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local RankedBook = require("../src/shared/Ranked/RankedBook")
local RankedRules = require("../src/shared/Ranked/RankedRules")
local RemoteDefs = require("../src/shared/RemoteDefs")
local Fake = require("./fake_datastore")
local ProfileStore = require("../src/shared/Profile/ProfileStore")
local SaveRetry = require("../src/shared/SaveRetry")

local test, eq, truthy = Harness.test, Harness.eq, Harness.truthy
local cfg = Config.Ranked

local function result(place: number, field: number?, kills: number?, humans: number?, won: boolean?)
	return {
		place = place,
		field = field or 8,
		kills = kills or 0,
		humans = humans or 3,
		won = if won == nil then place == 1 else won,
	}
end

local function stateAt(points: number, matches: number?): RankedRules.State
	local s = RankedRules.empty()
	s.points = points
	s.matches = matches or cfg.qualifyMatches
	return s
end

-- ===== config =====

test("ranked: tiers start at 0, climb, and have unique ids", function()
	eq(cfg.tiers[1].from, 0)
	local seen: { [string]: boolean } = {}
	for i, tier in cfg.tiers do
		truthy(not seen[tier.id], "unique id " .. tier.id)
		seen[tier.id] = true
		truthy(string.match(tier.id, "^[a-z][a-z0-9_]*$") ~= nil, "id shape")
		if i > 1 then
			truthy(tier.from > cfg.tiers[i - 1].from, "ascending")
			truthy(tier.from - cfg.tiers[i - 1].from >= cfg.divisions * 2, "room for the steps")
		end
	end
	truthy(cfg.tiers[cfg.soloCeilingTier] ~= nil, "solo ceiling is a real tier")
	truthy(cfg.lastPoints < 0 and cfg.winPoints > 0, "winning gains, losing loses")
end)

test("ranked: the remotes exist, the server ones are rate limited", function()
	for _, name in { "RankedRequest", "RankedToggle" } do
		local def = RemoteDefs.byName[name]
		truthy(def ~= nil and def.direction == "toServer" and def.rate ~= nil, name)
	end
	eq(RemoteDefs.byName.RankedUpdate.direction, "toClient")
end)

-- ===== read / save =====

test("ranked: read cleans junk and never errors", function()
	local s =
		RankedRules.read({ points = -5, matches = 0 / 0, stake = "x", peak = "nope", enabled = 1 })
	eq(s.points, 0)
	eq(s.matches, 0)
	eq(s.stake, 0)
	eq(s.peak, cfg.tiers[1].id)
	eq(s.enabled, false, "only true turns it on")
	eq(RankedRules.read(nil).points, 0)
	eq(RankedRules.read("x").matches, 0)
	eq(RankedRules.read({ points = 1e20, season = cfg.season }).points, cfg.maxPoints)
end)

test("ranked: saved state reads back the same", function()
	local s = stateAt(333, 5)
	s.enabled = true
	s.peak = "fuse"
	s.stake = 4
	local back = RankedRules.read(RankedRules.toSaved(s))
	eq(back.points, 333)
	eq(back.matches, 5)
	eq(back.peak, "fuse")
	eq(back.enabled, true)
	eq(back.stake, 4)
end)

test("ranked: a new season keeps part of the points and asks for warm-up again", function()
	local old = {
		season = cfg.season - 1,
		points = 301,
		matches = 9,
		peak = "relay",
		stake = 5,
		enabled = true,
	}
	local s = RankedRules.read(old)
	eq(s.points, math.floor(301 * cfg.seasonKeep))
	eq(s.matches, 0)
	eq(s.stake, 0)
	eq(s.peak, "relay", "the peak is kept for good")
	eq(s.season, cfg.season)
	eq(
		RankedRules.read({ season = cfg.season, points = 301, matches = 9 }).points,
		301,
		"same season untouched"
	)
end)

-- ===== standing =====

test("ranked: tier and step from points", function()
	local s0 = RankedRules.standing(stateAt(0))
	eq(s0.tierName, cfg.tiers[1].name)
	eq(s0.step, 1)
	eq(s0.label, cfg.tiers[1].name .. " III")
	local top = RankedRules.standing(stateAt(cfg.tiers[2].from - 1))
	eq(top.tierId, cfg.tiers[1].id)
	eq(top.step, cfg.divisions)
	eq(top.label, cfg.tiers[1].name .. " I")
	eq(top.toNextTier, 1)
	local next = RankedRules.standing(stateAt(cfg.tiers[2].from))
	eq(next.tierId, cfg.tiers[2].id)
	eq(next.step, 1)
	eq(next.intoStep, 0)
	local last = RankedRules.standing(stateAt(cfg.maxPoints))
	eq(last.tierId, cfg.tiers[#cfg.tiers].id)
	eq(last.step, 0)
	eq(last.nextTierName, nil)
	eq(last.label, cfg.tiers[#cfg.tiers].name)
end)

test("ranked: steps tile the tier with no gaps", function()
	for i = 1, #cfg.tiers - 1 do
		local from, to = cfg.tiers[i].from, cfg.tiers[i + 1].from
		local lastStep, covered = 0, 0
		for p = from, to - 1 do
			local s = RankedRules.standing(stateAt(p))
			eq(s.tierId, cfg.tiers[i].id)
			truthy(s.step >= lastStep and s.step - lastStep <= 1, "steps climb one at a time")
			truthy(s.intoStep >= 0 and s.intoStep < s.stepSize, "inside the step")
			lastStep = s.step
			covered += 1
		end
		eq(lastStep, cfg.divisions)
		eq(covered, to - from)
	end
end)

test("ranked: Unranked until the warm-up matches are done", function()
	local s = RankedRules.standing(stateAt(120, 1))
	eq(s.label, "Unranked")
	eq(s.qualified, false)
	eq(s.qualifyLeft, cfg.qualifyMatches - 1)
	eq(RankedRules.standing(stateAt(120, cfg.qualifyMatches)).qualified, true)
end)

-- ===== scoring =====

test("ranked: first gains most, last loses most, the middle sits between", function()
	eq(RankedRules.pointsFor(result(1)), cfg.winPoints)
	eq(RankedRules.pointsFor(result(8)), cfg.lastPoints)
	local last = nil
	for place = 1, 8 do
		local p = RankedRules.pointsFor(result(place))
		if last then
			truthy(p <= last, "never better for a worse place")
		end
		last = p
	end
	truthy(RankedRules.pointsFor(result(4)) > 0 and RankedRules.pointsFor(result(7)) < 0)
end)

test("ranked: kills add points, with a cap", function()
	eq(RankedRules.pointsFor(result(8, 8, 2)), cfg.lastPoints + 2 * cfg.killPoints)
	eq(RankedRules.pointsFor(result(8, 8, 50)), cfg.lastPoints + cfg.maxKillPoints)
end)

test("ranked: a draw for 1st counts as 2nd, not a win", function()
	eq(RankedRules.pointsFor(result(1, 8, 0, 3, false)), RankedRules.pointsFor(result(2)))
end)

test("ranked: junk numbers never error", function()
	local r = { place = -4, field = 0 / 0, kills = 1e9, humans = 3, won = false }
	truthy(type(RankedRules.pointsFor(r :: any)) == "number")
	eq(
		RankedRules.pointsFor({ place = 99, field = 4, kills = 0, humans = 3, won = false }),
		cfg.lastPoints
	)
end)

test("ranked: enough fighters are needed to count", function()
	eq(RankedRules.counts(cfg.minField), true)
	eq(RankedRules.counts(cfg.minField - 1), false)
	eq(RankedRules.counts(nil), false)
	eq(RankedRules.counts(0 / 0), false)
end)

test("ranked: apply moves points, counts the match and tells promotion", function()
	local edge = cfg.tiers[2].from - 3
	local c = RankedRules.apply(stateAt(edge), result(1))
	eq(c.delta, cfg.winPoints)
	eq(c.state.points, edge + cfg.winPoints)
	eq(c.state.matches, cfg.qualifyMatches + 1)
	eq(c.promoted, true)
	eq(c.demoted, false)
	eq(c.state.peak, cfg.tiers[2].id)
	truthy(c.fromLabel ~= c.toLabel)
end)

test("ranked: the lowest tier cannot lose points", function()
	local c = RankedRules.apply(stateAt(7), result(8))
	eq(c.state.points, 0)
	eq(c.delta, -7)
	eq(RankedRules.apply(stateAt(0), result(8)).delta, 0)
end)

test("ranked: a tier you reached is kept, unless dropping is switched on", function()
	local start = cfg.tiers[3].from
	local c = RankedRules.apply(stateAt(start + 5), result(8))
	eq(c.state.points, start, "stops at the start of the tier")
	eq(c.delta, -5)
	eq(c.demoted, false)
	eq(RankedRules.apply(stateAt(start), result(8)).delta, 0)
	-- with dropping on, the same loss takes you down a tier
	local dropping = table.clone(cfg)
	dropping.dropTiers = true
	local was = stateAt(start)
	was.peak = "fuse"
	local d = RankedRules.apply(was, result(8), dropping)
	eq(d.delta, cfg.lastPoints)
	eq(d.demoted, true)
	eq(d.state.peak, "fuse", "the peak stays as it was")
end)

test("ranked: the peak only grows and only after the warm-up", function()
	local warm = RankedRules.apply(stateAt(cfg.tiers[3].from, 0), result(1))
	eq(warm.state.peak, cfg.tiers[1].id)
	local s = stateAt(cfg.tiers[3].from)
	s.peak = "surge"
	eq(RankedRules.apply(s, result(1)).state.peak, "surge")
end)

test("ranked: a bots-only match gains half and stops under the solo ceiling", function()
	local solo = RankedRules.apply(stateAt(0), result(1, 8, 0, 1))
	eq(solo.delta, math.floor(cfg.winPoints * cfg.soloScale))
	local ceiling = cfg.tiers[cfg.soloCeilingTier].from - 1
	local near = RankedRules.apply(stateAt(ceiling - 2), result(1, 8, 0, 1))
	eq(near.state.points, ceiling)
	local over = RankedRules.apply(stateAt(ceiling + 40), result(1, 8, 0, 1))
	eq(over.delta, 0, "no gain over the ceiling")
	local loss = RankedRules.apply(stateAt(ceiling + 40), result(8, 8, 0, 1))
	eq(loss.delta, cfg.lastPoints, "losses still count")
end)

-- ===== the stake =====

test("ranked: the stake takes the last-place loss and apply hands it back", function()
	local start = stateAt(cfg.tiers[3].from + 50)
	local staked = RankedRules.takeStake(start)
	eq(staked.points, start.points + cfg.lastPoints)
	eq(staked.stake, -cfg.lastPoints)
	local last = RankedRules.apply(staked, result(8))
	eq(last.state.points, start.points + cfg.lastPoints, "same as without the stake")
	local win = RankedRules.apply(staked, result(1))
	eq(win.state.points, start.points + cfg.winPoints)
	eq(win.state.stake, 0)
end)

test("ranked: the stake cannot push you under the floor", function()
	local staked = RankedRules.takeStake(stateAt(5))
	eq(staked.points, 0)
	eq(staked.stake, 5)
	eq(RankedRules.apply(staked, result(1)).state.points, 5 + cfg.winPoints)
	local high = RankedRules.takeStake(stateAt(cfg.tiers[3].from + 2))
	eq(high.points, cfg.tiers[3].from, "stops at the tier start too")
	eq(high.stake, 2)
end)

test("ranked: an old unfinished stake is lost, not doubled", function()
	local once = RankedRules.takeStake(stateAt(200))
	local twice = RankedRules.takeStake(once)
	eq(twice.stake, once.stake, "one stake at a time")
end)

-- ===== the book =====

-- A pretend profile: saved states by user, once-only keys, and a switch that makes saving fail.
local function makeStore()
	local store = {
		saved = {} :: { [number]: RankedRules.State },
		keys = {} :: { [string]: boolean },
		loaded = {} :: { [number]: boolean },
		failing = false,
		told = {} :: { any },
	}
	local book = RankedBook.new({
		read = function(userId)
			if not store.loaded[userId] then
				return nil
			end
			store.saved[userId] = store.saved[userId] or RankedRules.empty()
			return store.saved[userId]
		end,
		write = function(userId, key, change)
			if not store.loaded[userId] or store.failing then
				return nil, "notLoaded"
			end
			if key ~= nil then
				local full = `{userId}:{key}`
				if store.keys[full] then
					return nil, "duplicate"
				end
				store.keys[full] = true
			end
			store.saved[userId] = change(store.saved[userId] or RankedRules.empty())
			return store.saved[userId], nil
		end,
		changed = function(_, payload)
			table.insert(store.told, payload)
		end,
	})
	return store, book
end

test("ranked book: the switch needs a loaded profile and shows in the payload", function()
	local store, book = makeStore()
	book:join(7)
	eq(book:setEnabled(7, true), false, "not loaded yet")
	eq(book:isOn(7), false)
	store.loaded[7] = true
	book:loaded(7)
	eq(book:setEnabled(7, true), true)
	eq(book:isOn(7), true)
	eq(book:get(7).enabled, true)
	eq(store.saved[7].enabled, true)
	eq(book:setEnabled(99, true), false, "stranger")
end)

test("ranked book: a scored match is saved once, even when told twice", function()
	local store, book = makeStore()
	store.loaded[7] = true
	book:join(7)
	book:loaded(7)
	book:score(7, "m1:rk", 1, result(1))
	book:score(7, "m1:rk", 1, result(1))
	eq(store.saved[7].points, cfg.winPoints)
	eq(store.saved[7].matches, 1)
	local shown = book:get(7)
	eq(shown.last.delta, cfg.winPoints)
	eq(shown.last.counted, true)
	eq(shown.saved, true)
end)

test("ranked book: a match scored before the profile loads waits and is not lost", function()
	local store, book = makeStore()
	book:join(7)
	book:score(7, "m1:rk", 1, result(2))
	eq(book:get(7).saved, false)
	eq(book:get(7).points, 0)
	store.loaded[7] = true
	book:loaded(7)
	eq(store.saved[7].matches, 1)
	eq(book:get(7).saved, true)
end)

test("ranked book: a failed save is tried again, in order, once", function()
	local store, book = makeStore()
	store.loaded[7] = true
	book:join(7)
	book:loaded(7)
	store.failing = true
	book:score(7, "m1:rk", 1, result(1))
	book:score(7, "m2:rk", 2, result(1))
	eq(store.saved[7].matches, 0)
	store.failing = false
	book:score(7, "m3:rk", 3, result(8))
	eq(store.saved[7].matches, 3)
	eq(store.saved[7].points, math.max(0, cfg.winPoints * 2 + cfg.lastPoints))
	eq(book:get(7).last.matchId, 3)
end)

test("ranked book: the stake is taken once and a leaver keeps the loss", function()
	local store, book = makeStore()
	store.loaded[7] = true
	book:join(7)
	book:loaded(7)
	store.saved[7].points = 200
	eq(book:stake(7, "m1:rs"), true)
	eq(book:stake(7, "m1:rs"), false, "same fight, same stake")
	eq(store.saved[7].points, 200 + cfg.lastPoints)
	book:leave(7)
	eq(store.saved[7].points, 200 + cfg.lastPoints, "nothing is handed back")
end)

test("ranked book: staying to the end hands the stake back", function()
	local store, book = makeStore()
	store.loaded[7] = true
	book:join(7)
	book:loaded(7)
	store.saved[7].points = 200
	store.saved[7].matches = cfg.qualifyMatches
	book:stake(7, "m1:rs")
	book:score(7, "m1:rk", 1, result(1))
	eq(store.saved[7].points, 200 + cfg.winPoints)
	eq(store.saved[7].stake, 0)
end)

test("ranked book: practice shows a result and changes no points", function()
	local store, book = makeStore()
	store.loaded[7] = true
	book:join(7)
	book:loaded(7)
	book:practice(7, 1, 2, 3)
	eq(book:get(7).last.counted, false)
	eq(book:get(7).last.delta, 0)
	eq(store.saved[7].matches, 0)
end)

test("ranked book: an unknown or gone player is ignored", function()
	local _, book = makeStore()
	book:score(5, "k", 1, result(1))
	book:practice(5, 1, 1, 0)
	eq(book:get(5), nil)
	book:leave(5)
end)

-- ===== on top of the real profile store (fake DataStore) =====

test("ranked: points, the switch and the once-only keys survive leave and rejoin", function()
	local fake = Fake.new()
	local now = 1000
	local store = ProfileStore.new({
		update = function(key: string, transform: (any) -> (any, { number }?))
			return fake:update(key, transform)
		end,
		jobId = "A",
		clock = function()
			return now
		end,
		wait = function(s: number)
			now += s
		end,
		retry = SaveRetry.run,
		cfg = Config.Profile,
		log = function() end,
	})
	local profile = (store:load(7) :: any) :: ProfileStore.Profile
	local function makeBook(p: ProfileStore.Profile)
		local book = RankedBook.new({
			read = function()
				return RankedRules.read(p.data[cfg.profileKey])
			end,
			write = function(_, key, change)
				local out: RankedRules.State? = nil
				local function apply(data: { [string]: any }): boolean
					out = change(RankedRules.read(data[cfg.profileKey]))
					data[cfg.profileKey] = RankedRules.toSaved(out :: RankedRules.State)
					return true
				end
				local ok, why
				if key then
					ok, why = store:grantOnce(p, key, apply)
				else
					ok, why = store:update(p, apply)
				end
				return if ok then out else nil, why
			end,
			changed = function() end,
		})
		book:join(7)
		book:loaded(7)
		return book
	end

	local book = makeBook(profile)
	eq(book:setEnabled(7, true), true)
	book:stake(7, "m:A:1:rs")
	book:score(7, "m:A:1:rk", 1, result(1))
	book:score(7, "m:A:1:rk", 1, result(1)) -- told twice
	store:release(profile)

	local again = (store:load(7) :: any) :: ProfileStore.Profile
	local saved = RankedRules.read(again.data[cfg.profileKey])
	eq(saved.points, cfg.winPoints)
	eq(saved.matches, 1)
	eq(saved.enabled, true)
	eq(saved.stake, 0)
	local book2 = makeBook(again)
	book2:score(7, "m:A:1:rk", 1, result(1)) -- the same match after a rejoin
	eq(RankedRules.read(again.data[cfg.profileKey]).points, cfg.winPoints, "paid once")
	eq(book2:isOn(7), true)
end)
