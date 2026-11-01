--!strict
-- Gates panel model: open / next / locked, comparison text, prices, ring diagram.
local Harness = require("./harness")
local Economy = require("../src/shared/Rules/Economy")
local Pricing = require("../src/shared/Rules/Pricing")
local Zones = require("../src/shared/Catalog/Zones")
local GatesModel = require("../src/shared/Ui/GatesModel")
local ShopModelUtil = require("../src/shared/Ui/ShopModelUtil")

local function rowOf(model: GatesModel.Model, id: number): GatesModel.Row
	return model.rows[id]
end

Harness.test("GatesModel: new player has the beach open and Fern Forest next", function()
	local m = GatesModel.build(Economy.blankProfile())
	Harness.eq(#m.rows, 5)
	Harness.eq(rowOf(m, 1).state, "open")
	Harness.eq(rowOf(m, 1).buttonLabel, "OPEN")
	Harness.eq(rowOf(m, 1).best, true)
	Harness.eq(rowOf(m, 2).state, "next")
	local price2 = Zones.byId[2].unlockPrice
	Harness.eq(rowOf(m, 2).price, price2)
	Harness.eq(rowOf(m, 2).needText, `Need {ShopModelUtil.coinsText(price2)} more coins!`)
	Harness.eq(rowOf(m, 2).reasonText, `Need {ShopModelUtil.coinsText(price2)} more coins!`)
	Harness.eq(rowOf(m, 3).state, "locked")
	Harness.eq(rowOf(m, 3).price, nil)
	Harness.eq(rowOf(m, 3).buttonLabel, "LOCKED")
	Harness.eq(rowOf(m, 3).reasonText, "Open Fern Forest first!")
	Harness.eq(m.nextId, 2)
	Harness.eq(m.bestId, 1)
	Harness.eq(m.canBuyAny, false)
end)

Harness.test("GatesModel: only the next zone is ever buyable, even with a fortune", function()
	local p = Economy.blankProfile()
	p.coins = 999999999
	local m = GatesModel.build(p)
	Harness.eq(rowOf(m, 2).affordable, true)
	Harness.eq(m.canBuyAny, true)
	for id = 3, 5 do
		Harness.eq(rowOf(m, id).price, nil, "zone " .. id)
		Harness.eq(rowOf(m, id).affordable, false)
		Harness.eq(rowOf(m, id).state, "locked")
		-- the same answer the server gives
		Harness.eq(Pricing.priceOf("zone", id, p), nil)
	end
end)

Harness.test("GatesModel: price and reason match Pricing", function()
	local p = Economy.blankProfile()
	p.zones = { ["1"] = true, ["2"] = true }
	local price3 = Zones.byId[3].unlockPrice
	p.coins = price3 - 1
	local m = GatesModel.build(p)
	Harness.eq(rowOf(m, 3).price, Pricing.priceOf("zone", 3, p))
	Harness.eq(rowOf(m, 3).missing, 1)
	Harness.eq(rowOf(m, 3).needText, "Need 1 more coins!")
	Harness.eq(rowOf(m, 2).state, "open")
	Harness.eq(rowOf(m, 2).best, true)
	Harness.eq(rowOf(m, 1).best, false)
	Harness.eq(rowOf(m, 4).reasonText, "Open Hot Springs first!")
	p.coins = price3
	Harness.eq(rowOf(GatesModel.build(p), 3).affordable, true)
end)

Harness.test("GatesModel: x-times comparison with the zone before", function()
	local m = GatesModel.build(Economy.blankProfile())
	Harness.eq(rowOf(m, 1).compareText, nil)
	Harness.eq(rowOf(m, 2).compareText, "x3 more coins per ash!")
	Harness.eq(rowOf(m, 3).compareText, "x2.7 more coins per ash!")
	Harness.eq(rowOf(m, 4).compareText, "x2.8 more coins per ash!")
	Harness.eq(rowOf(m, 5).compareText, "x2.7 more coins per ash!")
	Harness.eq(rowOf(m, 1).valueText, "1 coin per ash")
	Harness.eq(rowOf(m, 3).valueText, "8 coins per ash")
	for _, row in m.rows do
		Harness.eq(row.value, Zones.valueOf(row.id))
	end
end)

Harness.test("GatesModel: everything open", function()
	local p = Economy.blankProfile()
	p.zones = { ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, ["5"] = true }
	local m = GatesModel.build(p)
	Harness.eq(m.nextId, nil)
	Harness.eq(m.bestId, 5)
	Harness.eq(m.canBuyAny, false)
	for _, row in m.rows do
		Harness.eq(row.state, "open")
		Harness.eq(row.price, nil)
	end
	Harness.truthy(string.find(m.hint, "Every gate", 1, true) ~= nil)
end)

Harness.test("GatesModel: ring diagram is nested, uses the zone ground colours", function()
	local m = GatesModel.build(Economy.blankProfile())
	Harness.eq(#m.rings, 5)
	Harness.eq(m.rings[1].radiusFrac, 1)
	for i = 2, 5 do
		Harness.truthy(m.rings[i].radiusFrac < m.rings[i - 1].radiusFrac, "rings shrink")
		Harness.eq(m.rings[i].colorHex, Zones.byId[i].ground)
	end
	Harness.truthy(m.coreFrac > 0 and m.coreFrac < m.rings[5].radiusFrac, "volcano in the middle")
	Harness.eq(m.rings[1].state, "open")
	Harness.eq(m.rings[2].state, "next")
	Harness.eq(m.rings[3].state, "locked")
end)

Harness.test("GatesModel: broken zone tables never throw", function()
	Harness.eq(#GatesModel.build(nil).rows, 5)
	local weird: any = { coins = -50, zones = { ["2"] = "yes", ["9"] = true, bad = true } }
	local m = GatesModel.build(weird)
	Harness.eq(rowOf(m, 2).state, "next")
	Harness.eq(m.coins, 0)
end)

Harness.test("GatesModel.prompt: price on the next gate, hidden once open, why when far", function()
	local p = Economy.blankProfile()
	local price = Zones.byId[2].unlockPrice
	local nextGate = GatesModel.prompt(p, 2)
	Harness.eq(nextGate.enabled, true)
	Harness.truthy(
		string.find(nextGate.actionText, "Open gate (", 1, true) ~= nil
			and string.find(nextGate.actionText, "coins)", 1, true) ~= nil,
		nextGate.actionText
	)
	Harness.truthy(string.len(nextGate.actionText) <= 32, "fits a prompt")
	Harness.truthy(price > 0)
	local far = GatesModel.prompt(p, 3)
	Harness.eq(far.enabled, true)
	Harness.eq(far.actionText, `Open {Zones.byId[2].name} first`)
	p.zones["2"] = true
	Harness.eq(GatesModel.prompt(p, 2).enabled, false)
	Harness.eq(GatesModel.prompt(p, 1).enabled, false) -- the beach is always yours
	Harness.eq(GatesModel.prompt(p, 99).actionText, "Open gate")
	Harness.eq(GatesModel.prompt(nil, 2).enabled, true)
end)
