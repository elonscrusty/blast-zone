--!strict
-- Helpers panel model: six slots, buy/level-up buttons, income estimate.
local Harness = require("./harness")
local Economy = require("../src/shared/Rules/Economy")
local Helpers = require("../src/shared/Catalog/Helpers")
local Zones = require("../src/shared/Catalog/Zones")
local HelpersModel = require("../src/shared/Ui/HelpersModel")

Harness.test("HelpersModel: no bots yet", function()
	local m = HelpersModel.build(Economy.blankProfile())
	Harness.eq(m.count, 0)
	Harness.eq(#m.slots, 6)
	for _, slot in m.slots do
		Harness.eq(slot.filled, false)
	end
	Harness.eq(m.buy.price, 450)
	Harness.eq(m.buy.affordable, false)
	Harness.eq(m.buy.needText, "Need 450 more coins!")
	Harness.eq(m.up.price, nil)
	Harness.eq(m.up.label, "GET A BOT")
	Harness.eq(m.perMinute, 0)
	Harness.truthy(string.find(m.incomeText, "Get a bot", 1, true) ~= nil)
	Harness.eq(m.canBuyAny, false)
end)

Harness.test("HelpersModel: can afford the first bot and shows what it adds", function()
	local p = Economy.blankProfile()
	p.coins = 450
	local m = HelpersModel.build(p)
	Harness.eq(m.buy.affordable, true)
	Harness.eq(m.buy.needText, nil)
	Harness.eq(m.canBuyAny, true)
	-- one bot at level 0 on the beach: 0.108 coins/s = 6.48 a minute
	Harness.eq(m.buy.gainText, "+about 6 coins a minute")
end)

Harness.test("HelpersModel: slots fill from the left", function()
	local p = Economy.blankProfile()
	p.helpers = 4
	local m = HelpersModel.build(p)
	for i, slot in m.slots do
		Harness.eq(slot.filled, i <= 4)
		Harness.eq(slot.index, i)
	end
	Harness.eq(m.buy.price, Helpers.price(4))
end)

Harness.test(
	"HelpersModel: income estimate follows count, level, best zone and multipliers",
	function()
		local p = Economy.blankProfile()
		p.helpers = 6
		p.helperLevel = 5
		p.zones = { ["1"] = true, ["2"] = true, ["3"] = true }
		local view: any = p
		view.derived = { sellMult = 2, helperMult = 1.5 }
		local m = HelpersModel.build(view)
		local expected = Helpers.coinsPerSecond(6, 5, Zones.valueOf(3), 2, 1.5) * 60
		Harness.near(m.perMinute, expected, 1e-6)
		Harness.eq(m.zoneName, "Hot Springs")
		Harness.eq(m.zoneValue, 8)
		Harness.eq(
			m.incomeText,
			"about "
				.. require("../src/shared/Ui/ShopModelUtil").niceNumber(expected)
				.. " coins a minute"
		)
		-- the same bots in a richer zone earn more
		p.zones["4"] = true
		local richer = HelpersModel.build(view)
		Harness.truthy(richer.perMinute > m.perMinute, "zone 4 pays more")
		-- no derived yet: multipliers count as 1
		view.derived = nil
		local plain = HelpersModel.build(p)
		Harness.near(plain.perMinute, Helpers.coinsPerSecond(6, 5, 22, 1, 1) * 60, 1e-6)
	end
)

Harness.test("HelpersModel: level up needs a bot, shows speed now and next, then MAX", function()
	local p = Economy.blankProfile()
	p.helpers = 1
	p.helperLevel = 2
	p.coins = 100000
	local m = HelpersModel.build(p)
	Harness.eq(m.up.price, Helpers.upgradeCost(2))
	Harness.eq(m.up.affordable, true)
	Harness.eq(m.up.speedNow, "x1.6")
	Harness.eq(m.up.speedNext, "x2")
	Harness.eq(m.up.effectLine, "Bot speed x1.6 → x2")
	Harness.eq(m.levelText, "Level 2 of 15")
	p.helperLevel = 15
	m = HelpersModel.build(p)
	Harness.eq(m.up.price, nil)
	Harness.eq(m.up.label, "MAX")
	Harness.eq(m.up.speedNext, nil)
end)

Harness.test("HelpersModel: six bots show ALL 6", function()
	local p = Economy.blankProfile()
	p.helpers = 6
	p.coins = 99999999
	local m = HelpersModel.build(p)
	Harness.eq(m.buy.price, nil)
	Harness.eq(m.buy.label, "ALL 6!")
	Harness.eq(m.buy.affordable, false)
	-- the level button still works
	Harness.eq(m.up.affordable, true)
	p.helperLevel = 15
	Harness.eq(HelpersModel.build(p).canBuyAny, false)
end)

Harness.test("HelpersModel: out of range numbers are clamped", function()
	local p = Economy.blankProfile()
	p.helpers = 40
	p.helperLevel = 400
	local m = HelpersModel.build(p)
	Harness.eq(m.count, 6)
	Harness.eq(m.level, 15)
	Harness.eq(HelpersModel.build(nil).count, 0)
	Harness.eq(HelpersModel.build({ helpers = 0 / 0, derived = { sellMult = 0 / 0 } }).count, 0)
end)
