--!strict
-- Balance sim. An idealised player sweeps non-stop with the current tool stats, makes a 12 s round
-- trip to the Trade Hut for every sale, then buys whatever pays itself back fastest (upgrades,
-- tools, zone gates, helper bots). The milestone times must land within +-30% of the PACING
-- targets in plans/CONTRACTS.md. Tune the catalogs, not the tolerances.
--
-- Sweep model (units of ash per second, by hand):
--   cells   = Tools.cellsHit(reach, arc)        cells one swing covers
--   perCell = E[min(power, X)], X = ash level of a cell (uniform 1..9); sweet spot swings double
--   powerRate = cells x perCell / interval
--   moveRate  = 0.5 x walkSpeed x swathWidth x ashDensity   (you must walk through the ash)
--   rate = 0.9 x 1 / (1/powerRate + 1/moveRate)             so every stat always helps, a bit less
-- The sim ignores how fast the island regrows ash; it prints units/s so S2 can size the regrow.

local process = require("@lune/process")
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local Types = require("../src/shared/Types")
local Economy = require("../src/shared/Rules/Economy")
local Pricing = require("../src/shared/Rules/Pricing")
local StatsCalc = require("../src/shared/Rules/StatsCalc")
local Helpers = require("../src/shared/Catalog/Helpers")
local Tools = require("../src/shared/Catalog/Tools")
local Upgrades = require("../src/shared/Catalog/Upgrades")
local Zones = require("../src/shared/Catalog/Zones")

local SWEEP_EFFICIENCY = 0.9
local ASH_DENSITY = 6 / (Config.World.cellSize * Config.World.cellSize) -- units per stud^2
local MAX_SIM_SECONDS = 14 * 3600

local function clock(s: number?): string
	if s == nil then
		return "never"
	end
	local m = math.floor(s / 60)
	if m >= 60 then
		return string.format("%dh%02dm", math.floor(m / 60), m % 60)
	end
	return string.format("%d:%02d", m, math.floor(s % 60))
end

-- E[min(p, X)] for X uniform on 1..9 (integral of P(X > x) from 0 to p).
local function perCell(p: number): number
	local total, rem = 0, p
	local seg = math.min(rem, 1)
	total += seg
	rem -= seg
	for k = 1, 8 do
		if rem <= 0 then
			break
		end
		seg = math.min(rem, 1)
		total += seg * (9 - k) / 9
		rem -= seg
	end
	return total
end

local function handRate(d: StatsCalc.Full): number
	local cells = Tools.cellsHit(d.reach, d.arcDeg, Config.World.cellSize)
	local s = d.sweetChance
	local per = (1 - s) * perCell(d.power) + s * perCell(d.power * 2)
	local powerRate = cells * per / d.interval
	local half = math.rad(math.min(d.arcDeg, 180) / 2)
	local width = 2 * d.reach * math.sin(half)
	local moveRate = 0.5 * d.walkSpeed * width * ASH_DENSITY
	return SWEEP_EFFICIENCY / (1 / powerRate + 1 / moveRate)
end

local function bestZoneValue(p: Types.Profile): number
	local best = 1
	for _, z in Zones.list do
		if p.zones[tostring(z.id)] == true then
			best = math.max(best, z.value)
		end
	end
	return best
end

local function tripSeconds(d: StatsCalc.Full): number
	return Config.Player.tripSeconds * Config.Player.baseWalkSpeed / d.walkSpeed
end

local function helperCoinsPerSec(p: Types.Profile, d: StatsCalc.Full): number
	return Helpers.coinsPerSecond(
		p.helpers,
		p.helperLevel,
		bestZoneValue(p),
		d.sellMult,
		d.helperMult
	)
end

-- Coins per second of a whole fill-and-sell cycle (steady state).
local function income(p: Types.Profile): number
	local d = StatsCalc.compute(p, {}, 0)
	local fill = d.capacity / handRate(d)
	local cycle = fill + tripSeconds(d)
	local sale = d.capacity * bestZoneValue(p) * d.sellMult * (1 + d.luckyChance)
	return sale / cycle + helperCoinsPerSec(p, d)
end

local function copyProfile(p: Types.Profile): Types.Profile
	local function deep(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deep(x)
		end
		return out
	end
	return deep(p)
end

local function applyBuy(p: Types.Profile, kind: string, id: string | number)
	if kind == "upgrade" then
		p.upgrades[id :: string] = (p.upgrades[id :: string] or 0) + 1
	elseif kind == "tool" then
		p.toolsOwned[id :: string] = true
		local new, cur = Tools.byId[id :: string], Tools.byId[p.tool]
		if new.tier > cur.tier then
			p.tool = new.id
		end
	elseif kind == "zone" then
		p.zones[tostring(id)] = true
	elseif kind == "helper" then
		p.helpers += 1
	elseif kind == "helperUp" then
		p.helperLevel += 1
	elseif kind == "sparkPerk" then
		p.sparkPerks[id :: string] = (p.sparkPerks[id :: string] or 0) + 1
	end
end

type Candidate = { kind: string, id: string | number, price: number, ratio: number }

local function candidates(p: Types.Profile): { Candidate }
	local out: { Candidate } = {}
	local base = income(p)
	local function consider(kind: string, id: string | number)
		local price = Pricing.priceOf(kind, id, p)
		if price == nil then
			return
		end
		local trial = copyProfile(p)
		applyBuy(trial, kind, id)
		local gain = income(trial) - base
		table.insert(
			out,
			{ kind = kind, id = id, price = price, ratio = gain / math.max(1, price) }
		)
	end
	for _, up in Upgrades.list do
		consider("upgrade", up.id)
	end
	for _, tool in Tools.list do
		consider("tool", tool.id)
	end
	for _, zone in Zones.list do
		consider("zone", zone.id)
	end
	consider("helper", 0)
	consider("helperUp", 0)
	return out
end

type Run = {
	times: { [string]: number }, -- milestone name -> seconds
	steps: number,
	seconds: number,
	finished: boolean, -- true when there was nothing left to buy
	profile: Types.Profile,
	atCoolDown: Types.Profile?,
	unitsPerSec: { [string]: number }, -- tool id -> hand units/s the first time it is equipped
	log: { string }, -- every purchase, in order
}

local function run(start: Types.Profile, stopWhen: ((Types.Profile) -> boolean)?): Run
	local p = copyProfile(start)
	local r: Run = {
		times = {},
		steps = 0,
		seconds = 0,
		finished = false,
		profile = p,
		atCoolDown = nil,
		unitsPerSec = {},
		log = {},
	}
	local t = 0
	local function mark(name: string)
		if r.times[name] == nil then
			r.times[name] = t
		end
	end
	local function buyAll()
		while true do
			local list = candidates(p)
			if #list == 0 then
				r.finished = true
				return
			end
			local best = list[1]
			for _, c in list do
				if c.ratio > best.ratio then
					best = c
				end
			end
			local pick: Candidate? = nil
			if best.price <= p.coins then
				pick = best
			else
				for _, c in list do
					-- the very first purchase is eager: a new player grabs the first cheap upgrade
					local eager = #r.log == 0
					if c.price <= p.coins and (eager or c.ratio >= 0.5 * best.ratio) then
						if pick == nil or c.ratio > pick.ratio then
							pick = c
						end
					end
				end
			end
			if pick == nil then
				return
			end
			p.coins -= pick.price
			table.insert(
				r.log,
				`{clock(t)} {pick.kind} {pick.id} for {pick.price} (now {math.floor(income(p))} coins/s)`
			)
			applyBuy(p, pick.kind, pick.id)
			if pick.kind == "upgrade" then
				mark("first_upgrade")
			elseif pick.kind == "tool" then
				mark(pick.id :: string)
				if r.unitsPerSec[p.tool] == nil then
					r.unitsPerSec[p.tool] = handRate(StatsCalc.compute(p, {}, 0))
				end
			elseif pick.kind == "zone" then
				mark("zone_" .. tostring(pick.id))
			elseif pick.kind == "helper" then
				mark("helper_" .. tostring(p.helpers))
			elseif pick.kind == "helperUp" then
				mark("helperLevel_" .. tostring(p.helperLevel))
			end
		end
	end

	r.unitsPerSec[p.tool] = handRate(StatsCalc.compute(p, {}, 0))
	while t < MAX_SIM_SECONDS and not r.finished do
		r.steps += 1
		local d = StatsCalc.compute(p, {}, t)
		local trip = tripSeconds(d)
		local toSale = d.capacity / handRate(d) + trip / 2
		local sale = math.floor(d.capacity * bestZoneValue(p) * d.sellMult * (1 + d.luckyChance))
		local gain = sale + helperCoinsPerSec(p, d) * toSale
		t += toSale
		p.coins += gain
		p.runCoins += gain
		p.lifetimeCoins += gain
		mark("first_sale")
		if r.atCoolDown == nil and Economy.canCoolDown(p) then
			mark("cool_down")
			r.atCoolDown = copyProfile(p)
		end
		buyAll()
		if stopWhen and stopWhen(p) then
			break
		end
		local after = StatsCalc.compute(p, {}, t)
		local back = tripSeconds(after) / 2
		local backGain = helperCoinsPerSec(p, after) * back
		t += back
		p.coins += backGain
		p.runCoins += backGain
		p.lifetimeCoins += backGain
	end
	r.seconds = t
	return r
end

-- ===== the one big run, shared by the tests below =====
local first = run(Economy.blankProfile(), nil)

Harness.test("pacing: milestone times (printed for humans)", function()
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
		print(string.format("       %-14s %s", n, clock(first.times[n])))
	end
	if process.env.PACING_LOG then
		for i = 1, math.min(#first.log, 400) do
			print("       " .. first.log[i])
		end
	end
	print(
		string.format(
			"       everything bought at %s in %d sim steps",
			clock(first.seconds),
			first.steps
		)
	)
	for _, tool in Tools.list do
		local u = first.unitsPerSec[tool.id]
		if u then
			print(
				string.format(
					"       %-12s sweeps about %.1f ash/s when first equipped",
					tool.id,
					u
				)
			)
		end
	end
	Harness.truthy(first.times["first_sale"] ~= nil, "sold something")
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

Harness.test("pacing: first sale before 25 s, first upgrade before 45 s", function()
	Harness.truthy(
		(first.times["first_sale"] or 1e9) < 25,
		"first sale " .. clock(first.times["first_sale"])
	)
	Harness.truthy(
		(first.times["first_upgrade"] or 1e9) < 45,
		"first upgrade " .. clock(first.times["first_upgrade"])
	)
end)

for _, target in TARGETS do
	Harness.test(`pacing: {target.name} near {clock(target.seconds)} (+-30%)`, function()
		local at = first.times[target.name]
		Harness.truthy(at ~= nil, target.name .. " never reached")
		local ratio = (at :: number) / target.seconds
		Harness.truthy(
			ratio >= 0.7 and ratio <= 1.3,
			`{target.name} at {clock(at)}, wanted {clock(target.seconds)}`
		)
	end)
end

Harness.test("pacing: Volcano Vacuum is a 3 hour+ goal", function()
	local at = first.times["volcano_vac"]
	Harness.truthy(at ~= nil, "volcano_vac never bought")
	Harness.truthy(
		(at :: number) >= 3 * 3600 and (at :: number) <= 5 * 3600,
		"volcano_vac at " .. clock(at)
	)
end)

Harness.test("pacing: nothing is a dead end, and the sim is short", function()
	Harness.truthy(
		first.finished,
		"sim ended with things still unbought at " .. clock(first.seconds)
	)
	Harness.truthy(first.steps < 4000, `{first.steps} steps`)
	local p = first.profile
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
	local hand = handRate(StatsCalc.compute(p, {}, 0))
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
	local snap = first.atCoolDown
	Harness.truthy(snap ~= nil, "cool down never offered")
	local gained = Economy.sparksFor((snap :: Types.Profile).runCoins)
	print(`       first Cool Down at {clock(first.times["cool_down"])} gives {gained} Sparks`)
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
				applyBuy(reset, "sparkPerk", id)
				local coins, toolId = Economy.perkGrant(id, reset.sparkPerks[id])
				reset.coins += coins
				if toolId then
					applyBuy(reset, "tool", toolId)
				end
				bought = true
				break
			end
		end
	end
	local second = run(reset, function(p)
		return p.zones["5"] == true
	end)
	local t1, t2 = first.times["zone_5"] :: number, second.seconds
	print(`       run 2 reaches Lava Heart at {clock(t2)} (run 1: {clock(t1)})`)
	Harness.truthy(t2 < t1 * 0.85, "second run should be clearly faster")
	Harness.truthy(t2 > t1 * 0.3, "second run should not be trivial")
end)
