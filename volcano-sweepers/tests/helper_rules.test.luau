--!strict
-- Helper bots: income maths, which cells they may sweep, formation, visible cap.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local AshGrid = require("../src/shared/Ash/AshGrid")
local Helpers = require("../src/shared/Catalog/Helpers")
local Zones = require("../src/shared/Catalog/Zones")
local Rng = require("../src/shared/Rng")
local HelperRules = require("../src/shared/Player/HelperRules")

local MAX = Config.World.maxUnitsPerCell

-- spots: the middle of Sunny Beach and Fern Forest, far from the hub (the hub is at +z)
local ZONES = Config.World.zones
local BEACH_X, BEACH_Z = 0, -(ZONES[1].inner + ZONES[1].outer) / 2
local FOREST_X, FOREST_Z = 0, -(ZONES[2].inner + ZONES[2].outer) / 2

local function sum(grid: AshGrid.AshGrid): number
	return grid.totalUnits
end

Harness.test("helper: units accrue by level and never lose a fraction", function()
	local whole, carry = HelperRules.accrue(0, 0, 1)
	Harness.eq(whole, 0)
	Harness.near(carry, Helpers.unitsPerSecond(0), 1e-9)
	-- 100 one-second ticks give 100 x rate units, to within one unit
	for _, level in { 0, 5, 15 } do
		local units, c = 0, 0
		for _ = 1, 100 do
			local w
			w, c = HelperRules.accrue(c, level, 1)
			units += w
		end
		Harness.near(units + c, 100 * Helpers.unitsPerSecond(level), 1e-6, `level {level}`)
	end
end)

Harness.test("helper: a lag spike or bad dt can't pay a pile", function()
	local whole = HelperRules.accrue(0, 15, 1000)
	Harness.truthy(whole <= math.ceil(Helpers.unitsPerSecond(15) * HelperRules.MAX_DT))
	Harness.eq((HelperRules.accrue(0, 5, -3)), 0)
	Harness.eq((HelperRules.accrue(0, 5, 0 / 0)), 0)
	local w, c = HelperRules.accrue(0 / 0, 5, 1)
	Harness.truthy(w >= 0 and c >= 0 and c < 1)
end)

Harness.test("helper: income = value x helperMult x sellMult (share 1)", function()
	Harness.near(HelperRules.coinsFor(10, 1.5, 2), 30 * HelperRules.PAY_SHARE)
	Harness.eq(HelperRules.coinsFor(-10, 1, 1), 0)
	Harness.eq(HelperRules.coinsFor(10, 0 / 0, 1), 0)
	Harness.eq(HelperRules.coinsFor(10, 1, -2), 0)
	Harness.eq(HelperRules.coinsFor(math.huge, 1, 1), 0)
end)

Harness.test("helper: 6 bots over a minute match Helpers.coinsPerSecond", function()
	local level, bots, zone = 5, 6, 3
	local sellMult, helperMult = 1.4, 1.2
	local value = Zones.valueOf(zone)
	local units = 0
	local carries = table.create(bots, 0)
	for _ = 1, 60 do
		for b = 1, bots do
			local w
			w, carries[b] = HelperRules.accrue(carries[b], level, 1)
			units += w
		end
	end
	local pending = HelperRules.coinsFor(units * value, helperMult, sellMult)
	local expected = Helpers.coinsPerSecond(bots, level, value, sellMult, helperMult) * 60
	Harness.near(pending, expected, value * sellMult * helperMult * bots, "within one unit per bot")
end)

Harness.test("helper: settle keeps the fraction for next time", function()
	local whole, rest = HelperRules.settle(12.75)
	Harness.eq(whole, 12)
	Harness.near(rest, 0.75)
	whole, rest = HelperRules.settle(0.4)
	Harness.eq(whole, 0)
	Harness.near(rest, 0.4)
	whole, rest = HelperRules.settle(0 / 0)
	Harness.eq(whole, 0)
	Harness.eq(rest, 0)
	whole, rest = HelperRules.settle(-3)
	Harness.eq(whole, 0)
	Harness.eq(rest, 0)
end)

Harness.test("helper: allowedZones follows the owner's gates", function()
	local z = HelperRules.allowedZones({ ["1"] = true, ["3"] = true, ["9"] = true, junk = true })
	Harness.eq(z[1], true)
	Harness.eq(z[2], nil)
	Harness.eq(z[3], true)
	Harness.eq(z[9], nil)
	Harness.eq(next(HelperRules.allowedZones({})), nil)
end)

Harness.test("helper: sweeps the ground near the bot and reports the value", function()
	local grid = AshGrid.new("full")
	local rng = Rng.new(5)
	local before = sum(grid)
	local r = HelperRules.sweepAround(grid, BEACH_X, BEACH_Z, 5, { [1] = true }, rng)
	Harness.eq(r.units, 5)
	Harness.eq(r.valueUnits, 5 * Zones.valueOf(1))
	Harness.eq(sum(grid), before - 5)
end)

Harness.test("helper: every changed cell is near the bot", function()
	local grid = AshGrid.new("full")
	HelperRules.sweepAround(grid, FOREST_X, FOREST_Z, 40, { [2] = true }, Rng.new(9))
	local flat = grid:takeDirty()
	Harness.truthy(#flat > 0)
	for k = 1, #flat, 2 do
		local i = flat[k]
		local dx, dz = grid.layout.cx[i] - FOREST_X, grid.layout.cz[i] - FOREST_Z
		Harness.truthy(
			math.sqrt(dx * dx + dz * dz) <= HelperRules.SWEEP_RADIUS + 1e-6,
			"cell too far"
		)
	end
end)

Harness.test("helper: cells in zones the owner hasn't opened are skipped", function()
	local grid = AshGrid.new("full")
	local before = sum(grid)
	-- standing in the middle of zone 2 with only zone 1 open: nothing to sweep
	local r = HelperRules.sweepAround(grid, FOREST_X, FOREST_Z, 100, { [1] = true }, Rng.new(1))
	Harness.eq(r.units, 0)
	Harness.eq(r.valueUnits, 0)
	Harness.eq(sum(grid), before)

	-- on the border of zones 1 and 2: only the open zone's cells lose ash
	local r2 = HelperRules.sweepAround(grid, 0, -ZONES[2].outer, 60, { [1] = true }, Rng.new(2))
	Harness.truthy(r2.units > 0)
	Harness.eq(r2.valueUnits, r2.units * Zones.valueOf(1))
	local flat = grid:takeDirty()
	for k = 1, #flat, 2 do
		Harness.eq(grid.layout.zone[flat[k]], 1)
	end
end)

Harness.test("helper: zone value is used per unit", function()
	local grid = AshGrid.new("full")
	local r = HelperRules.sweepAround(grid, FOREST_X, FOREST_Z, 7, { [2] = true }, Rng.new(3))
	Harness.eq(r.units, 7)
	Harness.eq(r.valueUnits, 7 * Zones.valueOf(2))
end)

Harness.test("helper: bare ground and zero units do nothing", function()
	local empty = AshGrid.new("empty")
	local r = HelperRules.sweepAround(empty, BEACH_X, BEACH_Z, 50, { [1] = true }, Rng.new(1))
	Harness.eq(r.units, 0)
	local grid = AshGrid.new("full")
	Harness.eq(
		HelperRules.sweepAround(grid, BEACH_X, BEACH_Z, 0, { [1] = true }, Rng.new(1)).units,
		0
	)
	Harness.eq(
		HelperRules.sweepAround(grid, BEACH_X, BEACH_Z, -4, { [1] = true }, Rng.new(1)).units,
		0
	)
	Harness.eq(
		HelperRules.sweepAround(grid, BEACH_X, BEACH_Z, 0 / 0, { [1] = true }, Rng.new(1)).units,
		0
	)
	Harness.eq(grid.totalUnits, grid.N * MAX)
end)

Harness.test("helper: asking for more than is there clears the area and stops", function()
	local grid = AshGrid.new("full")
	local near = grid.layout.cellsInRadius(BEACH_X, BEACH_Z, HelperRules.SWEEP_RADIUS)
	local r = HelperRules.sweepAround(grid, BEACH_X, BEACH_Z, 100000, { [1] = true }, Rng.new(4))
	Harness.eq(r.units, #near * MAX)
	Harness.eq(r.cleared, #near)
	for _, i in near do
		Harness.eq(grid:get(i), 0)
	end
end)

Harness.test("helper: golden cells are left for the players", function()
	local grid = AshGrid.new("full")
	local near = grid.layout.cellsInRadius(BEACH_X, BEACH_Z, HelperRules.SWEEP_RADIUS)
	local gold = near[1]
	grid.goldenSet[gold] = true
	grid.goldenCount += 1
	local r = HelperRules.sweepAround(grid, BEACH_X, BEACH_Z, 100000, { [1] = true }, Rng.new(4))
	Harness.eq(grid:get(gold), MAX)
	Harness.eq(r.units, (#near - 1) * MAX)
end)

Harness.test("helper: same seed, same sweep", function()
	local a, b = AshGrid.new("full"), AshGrid.new("full")
	HelperRules.sweepAround(a, BEACH_X, BEACH_Z, 30, { [1] = true }, Rng.new(42))
	HelperRules.sweepAround(b, BEACH_X, BEACH_Z, 30, { [1] = true }, Rng.new(42))
	Harness.eq(a:encode(), b:encode())
end)

Harness.test("helper: formation is a loose fan behind the owner, nobody overlaps", function()
	for count = 1, Config.Economy.maxHelpers do
		local pts: { { number } } = {}
		for i = 1, count do
			local x, z = HelperRules.formationOffset(i, count)
			Harness.truthy(z > 0, "behind the owner")
			local r = math.sqrt(x * x + z * z)
			Harness.truthy(r >= 4.9 and r <= 6.6, "stays close")
			table.insert(pts, { x, z })
		end
		for i = 1, #pts do
			for j = i + 1, #pts do
				local dx, dz = pts[i][1] - pts[j][1], pts[i][2] - pts[j][2]
				Harness.truthy(
					math.sqrt(dx * dx + dz * dz) > 2.2,
					`bots {i} and {j} of {count} overlap`
				)
			end
		end
	end
	local x1 = HelperRules.formationOffset(1, 1)
	Harness.near(x1, 0, 1e-9)
end)

Harness.test("helper: bob, follow alpha and teleport", function()
	for i = 1, 6 do
		for t = 0, 20 do
			Harness.truthy(math.abs(HelperRules.bob(t * 0.37, i)) <= 0.35 + 1e-9)
		end
	end
	Harness.eq(HelperRules.followAlpha(0), 0)
	local a1, a2 = HelperRules.followAlpha(0.05), HelperRules.followAlpha(0.1)
	Harness.truthy(a1 > 0 and a2 > a1 and a2 < 1)
	Harness.truthy(HelperRules.followAlpha(100) < 1)
	Harness.eq(HelperRules.shouldTeleport(80), false)
	Harness.eq(HelperRules.shouldTeleport(80.5), true)
	Harness.eq(HelperRules.shouldTeleport(0), false)
end)

Harness.test("helper: never more than the visible cap, fair to everyone", function()
	local counts: { number } = {}
	for i = 1, 16 do
		counts[i] = 6
	end
	local out = HelperRules.allocateVisible(counts, HelperRules.MAX_VISIBLE)
	local total = 0
	for i, n in out do
		total += n
		Harness.truthy(n <= counts[i])
		Harness.truthy(n >= 3 and n <= 4, "fair share") -- 60 / 16 = 3.75
	end
	Harness.eq(total, 60)
	-- under the cap everyone gets all of theirs
	local small = HelperRules.allocateVisible({ 3, 0, 2, 6 }, 60)
	Harness.eq(small[1], 3)
	Harness.eq(small[2], 0)
	Harness.eq(small[3], 2)
	Harness.eq(small[4], 6)
	-- a tight cap shares one each first
	local tight = HelperRules.allocateVisible({ 6, 6, 6 }, 3)
	Harness.eq(tight[1] + tight[2] + tight[3], 3)
	Harness.eq(tight[1], 1)
	Harness.eq(tight[2], 1)
	Harness.eq(tight[3], 1)
	Harness.eq(HelperRules.allocateVisible({ 6, 6 }, 0)[1], 0)
	Harness.eq(#HelperRules.allocateVisible({}, 60), 0)
	Harness.eq(HelperRules.allocateVisible({ 5 }, 0 / 0)[1], 0)
end)

Harness.test("helper: float text and its rate limit", function()
	Harness.eq(HelperRules.floatText(12), "+12")
	Harness.eq(HelperRules.floatText(12.9), "+12")
	Harness.eq(HelperRules.floatText(999), "+999")
	Harness.eq(HelperRules.floatText(1000), "+1K")
	Harness.eq(HelperRules.floatText(1500), "+1.5K")
	Harness.eq(HelperRules.floatText(2500000), "+2.5M")
	Harness.eq(HelperRules.floatText(-5), "+0")
	Harness.eq(HelperRules.floatText(0 / 0), "+0")
	Harness.eq(HelperRules.canShowFloat(10, 11.9), false)
	Harness.eq(HelperRules.canShowFloat(10, 12), true)
	Harness.eq(HelperRules.canShowFloat(-100, 0), true)
end)
