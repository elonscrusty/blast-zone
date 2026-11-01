--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local Types = require("../src/shared/Types")
local Rng = require("../src/shared/Rng")
local Economy = require("../src/shared/Rules/Economy")
local Pricing = require("../src/shared/Rules/Pricing")
local StatsCalc = require("../src/shared/Rules/StatsCalc")
local Finds = require("../src/shared/Catalog/Finds")
local Helpers = require("../src/shared/Catalog/Helpers")
local SparkPerks = require("../src/shared/Catalog/SparkPerks")
local Tools = require("../src/shared/Catalog/Tools")
local Upgrades = require("../src/shared/Catalog/Upgrades")
local Zones = require("../src/shared/Catalog/Zones")

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

-- ===== StatsCalc =====
Harness.test("stats: a new player has the base numbers", function()
	local d = StatsCalc.compute(Economy.blankProfile(), {}, 0)
	local twig = Tools.byId["twig_broom"]
	Harness.eq(d.reach, twig.reach)
	Harness.eq(d.arcDeg, twig.arcDeg)
	Harness.eq(d.power, twig.power)
	Harness.eq(d.interval, twig.interval)
	Harness.eq(d.capacity, Config.Player.baseCapacity)
	Harness.eq(d.walkSpeed, Config.Player.baseWalkSpeed)
	Harness.eq(d.sellMult, 1)
	Harness.eq(d.luck, 1)
	Harness.eq(d.armor, 0)
	Harness.eq(d.sweetChance, 0)
	Harness.eq(d.luckyChance, 0)
end)

Harness.test("stats: tool, upgrades and perks add up", function()
	local p = Economy.blankProfile()
	p.tool = "leaf_blower"
	p.upgrades = { power = 5, speed = 5, reach = 5, backpack = 5, walk = 4, luck = 3, armor = 6 }
	p.sparkPerks = { big_pockets = 2, quick_feet = 2, lucky_charm = 2 }
	local d = StatsCalc.compute(p, {}, 0)
	local t = Tools.byId["leaf_blower"]
	Harness.near(d.reach, t.reach * 1.2, 1e-9)
	Harness.near(d.power, t.power * 1.4, 1e-9)
	Harness.near(d.interval, t.interval / 1.25, 1e-9)
	Harness.eq(d.capacity, math.floor((30 + t.capacityBonus + 20) * 1.5))
	Harness.near(d.walkSpeed, 17 * 1.1, 1e-9)
	Harness.near(d.luck, 1 + 0.3 + 0.2, 1e-9)
	Harness.near(d.armor, 0.3, 1e-9)
end)

Harness.test("stats: maxed upgrades stay inside the caps; junk levels are harmless", function()
	local p = Economy.blankProfile()
	for _, up in Upgrades.list do
		p.upgrades[up.id] = 999
	end
	local d = StatsCalc.compute(p, {}, 0)
	Harness.truthy(d.armor <= Config.Player.maxArmor + 1e-9)
	Harness.truthy(d.interval >= Config.Player.minInterval)
	Harness.truthy(d.luckyChance <= 0.15 and d.sweetChance <= 0.35)
	p.upgrades = { power = 0 / 0, speed = -4, reach = 2.7 }
	p.tool = "not_a_tool"
	local d2 = StatsCalc.compute(p, {}, 0)
	Harness.eq(d2.power, Tools.byId["twig_broom"].power)
	Harness.near(d2.reach, Tools.byId["twig_broom"].reach * 1.08, 1e-9)
end)

Harness.test(
	"stats: sell multiplier formula (upgrades + sets + sparks) x party x perfect",
	function()
		local p = Economy.blankProfile()
		p.upgrades = { sell = 4 } -- +20%
		p.setsClaimed = { beach = true, forest = true } -- +2% +3%
		p.sparks = 10
		local sparkBonus = StatsCalc.sparkBonus(10)
		Harness.truthy(sparkBonus > 0.45 and sparkBonus < 0.5, "10 sparks is just under +50%")
		local plain = 1 + 0.2 + 0.05 + sparkBonus
		Harness.near(StatsCalc.compute(p, {}, 100).sellMult, plain, 1e-9)

		-- buffs only count while endsAt > now
		Harness.near(StatsCalc.compute(p, { party = 150 }, 100).sellMult, plain * 2, 1e-9)
		local pm = Config.Economy.perfectMult
		Harness.near(StatsCalc.compute(p, { perfect = 150 }, 100).sellMult, plain * pm, 1e-9)
		Harness.near(
			StatsCalc.compute(p, { party = 150, perfect = 101 }, 100).sellMult,
			plain * 2 * pm,
			1e-9
		)
		Harness.near(StatsCalc.compute(p, { party = 100 }, 100).sellMult, plain, 1e-9)
		Harness.near(StatsCalc.compute(p, { party = 50, perfect = 99 }, 100).sellMult, plain, 1e-9)
		-- golden is NOT a multiplier (golden cells are worth more themselves)
		Harness.near(StatsCalc.compute(p, { golden = 500 }, 100).sellMult, plain, 1e-9)
	end
)

Harness.test("stats: Sparks add 5% each at first and never pass x10 total", function()
	Harness.eq(StatsCalc.sparkBonus(0), 0)
	Harness.eq(StatsCalc.sparkBonus(-5), 0)
	Harness.near(StatsCalc.sparkBonus(1), 0.05, 0.001)
	Harness.truthy(StatsCalc.sparkBonus(20) < 1.0 and StatsCalc.sparkBonus(20) > 0.8)
	local prev = 0
	for _, n in { 1, 5, 25, 100, 400, 2000, 1e6, 1e12 } do
		local b = StatsCalc.sparkBonus(n)
		Harness.truthy(b > prev or n >= 1e6, "keeps growing, slowly")
		Harness.truthy(b <= Config.Economy.sparkBonusCap + 1e-9, "cap")
		prev = b
	end
	Harness.truthy(1 + StatsCalc.sparkBonus(1e12) <= 10 + 1e-9, "never more than x10 from Sparks")
	-- Sparks spent on perks still count
	local p = Economy.blankProfile()
	p.sparks = 4
	p.sparkPerks = { free_push = 1 } -- cost 3
	Harness.eq(StatsCalc.totalSparks(p), 7)
	Harness.near(StatsCalc.compute(p, {}, 0).sellMult, 1 + StatsCalc.sparkBonus(7), 1e-9)
end)

Harness.test("stats: spark perks feed helper power and buff time", function()
	local p = Economy.blankProfile()
	p.sparkPerks = { bot_boost = 3, long_buffs = 2 }
	local d = StatsCalc.compute(p, {}, 0)
	Harness.near(d.helperMult, 1.3, 1e-9)
	Harness.near(d.buffTime, 1.2, 1e-9)
end)

-- ===== selling =====
Harness.test("sell: pays carried value x sell multiplier, whole coins", function()
	local p = Economy.blankProfile()
	local d = StatsCalc.compute(p, {}, 0)
	local rng = Rng.new(1)
	local coins, bonus, lucky = Economy.sellValue(120, d, rng)
	Harness.eq(coins, 120)
	Harness.eq(bonus, 0)
	Harness.eq(lucky, false)
	p.upgrades = { sell = 2 }
	p.zones["2"] = true
	local d2 = StatsCalc.compute(p, { party = 10 }, 0)
	local c2 = Economy.sellValue(33, d2, rng)
	Harness.eq(c2, math.floor(33 * 1.1 * 2 + 0.5))
	Harness.eq((Economy.sellValue(0, d, rng)), 0)
end)

Harness.test("sell: bad numbers never pay negative or NaN", function()
	local d = StatsCalc.compute(Economy.blankProfile(), {}, 0)
	local rng = Rng.new(2)
	for _, v in { -50, 0 / 0, math.huge, -math.huge } do
		local coins = Economy.sellValue(v, d, rng)
		Harness.truthy(coins >= 0 and coins == coins and coins < math.huge, tostring(v))
	end
	d.sellMult = -3
	Harness.eq((Economy.sellValue(100, d, rng)), 0)
end)

Harness.test("sell: Lucky Coins doubles about the right share of sales", function()
	local p = Economy.blankProfile()
	p.upgrades = { lucky_coins = 10 } -- 10%
	local d = StatsCalc.compute(p, {}, 0)
	Harness.near(d.luckyChance, 0.1, 1e-9)
	local rng = Rng.new(2026)
	local doubles, total, paid = 0, 20000, 0
	for _ = 1, total do
		local coins, bonus, lucky = Economy.sellValue(50, d, rng)
		paid += coins
		if lucky then
			doubles += 1
			Harness.eq(coins, 100)
			Harness.eq(bonus, 50)
		else
			Harness.eq(coins, 50)
			Harness.eq(bonus, 0)
		end
	end
	Harness.near(doubles / total, 0.1, 0.01, "double rate")
	Harness.near(paid / total, 55, 1.0, "average pay")
end)

Harness.test("sell: no rng is used when there is no luck", function()
	local d = StatsCalc.compute(Economy.blankProfile(), {}, 0)
	local rng = Rng.new(77)
	local before = rng.state
	Economy.sellValue(100, d, rng)
	Harness.eq(rng.state, before)
end)

-- ===== sparks + cool down =====
Harness.test("sparks: sublinear, start at the minimum, 5-15 for the first Cool Down", function()
	local min = Config.Economy.coolDownMinRunCoins
	Harness.eq(Economy.sparksFor(0), 0)
	Harness.eq(Economy.sparksFor(-10), 0)
	Harness.eq(Economy.sparksFor(0 / 0), 0)
	local first = Economy.sparksFor(min)
	Harness.truthy(first >= 5 and first <= 15, "first cool down gives " .. first)
	local prev = 0
	for i = 1, 12 do
		local s = Economy.sparksFor(min * 2 ^ (i - 1))
		Harness.truthy(s >= prev, "never goes down")
		prev = s
	end
	-- doubling the coins must give well under double the sparks
	Harness.truthy(Economy.sparksFor(min * 4) < 2.5 * Economy.sparksFor(min))
	Harness.truthy(Economy.sparksFor(min * 100) <= 12 * first)
end)

Harness.test("cool down: offered only after enough coins this run", function()
	local p = Economy.blankProfile()
	Harness.eq(Economy.canCoolDown(p), false)
	p.runCoins = Config.Economy.coolDownMinRunCoins - 1
	Harness.eq(Economy.canCoolDown(p), false)
	p.runCoins = Config.Economy.coolDownMinRunCoins
	Harness.eq(Economy.canCoolDown(p), true)
end)

local function richProfile(): Types.Profile
	local p = Economy.blankProfile()
	p.coins = 123456
	p.runCoins = Config.Economy.coolDownMinRunCoins * 4
	p.lifetimeCoins = p.runCoins + 999
	p.sparks = 7
	p.coolDowns = 2
	p.tool = "lava_mop"
	p.toolsOwned = { twig_broom = true, push_broom = true, lava_mop = true }
	p.upgrades = { power = 9, sell = 4 }
	p.zones = { ["1"] = true, ["2"] = true, ["3"] = true }
	p.helpers = 4
	p.helperLevel = 6
	p.sparkPerks = { head_start = 2, haggler = 1 }
	p.finds = { shiny_shell = 3, fire_opal = 1 }
	p.setsClaimed = { beach = true }
	p.goalsClaimed = { first_sales = true }
	p.daily = { lastDay = 20500, streak = 5 }
	p.stats.ashSwept = 88888
	p.stats.sellCount = 41
	p.settings.music = false
	p.tutorialDone = true
	return p
end

Harness.test("cool down: keeps the right fields exactly and resets the rest", function()
	local p = richProfile()
	local before = deepCopy(p)
	local out, gained = Economy.coolDownReset(p)
	Harness.truthy(deepEqual(p, before), "the input profile must not change")
	Harness.eq(gained, Economy.sparksFor(before.runCoins))
	Harness.truthy(gained >= 1)

	-- same set of fields
	for k in before :: any do
		Harness.truthy((out :: any)[k] ~= nil, "lost field " .. k)
	end
	for k in out :: any do
		Harness.truthy((before :: any)[k] ~= nil, "new field " .. k)
	end

	-- kept
	Harness.eq(out.version, before.version)
	Harness.eq(out.lifetimeCoins, before.lifetimeCoins)
	Harness.eq(out.sparks, before.sparks + gained)
	Harness.eq(out.coolDowns, before.coolDowns + 1)
	for _, key in
		{ "sparkPerks", "finds", "setsClaimed", "goalsClaimed", "daily", "stats", "settings" }
	do
		Harness.truthy(deepEqual((out :: any)[key], (before :: any)[key]), "kept " .. key)
	end
	Harness.eq(out.tutorialDone, true)

	-- reset (head_start level 2 = 250 x 3 = 750 starting coins)
	Harness.eq(out.coins, 750)
	Harness.eq(out.runCoins, 0)
	Harness.eq(out.tool, "twig_broom")
	Harness.truthy(deepEqual(out.toolsOwned, { twig_broom = true }), "only the twig broom")
	Harness.truthy(deepEqual(out.upgrades, {}), "upgrades")
	Harness.truthy(deepEqual(out.zones, { ["1"] = true }), "only zone 1")
	Harness.eq(out.helpers, 0)
	Harness.eq(out.helperLevel, 0)

	-- the new profile shares no tables with the old one
	out.finds["new_find"] = 1
	out.stats.ashSwept = 0
	out.sparkPerks["haggler"] = 5
	Harness.eq(before.finds["new_find"], nil)
	Harness.eq(p.stats.ashSwept, 88888)
	Harness.eq(p.sparkPerks["haggler"], 1)
end)

Harness.test("cool down: Free Push Broom perk starts you with it equipped", function()
	local p = richProfile()
	p.sparkPerks["free_push"] = 1
	local out = Economy.coolDownReset(p)
	Harness.eq(out.tool, "push_broom")
	Harness.truthy(deepEqual(out.toolsOwned, { twig_broom = true, push_broom = true }))
	Harness.eq(Economy.startingCoins(p), 750)
	Harness.eq(Economy.startingCoins(Economy.blankProfile()), 0)
end)

Harness.test("cool down: buying a perk afterwards helps right away (perkGrant)", function()
	local coins, tool = Economy.perkGrant("head_start", 1)
	Harness.eq(coins, 250)
	Harness.eq(tool, nil)
	local c2 = Economy.perkGrant("head_start", 3)
	Harness.eq(c2, SparkPerks.value("head_start", 3) - SparkPerks.value("head_start", 2))
	local c3, t3 = Economy.perkGrant("free_push", 1)
	Harness.eq(c3, 0)
	Harness.eq(t3, "push_broom")
	local c4, t4 = Economy.perkGrant("haggler", 1)
	Harness.eq(c4, 0)
	Harness.eq(t4, nil)
end)

-- ===== pricing =====
Harness.test("pricing: upgrades follow the catalog, Haggler makes them cheaper", function()
	local p = Economy.blankProfile()
	Harness.eq(Pricing.priceOf("upgrade", "power", p), Upgrades.cost("power", 0))
	p.upgrades["power"] = 3
	Harness.eq(Pricing.priceOf("upgrade", "power", p), Upgrades.cost("power", 3))
	p.sparkPerks["haggler"] = 10
	local base = Upgrades.cost("power", 3) :: number
	Harness.eq(Pricing.priceOf("upgrade", "power", p), math.floor(base * 0.85 + 0.5))
	Harness.truthy((Pricing.priceOf("upgrade", "power", p) :: number) >= 1)
	p.upgrades["power"] = Upgrades.byId["power"].maxLevel
	Harness.eq(Pricing.priceOf("upgrade", "power", p), nil)
	Harness.eq(Pricing.priceOf("upgrade", "bogus", p), nil)
	Harness.eq(Pricing.priceOf("upgrade", 7, p), nil)
end)

Harness.test("pricing: tools, zones in order, bots, sparks perks", function()
	local p = Economy.blankProfile()
	Harness.eq(Pricing.priceOf("tool", "twig_broom", p), nil) -- already owned
	Harness.eq(Pricing.priceOf("tool", "push_broom", p), Tools.byId["push_broom"].price)
	Harness.eq(Pricing.priceOf("tool", "nope", p), nil)
	p.toolsOwned["push_broom"] = true
	Harness.eq(Pricing.priceOf("tool", "push_broom", p), nil)

	Harness.eq(Pricing.priceOf("zone", 1, p), nil)
	Harness.eq(Pricing.priceOf("zone", 2, p), Zones.price(2))
	Harness.eq(Pricing.priceOf("zone", "2", p), Zones.price(2)) -- saved keys are strings
	Harness.eq(Pricing.priceOf("zone", 3, p), nil) -- gates open one ring at a time
	Harness.eq(Pricing.priceOf("zone", 9, p), nil)
	Harness.eq(Pricing.priceOf("zone", 2.5, p), nil)
	p.zones["2"] = true
	Harness.eq(Pricing.priceOf("zone", 3, p), Zones.price(3))

	Harness.eq(Pricing.priceOf("helperUp", 0, p), nil) -- no bots yet
	Harness.eq(Pricing.priceOf("helper", 0, p), Helpers.price(0))
	p.helpers = 6
	Harness.eq(Pricing.priceOf("helper", 0, p), nil)
	Harness.eq(Pricing.priceOf("helperUp", 0, p), Helpers.upgradeCost(0))
	p.helperLevel = 15
	Harness.eq(Pricing.priceOf("helperUp", 0, p), nil)

	Harness.eq(Pricing.priceOf("sparkPerk", "head_start", p), 2)
	p.sparkPerks["head_start"] = 8
	Harness.eq(Pricing.priceOf("sparkPerk", "head_start", p), nil)
	Harness.eq(Pricing.priceOf("nonsense", "x", p), nil)
end)

Harness.test("pricing: reason is nil only when you can buy it right now", function()
	local p = Economy.blankProfile()
	Harness.eq(Pricing.reason("upgrade", "power", p), "Need 12 more coins")
	p.coins = 12
	Harness.eq(Pricing.reason("upgrade", "power", p), nil)
	Harness.eq(Pricing.reason("tool", "twig_broom", p), "You own this")
	Harness.eq(Pricing.reason("tool", "nope", p), "Unknown tool")
	Harness.eq(Pricing.reason("zone", 3, p), "Open Fern Forest first")
	Harness.eq(Pricing.reason("zone", 1, p), "Already open")
	Harness.eq(Pricing.reason("helperUp", 0, p), "Get a helper bot first")
	p.upgrades["power"] = 99
	Harness.eq(Pricing.reason("upgrade", "power", p), "Maxed out!")
	Harness.eq(Pricing.reason("sparkPerk", "free_push", p), "Need 3 more Sparks")
	p.sparks = 3
	Harness.eq(Pricing.reason("sparkPerk", "free_push", p), nil)
	Harness.truthy(Pricing.reason("whatever", "x", p) ~= nil)
end)

Harness.test("finds sets: claimed sets raise the sell multiplier by their reward", function()
	local p = Economy.blankProfile()
	local total = 0
	for _, s in Finds.sets do
		p.setsClaimed[s.id] = true
		total += s.reward
	end
	Harness.near(StatsCalc.compute(p, {}, 0).sellMult, 1 + total, 1e-9)
	p.setsClaimed = { not_a_set = true }
	Harness.eq(StatsCalc.compute(p, {}, 0).sellMult, 1)
end)
