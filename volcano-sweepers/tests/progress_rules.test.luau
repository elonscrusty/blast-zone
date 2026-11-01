--!strict
local Harness = require("./harness")
local AshGrid = require("../src/shared/Ash/AshGrid")
local Config = require("../src/shared/Config")
local ProgressRules = require("../src/shared/Sweep/ProgressRules")
local Rng = require("../src/shared/Rng")
local Tools = require("../src/shared/Catalog/Tools")
local Zones = require("../src/shared/Catalog/Zones")

local ISLAND = ProgressRules.ISLAND

-- ===== milestones =====

Harness.test("milestones: each one fires once while the fraction climbs", function()
	local t = ProgressRules.newTracker()
	local fired: { number } = {}
	local f = 0
	while f <= 1.0001 do
		local m = ProgressRules.update(t, 1, math.min(f, 1))
		if m then
			table.insert(fired, m)
		end
		f += 0.01
	end
	Harness.eq(#fired, 4)
	Harness.eq(fired[1], 0.25)
	Harness.eq(fired[2], 0.5)
	Harness.eq(fired[3], 0.75)
	Harness.eq(fired[4], 1.0)
	-- staying at the top does nothing more
	Harness.eq(ProgressRules.update(t, 1, 1), nil)
	Harness.eq(ProgressRules.update(t, 1, 0.999), nil)
end)

Harness.test("milestones: a jump over several celebrates only the highest, once", function()
	local t = ProgressRules.newTracker()
	Harness.eq(ProgressRules.update(t, 3, 0.1), nil)
	Harness.eq(ProgressRules.update(t, 3, 0.8), 0.75)
	Harness.eq(ProgressRules.update(t, 3, 0.8), nil)
	-- 25% and 50% were skipped, not owed
	Harness.eq(ProgressRules.update(t, 3, 0.76), nil)
	Harness.eq(ProgressRules.update(t, 3, 1.0), 1.0)
end)

Harness.test("milestones: wobbling around a line does not repeat the party", function()
	local t = ProgressRules.newTracker()
	Harness.eq(ProgressRules.update(t, 2, 0.26), 0.25)
	for _ = 1, 20 do
		Harness.eq(ProgressRules.update(t, 2, 0.24), nil)
		Harness.eq(ProgressRules.update(t, 2, 0.26), nil)
		Harness.eq(ProgressRules.update(t, 2, 0.17), nil) -- 25% re-arms only under 15%
	end
end)

Harness.test("milestones: re-arms only after a deep dip (50% re-arms under 30%)", function()
	local t = ProgressRules.newTracker()
	Harness.eq(ProgressRules.update(t, 2, 0.51), 0.5)
	Harness.eq(ProgressRules.update(t, 2, 0.31), nil) -- an Ash Storm sized dip: not enough
	Harness.eq(ProgressRules.update(t, 2, 0.5), nil)
	Harness.eq(ProgressRules.update(t, 2, 0.24), nil) -- dipped: 50% is armed again
	Harness.eq(ProgressRules.update(t, 2, 0.5), 0.5)
	Harness.eq(ProgressRules.update(t, 2, 0.5), nil)
end)

Harness.test("milestones: parties keep 5 minutes apart, and a waiting one is not lost", function()
	local t = ProgressRules.newTracker()
	Harness.eq(ProgressRules.update(t, 1, 0.3, 100), 0.25)
	Harness.eq(ProgressRules.update(t, 2, 0.3, 120), nil, "another zone waits")
	Harness.eq(ProgressRules.update(t, ISLAND, 0.3, 200), nil, "the island waits too")
	Harness.eq(ProgressRules.update(t, 2, 0.3, 100 + ProgressRules.PARTY_COOLDOWN), 0.25)
	Harness.eq(ProgressRules.update(t, ISLAND, 0.3, 100 + ProgressRules.PARTY_COOLDOWN + 5), nil)
	Harness.eq(
		ProgressRules.update(t, ISLAND, 0.3, 100 + 2 * ProgressRules.PARTY_COOLDOWN),
		0.25,
		"still owed after the cooldown"
	)
	-- without `now` (the start-up seeding) there is no cooldown
	local s = ProgressRules.newTracker()
	Harness.eq(ProgressRules.update(s, 1, 0.3), 0.25)
	Harness.eq(ProgressRules.update(s, 2, 0.3), 0.25)
end)

Harness.test("gifts: only recent sweepers, never more than their own best zone", function()
	Harness.eq(ProgressRules.giftFor(5, 1), ProgressRules.gift(1), "a newcomer gets a beach gift")
	Harness.eq(ProgressRules.giftFor(2, 5), ProgressRules.gift(2), "a veteran gets the zone's gift")
	Harness.eq(
		ProgressRules.giftFor(ISLAND, 3),
		math.min(ProgressRules.gift(ISLAND), ProgressRules.gift(3))
	)
	Harness.eq(
		ProgressRules.giftFor(4, 0 / 0),
		ProgressRules.gift(1),
		"bad zone counts as the beach"
	)
	Harness.truthy(ProgressRules.earnsGift(100, 150))
	Harness.eq(ProgressRules.earnsGift(100, 100 + ProgressRules.GIFT_RECENT_SECONDS + 1), false)
	Harness.eq(ProgressRules.earnsGift(0, 10), false, "never swept")
	Harness.eq(ProgressRules.earnsGift(0 / 0, 10), false)
end)

Harness.test("milestones: a deep dip re-arms the lower ones too", function()
	local t = ProgressRules.newTracker()
	Harness.eq(ProgressRules.update(t, 4, 0.76), 0.75)
	Harness.eq(ProgressRules.update(t, 4, 0.1), nil)
	Harness.eq(ProgressRules.update(t, 4, 0.3), 0.25)
	Harness.eq(ProgressRules.update(t, 4, 0.55), 0.5)
	Harness.eq(ProgressRules.update(t, 4, 0.8), 0.75)
end)

Harness.test("milestones: zones and the island are tracked separately", function()
	local t = ProgressRules.newTracker()
	Harness.eq(ProgressRules.update(t, 1, 0.3), 0.25)
	Harness.eq(ProgressRules.update(t, 2, 0.3), 0.25)
	Harness.eq(ProgressRules.update(t, ISLAND, 0.3), 0.25)
	Harness.eq(ProgressRules.update(t, 1, 0.3), nil)
	Harness.eq(ProgressRules.update(t, ISLAND, 0.55), 0.5)
	Harness.eq(ProgressRules.update(t, 2, 0.3), nil)
end)

Harness.test("milestones: start below 25% is silent, bad numbers are ignored", function()
	local t = ProgressRules.newTracker()
	Harness.eq(ProgressRules.update(t, 1, 0.15), nil)
	Harness.eq(ProgressRules.update(t, 1, 0), nil)
	Harness.eq(ProgressRules.update(t, 1, 0 / 0), nil)
	Harness.eq(ProgressRules.update(t, 1, -3), nil)
	Harness.eq(ProgressRules.update(t, 1, 0.249), nil)
	Harness.eq(ProgressRules.update(t, 1, 0.25), 0.25)
end)

Harness.test("milestones: 100% needs a really clean zone, 0.9999 is not it", function()
	local t = ProgressRules.newTracker()
	Harness.eq(ProgressRules.update(t, 5, 0.9999), 0.75)
	Harness.eq(ProgressRules.update(t, 5, 1), 1.0)
end)

Harness.test("percent: milestone to whole percent", function()
	Harness.eq(ProgressRules.percent(0.25), 25)
	Harness.eq(ProgressRules.percent(0.5), 50)
	Harness.eq(ProgressRules.percent(0.75), 75)
	Harness.eq(ProgressRules.percent(1.0), 100)
end)

-- ===== gifts =====

Harness.test("gifts: zone value x 400, island x 4000, always clamped", function()
	Harness.eq(ProgressRules.gift(1), 400)
	Harness.eq(ProgressRules.gift(2), 1200)
	Harness.eq(ProgressRules.gift(3), 3200)
	Harness.eq(ProgressRules.gift(4), 8800)
	Harness.eq(ProgressRules.gift(5), 24000)
	Harness.eq(ProgressRules.gift(ISLAND), 4000 * ProgressRules.ISLAND_UNIT_VALUE)
	for z = -2, 9 do
		local g = ProgressRules.gift(z)
		Harness.truthy(g >= ProgressRules.GIFT_MIN and g <= ProgressRules.GIFT_MAX, "clamp")
		Harness.eq(g, math.floor(g), "whole coins")
	end
	Harness.eq(ProgressRules.gift(77), ProgressRules.GIFT_MIN, "unknown zone gets the floor")
	for _, z in Zones.list do
		Harness.eq(ProgressRules.gift(z.id), 400 * z.value)
	end
end)

-- ===== progress remote =====

Harness.test("progress: only sends when something moved by 0.005", function()
	local last = { [0] = 0.2, [1] = 0.3, [2] = 0.1 }
	local cur = { [0] = 0.2, [1] = 0.3, [2] = 0.1 }
	Harness.eq(ProgressRules.changedEnough(last, cur, 0.005), false)
	cur[1] = 0.3049
	Harness.eq(ProgressRules.changedEnough(last, cur, 0.005), false)
	cur[1] = 0.305
	Harness.eq(ProgressRules.changedEnough(last, cur, 0.005), true)
	cur[1] = 0.3
	cur[2] = 0.09
	Harness.eq(ProgressRules.changedEnough(last, cur, 0.005), true, "downwards counts too")
	Harness.eq(ProgressRules.changedEnough({}, cur, 0.005), true, "nothing sent yet")
	local copy: { [number]: number } = {}
	ProgressRules.copyInto(copy, cur)
	Harness.eq(ProgressRules.changedEnough(copy, cur, 0.005), false)
	Harness.near(ProgressRules.round3(0.12349), 0.123)
	Harness.near(ProgressRules.round3(0.1236), 0.124)
end)

-- ===== delta chunking =====

local function flatOf(pairsCount: number): { number }
	local flat = {}
	for k = 1, pairsCount do
		flat[k * 2 - 1] = k
		flat[k * 2] = k % 10
	end
	return flat
end

Harness.test("chunking: nothing in, nothing out", function()
	Harness.eq(#ProgressRules.chunkDelta({}, 400), 0)
	Harness.eq(#ProgressRules.chunkDelta({ 5 }, 400), 0, "dangling half pair")
end)

Harness.test("chunking: small lists are passed through as they are", function()
	local flat = flatOf(10)
	local chunks = ProgressRules.chunkDelta(flat, 400)
	Harness.eq(#chunks, 1)
	Harness.eq(chunks[1], flat)
	local exact = flatOf(400)
	local c2 = ProgressRules.chunkDelta(exact, 400)
	Harness.eq(#c2, 1)
	Harness.eq(#c2[1], 800)
end)

Harness.test("chunking: never more than 400 pairs, order and pairs kept", function()
	for _, count in { 401, 800, 801, 1234, 3000 } do
		local flat = flatOf(count)
		local chunks = ProgressRules.chunkDelta(flat, 400)
		Harness.eq(#chunks, math.ceil(count / 400), `chunks for {count}`)
		local seen = 0
		for _, chunk in chunks do
			Harness.truthy(#chunk % 2 == 0, "whole pairs")
			Harness.truthy(#chunk <= 800, "<= 400 pairs")
			for k = 1, #chunk, 2 do
				seen += 1
				Harness.eq(chunk[k], seen, "index order")
				Harness.eq(chunk[k + 1], seen % 10, "level stays with its index")
			end
		end
		Harness.eq(seen, count)
	end
end)

Harness.test("chunking: odd tail is dropped, bad size is made sane", function()
	local flat = flatOf(5)
	table.insert(flat, 99)
	local chunks = ProgressRules.chunkDelta(flat, 2)
	Harness.eq(#chunks, 3)
	Harness.eq(#chunks[3], 2)
	local c0 = ProgressRules.chunkDelta(flatOf(3), 0)
	Harness.eq(#c0, 3, "size 0 becomes 1 pair per chunk")
end)

Harness.test("chunking: a real grid delta round-trips through chunks", function()
	local server = AshGrid.new("full")
	local client = AshGrid.new("full")
	server:takeDirty()
	server:rain(Rng.new(1), 0.1) -- no-op on a full grid
	for i = 1, server.N, 3 do
		server:set(i, i % 7)
	end
	local flat = server:takeDirty()
	local chunks = ProgressRules.chunkDelta(flat, 400)
	Harness.truthy(#chunks > 1, "many chunks")
	for _, chunk in chunks do
		client:applyDelta(chunk)
	end
	Harness.eq(client:encode(), server:encode())
end)

-- ===== regrow =====

Harness.test("regrow: rate scales with players and is capped", function()
	Harness.eq(ProgressRules.regrowRate(0), 0)
	Harness.eq(ProgressRules.regrowRate(-4), 0)
	Harness.eq(ProgressRules.regrowRate(0 / 0), 0)
	Harness.near(ProgressRules.regrowRate(1), 0.9)
	Harness.near(ProgressRules.regrowRate(2), 2.0)
	local prev = 0
	for n = 1, Config.Game.MaxPlayers do
		local r = ProgressRules.regrowRate(n)
		Harness.truthy(r > prev, "more players, more regrow")
		Harness.truthy(r <= ProgressRules.REGROW_CAP, "cap")
		prev = r
	end
	Harness.near(ProgressRules.regrowRate(16), 17.4)
	Harness.near(
		ProgressRules.regrowRate(200),
		ProgressRules.regrowRate(16),
		1e-9,
		"no more than a full server"
	)
end)

-- Units per second a lone starter player pulls while sweeping fresh ash, measured on the real
-- grid: walks along the Fern Forest ring swinging every 4 studs, average units per swing / interval.
local function soloSweepRate(): number
	local tool = Tools.list[1]
	local g = AshGrid.new("full")
	local rng = Rng.new(7)
	local allowed: { [number]: boolean } =
		{ [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }
	local scratch = { reach = tool.reach, arcDeg = tool.arcDeg, power = tool.power }
	-- walk along the ring of zone 2 (radius 165), a swing every 4 studs, always facing forward
	local steps = 120
	local removed = 0
	local swings = 0
	for s = 0, steps - 1 do
		local a = math.rad(200 + s * 1.4)
		local px, pz = 165 * math.cos(a), 165 * math.sin(a)
		local dx, dz = -math.sin(a), math.cos(a)
		local r = g:sweep(px, pz, dx, dz, scratch, allowed, 1e9, rng, 0, nil)
		removed += r.removedUnits
		swings += 1
	end
	return removed / swings / tool.interval
end

Harness.test("regrow: a lone starter player can never out-clear 5x the solo regrow", function()
	local perSwingRate = soloSweepRate()
	-- backpack and trips: the pack fills in capacity / rate seconds, then tripSeconds to sell
	local cap = Config.Player.baseCapacity
	local sustained = cap / (cap / perSwingRate + Config.Player.tripSeconds)
	print(
		`       solo starter: {string.format("%.1f", perSwingRate)} u/s while sweeping, `
			.. `{string.format("%.1f", sustained)} u/s with trips; solo regrow {ProgressRules.regrowRate(
				1
			)} u/s`
	)
	Harness.truthy(
		sustained <= ProgressRules.regrowRate(1) * 5,
		`solo clears {sustained} u/s, regrow x5 = {ProgressRules.regrowRate(1) * 5}`
	)
	-- and even the raw sweeping peak is within reach of 5x x a handful of players
	Harness.truthy(perSwingRate <= ProgressRules.regrowRate(1) * 5 * 6, "peak sanity")
end)

Harness.test("regrow: budget carries fractions and never floods", function()
	local carry = 0
	local total = 0
	for _ = 1, 100 do -- 100 ticks of 2 s with 1 player: 0.9 x 200 = 180 units
		local whole
		whole, carry = ProgressRules.regrowBudget(1, 2, carry)
		Harness.truthy(whole >= 0 and carry >= 0 and carry < 1, "valid")
		total += whole
	end
	Harness.truthy(total >= 179 and total <= 180, `total {total}`)
	-- a stall of an hour is treated as 5 s, not 3600 s
	local whole = ProgressRules.regrowBudget(16, 3600, 0)
	Harness.eq(whole, math.floor(ProgressRules.regrowRate(16) * 5))
	Harness.eq((ProgressRules.regrowBudget(0, 2, 0)), 0)
	Harness.eq((ProgressRules.regrowBudget(4, -5, 0)), 0)
end)

Harness.test("regrow: the real grid gets exactly the budget (when there is room)", function()
	local g = AshGrid.new(0)
	local rng = Rng.new(3)
	local added = g:regrow(rng, (ProgressRules.regrowBudget(4, 2, 0)), nil)
	Harness.eq(added, 8) -- floor(4.2 x 2)
	Harness.eq(g.totalUnits, 8)
end)

-- ===== adaptive regrow =====

Harness.test("adaptive: no boost while the island is dirty, base rate for 1..16 players", function()
	for n = 1, 16 do
		Harness.near(ProgressRules.adaptiveRate(n, 0.15, 0.3, 0), ProgressRules.regrowRate(n))
	end
	Harness.eq(ProgressRules.adaptiveRate(0, 0.99, 0.99, 100), 0, "nobody there, nothing grows")
	Harness.near(ProgressRules.adaptiveRate(4, 0.7, 0.2, 0), ProgressRules.regrowRate(4), 1e-9)
end)

Harness.test("adaptive: clean island or a nearly bare zone boosts up to BOOST_MULT", function()
	local base = ProgressRules.regrowRate(2)
	local top = ProgressRules.BOOST_MULT
	Harness.near(ProgressRules.adaptiveRate(2, 0.95, 0.5, 0), base * top, 1e-9, "island 95% clean")
	Harness.near(
		ProgressRules.adaptiveRate(2, 0.2, 0.95, 0),
		base * top,
		1e-9,
		"one zone 95% clean"
	)
	local mid = ProgressRules.adaptiveRate(2, 0.825, 0.2, 0)
	Harness.near(mid, base * (1 + top) / 2, 1e-9, "halfway up the ramp")
	-- the cleanest zone at 60% clean = ~40% of its ash left: still no boost, 70%+ is where it starts
	Harness.near(ProgressRules.adaptiveRate(2, 0.2, 0.6, 0), base, 1e-9)
	Harness.truthy(ProgressRules.adaptiveRate(2, 0.2, 0.7, 0) > base)
end)

Harness.test(
	"adaptive: monotonic in clean fraction, players and sweep rate; always capped",
	function()
		local prev = 0
		for c = 0, 100 do
			local r = ProgressRules.adaptiveRate(3, c / 100, c / 100, 20)
			Harness.truthy(r >= prev - 1e-9, "more clean never less regrow")
			prev = r
		end
		prev = 0
		for s = 0, 500, 5 do
			local r = ProgressRules.adaptiveRate(3, 0.9, 0.9, s)
			Harness.truthy(r >= prev - 1e-9, "faster sweeping never less regrow")
			Harness.truthy(r <= ProgressRules.totalCap(3) + 1e-9, "cap")
			prev = r
		end
		prev = 0
		for n = 1, 16 do
			local r = ProgressRules.adaptiveRate(n, 0.9, 0.9, 30, 20 * n)
			Harness.truthy(r >= prev - 1e-9, "more players never less regrow")
			Harness.truthy(r <= ProgressRules.totalCap(n) + 1e-9, "cap")
			prev = r
		end
		Harness.eq(ProgressRules.adaptiveRate(16, 1, 1, 1e9), ProgressRules.TOTAL_CAP)
		Harness.eq(ProgressRules.adaptiveRate(16, 1, 1, 0, 1e9), ProgressRules.TOTAL_CAP)
	end
)

Harness.test(
	"adaptive: the island feeds a fast sweeper but always puts back less than they take",
	function()
		-- two fast sweepers (~58 u/s together) on a half-clean island: 35% comes back
		Harness.near(ProgressRules.demandShare(0.5), 0.35, 1e-9)
		Harness.near(ProgressRules.adaptiveRate(2, 0.5, 0.5, 58), 0.35 * 58, 1e-9)
		-- nearly clean: up to 85%
		Harness.near(ProgressRules.demandShare(0.95), 0.85, 1e-9)
		Harness.near(ProgressRules.adaptiveRate(2, 0.95, 0.95, 58), 0.85 * 58, 1e-9)
		-- the zone being emptied counts even when the cheap zones are full
		Harness.near(ProgressRules.adaptiveRate(2, 0.2, 0.95, 58), 0.85 * 58, 1e-9)
		-- one kid alone is capped at TOTAL_CAP_PER_PLAYER
		Harness.near(
			ProgressRules.adaptiveRate(1, 0.95, 0.95, 58),
			ProgressRules.TOTAL_CAP_PER_PLAYER,
			1e-9
		)
		for c = 0, 100 do
			Harness.truthy(ProgressRules.demandShare(c / 100) < 1, "share stays below 1")
		end
		-- bad numbers never break it
		Harness.near(
			ProgressRules.adaptiveRate(2, 0 / 0, 0 / 0, 0 / 0),
			ProgressRules.regrowRate(2),
			1e-9
		)
		Harness.near(
			ProgressRules.adaptiveRate(2, 0.5, 0.5, -10),
			ProgressRules.regrowRate(2),
			1e-9
		)
		Harness.near(
			ProgressRules.adaptiveRate(2, 0.5, 0.5, math.huge),
			ProgressRules.regrowRate(2),
			1e-9
		)
	end
)

Harness.test("adaptive: smoothing follows the sweep rate", function()
	local avg = 0
	for _ = 1, 40 do
		avg = ProgressRules.smooth(avg, 30)
	end
	Harness.near(avg, 30, 0.1)
	for _ = 1, 40 do
		avg = ProgressRules.smooth(avg, 0)
	end
	Harness.near(avg, 0, 0.1)
	Harness.near(ProgressRules.smooth(5, 0 / 0), 5 * 0.7, 1e-9)
end)

Harness.test("adaptive: budget uses the extra inputs", function()
	local plain = ProgressRules.regrowBudget(1, 2, 0)
	local boosted = ProgressRules.regrowBudget(2, 2, 0, 0.95, 0.95, 58)
	Harness.eq(plain, 1)
	Harness.eq(boosted, math.floor(0.85 * 58 * 2))
	local fed = ProgressRules.regrowBudget(2, 2, 0, 0.95, 0.95, 0, 40)
	Harness.eq(fed, math.floor(ProgressRules.paceShare(2) * 40 * 2))
end)

-- Island sim on the real grid: `players` sweepers each removing `perPlayer` units per second from
-- random bumpy ground, regrowth by the adaptive budget every 2 s. Returns the minutes until the
-- whole-island clean fraction first reaches `target` (nil if not within `maxMinutes`).
local function minutesToClean(
	players: number,
	perPlayer: number,
	target: number,
	maxMinutes: number
): number?
	local g = AshGrid.new("full")
	local rng = Rng.new(5)
	for i = 1, g.N do
		g:set(i, ProgressRules.startLevel(rng, 0.85, 9))
	end
	local ema, carry, removedSince = 0, 0, 0
	local zoneIds = g.layout.zoneIds
	for sec = 1, maxMinutes * 60 do
		local want = players * perPlayer
		local done = 0
		local tries = 0
		while done < want and tries < want * 6 do
			tries += 1
			if g:remove(rng:int(1, g.N), 1) > 0 then
				done += 1
			end
		end
		removedSince += done
		if sec % 2 == 0 then
			ema = ProgressRules.smooth(ema, removedSince / 2)
			removedSince = 0
			local cleanest = 0
			for _, z in zoneIds do
				cleanest = math.max(cleanest, g:zoneClean(z))
			end
			local whole
			whole, carry =
				ProgressRules.regrowBudget(players, 2, carry, g:totalClean(), cleanest, ema)
			g:regrow(rng, whole, nil)
		end
		if g:totalClean() >= target then
			return sec / 60
		end
	end
	return nil
end

Harness.test(
	"adaptive: milestones stay reachable from a lone Leaf Blower to a full server",
	function()
		local cases = {
			{ n = 1, per = 5.2, target = 0.75, within = 150 },
			{ n = 1, per = 10, target = 0.75, within = 90 },
			{ n = 4, per = 5, target = 0.75, within = 60 },
			{ n = 4, per = 10, target = 0.95, within = 60 },
			{ n = 16, per = 4, target = 0.95, within = 60 },
			{ n = 16, per = 10, target = 0.95, within = 30 },
			{ n = 1, per = 58, target = 0.95, within = 30 },
		}
		for _, c in cases do
			local m = minutesToClean(c.n, c.per, c.target, c.within)
			print(
				`       {c.n} player(s) at {c.per} u/s each reach {c.target * 100}% clean in {m and string.format(
					"%.1f",
					m
				) or "never"} min`
			)
			Harness.truthy(m ~= nil, `{c.n} x {c.per} u/s never reached {c.target}`)
		end
	end
)

Harness.test(
	"adaptive: a lone starter player keeps finding ash and cannot drain the island",
	function()
		-- Twig Broom pace with trips (2 u/s): the island must stay mostly full for a long time
		local g = AshGrid.new("full")
		local rng = Rng.new(9)
		for i = 1, g.N do
			g:set(i, ProgressRules.startLevel(rng, 0.85, 9))
		end
		local carry, ema, removed = 0, 0, 0
		for sec = 1, 3600 do
			for _ = 1, 2 do
				g:remove(rng:int(1, g.N), 1)
				removed += 1
			end
			if sec % 2 == 0 then
				ema = ProgressRules.smooth(ema, 4)
				local whole
				whole, carry =
					ProgressRules.regrowBudget(1, 2, carry, g:totalClean(), g:zoneClean(2), ema)
				g:regrow(rng, whole, nil)
			end
		end
		Harness.truthy(g:totalClean() < 0.7, `an hour of twig sweeping left {g:totalClean()} clean`)
	end
)

-- ===== starting fill =====

Harness.test("start fill: average is the target, every level is valid", function()
	local rng = Rng.new(11)
	local n = 20000
	local sum = 0
	local seen: { [number]: boolean } = {}
	for _ = 1, n do
		local v = ProgressRules.startLevel(rng, 0.85, 9)
		Harness.truthy(v >= 0 and v <= 9 and v == math.floor(v), "valid level")
		sum += v
		seen[v] = true
	end
	Harness.near(sum / n / 9, 0.85, 0.02, "mean fill")
	Harness.truthy(seen[9] and seen[6], "some variety")
	-- 0 and 1 targets behave
	Harness.eq(ProgressRules.startLevel(Rng.new(1), 0, 9) <= 2, true)
	Harness.eq(ProgressRules.startLevel(Rng.new(1), 1, 9) >= 7, true)
end)

-- ===== dropping ash back =====

Harness.test("drop: units spread over nearby cells, one per cell per pass", function()
	local g = AshGrid.new(0)
	local cells = g.layout.cellsInRadius(0, -165, 12)
	Harness.truthy(#cells >= 5, "cells near")
	local put = ProgressRules.spreadDrop(g, cells, 5, 0)
	Harness.eq(put, 5)
	Harness.eq(g.totalUnits, 5)
	local touched = 0
	for _, j in cells do
		if g.levels[j] > 0 then
			touched += 1
			Harness.eq(g.levels[j], 1)
		end
	end
	Harness.eq(touched, 5)
end)

Harness.test("drop: second pass stacks, full cells are skipped, extra units are lost", function()
	local g = AshGrid.new(0)
	local cells = { 10, 11, 12 }
	Harness.eq(ProgressRules.spreadDrop(g, cells, 7, 0), 7)
	Harness.eq(g.levels[10] + g.levels[11] + g.levels[12], 7)
	Harness.truthy(g.levels[10] >= 2 and g.levels[10] <= 3, "even spread")
	-- more than the cells can hold
	local g2 = AshGrid.new(0)
	Harness.eq(ProgressRules.spreadDrop(g2, { 1, 2 }, 100, 0), 18)
	Harness.eq(g2.levels[1], 9)
	Harness.eq(g2.levels[2], 9)
	-- full grid
	local g3 = AshGrid.new("full")
	Harness.eq(ProgressRules.spreadDrop(g3, { 1, 2 }, 5, 0), 0)
end)

Harness.test("drop: bad input places nothing", function()
	local g = AshGrid.new(0)
	Harness.eq(ProgressRules.spreadDrop(g, {}, 5, 0), 0)
	Harness.eq(ProgressRules.spreadDrop(g, { 1 }, 0, 0), 0)
	Harness.eq(ProgressRules.spreadDrop(g, { 1 }, -3, 0), 0)
	Harness.eq(ProgressRules.spreadDrop(g, { 1 }, 0 / 0, 0), 0)
	Harness.eq(g.totalUnits, 0)
	-- the start offset only rotates which cell gets the first unit
	Harness.eq(ProgressRules.spreadDrop(g, { 1, 2, 3 }, 1, 7), 1)
	Harness.eq(g.levels[2], 1) -- 7 % 3 = 1 -> cells[2]
end)

Harness.test("adaptive: pace feeds big tools, more with friends, never past the cap", function()
	local twig =
		ProgressRules.pace({ reach = 7, arcDeg = 90, power = 1, interval = 0.34, capacity = 30 })
	local volcano = ProgressRules.pace({
		reach = 22,
		arcDeg = 270,
		power = 4,
		interval = 0.22,
		capacity = 2000,
	})
	Harness.truthy(twig > 0.5 and twig < 3, `twig pace {twig}`)
	Harness.truthy(volcano > twig * 10, `volcano pace {volcano}`)
	local function junk(d: {
		reach: number,
		arcDeg: number,
		power: number,
		interval: number,
		capacity: number,
	})
		Harness.eq(ProgressRules.pace(d), 0)
	end
	junk({ reach = 0 / 0, arcDeg = 90, power = 1, interval = 0.3, capacity = 30 })
	junk({ reach = 7, arcDeg = 90, power = 1, interval = 0, capacity = 30 })
	junk({ reach = 7, arcDeg = 90, power = 1, interval = 0.3, capacity = -5 })
	-- share: half solo, grows with friends, always below 1
	Harness.near(ProgressRules.paceShare(1), 0.5, 1e-9)
	local prev = 0
	for n = 1, 16 do
		local sh = ProgressRules.paceShare(n)
		Harness.truthy(sh >= prev and sh < 1, `share {sh} for {n}`)
		prev = sh
	end
	Harness.eq(ProgressRules.paceShare(0), 0)
	Harness.eq(ProgressRules.paceShare(0 / 0), 0)
	-- a dirty island ignores pace; an emptied zone gets it
	local base = ProgressRules.regrowRate(1)
	Harness.near(ProgressRules.adaptiveRate(1, 0.05, 0.05, 0, 20), base, 1e-9)
	Harness.near(ProgressRules.adaptiveRate(1, 0.1, 0.9, 0, 20), 0.5 * 20, 1e-9)
	Harness.near(ProgressRules.adaptiveRate(1, 0.1, 0.9, 0, 1e6), ProgressRules.totalCap(1), 1e-9)
	Harness.near(
		ProgressRules.adaptiveRate(1, 0.1, 0.95, 0, 0 / 0),
		base * ProgressRules.BOOST_MULT,
		1e-9
	)
	-- the cap grows with players, up to TOTAL_CAP
	Harness.eq(ProgressRules.totalCap(1), ProgressRules.TOTAL_CAP_PER_PLAYER)
	Harness.eq(ProgressRules.totalCap(0), 0)
	Harness.truthy(ProgressRules.totalCap(16) <= ProgressRules.TOTAL_CAP)
	Harness.truthy(ProgressRules.totalCap(8) > ProgressRules.totalCap(4))
end)

Harness.test("regrow: lands in small piles, never over the cell max, exactly the budget", function()
	local g = AshGrid.new(0)
	local rng = Rng.new(21)
	local added = g:regrow(rng, 600, nil)
	Harness.eq(added, 600)
	Harness.eq(g.totalUnits, 600)
	local cells, biggest = 0, 0
	for j = 1, g.N do
		local v = g.levels[j]
		if v > 0 then
			cells += 1
			biggest = math.max(biggest, v)
		end
	end
	Harness.truthy(cells < 600 * 0.8, `{cells} cells for 600 units: piles, not dust`)
	Harness.truthy(biggest <= g.max, "max")
	-- a full grid takes nothing
	local full = AshGrid.new("full")
	Harness.eq(full:regrow(rng, 50, nil), 0)
end)

return {}
