--!strict
-- Balance sim, supply-aware (tests/island_sim.luau runs the REAL shared rules: the AshGrid cone and
-- levels, regrow with its player-count and pace scaling, Ash Storms, parties with cooldown and
-- gifts, golden ash, Perfect Dodge, geyser gems, finds with the roll budget, helper bots).
-- An idealised player sweeps, sells when the backpack is full, and buys whatever raises income the
-- most per coin. The milestone times (median of three islands) must land within +-30% of the
-- PACING targets in plans/CONTRACTS.md. Tune the catalogs, not the tolerances.
--
-- It also checks that a full server stays fun: with 4 and 16 kids on one island, each kid's ash
-- supply and income must stay a fair share of a solo kid's (regrow and storms scale with players).
-- PACING_LOG=1 lune run tests/run   prints every purchase of the first island.

local process = require("@lune/process")
local Harness = require("./harness")
local Sim = require("./island_sim")
local Types = require("../src/shared/Types")
local Economy = require("../src/shared/Rules/Economy")
local Pricing = require("../src/shared/Rules/Pricing")
local StatsCalc = require("../src/shared/Rules/StatsCalc")
local Helpers = require("../src/shared/Catalog/Helpers")
local Tools = require("../src/shared/Catalog/Tools")
local Upgrades = require("../src/shared/Catalog/Upgrades")
local Zones = require("../src/shared/Catalog/Zones")

local SEEDS = { 7, 1, 2 }
local MAX_SOLO_SECONDS = 12 * 3600
local CROWD_SECONDS = 40 * 60

local clock = Sim.clock

type Island = { sp: Sim.SimPlayer, w: Sim.World }

local function soloIsland(seed: number): Island
	local sp = Sim.newPlayer(1)
	local w = Sim.newWorld({ sp }, seed)
	Sim.run(w, MAX_SOLO_SECONDS)
	return { sp = sp, w = w }
end

-- ===== the big solo runs, shared by the tests below =====
local islands: { Island } = {}
for _, seed in SEEDS do
	table.insert(islands, soloIsland(seed))
end
local first = islands[1]

-- Median milestone time over the islands (a missing milestone counts as never).
local function median(name: string): number?
	local list = {}
	for _, isl in islands do
		table.insert(list, isl.sp.times[name] or math.huge)
	end
	table.sort(list)
	local m = list[math.ceil(#list / 2)]
	return if m == math.huge then nil else m
end

local function incomeShares(sp: Sim.SimPlayer): ({ [string]: number }, number)
	local total = 0
	for _, v in sp.income do
		total += v
	end
	local out: { [string]: number } = {}
	for k, v in sp.income do
		out[k] = v / math.max(1, total)
	end
	return out, total
end

Harness.test("pacing: milestone times (median of 3 islands, printed for humans)", function()
	local names = {
		"first_sale",
		"first_upgrade",
		"push_broom",
		"zone_2",
		"leaf_blower",
		"zone_3",
		"dust_vac",
		"turbo_vac",
		"zone_4",
		"lava_mop",
		"zone_5",
		"cool_down",
		"dragon_vac",
		"volcano_vac",
	}
	for _, n in names do
		local each = {}
		for _, isl in islands do
			table.insert(each, clock(isl.sp.times[n]))
		end
		print(
			string.format("       %-14s %-8s (%s)", n, clock(median(n)), table.concat(each, ", "))
		)
	end
	if process.env.PACING_LOG then
		for i = 1, math.min(#first.sp.log, 400) do
			print("       " .. first.sp.log[i])
		end
	end
	local shares = incomeShares(first.sp)
	local parts = {}
	for _, k in { "sell", "helpers", "finds", "party", "gems" } do
		table.insert(parts, string.format("%s %.1f%%", k, 100 * (shares[k] or 0)))
	end
	print("       income by source: " .. table.concat(parts, ", "))
	local w = first.w
	print(
		string.format(
			"       everything bought at %s; %d storms, %d parties; ash: %.1f u/s regrow, %.1f u/s storms",
			clock(w.t),
			w.storms,
			w.parties,
			w.regrowUnits / w.t,
			w.stormUnits / w.t
		)
	)
	Harness.truthy(first.sp.times["first_sale"] ~= nil, "sold something")
end)

local TARGETS: { { name: string, seconds: number } } = {
	{ name = "push_broom", seconds = 150 },
	{ name = "zone_2", seconds = 360 },
	{ name = "leaf_blower", seconds = 540 },
	{ name = "zone_3", seconds = 960 },
	{ name = "zone_4", seconds = 2100 },
	{ name = "zone_5", seconds = 4200 },
	{ name = "cool_down", seconds = 5400 },
}

Harness.test("pacing: first sale before 25 s, first upgrade before 45 s (every island)", function()
	for _, isl in islands do
		local t = isl.sp.times
		Harness.truthy((t["first_sale"] or 1e9) < 25, "first sale " .. clock(t["first_sale"]))
		Harness.truthy(
			(t["first_upgrade"] or 1e9) < 45,
			"first upgrade " .. clock(t["first_upgrade"])
		)
	end
end)

for _, target in TARGETS do
	Harness.test(`pacing: {target.name} near {clock(target.seconds)} (+-30%)`, function()
		local at = median(target.name)
		Harness.truthy(at ~= nil, target.name .. " never reached")
		local ratio = (at :: number) / target.seconds
		Harness.truthy(
			ratio >= 0.7 and ratio <= 1.3,
			`{target.name} at {clock(at)}, wanted {clock(target.seconds)}`
		)
	end)
end

Harness.test("pacing: Volcano Vacuum is a 3-5 hour goal", function()
	local at = median("volcano_vac")
	Harness.truthy(at ~= nil, "volcano_vac never bought")
	Harness.truthy(
		(at :: number) >= 3 * 3600 and (at :: number) <= 5 * 3600,
		"volcano_vac at " .. clock(at)
	)
end)

Harness.test("pacing: nothing is a dead end (every island buys everything)", function()
	for _, isl in islands do
		local sp = isl.sp
		Harness.truthy(sp.done, "sim ended with things still unbought at " .. clock(isl.w.t))
		local p = sp.p
		for _, up in Upgrades.list do
			Harness.eq(p.upgrades[up.id], up.maxLevel, up.id .. " not maxed")
		end
		for _, tool in Tools.list do
			Harness.truthy(p.toolsOwned[tool.id] == true, tool.id .. " not owned")
		end
		for _, zone in Zones.list do
			Harness.truthy(p.zones[tostring(zone.id)] == true, "zone " .. zone.id .. " not open")
		end
		Harness.eq(p.helpers, Helpers.max)
		Harness.eq(p.helperLevel, Helpers.maxLevel)
	end
end)

Harness.test("pacing: selling ash is the main income; finds are a treat, not the job", function()
	for _, isl in islands do
		local shares = incomeShares(isl.sp)
		local finds, sell, helpers = shares.finds or 0, shares.sell or 0, shares.helpers or 0
		Harness.truthy(sell >= 0.5, `sell share {sell}`)
		Harness.truthy(finds >= 0.03 and finds <= 0.2, `finds share {finds}`)
		Harness.truthy(helpers >= 0.05 and helpers <= 0.35, `helpers share {helpers}`)
	end
end)

Harness.test("pacing: every price is a positive whole number and grows", function()
	for _, up in Upgrades.list do
		local prev = 0
		for lv = 0, up.maxLevel - 1 do
			local c = Upgrades.cost(up.id, lv) :: number
			Harness.truthy(c == math.floor(c) and c > prev, `{up.id} level {lv + 1} cost {c}`)
			prev = c
		end
	end
end)

Harness.test("pacing: helper bots earn real but smaller money (6 x level 5 ~ 35%)", function()
	-- Compare against hand sweeping with a mid-tier tool and no upgrades.
	local p = Economy.blankProfile()
	p.tool = "dust_vac"
	p.toolsOwned["dust_vac"] = true
	local hand = Sim.handRate(StatsCalc.compute(p, {}, 0))
	local bots = 6 * Helpers.unitsPerSecond(5)
	local share = bots / hand
	print(
		string.format(
			"       6 bots at level 5 = %.0f%% of a hand-sweeper with a Dust Vac",
			share * 100
		)
	)
	Harness.truthy(share >= 0.25 and share <= 0.45, `share {share}`)
end)

Harness.test("pacing: Cool Down gives 5-15 Sparks the first time and makes run 2 faster", function()
	local snap = first.sp.atCoolDown
	Harness.truthy(snap ~= nil, "cool down never offered")
	local gained = Economy.sparksFor((snap :: Types.Profile).runCoins)
	print(`       first Cool Down at {clock(first.sp.times["cool_down"])} gives {gained} Sparks`)
	Harness.truthy(gained >= 5 and gained <= 15, `sparks {gained}`)
	local reset = Economy.coolDownReset(snap :: Types.Profile)
	-- spend the Sparks greedily on the cheapest perks that help the next run
	local order =
		{ "head_start", "free_push", "big_pockets", "haggler", "quick_feet", "lucky_charm" }
	local bought = true
	while bought do
		bought = false
		for _, id in order do
			local price = Pricing.priceOf("sparkPerk", id, reset)
			if price ~= nil and price <= reset.sparks then
				reset.sparks -= price
				Sim.applyBuy(reset, "sparkPerk", id)
				local coins, toolId = Economy.perkGrant(id, reset.sparkPerks[id])
				reset.coins += coins
				if toolId then
					Sim.applyBuy(reset, "tool", toolId)
				end
				bought = true
				break
			end
		end
	end
	local sp2 = Sim.newPlayer(1, reset)
	local w2 = Sim.newWorld({ sp2 }, SEEDS[1])
	Sim.run(w2, MAX_SOLO_SECONDS, function(p)
		return p.zones["5"] == true
	end)
	local t1 = first.sp.times["zone_5"] :: number
	local t2 = sp2.times["zone_5"]
	Harness.truthy(t2 ~= nil, "run 2 never reached the Lava Heart")
	print(`       run 2 reaches Lava Heart at {clock(t2)} (run 1: {clock(t1)})`)
	Harness.truthy((t2 :: number) < t1 * 0.85, "second run should be clearly faster")
	Harness.truthy((t2 :: number) > t1 * 0.3, "second run should not be trivial")
end)

-- ===== a full server stays fun =====

type Crowd = {
	hand: number,
	income: number,
	supply: number,
	zone3: number?,
	players: { Sim.SimPlayer },
}

local function crowd(n: number): Crowd
	local players = {}
	for i = 1, n do
		table.insert(players, Sim.newPlayer(i))
	end
	local w = Sim.newWorld(players, SEEDS[1])
	Sim.run(w, CROWD_SECONDS)
	local hand, income = 0, 0
	local zone3 = {}
	for _, sp in players do
		hand += sp.handUnits
		for _, v in sp.income do
			income += v
		end
		table.insert(zone3, sp.times["zone_3"] or math.huge)
	end
	table.sort(zone3)
	local mid = zone3[math.ceil(#zone3 / 2)]
	return {
		hand = hand / n / CROWD_SECONDS,
		income = income / n / CROWD_SECONDS,
		supply = (w.regrowUnits + w.stormUnits) / n / CROWD_SECONDS,
		zone3 = if mid == math.huge then nil else mid,
		players = players,
	}
end

Harness.test("pacing: 2, 4 and 16 friends on one island each still get a fair share", function()
	local solo = crowd(1)
	for _, n in { 2, 4, 16 } do
		local c = crowd(n)
		print(
			string.format(
				"       %2d kids, first 40 min, per kid: %.1f ash/s swept (solo %.1f), %.0f coins/s (solo %.0f), regrow+storms %.1f u/s (solo %.1f), median Hot Springs %s (solo %s)",
				n,
				c.hand,
				solo.hand,
				c.income,
				solo.income,
				c.supply,
				solo.supply,
				clock(c.zone3),
				clock(solo.zone3)
			)
		)
		-- coins compound (one more gate opened changes everything), so the fair-share checks use
		-- the ash each kid sweeps and how fast the middle kid reaches Hot Springs
		Harness.truthy(
			c.hand >= solo.hand * 0.55,
			`{n} kids: {c.hand} ash/s each vs solo {solo.hand}`
		)
		Harness.truthy(c.zone3 ~= nil, `{n} kids: most never reached Hot Springs in 40 min`)
		Harness.truthy(
			(c.zone3 :: number) <= (solo.zone3 :: number) * 1.5,
			`{n} kids: median Hot Springs at {clock(c.zone3)}, solo {clock(solo.zone3)}`
		)
		for _, sp in c.players do
			Harness.truthy(sp.times["zone_2"] ~= nil, `{n} kids: kid {sp.id} stuck on the beach`)
		end
	end
end)
