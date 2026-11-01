--!strict
-- Buying: nobody can overspend, buy what they own, pass a max level or skip a gate. Also the
-- gate prompt messages, equip / settings checks and what a Cool Down keeps.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local Types = require("../src/shared/Types")
local Economy = require("../src/shared/Rules/Economy")
local Pricing = require("../src/shared/Rules/Pricing")
local Helpers = require("../src/shared/Catalog/Helpers")
local SparkPerks = require("../src/shared/Catalog/SparkPerks")
local Tools = require("../src/shared/Catalog/Tools")
local Upgrades = require("../src/shared/Catalog/Upgrades")
local Zones = require("../src/shared/Catalog/Zones")
local ProfileSchema = require("../src/shared/Profile/ProfileSchema")
local PurchaseRules = require("../src/shared/Player/PurchaseRules")
local Rng = require("../src/shared/Rng")

local function fresh(coins: number?): Types.Profile
	local p = ProfileSchema.default()
	p.coins = coins or 0
	return p
end

local function assertValid(p: Types.Profile, msg: string?)
	local ok, why = ProfileSchema.isValid(p)
	Harness.truthy(ok, `{msg or "profile"} invalid: {tostring(why)}`)
end

-- ===== upgrades =====

Harness.test("buy: cannot overspend, nothing changes", function()
	local cost = Upgrades.cost("power", 0) :: number
	local p = fresh(cost - 1)
	local before = p.coins
	local r = PurchaseRules.buy(p, "upgrade", "power")
	Harness.eq(r.ok, false)
	Harness.eq(p.coins, before)
	Harness.eq(p.upgrades["power"], nil)
	Harness.truthy(string.find(r.message, "Need 1 more coins", 1, true) ~= nil, r.message)
	Harness.eq(#r.keys, 0)
end)

Harness.test("buy: exact funds works and spends exactly the price", function()
	local cost = Upgrades.cost("power", 0) :: number
	local p = fresh(cost)
	local r = PurchaseRules.buy(p, "upgrade", "power")
	Harness.eq(r.ok, true)
	Harness.eq(p.coins, 0)
	Harness.eq(p.upgrades["power"], 1)
	Harness.eq(r.price, cost)
	Harness.eq(r.currency, "coins")
	Harness.truthy(table.find(r.keys, "coins") ~= nil and table.find(r.keys, "upgrades") ~= nil)
	assertValid(p)
end)

Harness.test("buy: every upgrade climbs to its max level, then says maxed", function()
	for _, up in Upgrades.list do
		local p = fresh(1e12)
		for level = 1, up.maxLevel do
			local r = PurchaseRules.buy(p, "upgrade", up.id)
			Harness.eq(r.ok, true, `{up.id} level {level}`)
			Harness.eq(p.upgrades[up.id], level)
		end
		local coins = p.coins
		local r = PurchaseRules.buy(p, "upgrade", up.id)
		Harness.eq(r.ok, false, `{up.id} beyond max`)
		Harness.eq(p.upgrades[up.id], up.maxLevel)
		Harness.eq(p.coins, coins)
		Harness.eq(r.message, "Maxed out!")
		assertValid(p, up.id)
	end
end)

Harness.test("buy: price matches Pricing (Haggler discount included)", function()
	local p = fresh(1e9)
	p.sparkPerks["haggler"] = 10
	local expected = Pricing.priceOf("upgrade", "reach", p) :: number
	Harness.truthy(expected < (Upgrades.cost("reach", 0) :: number), "discount applies")
	local before = p.coins
	local r = PurchaseRules.buy(p, "upgrade", "reach")
	Harness.eq(r.ok, true)
	Harness.eq(before - p.coins, expected)
end)

Harness.test("buy: a double tap with money for one only buys one", function()
	local cost = Upgrades.cost("backpack", 0) :: number
	local p = fresh(cost)
	local a = PurchaseRules.buy(p, "upgrade", "backpack")
	local b = PurchaseRules.buy(p, "upgrade", "backpack")
	Harness.eq(a.ok, true)
	Harness.eq(b.ok, false)
	Harness.eq(p.upgrades["backpack"], 1)
	Harness.eq(p.coins, 0)
end)

-- ===== tools =====

Harness.test("buy tool: owned and equipped at once, cannot buy twice", function()
	local price = Tools.byId["push_broom"].price
	local p = fresh(price + 5)
	local r = PurchaseRules.buy(p, "tool", "push_broom")
	Harness.eq(r.ok, true)
	Harness.eq(p.coins, 5)
	Harness.eq(p.toolsOwned["push_broom"], true)
	Harness.eq(p.tool, "push_broom")
	Harness.truthy(table.find(r.keys, "tool") ~= nil)
	local again = PurchaseRules.buy(p, "tool", "push_broom")
	Harness.eq(again.ok, false)
	Harness.eq(again.message, "You own this")
	Harness.eq(p.coins, 5)
	assertValid(p)
end)

Harness.test("buy tool: starter tool, unknown tool, too poor", function()
	local p = fresh(1e12)
	Harness.eq(PurchaseRules.buy(p, "tool", "twig_broom").ok, false)
	Harness.eq(PurchaseRules.buy(p, "tool", "laser_cannon").message, "Unknown tool")
	local poor = fresh(Tools.byId["volcano_vac"].price - 1)
	Harness.eq(PurchaseRules.buy(poor, "tool", "volcano_vac").ok, false)
	Harness.eq(poor.toolsOwned["volcano_vac"], nil)
	Harness.eq(poor.tool, "twig_broom")
end)

-- ===== zones =====

Harness.test("buy zone: one ring at a time, id as number or text", function()
	local p = fresh(1e12)
	local skip = PurchaseRules.buy(p, "zone", "3")
	Harness.eq(skip.ok, false)
	Harness.eq(skip.message, "Open Fern Forest first")
	Harness.eq(p.zones["3"], nil)
	Harness.eq(p.coins, 1e12)

	local two = PurchaseRules.buy(p, "zone", 2)
	Harness.eq(two.ok, true)
	Harness.eq(p.zones["2"], true)
	Harness.eq(p.coins, 1e12 - (Zones.price(2) :: number))
	Harness.eq(two.toastKind, "gold")

	local three = PurchaseRules.buy(p, "zone", "3")
	Harness.eq(three.ok, true)
	Harness.eq(p.zones["3"], true)
	assertValid(p)
end)

Harness.test("buy zone: owned, unknown, zone 1, fractions", function()
	local p = fresh(1e12)
	Harness.eq(PurchaseRules.buy(p, "zone", "1").message, "Already open")
	Harness.eq(PurchaseRules.buy(p, "zone", "9").message, "Unknown zone")
	Harness.eq(PurchaseRules.buy(p, "zone", "2.5").ok, false)
	Harness.eq(PurchaseRules.buy(p, "zone", "abc").ok, false)
	Harness.eq(PurchaseRules.buy(p, "zone", 0).ok, false)
	Harness.eq(PurchaseRules.buy(p, "zone", -1).ok, false)
	Harness.eq(p.coins, 1e12)
end)

-- ===== helper bots =====

Harness.test("buy helper: price climbs, stops at six", function()
	local p = fresh(1e12)
	for n = 0, Config.Economy.maxHelpers - 1 do
		local price = Helpers.price(n) :: number
		local before = p.coins
		local r = PurchaseRules.buy(p, "helper", "")
		Harness.eq(r.ok, true)
		Harness.eq(before - p.coins, price)
		Harness.eq(p.helpers, n + 1)
	end
	local r = PurchaseRules.buy(p, "helper", "")
	Harness.eq(r.ok, false)
	Harness.eq(p.helpers, Config.Economy.maxHelpers)
	assertValid(p)
end)

Harness.test("buy helperUp: needs a bot first, stops at the max level", function()
	local p = fresh(1e12)
	Harness.eq(PurchaseRules.buy(p, "helperUp", "x").message, "Get a helper bot first")
	PurchaseRules.buy(p, "helper", "")
	for level = 1, Config.Economy.maxHelperLevel do
		Harness.eq(PurchaseRules.buy(p, "helperUp", "").ok, true)
		Harness.eq(p.helperLevel, level)
	end
	Harness.eq(PurchaseRules.buy(p, "helperUp", "").ok, false)
	Harness.eq(p.helperLevel, Config.Economy.maxHelperLevel)
	assertValid(p)
end)

-- ===== spark perks =====

Harness.test("buy sparkPerk: paid in Sparks, coins never touched", function()
	local p = fresh(1e9)
	p.sparks = 1
	local r = PurchaseRules.buy(p, "sparkPerk", "head_start")
	Harness.eq(r.ok, false) -- costs 2
	Harness.eq(r.message, "Need 1 more Sparks")
	p.sparks = 5
	r = PurchaseRules.buy(p, "sparkPerk", "head_start")
	Harness.eq(r.ok, true)
	Harness.eq(r.currency, "sparks")
	Harness.eq(p.sparks, 3)
	Harness.eq(p.coins, 1e9 + 250) -- Head Start hands over its coins at once, the price is Sparks only
	Harness.eq(p.sparkPerks["head_start"], 1)
	Harness.truthy(table.find(r.keys, "sparks") ~= nil and table.find(r.keys, "sparkPerks") ~= nil)
	assertValid(p)
end)

Harness.test("buy sparkPerk: coins can't pay, max level stops", function()
	local rich = fresh(1e15)
	Harness.eq(PurchaseRules.buy(rich, "sparkPerk", "free_push").ok, false)
	local p = fresh(0)
	p.sparks = 1e6
	local perk = SparkPerks.byId["free_push"]
	for _ = 1, perk.maxLevel do
		Harness.eq(PurchaseRules.buy(p, "sparkPerk", "free_push").ok, true)
	end
	local sparks = p.sparks
	Harness.eq(PurchaseRules.buy(p, "sparkPerk", "free_push").ok, false)
	Harness.eq(p.sparks, sparks)
	Harness.eq(PurchaseRules.buy(p, "sparkPerk", "nope").message, "Unknown perk")
end)

Harness.test("buy sparkPerk: Head Start and Free Push Broom pay out at once", function()
	local p = fresh(0)
	p.sparks = 100
	Harness.eq(PurchaseRules.buy(p, "sparkPerk", "head_start").ok, true)
	Harness.eq(p.coins, 250)
	Harness.eq(PurchaseRules.buy(p, "sparkPerk", "head_start").ok, true)
	Harness.eq(p.coins, 250 + 500) -- level 2 adds 500 more (750 in total)
	Harness.eq(p.runCoins, 0)
	local r = PurchaseRules.buy(p, "sparkPerk", "free_push")
	Harness.eq(r.ok, true)
	Harness.eq(p.toolsOwned["push_broom"], true)
	Harness.eq(p.tool, "push_broom")
	Harness.truthy(table.find(r.keys, "toolsOwned") ~= nil)
	assertValid(p)
	-- a player holding another tool keeps it
	local q = fresh(0)
	q.sparks = 10
	q.toolsOwned["leaf_blower"] = true
	q.tool = "leaf_blower"
	PurchaseRules.buy(q, "sparkPerk", "free_push")
	Harness.eq(q.tool, "leaf_blower")
	Harness.eq(q.toolsOwned["push_broom"], true)
end)

-- ===== garbage in =====

Harness.test("buy: junk kinds and ids are refused and change nothing", function()
	local p = fresh(1e9)
	p.sparks = 100
	local junkKinds: { any } = { "", "UPGRADE", "sell", "upgrade ", 5, true, {}, "x" }
	for _, kind in junkKinds do
		Harness.eq(PurchaseRules.buy(p, kind, "power").ok, false)
	end
	local junkIds: { any } = { "", "POWER", "__index", "power ", 5, true, {}, 1e300 }
	for _, id in junkIds do
		Harness.eq(PurchaseRules.buy(p, "upgrade", id).ok, false)
		Harness.eq(PurchaseRules.buy(p, "tool", id).ok, false)
		Harness.eq(PurchaseRules.buy(p, "sparkPerk", id).ok, false)
	end
	Harness.eq(p.coins, 1e9)
	Harness.eq(p.sparks, 100)
	Harness.eq(next(p.upgrades), nil)
	Harness.eq(next(p.sparkPerks), nil)
	Harness.eq(PurchaseRules.buy(p, nil, nil).ok, false)
end)

Harness.test("buy: random buying never breaks the wallet or the profile", function()
	local rng = Rng.new(777)
	local kinds = { "upgrade", "tool", "zone", "helper", "helperUp", "sparkPerk" }
	local ids: { string } = {}
	for _, id in Upgrades.order do
		table.insert(ids, id)
	end
	for _, id in Tools.order do
		table.insert(ids, id)
	end
	for _, id in SparkPerks.order do
		table.insert(ids, id)
	end
	for zone = 1, 5 do
		table.insert(ids, tostring(zone))
	end
	table.insert(ids, "")
	local p = fresh(0)
	for step = 1, 4000 do
		if step % 7 == 0 then
			p.coins += rng:int(0, 5000) * rng:int(1, 400)
		end
		if step % 31 == 0 then
			p.sparks += rng:int(0, 6)
		end
		local coinsBefore, sparksBefore = p.coins, p.sparks
		local r = PurchaseRules.buy(p, rng:pick(kinds), rng:pick(ids))
		Harness.truthy(p.coins >= 0 and p.sparks >= 0, "wallet went negative")
		if not r.ok then
			Harness.eq(p.coins, coinsBefore)
			Harness.eq(p.sparks, sparksBefore)
		end
	end
	assertValid(p, "after random buying")
end)

-- ===== equip / settings =====

Harness.test("equip: only a tool you own", function()
	local p = fresh()
	local ok, why = PurchaseRules.equip(p, "push_broom")
	Harness.eq(ok, false)
	Harness.eq(why, "You don't own this yet")
	Harness.eq(p.tool, "twig_broom")
	p.toolsOwned["push_broom"] = true
	ok, why = PurchaseRules.equip(p, "push_broom")
	Harness.eq(ok, true)
	Harness.eq(why, "Push Broom")
	Harness.eq(p.tool, "push_broom")
	Harness.eq((PurchaseRules.equip(p, "nope")), false)
	Harness.eq((PurchaseRules.equip(p, 3)), false)
	Harness.eq((PurchaseRules.equip(p, nil)), false)
	-- unknown id that an old save still lists as owned is not equippable either
	p.toolsOwned["removed_tool"] = true
	Harness.eq((PurchaseRules.equip(p, "removed_tool")), false)
	Harness.eq(p.tool, "push_broom")
end)

Harness.test("settings: only the five real keys, only booleans", function()
	local p = fresh()
	for _, key in ProfileSchema.SETTING_KEYS do
		Harness.eq(PurchaseRules.setSetting(p, key, false), true)
		Harness.eq((p.settings :: any)[key], false)
		Harness.eq(PurchaseRules.setSetting(p, key, true), true)
		Harness.eq((p.settings :: any)[key], true)
	end
	Harness.eq(PurchaseRules.setSetting(p, "coins", true), false)
	Harness.eq(PurchaseRules.setSetting(p, "__index", true), false)
	Harness.eq(PurchaseRules.setSetting(p, "music", 1), false)
	Harness.eq(PurchaseRules.setSetting(p, "music", "false"), false)
	Harness.eq(PurchaseRules.setSetting(p, "music", nil), false)
	Harness.eq(p.settings.music, true)
	Harness.eq((p.settings :: any).coins, nil)
	assertValid(p)
end)

-- ===== gate prompts =====

Harness.test("gate: open / buy / short / blocked / unknown", function()
	local p = fresh()
	Harness.eq(PurchaseRules.gate(p, 1).state, "open")
	Harness.eq(PurchaseRules.gate(p, 1).text, "Already open!")

	local price = Zones.price(2) :: number
	local short = PurchaseRules.gate(p, 2)
	Harness.eq(short.state, "short")
	Harness.eq(short.text, `Collect {PurchaseRules.fmt(price)} more coins to open Fern Forest!`)

	p.coins = price - 1
	Harness.truthy(
		string.find(PurchaseRules.gate(p, 2).text, "Collect 1 more coins", 1, true) ~= nil
	)

	p.coins = price
	Harness.eq(PurchaseRules.gate(p, 2).state, "buy")
	Harness.eq(PurchaseRules.gate(p, "2").state, "buy")

	local blocked = PurchaseRules.gate(p, 4)
	Harness.eq(blocked.state, "blocked")
	Harness.truthy(
		string.find(blocked.text, "Open Hot Springs first", 1, true) ~= nil,
		blocked.text
	)

	Harness.eq(PurchaseRules.gate(p, 99).state, "unknown")
	Harness.eq(PurchaseRules.gate(p, nil).state, "unknown")
	Harness.eq(PurchaseRules.gate(p, "x").state, "unknown")
end)

Harness.test("fmt: thousands separators", function()
	Harness.eq(PurchaseRules.fmt(0), "0")
	Harness.eq(PurchaseRules.fmt(999), "999")
	Harness.eq(PurchaseRules.fmt(1000), "1,000")
	Harness.eq(PurchaseRules.fmt(1234567), "1,234,567")
	Harness.eq(PurchaseRules.fmt(12.9), "12")
	Harness.eq(PurchaseRules.fmt(0 / 0), "0")
	Harness.eq(PurchaseRules.fmt(-45000), "-45,000")
end)

-- ===== Cool Down keeps what it must =====

Harness.test("cool down: keeps progress, resets the run, same live table", function()
	local live = fresh()
	live.coins = 123
	live.runCoins = Config.Economy.coolDownMinRunCoins * 2
	live.lifetimeCoins = live.runCoins + 5000000
	live.sparks = 4
	live.coolDowns = 1
	live.tool = "dust_vac"
	live.toolsOwned = { twig_broom = true, push_broom = true, dust_vac = true }
	live.upgrades = { power = 9, sell = 3 }
	live.zones = { ["1"] = true, ["2"] = true, ["3"] = true }
	live.helpers = 4
	live.helperLevel = 6
	live.sparkPerks = { head_start = 2, free_push = 1 }
	live.finds = { shiny_shell = 3 }
	live.setsClaimed = { beach = true }
	live.goalsClaimed = { first_sweeps = true }
	live.daily = { lastDay = 20000, streak = 3 }
	live.stats.ashSwept = 5555
	live.stats.findsTotal = 7
	live.settings.music = false
	live.tutorialDone = true
	local identity = live

	local ok = Economy.canCoolDown(live)
	Harness.eq(ok, true)
	local out, gained = Economy.coolDownReset(live)
	Harness.truthy(gained >= 1)
	ProfileSchema.assign(live :: any, out :: any)

	Harness.truthy(rawequal(identity, live))
	-- kept
	Harness.eq(live.sparks, 4 + gained)
	Harness.eq(live.coolDowns, 2)
	Harness.eq(live.lifetimeCoins, Config.Economy.coolDownMinRunCoins * 2 + 5000000)
	Harness.eq(live.sparkPerks["head_start"], 2)
	Harness.eq(live.finds["shiny_shell"], 3)
	Harness.eq(live.setsClaimed["beach"], true)
	Harness.eq(live.goalsClaimed["first_sweeps"], true)
	Harness.eq(live.daily.lastDay, 20000)
	Harness.eq(live.daily.streak, 3)
	Harness.eq(live.stats.ashSwept, 5555)
	Harness.eq(live.stats.findsTotal, 7)
	Harness.eq(live.settings.music, false)
	Harness.eq(live.tutorialDone, true)
	-- reset
	Harness.eq(live.coins, 250 * 2 * 3 / 2) -- Head Start level 2 = 750
	Harness.eq(live.runCoins, 0)
	Harness.eq(live.helpers, 0)
	Harness.eq(live.helperLevel, 0)
	Harness.eq(next(live.upgrades), nil)
	Harness.eq(live.tool, "push_broom") -- Free Push Broom perk
	Harness.eq(live.toolsOwned["dust_vac"], nil)
	Harness.eq(live.toolsOwned["push_broom"], true)
	Harness.eq(live.zones["2"], nil)
	Harness.eq(live.zones["1"], true)
	assertValid(live, "after cool down")
	-- not offered again until a new run earns enough
	Harness.eq(Economy.canCoolDown(live), false)
end)
