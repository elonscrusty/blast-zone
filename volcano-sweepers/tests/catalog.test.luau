--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Rules/Economy")
local Daily = require("../src/shared/Catalog/Daily")
local Finds = require("../src/shared/Catalog/Finds")
local Goals = require("../src/shared/Catalog/Goals")
local Helpers = require("../src/shared/Catalog/Helpers")
local SparkPerks = require("../src/shared/Catalog/SparkPerks")
local Tools = require("../src/shared/Catalog/Tools")
local Upgrades = require("../src/shared/Catalog/Upgrades")
local Zones = require("../src/shared/Catalog/Zones")

local function isWhole(n: number): boolean
	return n == math.floor(n) and n == n and math.abs(n) < 1e15
end

local function isHex(s: string): boolean
	return string.match(s, "^#%x%x%x%x%x%x$") ~= nil
end

local function isId(s: string): boolean
	return string.match(s, "^[a-z][a-z0-9_]*$") ~= nil
end

-- ===== tools =====
Harness.test("catalog tools: the 8 fixed ids, in order", function()
	local want = {
		"twig_broom",
		"push_broom",
		"leaf_blower",
		"dust_vac",
		"turbo_vac",
		"lava_mop",
		"dragon_vac",
		"volcano_vac",
	}
	Harness.eq(#Tools.list, 8)
	for i, id in want do
		Harness.eq(Tools.list[i].id, id)
		Harness.eq(Tools.order[i], id)
		Harness.eq(Tools.byId[id].tier, i)
	end
end)

Harness.test(
	"catalog tools: sane numbers, whole prices, price climbs about x4-x5 a tier",
	function()
		Harness.eq(Tools.list[1].price, 0)
		local prevPrice, prevCap = 0, 0
		for i, t in Tools.list do
			Harness.truthy(isWhole(t.price) and t.price >= 0, t.id .. " price")
			Harness.truthy(isHex(t.color), t.id .. " color")
			Harness.truthy(t.reach > 0 and t.arcDeg > 0 and t.arcDeg <= 360, t.id .. " shape")
			Harness.truthy(
				t.power > 0 and t.interval >= Config.Player.minInterval,
				t.id .. " stats"
			)
			Harness.truthy(#t.name > 0 and #t.trait > 0 and #t.blurb > 0, t.id .. " text")
			Harness.truthy(
				t.capacityBonus >= prevCap and isWhole(t.capacityBonus),
				t.id .. " capacity"
			)
			if i > 1 then
				Harness.truthy(t.price > prevPrice, t.id .. " costs more than the tier before")
				if i > 2 then
					local ratio = t.price / prevPrice
					Harness.truthy(ratio >= 3 and ratio <= 40, `{t.id} price ratio {ratio}`)
				end
			end
			prevPrice, prevCap = t.price, t.capacityBonus
		end
	end
)

Harness.test("catalog tools: every tier sweeps more ash per second than the one before", function()
	local prev = 0
	for _, t in Tools.list do
		local cells = Tools.cellsHit(t.reach, t.arcDeg, Config.World.cellSize)
		local rate = cells * t.power / t.interval
		Harness.truthy(rate > prev, t.id .. " is not an upgrade")
		prev = rate
	end
end)

Harness.test("catalog tools: next()", function()
	Harness.eq((Tools.next("twig_broom") :: Tools.Tool).id, "push_broom")
	Harness.eq((Tools.next("dragon_vac") :: Tools.Tool).id, "volcano_vac")
	Harness.eq(Tools.next("volcano_vac"), nil)
	Harness.eq(Tools.next("nope"), nil)
end)

-- ===== upgrades =====
Harness.test("catalog upgrades: the 10 fixed ids", function()
	local want = {
		"power",
		"speed",
		"reach",
		"backpack",
		"walk",
		"sell",
		"luck",
		"armor",
		"sweetspot",
		"lucky_coins",
	}
	Harness.eq(#Upgrades.list, 10)
	for _, id in want do
		Harness.truthy(Upgrades.byId[id] ~= nil, "missing " .. id)
	end
end)

Harness.test("catalog upgrades: 12-20 levels, growth 1.25-1.4, whole rising costs", function()
	local cheapest = math.huge
	for _, up in Upgrades.list do
		Harness.truthy(up.maxLevel >= 12 and up.maxLevel <= 20, up.id .. " levels")
		Harness.truthy(up.growth >= 1.25 and up.growth <= 1.4, up.id .. " growth")
		Harness.truthy(#up.name > 0 and #up.desc > 0, up.id .. " text")
		local prev = 0
		for lv = 0, up.maxLevel - 1 do
			local c = Upgrades.cost(up.id, lv) :: number
			Harness.truthy(isWhole(c) and c > prev, `{up.id} level {lv + 1} cost {c}`)
			if lv > 0 then
				local g = c / prev
				Harness.truthy(g >= 1.2 and g <= 1.45, `{up.id} level {lv + 1} grows x{g}`)
			end
			prev = c
		end
		cheapest = math.min(cheapest, Upgrades.cost(up.id, 0) :: number)
		Harness.eq(Upgrades.cost(up.id, up.maxLevel), nil, up.id .. " maxed")
		Harness.eq(Upgrades.cost(up.id, up.maxLevel + 5), nil)
	end
	Harness.truthy(cheapest <= 20, "the cheapest first level should cost <= 20, got " .. cheapest)
	Harness.eq(Upgrades.cost("nope", 0), nil)
end)

Harness.test("catalog upgrades: a higher level always gives a strictly bigger bonus", function()
	for _, up in Upgrades.list do
		local prev = -1
		for lv = 0, up.maxLevel do
			local e = Upgrades.effect(up.id, lv)
			Harness.truthy(e > prev, `{up.id} level {lv} does not help`)
			prev = e
		end
		-- levels past the max add nothing
		Harness.eq(Upgrades.effect(up.id, up.maxLevel + 9), Upgrades.effect(up.id, up.maxLevel))
	end
end)

Harness.test(
	"catalog upgrades: caps keep sell, luck, armor, sweet spot and lucky coins sensible",
	function()
		local function top(id: string): number
			return Upgrades.effect(id, (Upgrades.byId[id] :: Upgrades.Upgrade).maxLevel)
		end
		Harness.truthy(top("sell") <= 1.0 and top("sell") >= 0.5, "sell")
		Harness.truthy(
			top("armor") <= Config.Player.maxArmor + 1e-9 and top("armor") >= 0.5,
			"armor"
		)
		Harness.truthy(top("lucky_coins") <= 0.15 and top("lucky_coins") > 0, "lucky coins")
		Harness.truthy(top("sweetspot") <= 0.35 and top("sweetspot") > 0, "sweet spot")
		Harness.truthy(top("luck") <= 3, "luck")
	end
)

Harness.test("catalog upgrades: effect text reads like '+8% reach'", function()
	Harness.eq(Upgrades.effectText("reach", 2), "+8% reach")
	Harness.eq(Upgrades.effectText("reach", 0), "+0% reach")
	Harness.eq(Upgrades.effectText("walk", 1), "+2.5% walk speed")
	Harness.eq(Upgrades.effectText("armor", 4), "+20% burp armor")
	Harness.eq(Upgrades.effectText("nope", 4), "")
	for _, up in Upgrades.list do
		local text = Upgrades.effectText(up.id, up.maxLevel)
		Harness.truthy(string.match(text, "^%+[%d%.]+%% .+") ~= nil, text)
	end
end)

-- ===== zones =====
Harness.test("catalog zones: 5 zones that match the world config", function()
	Harness.eq(#Zones.list, #Config.World.zones)
	local values = { 1, 3, 8, 22, 60 }
	local prevPrice = -1
	for i, z in Zones.list do
		Harness.eq(z.id, i)
		Harness.eq(z.name, Config.World.zones[i].name)
		Harness.eq(Zones.valueOf(i), values[i])
		Harness.truthy(isHex(z.ground) and isHex(z.ash), "colors")
		Harness.truthy(#z.blurb > 0, "blurb")
		Harness.truthy(isWhole(z.unlockPrice) and z.unlockPrice > prevPrice, "price " .. i)
		prevPrice = z.unlockPrice
	end
	Harness.eq(Zones.price(1), 0)
	Harness.truthy((Zones.price(2) :: number) > 0)
	Harness.eq(Zones.price(9), nil)
	Harness.eq(Zones.valueOf(9), 0)
end)

-- ===== finds =====
Harness.test("catalog finds: 30 finds, 5 per zone + 5 rainbow, unique ids", function()
	Harness.eq(#Finds.list, 30)
	local perZone: { [number]: number } = {}
	local seen: { [string]: boolean } = {}
	for _, f in Finds.list do
		Harness.truthy(isId(f.id) and not seen[f.id], "id " .. f.id)
		seen[f.id] = true
		Harness.truthy(Finds.rarityById[f.rarity] ~= nil, f.id .. " rarity")
		Harness.truthy(Finds.setById[f.set] ~= nil, f.id .. " set")
		Harness.eq(Finds.setById[f.set].zone, f.zone, f.id .. " set/zone")
		Harness.truthy(#f.name > 0 and isWhole(f.coins) and f.coins > 0, f.id .. " data")
		Harness.eq(Finds.byId[f.id], f)
		perZone[f.zone] = (perZone[f.zone] or 0) + 1
	end
	for zone = 0, 5 do
		Harness.eq(perZone[zone], 5, "zone " .. zone)
	end
	Harness.eq(#Finds.sets, 6)
end)

Harness.test("catalog finds: rarities, odds text, coins climb with rarity", function()
	Harness.eq(#Finds.rarities, 4)
	local want = { "common", "uncommon", "rare", "legendary" }
	local sum = 0
	for i, r in Finds.rarities do
		Harness.eq(r.id, want[i])
		Harness.truthy(isHex(r.colorHex) and r.weight > 0 and #r.label > 0, r.id)
		Harness.truthy(i == 1 or r.weight < Finds.rarities[i - 1].weight, "rarer = lower weight")
		Harness.truthy(i == 1 or r.coinMult > Finds.rarities[i - 1].coinMult, "rarer = more coins")
		sum += tonumber((string.gsub(Finds.oddsText(r.id), "%%", ""))) :: number
	end
	Harness.eq(sum, 100)
	Harness.eq(Finds.oddsText("common"), "62%")
	Harness.eq(Finds.oddsText("legendary"), "2%")
	Harness.eq(Finds.oddsText("mythic"), "")
	-- every zone has every rarity (so the roller never runs dry), rainbow only rare+legendary
	for zone = 1, 5 do
		for _, r in Finds.rarities do
			local n = 0
			for _, f in Finds.list do
				if f.zone == zone and f.rarity == r.id then
					n += 1
				end
			end
			Harness.truthy(n >= 1, `zone {zone} has no {r.id}`)
		end
	end
	for _, f in Finds.inSet("rainbow") do
		Harness.truthy(f.rarity == "rare" or f.rarity == "legendary", f.id)
	end
	Harness.eq(#Finds.inSet("beach"), 5)
end)

Harness.test("catalog finds: set rewards are small permanent bonuses", function()
	local total = 0
	for _, s in Finds.sets do
		Harness.truthy(s.reward > 0 and s.reward <= 0.15, s.id)
		total += s.reward
	end
	Harness.truthy(total <= 0.5, "all sets together stay a modest bonus")
end)

-- ===== helpers =====
Harness.test("catalog helpers: 6 bots, 15 levels, costs rise, income rises", function()
	Harness.eq(Helpers.max, 6)
	Harness.eq(Helpers.maxLevel, 15)
	local prev = 0
	for owned = 0, 5 do
		local c = Helpers.price(owned) :: number
		Harness.truthy(isWhole(c) and c > prev, "bot " .. owned)
		prev = c
	end
	Harness.eq(Helpers.price(6), nil)
	prev = 0
	for lv = 0, 14 do
		local c = Helpers.upgradeCost(lv) :: number
		Harness.truthy(isWhole(c) and c > prev, "level " .. lv)
		prev = c
	end
	Harness.eq(Helpers.upgradeCost(15), nil)
	local u = 0
	for lv = 0, 15 do
		local now = Helpers.unitsPerSecond(lv)
		Harness.truthy(now > u, "level " .. lv)
		u = now
	end
	Harness.near(Helpers.unitsPerSecond(3, 8), Helpers.unitsPerSecond(3) * 8, 1e-9)
end)

-- ===== spark perks =====
Harness.test("catalog spark perks: 8 perks with rising Spark costs", function()
	Harness.eq(#SparkPerks.list, 8)
	for _, p in SparkPerks.list do
		Harness.truthy(isId(p.id) and #p.name > 0 and #p.desc > 0, p.id)
		Harness.eq(#p.costs, p.maxLevel, p.id .. " cost list")
		local prev = 0
		for lv = 0, p.maxLevel - 1 do
			local c = SparkPerks.cost(p.id, lv) :: number
			Harness.truthy(isWhole(c) and c >= prev and c >= 1, `{p.id} level {lv + 1}`)
			prev = c
		end
		Harness.eq(SparkPerks.cost(p.id, p.maxLevel), nil)
		local last = -1
		for lv = 0, p.maxLevel do
			local v = SparkPerks.value(p.id, lv)
			Harness.truthy(v > last, `{p.id} level {lv} does not help`)
			last = v
		end
	end
	Harness.near(SparkPerks.value("haggler", 10), 0.15, 1e-9)
	Harness.eq(SparkPerks.value("free_push", 1), 1)
	Harness.eq(SparkPerks.spent({ free_push = 1, head_start = 2 }), 3 + 2 + 3)
	Harness.eq(SparkPerks.effectText("lucky_charm", 3), "+30% treasure luck")
end)

-- ===== goals + daily =====
Harness.test("catalog goals: 14 one-time goals on real stats", function()
	Harness.eq(#Goals.list, 14)
	local stats = Economy.blankProfile().stats :: any
	local seen: { [string]: boolean } = {}
	for _, g in Goals.list do
		Harness.truthy(isId(g.id) and not seen[g.id], "id " .. g.id)
		seen[g.id] = true
		Harness.truthy(stats[g.stat] ~= nil, g.id .. " uses unknown stat " .. g.stat)
		Harness.truthy(g.target > 0 and isWhole(g.target), g.id .. " target")
		Harness.truthy(isWhole(g.rewardCoins) and g.rewardCoins > 0, g.id .. " coins")
		Harness.truthy(isWhole(g.rewardSparks) and g.rewardSparks >= 0, g.id .. " sparks")
		Harness.eq(Goals.byId[g.id], g)
	end
	local blank = Economy.blankProfile()
	Harness.eq(Goals.isDone(Goals.byId["first_sales"], blank.stats), false)
	blank.stats.sellCount = 5
	Harness.eq(Goals.isDone(Goals.byId["first_sales"], blank.stats), true)
end)

Harness.test("catalog daily: 7 day ladder, coins rise, day 7 gives Sparks", function()
	Harness.eq(#Daily.ladder, 7)
	local prev = 0
	for i, r in Daily.ladder do
		Harness.eq(r.day, i)
		Harness.truthy(isWhole(r.coins) and r.coins > prev, "day " .. i)
		prev = r.coins
		Harness.eq(Daily.rewardFor(i).coins, r.coins)
	end
	Harness.truthy(Daily.rewardFor(7).sparks > 0)
	Harness.eq(Daily.rewardFor(6).sparks, 0)
	Harness.eq(Daily.rewardFor(8).day, 1) -- the ladder starts again
	Harness.eq(Daily.rewardFor(14).day, 7)
	Harness.eq(Daily.rewardFor(0).day, 1)
	Harness.eq(Daily.rewardFor(0 / 0).day, 1)
	Harness.eq(Daily.rewardFor(1, 3).coins, Daily.ladder[1].coins * 3)
end)
