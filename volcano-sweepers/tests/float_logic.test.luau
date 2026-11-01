--!strict
local Harness = require("./harness")
local FloatLogic = require("../src/shared/Client/FloatLogic")

Harness.test("float: gains add up, losses and bad numbers are ignored", function()
	local acc = FloatLogic.new()
	FloatLogic.add(acc, 2, 2, 1)
	FloatLogic.add(acc, -5, -5, 1) -- a sale or a lava hit: not a pop
	FloatLogic.add(acc, 0 / 0, 3, 1)
	FloatLogic.add(acc, 1, 1, 1)
	Harness.eq(acc.units, 3)
	Harness.eq(acc.value, 3)
	Harness.eq(acc.golden, false)
end)

Harness.test("float: flush gap throttles, take empties", function()
	local acc = FloatLogic.new()
	Harness.eq(FloatLogic.ready(acc, 0, 0.15), false, "nothing to show")
	FloatLogic.add(acc, 3, 3, 1)
	Harness.eq(FloatLogic.ready(acc, 0, 0.15), true, "first pop shows at once")
	local pop = FloatLogic.take(acc, 0, 1) :: FloatLogic.Pop
	Harness.eq(pop.amount, 3)
	Harness.eq(acc.units, 0)
	FloatLogic.add(acc, 2, 2, 1)
	Harness.eq(FloatLogic.ready(acc, 0.1, 0.15), false, "too soon")
	Harness.eq(FloatLogic.ready(acc, 0.16, 0.15), true)
	Harness.eq(FloatLogic.take(FloatLogic.new(), 1, 1), nil, "empty take")
end)

Harness.test("float: the number is the coin worth (value x sellMult), at least 1", function()
	local acc = FloatLogic.new()
	FloatLogic.add(acc, 2, 120, 60) -- 2 units in the Lava Heart
	local pop = FloatLogic.take(acc, 0, 1.5) :: FloatLogic.Pop
	Harness.eq(pop.amount, 180)
	Harness.eq(pop.golden, false)
	FloatLogic.add(acc, 1, 0.2, 1)
	Harness.eq((FloatLogic.take(acc, 1, 1) :: FloatLogic.Pop).amount, 1, "never +0")
	FloatLogic.add(acc, 4, 0, 0) -- no value known: show units
	Harness.eq((FloatLogic.take(acc, 2, 0 / 0) :: FloatLogic.Pop).amount, 4)
end)

Harness.test("float: golden cells are detected, zone edges are not", function()
	local acc = FloatLogic.new()
	FloatLogic.add(acc, 2, 10, 1) -- 5x zone value: golden
	Harness.eq(acc.golden, true)
	local edge = FloatLogic.new()
	FloatLogic.add(edge, 2, 6, 3) -- forest ash swept while the richest zone is the forest
	Harness.eq(edge.golden, false)
	local rich = FloatLogic.new()
	FloatLogic.add(rich, 1, 60, 22) -- lava heart cell from the rim edge (60/22 < 3.5)
	Harness.eq(rich.golden, false)
end)

Harness.test("float: style colour by zone tier, gold for golden, bigger for more", function()
	local small = FloatLogic.style({ amount = 1, units = 1, zoneValue = 1, golden = false })
	local big = FloatLogic.style({ amount = 5000, units = 9, zoneValue = 60, golden = false })
	local gold = FloatLogic.style({ amount = 5, units = 1, zoneValue = 1, golden = true })
	Harness.eq(small.text, "+1")
	Harness.eq(big.text, "+5K")
	Harness.truthy(big.scale > small.scale, "more coins, bigger text")
	Harness.truthy(big.scale <= 1.6 and small.scale >= 0.85, "scale clamped")
	Harness.eq(gold.color, FloatLogic.GOLD_COLOR)
	Harness.truthy(gold.scale > small.scale)
	Harness.truthy(FloatLogic.tierColor(1) ~= FloatLogic.tierColor(60), "zones look different")
	local seen: { [string]: boolean } = {}
	for _, v in { 1, 3, 8, 22, 60 } do
		local c = FloatLogic.tierColor(v)
		Harness.eq(seen[c], nil, "one colour per zone")
		seen[c] = true
		Harness.truthy(string.match(c, "^#%x%x%x%x%x%x$") ~= nil)
	end
end)

Harness.test("float: becameFull fires once on the filling change only", function()
	Harness.eq(FloatLogic.becameFull(20, 30, 30), true)
	Harness.eq(FloatLogic.becameFull(30, 30, 30), false)
	Harness.eq(FloatLogic.becameFull(10, 20, 30), false)
	Harness.eq(FloatLogic.becameFull(30, 0, 30), false)
	Harness.eq(FloatLogic.becameFull(nil, 30, 30), false)
	Harness.eq(FloatLogic.becameFull(10, 30, 0), false)
end)
