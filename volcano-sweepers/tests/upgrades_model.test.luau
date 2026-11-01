--!strict
-- Upgrades panel model: rows, affordability, maxed, "need N more", next-effect text, best next buy.
local Harness = require("./harness")
local Economy = require("../src/shared/Rules/Economy")
local Pricing = require("../src/shared/Rules/Pricing")
local Upgrades = require("../src/shared/Catalog/Upgrades")
local UpgradesModel = require("../src/shared/Ui/UpgradesModel")
local ShopModelUtil = require("../src/shared/Ui/ShopModelUtil")

local function rowOf(model: UpgradesModel.Model, id: string): UpgradesModel.Row
	for _, row in model.rows do
		if row.id == id then
			return row
		end
	end
	error("no row " .. id)
end

Harness.test("UpgradesModel: ten rows in catalog order for a brand new player", function()
	local model = UpgradesModel.build(Economy.blankProfile())
	Harness.eq(#model.rows, 10)
	for i, id in Upgrades.order do
		Harness.eq(model.rows[i].id, id)
		Harness.eq(model.rows[i].level, 0)
		Harness.eq(model.rows[i].maxed, false)
		Harness.truthy(model.rows[i].icon ~= "", "icon")
		Harness.truthy(model.rows[i].desc ~= "", "desc")
	end
	Harness.eq(model.coins, 0)
	Harness.eq(model.canBuyAny, false)
	Harness.eq(model.allMaxed, false)
end)

Harness.test("UpgradesModel: broke player sees 'Need N more coins!' and a grey button", function()
	local p = Economy.blankProfile()
	p.coins = 5
	local model = UpgradesModel.build(p)
	local power = rowOf(model, "power")
	Harness.eq(power.price, 12)
	Harness.eq(power.affordable, false)
	Harness.eq(power.missing, 7)
	Harness.eq(power.needText, "Need 7 more coins!")
	Harness.eq(model.canBuyAny, false)
end)

Harness.test("UpgradesModel: exact money is affordable, one short is not", function()
	local p = Economy.blankProfile()
	p.coins = 12
	local row = rowOf(UpgradesModel.build(p), "power")
	Harness.eq(row.affordable, true)
	Harness.eq(row.missing, 0)
	Harness.eq(row.needText, nil)
	p.coins = 11
	row = rowOf(UpgradesModel.build(p), "power")
	Harness.eq(row.affordable, false)
	Harness.eq(row.needText, "Need 1 more coins!")
end)

Harness.test("UpgradesModel: price matches what the server charges (Pricing.priceOf)", function()
	local p = Economy.blankProfile()
	p.coins = 1000000
	p.upgrades = { power = 3, reach = 5, sell = 1 }
	p.sparkPerks = { haggler = 2 }
	local model = UpgradesModel.build(p)
	for _, row in model.rows do
		Harness.eq(row.price, Pricing.priceOf("upgrade", row.id, p), row.id)
	end
end)

Harness.test("UpgradesModel: effect text goes from now to next", function()
	local p = Economy.blankProfile()
	p.upgrades = { reach = 4 }
	local row = rowOf(UpgradesModel.build(p), "reach")
	Harness.eq(row.effectNow, "+16% reach")
	Harness.eq(row.effectNext, "+20%")
	Harness.eq(row.effectLine, "+16% reach → +20%")
	Harness.eq(row.levelText, "Level 4 of 12")
	-- level 0 starts at +0%
	local first = rowOf(UpgradesModel.build(Economy.blankProfile()), "reach")
	Harness.eq(first.effectLine, "+0% reach → +4%")
end)

Harness.test("UpgradesModel: a maxed line says MAX and has no price", function()
	local p = Economy.blankProfile()
	p.coins = 999999999
	p.upgrades = { reach = 12 }
	local row = rowOf(UpgradesModel.build(p), "reach")
	Harness.eq(row.maxed, true)
	Harness.eq(row.price, nil)
	Harness.eq(row.buttonLabel, "MAX")
	Harness.eq(row.affordable, false)
	Harness.eq(row.effectNext, nil)
	Harness.eq(row.needText, nil)
	Harness.eq(row.best, false)
	-- a level above the max (a bug in a save) still reads as maxed
	p.upgrades = { reach = 99 }
	Harness.eq(rowOf(UpgradesModel.build(p), "reach").level, 12)
end)

Harness.test("UpgradesModel: all lines maxed", function()
	local p = Economy.blankProfile()
	for _, up in Upgrades.list do
		p.upgrades[up.id] = up.maxLevel
	end
	local model = UpgradesModel.build(p)
	Harness.eq(model.allMaxed, true)
	Harness.eq(model.bestId, nil)
	Harness.eq(model.canBuyAny, false)
	for _, row in model.rows do
		Harness.eq(row.maxed, true)
		Harness.eq(row.best, false)
	end
end)

Harness.test(
	"UpgradesModel: best next buy is the cheapest price (affordable first, else closest)",
	function()
		-- nothing affordable: closest = cheapest = Sweep Power (12)
		local p = Economy.blankProfile()
		p.coins = 1
		local model = UpgradesModel.build(p)
		Harness.eq(model.bestId, "power")
		Harness.eq(rowOf(model, "power").best, true)
		local stars = 0
		for _, row in model.rows do
			if row.best then
				stars += 1
			end
		end
		Harness.eq(stars, 1)

		-- power is already level 5 (cost 12 x 1.38^5 = 60); backpack (15) is now the cheapest
		p.upgrades = { power = 5 }
		p.coins = 100
		model = UpgradesModel.build(p)
		Harness.eq(model.bestId, "backpack")
		Harness.eq(model.canBuyAny, true)

		-- cheapest line maxed out: the next cheapest takes the star
		local q = Economy.blankProfile()
		q.upgrades = { power = 16, backpack = 20 }
		Harness.eq(UpgradesModel.build(q).bestId, "speed")
	end
)

Harness.test("UpgradesModel: levelUps spots only lines that went up", function()
	local p = Economy.blankProfile()
	local before = UpgradesModel.levels(p)
	Harness.eq(#UpgradesModel.levelUps(before, p), 0)
	p.upgrades = { power = 1, walk = 2 }
	local ups = UpgradesModel.levelUps(before, p)
	Harness.eq(#ups, 2)
	Harness.eq(ups[1], "power")
	Harness.eq(ups[2], "walk")
	-- a Cool Down (levels fall) is not a level up
	Harness.eq(#UpgradesModel.levelUps(UpgradesModel.levels(p), Economy.blankProfile()), 0)
end)

Harness.test("UpgradesModel: half empty or hostile store tables never throw", function()
	local model = UpgradesModel.build(nil)
	Harness.eq(#model.rows, 10)
	model = UpgradesModel.build({})
	Harness.eq(model.coins, 0)
	local weird: any = {
		coins = 0 / 0,
		upgrades = { power = "lots", reach = -4, speed = 1e9 },
		sparkPerks = 7,
		derived = "nope",
	}
	model = UpgradesModel.build(weird)
	Harness.eq(rowOf(model, "power").level, 0)
	Harness.eq(rowOf(model, "reach").level, 0)
	Harness.eq(rowOf(model, "speed").maxed, true)
	Harness.eq(model.coins, 0)
	Harness.eq(ShopModelUtil.profile(weird).coins, 0)
end)

Harness.test("UpgradesModel: hint is always a sentence", function()
	local p = Economy.blankProfile()
	Harness.truthy(string.find(UpgradesModel.build(p).hint, "Next goal", 1, true) ~= nil)
	p.coins = 50
	Harness.truthy(string.find(UpgradesModel.build(p).hint, "green", 1, true) ~= nil)
end)
