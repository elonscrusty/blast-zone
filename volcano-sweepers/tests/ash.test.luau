--!strict
local Harness = require("./harness")
local AshGrid = require("../src/shared/Ash/AshGrid")
local Config = require("../src/shared/Config")
local Layout = require("../src/shared/Ash/Layout")
local Rng = require("../src/shared/Rng")
local WorldPlan = require("../src/shared/WorldPlan")

local W = Config.World
-- island radii from Config (the island grew 2x: never hard-code them here)
local OUTER = W.zones[1].outer -- beach edge
local INNER = W.zones[5].inner -- volcano cone edge
local FERN_OUTER = W.zones[2].outer -- the Sunny Beach / Fern Forest border
local FERN_MID = (W.zones[2].inner + W.zones[2].outer) / 2
local MAX = W.maxUnitsPerCell
local ALL_ZONES: { [number]: boolean } =
	{ [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }
local ZONE_VALUES: { [number]: number } = { [1] = 1, [2] = 3, [3] = 8, [4] = 22, [5] = 60 }

-- a spot in the middle of Fern Forest on the far side from the hub
local PX, PZ = 0, -FERN_MID

local function sumLevels(g: AshGrid.AshGrid): number
	local s = 0
	for i = 1, g.N do
		s += g.levels[i]
	end
	return s
end

-- ===== Layout =====

Harness.test("layout: same result every build, cell count in range", function()
	local a = Layout.build(W)
	local b = Layout.build(W)
	Harness.eq(a.N, b.N)
	Harness.eq(a.N, Layout.N)
	for i = 1, a.N do
		Harness.eq(a.cx[i], b.cx[i])
		Harness.eq(a.cz[i], b.cz[i])
		Harness.eq(a.zone[i], b.zone[i])
	end
	-- annulus area / cell area, minus the hub circle and the Trade Post circles that are cleared
	local ring = math.pi * (OUTER ^ 2 - INNER ^ 2) / (W.cellSize ^ 2)
	local hub = math.pi * W.hub.clearRadius ^ 2 / (W.cellSize ^ 2)
	local posts = 0
	for _, p in WorldPlan.postSpots(W) do
		posts += math.pi * p.clearRadius ^ 2 / (W.cellSize ^ 2)
	end
	Harness.near(Layout.N, ring - hub - posts, ring * 0.02, "N vs area")
	print(`       (island has {Layout.N} ash cells)`)
end)

Harness.test("layout: row-major compact order, cellOf round trip", function()
	local prevZ, prevX = -math.huge, -math.huge
	for i = 1, Layout.N do
		local x, z = Layout.cx[i], Layout.cz[i]
		Harness.truthy(z > prevZ or (z == prevZ and x > prevX), "row-major order")
		prevZ, prevX = z, x
		Harness.eq(Layout.cellOf(x, z), i, "cellOf centre")
		Harness.eq(Layout.cellOf(x + 3.9, z - 3.9), i, "cellOf inside cell")
	end
	Harness.eq(Layout.cellOf(0, 0), nil, "volcano centre has no ash")
	Harness.eq(Layout.cellOf(OUTER + 150, 0), nil, "outside the island")
	Harness.eq(Layout.cellOf(0 / 0, 1), nil, "nan")
end)

Harness.test("layout: cells sit in rings, hub circle is clear, zones match radius", function()
	local counts = { 0, 0, 0, 0, 0 }
	for i = 1, Layout.N do
		local x, z = Layout.cx[i], Layout.cz[i]
		local r = math.sqrt(x * x + z * z)
		Harness.truthy(r >= INNER and r <= OUTER, "inside rings")
		local zone = Layout.zone[i]
		local def = W.zones[zone]
		Harness.truthy(r >= def.inner and r <= def.outer, `zone {zone} radius {r}`)
		local hx, hz = x - Layout.hubX, z - Layout.hubZ
		Harness.truthy(math.sqrt(hx * hx + hz * hz) > W.hub.clearRadius, "hub clear")
		for _, p in WorldPlan.postSpots(W) do
			local px, pz = x - p.x, z - p.z
			Harness.truthy(math.sqrt(px * px + pz * pz) > p.clearRadius, "trade post clear")
		end
		counts[zone] += 1
	end
	for z = 1, 5 do
		Harness.truthy(counts[z] > 50, `zone {z} has cells`)
		Harness.eq(counts[z], Layout.zoneCount[z])
		Harness.eq(#Layout.zoneCells[z], counts[z])
	end
	-- outer rings are bigger than inner rings
	Harness.truthy(counts[1] > counts[2] and counts[2] > counts[3] and counts[3] > counts[4])
	-- cells close to the hub (but outside the circle) still exist
	Harness.truthy(Layout.cellOf(Layout.hubX, Layout.hubZ - W.hub.clearRadius - 6) ~= nil)
	Harness.eq(Layout.cellOf(Layout.hubX, Layout.hubZ), nil, "hub centre cleared")
	for _, p in WorldPlan.postSpots(W) do
		Harness.eq(Layout.cellOf(p.x, p.z), nil, `trade post {p.zoneId} centre cleared`)
	end
end)

Harness.test("layout: neighbours and radius queries", function()
	local i = assert(Layout.cellOf(PX, PZ))
	local nb = Layout.neighbours(i)
	Harness.eq(#nb, 8)
	for _, j in nb do
		Harness.truthy(
			math.abs(Layout.cx[j] - Layout.cx[i]) <= 8.001
				and math.abs(Layout.cz[j] - Layout.cz[i]) <= 8.001
		)
		local back = Layout.neighbours(j)
		Harness.truthy(table.find(back, i) ~= nil, "symmetric")
	end
	local near = Layout.cellsInRadius(PX, PZ, 12)
	Harness.truthy(#near > 0 and #near < 60)
	for _, j in near do
		local dx, dz = Layout.cx[j] - PX, Layout.cz[j] - PZ
		Harness.truthy(dx * dx + dz * dz <= 144 + 1e-9)
	end
end)

-- ===== Grid basics =====

Harness.test("grid: fills, units and clean fractions", function()
	local full = AshGrid.new("full")
	Harness.eq(full.N, Layout.N)
	Harness.eq(sumLevels(full), Layout.N * MAX)
	Harness.near(full:totalClean(), 0)
	local empty = AshGrid.new("empty")
	Harness.near(empty:totalClean(), 1)
	local part = AshGrid.new(3)
	Harness.eq(part:get(5), 3)
	Harness.near(part:totalClean(), 1 - 3 / MAX, 1e-9)
	Harness.near(part:zoneClean(2), 1 - 3 / MAX, 1e-9)
	Harness.eq(AshGrid.new(99):get(1), MAX, "level clamped")
	Harness.eq(#full:takeDirty(), 0, "fresh grid has nothing dirty")
end)

Harness.test("grid: set, remove, add conserve units and clamp", function()
	local g = AshGrid.new(4)
	Harness.eq(g:remove(10, 3), 3)
	Harness.eq(g:get(10), 1)
	Harness.eq(g:remove(10, 5), 1, "cannot remove more than is there")
	Harness.eq(g:get(10), 0)
	Harness.eq(g:remove(10, 5), 0)
	Harness.eq(g:add(10, 20), MAX, "add stops at max")
	Harness.eq(g:add(10, 1), 0)
	Harness.eq(g:remove(0, 1), 0, "bad index")
	Harness.eq(g:remove(g.N + 1, 1), 0, "bad index")
	Harness.eq(g:remove(3, -4), 0, "negative")
	Harness.eq(g:set(3, 99), true)
	Harness.eq(g:get(3), MAX)
	Harness.eq(g:set(g.N + 5, 1), false)
	Harness.eq(g.totalUnits, sumLevels(g), "running total matches")
	local z = 0
	for _, zid in Layout.zoneIds do
		z += g.zoneUnits[zid]
	end
	Harness.eq(z, g.totalUnits, "zone totals add up")
end)

-- ===== Cone =====

Harness.test("cone: nearest first, within reach and arc, small", function()
	local g = AshGrid.new("full")
	for _, arc in { 30, 90, 180, 360 } do
		local cells = g:queryCone(PX, PZ, 1, 0, 12, arc)
		Harness.truthy(#cells > 0 and #cells < 60, `arc {arc}: {#cells} cells`)
		local prev = -1
		for _, j in cells do
			local dx, dz = Layout.cx[j] - PX, Layout.cz[j] - PZ
			local d = math.sqrt(dx * dx + dz * dz)
			Harness.truthy(d >= prev - 1e-9, "sorted nearest first")
			prev = d
			if j ~= AshGrid.ownCell(Layout, PX, PZ) then
				Harness.truthy(d <= AshGrid.coneReach(12, W.cellSize) + 1e-9, "within reach")
				if arc < 360 then
					local ang = math.deg(math.acos(math.clamp(dx / d, -1, 1)))
					Harness.truthy(ang <= arc / 2 + 1e-6, `angle {ang} within {arc / 2}`)
				end
			end
		end
	end
	local own = assert(Layout.cellOf(PX, PZ))
	Harness.eq(
		g:queryCone(Layout.cx[own] + 1, Layout.cz[own] - 1, 0, 1, 1, 10)[1],
		own,
		"own cell is first even for a tiny reach"
	)
	-- facing the other way gives different far cells
	local east = g:queryCone(PX, PZ, 1, 0, 24, 60)
	local west = g:queryCone(PX, PZ, -1, 0, 24, 60)
	local seen: { [number]: boolean } = {}
	for _, j in east do
		seen[j] = true
	end
	local overlap = 0
	for _, j in west do
		if seen[j] then
			overlap += 1
		end
	end
	Harness.truthy(overlap <= 9, "east and west cones only share the cells near the player")
	Harness.eq(#g:queryCone(PX, PZ, 0, 0, 12, 90) > 3, true, "no facing falls back to all round")
end)

Harness.test("cone: only the cell you stand in is free; what is behind you is never hit", function()
	local g = AshGrid.new("full")
	local own = AshGrid.ownCell(Layout, PX, PZ)
	Harness.truthy(own > 0)
	local cx, cz = Layout.cx[own], Layout.cz[own]
	-- stand in the middle of the cell, face east: the west neighbour (8 studs away) is behind
	local west = assert(Layout.cellOf(cx - W.cellSize, cz))
	local east = assert(Layout.cellOf(cx + W.cellSize, cz))
	local cells = g:queryCone(cx, cz, 1, 0, 7, 90)
	local set: { [number]: boolean } = {}
	for _, j in cells do
		set[j] = true
	end
	Harness.truthy(set[own], "own cell")
	Harness.truthy(
		set[east],
		"the cell in front (8 studs) is within a 7-stud reach to its near part"
	)
	Harness.eq(set[west], nil, "the cell behind is not hit any more")
	Harness.eq(AshGrid.ownCell(Layout, 0 / 0, 0), 0)
	Harness.eq(AshGrid.ownCell(Layout, 99999, 0), 0)
end)

-- Average cells per swing over many beach spots and facings (what a player really gets).
local function meanCells(reach: number, arc: number): number
	local g = AshGrid.new("full")
	local rng = Rng.new(11)
	local total = 0
	local n = 1200
	for _ = 1, n do
		local r = rng:range(196, 244)
		local a = rng:range(0, math.pi * 2)
		local f = rng:range(0, math.pi * 2)
		total += #g:queryCone(
			r * math.cos(a),
			r * math.sin(a),
			math.cos(f),
			math.sin(f),
			reach,
			arc
		)
	end
	return total / n
end

Harness.test("cone: every bit of Reach and arc adds cells on average", function()
	local base = meanCells(7, 90)
	local reach4 = meanCells(7 * 1.04, 90) -- Reach level 1 on a Twig Broom
	local reach12 = meanCells(7 * 1.48, 90) -- Reach maxed
	local wide = meanCells(7, 120)
	print(
		string.format(
			"       twig %.2f cells, reach +4%% %.2f, reach +48%% %.2f, arc 120 %.2f",
			base,
			reach4,
			reach12,
			wide
		)
	)
	Harness.truthy(reach4 > base, "Reach level 1 helps")
	Harness.truthy(reach12 > base * 1.35, "maxed Reach is a big, visible change")
	Harness.truthy(wide > base, "a wider fan helps")
end)

Harness.test("sweep: melt clears the leftovers of a cell (Lava Mop trait)", function()
	local g = AshGrid.new(0)
	local own = AshGrid.ownCell(Layout, PX, PZ)
	g:set(own, 5)
	local plain = g:sweep(
		PX,
		PZ,
		1,
		0,
		{ reach = 0.1, arcDeg = 10, power = 2 },
		ALL_ZONES,
		100,
		Rng.new(1),
		0
	)
	Harness.eq(plain.removedUnits, 2)
	Harness.eq(g.levels[own], 3)
	local melted = g:sweep(
		PX,
		PZ,
		1,
		0,
		{ reach = 0.1, arcDeg = 10, power = 2, melt = 3 },
		ALL_ZONES,
		100,
		Rng.new(1),
		0
	)
	Harness.eq(melted.removedUnits, 3, "2 swept + 1 melted")
	Harness.eq(g.levels[own], 0)
	Harness.eq(#melted.clearedCells, 1)
	-- melt never overfills the backpack
	g:set(own, 4)
	local tight = g:sweep(
		PX,
		PZ,
		1,
		0,
		{ reach = 0.1, arcDeg = 10, power = 2, melt = 3 },
		ALL_ZONES,
		3,
		Rng.new(1),
		0
	)
	Harness.eq(tight.removedUnits, 3)
	Harness.eq(g.levels[own], 1)
end)

-- ===== Sweep =====

Harness.test("sweep: conservation, value, nearest first", function()
	local g = AshGrid.new("full")
	local rng = Rng.new(1)
	local before = g.totalUnits
	local res = g:sweep(
		PX,
		PZ,
		1,
		0,
		{ reach = 14, arcDeg = 120, power = 2 },
		ALL_ZONES,
		1000,
		rng,
		0,
		ZONE_VALUES
	)
	Harness.eq(before - g.totalUnits, res.removedUnits, "removed == level drop")
	Harness.truthy(res.removedUnits > 0)
	local sum = 0
	for _, n in res.perCell do
		sum += n
	end
	Harness.eq(sum, res.removedUnits)
	Harness.eq(#res.changed, #res.perCell)
	Harness.eq(res.valueUnits, res.removedUnits * ZONE_VALUES[2], "all cells are zone 2")
	Harness.eq(res.full, false)
	for k, j in res.changed do
		Harness.eq(g:get(j), MAX - res.perCell[k])
	end
	Harness.eq(#res.clearedCells, 0, "9 units, power 2: nothing cleared yet")
	-- default zone value is 1
	local g2 = AshGrid.new("full")
	local r2 =
		g2:sweep(PX, PZ, 1, 0, { reach = 14, arcDeg = 120, power = 2 }, ALL_ZONES, 1000, rng, 0)
	Harness.eq(r2.valueUnits, r2.removedUnits)
end)

Harness.test("sweep: clears cells, reports them, stops at zero", function()
	local g = AshGrid.new(2)
	local rng = Rng.new(2)
	local res = g:sweep(
		PX,
		PZ,
		0,
		1,
		{ reach = 12, arcDeg = 360, power = 3 },
		ALL_ZONES,
		1000,
		rng,
		0,
		ZONE_VALUES
	)
	Harness.eq(#res.clearedCells, #res.changed)
	Harness.eq(res.removedUnits, 2 * #res.changed, "only 2 units per cell exist")
	for _, j in res.clearedCells do
		Harness.eq(g:get(j), 0)
	end
	local again =
		g:sweep(PX, PZ, 0, 1, { reach = 12, arcDeg = 360, power = 3 }, ALL_ZONES, 1000, rng, 0)
	Harness.eq(again.removedUnits, 0, "nothing left")
	Harness.eq(#again.changed, 0)
end)

Harness.test("sweep: capacity limit stops the sweep and never overfills", function()
	for cap = 0, 12 do
		local g = AshGrid.new("full")
		local rng = Rng.new(3)
		local res =
			g:sweep(PX, PZ, 1, 0, { reach = 14, arcDeg = 360, power = 4 }, ALL_ZONES, cap, rng, 0)
		Harness.truthy(res.removedUnits <= cap, "never more than capacity")
		Harness.eq(res.removedUnits, cap, "plenty of ash: capacity is used exactly")
		Harness.eq(res.full, true)
		Harness.eq(g.totalUnits, Layout.N * MAX - cap)
	end
	local g = AshGrid.new("full")
	local res = g:sweep(
		PX,
		PZ,
		1,
		0,
		{ reach = 14, arcDeg = 360, power = 1 },
		ALL_ZONES,
		2.9,
		Rng.new(1),
		0
	)
	Harness.eq(res.removedUnits, 2, "fractional capacity rounds down")
	-- nearest cell is taken first
	local own = assert(Layout.cellOf(PX, PZ))
	local g3 = AshGrid.new("full")
	g3:sweep(PX, PZ, 1, 0, { reach = 14, arcDeg = 360, power = 1 }, ALL_ZONES, 1, Rng.new(1), 0)
	local nearest = g3:queryCone(PX, PZ, 1, 0, 14, 360)[1]
	Harness.eq(g3:get(nearest), MAX - 1)
	Harness.truthy(g3:get(own) <= MAX)
end)

Harness.test("sweep: locked zones are untouched", function()
	local g = AshGrid.new("full")
	-- stand on the zone 1/2 border; only zone 2 may be swept
	local res = g:sweep(
		0,
		-FERN_OUTER,
		0,
		-1,
		{ reach = 20, arcDeg = 360, power = 2 },
		{ [2] = true },
		1000,
		Rng.new(4),
		0
	)
	Harness.truthy(#res.changed > 0)
	for _, j in res.changed do
		Harness.eq(Layout.zone[j], 2)
	end
	local none = g:sweep(
		0,
		-FERN_OUTER,
		0,
		-1,
		{ reach = 20, arcDeg = 360, power = 2 },
		{},
		1000,
		Rng.new(4),
		0
	)
	Harness.eq(none.removedUnits, 0)
end)

Harness.test("sweep: fractional power averages out; sweet spot doubles", function()
	local function average(power: number, sweet: number): number
		local g = AshGrid.new("full")
		local rng = Rng.new(77)
		local cells = g:queryCone(PX, PZ, 1, 0, 14, 90)
		local tool = { reach = 14, arcDeg = 90, power = power }
		local removed, visits = 0, 0
		for _ = 1, 3000 do
			for _, j in cells do
				g:set(j, MAX)
			end
			local res = g:sweep(PX, PZ, 1, 0, tool, ALL_ZONES, 1e9, rng, sweet)
			removed += res.removedUnits
			visits += #res.changed
		end
		return removed / visits
	end
	Harness.near(average(1, 0), 1, 1e-9, "whole power is exact")
	Harness.near(average(1.5, 0), 1.5, 0.03, "power 1.5")
	Harness.near(
		average(0.25, 0),
		0.25 / (0.25 * 1),
		0.0001 + 1.0 - 1.0 + 0,
		"only cells that lose units are counted"
	)
	Harness.near(average(2, 0.5), 3, 0.05, "sweet spot 50% doubles")
end)

Harness.test("sweep: golden cells pay x5 and clear their flag", function()
	local g = AshGrid.new("empty")
	local rng = Rng.new(8)
	local cells = g:spawnGolden(rng, 25, { [2] = true })
	Harness.eq(#cells, 25)
	Harness.eq(g.goldenCount, 25)
	for _, j in cells do
		Harness.truthy(g:isGolden(j))
		Harness.eq(Layout.zone[j], 2)
		Harness.truthy(g:get(j) >= 6, "golden cells are worth racing for")
	end
	local j = cells[1]
	local before = g:get(j)
	local res = g:sweep(
		Layout.cx[j],
		Layout.cz[j],
		1,
		0,
		{ reach = 1, arcDeg = 360, power = 100 },
		ALL_ZONES,
		1e9,
		rng,
		0,
		ZONE_VALUES
	)
	Harness.truthy(table.find(res.changed, j) ~= nil)
	Harness.truthy(res.goldenCleared >= 1)
	Harness.eq(g:isGolden(j), false, "emptied golden cell is no longer golden")
	-- value: golden cell units x3 x5, other zone-2 non-golden cells x3
	local expected = 0
	for k, c in res.changed do
		local mult = (c == j or table.find(cells, c) ~= nil) and 5 or 1
		expected += res.perCell[k] * 3 * mult
	end
	Harness.eq(res.valueUnits, expected)
	Harness.truthy(res.valueUnits >= before * 3 * 5)
	local gone = g:clearGolden()
	Harness.eq(g.goldenCount, 0)
	Harness.truthy(#gone >= 1)
end)

-- ===== Regrow and rain =====

Harness.test("regrow: adds units, favours emptier zones, never overfills", function()
	local g = AshGrid.new("full")
	for _, j in Layout.zoneCells[5] do
		g:set(j, 0)
	end
	local rng = Rng.new(9)
	local before = g.totalUnits
	local added = g:regrow(rng, 600, nil)
	Harness.eq(g.totalUnits - before, added)
	Harness.truthy(added > 590)
	Harness.eq(g.zoneUnits[5], added, "all growth lands in the only non-full zone")
	-- bias works
	local g2 = AshGrid.new(3)
	local added2 = g2:regrow(rng, 800, { [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 1 })
	Harness.truthy(added2 > 750, "most picks succeed")
	Harness.eq(g2.zoneUnits[5] - Layout.zoneCount[5] * 3, added2, "bias to zone 5 only")
	Harness.eq(AshGrid.new("full"):regrow(rng, 50), 0, "a full island cannot grow")
	for i = 1, g.N do
		Harness.truthy(g.levels[i] <= MAX)
	end
	-- emptier zones get more growth than a fuller zone
	local g3 = AshGrid.new(6)
	for _, j in Layout.zoneCells[3] do
		g3:set(j, 1)
	end
	g3:regrow(rng, 1000)
	local grow3 = g3.zoneUnits[3] - Layout.zoneCount[3]
	local grow2 = g3.zoneUnits[2] - Layout.zoneCount[2] * 6
	Harness.truthy(grow3 > grow2 * 2, `emptier zone grows faster ({grow3} vs {grow2})`)
end)

Harness.test("rain: +1..2 units across the island", function()
	local g = AshGrid.new("empty")
	local added = g:rain(Rng.new(10), 1)
	Harness.eq(added, g.totalUnits)
	for i = 1, g.N do
		Harness.truthy(g.levels[i] >= 1 and g.levels[i] <= 2)
	end
	local g2 = AshGrid.new("empty")
	local part = g2:rain(Rng.new(11), 0.3)
	Harness.truthy(
		part > 0.3 * g2.N * 1.2 and part < 0.3 * g2.N * 1.8,
		"about 30% of cells, 1.5 units each"
	)
	Harness.eq(AshGrid.new("full"):rain(Rng.new(1), 1), 0)
end)

-- ===== Network encoding =====

Harness.test("encode/decode roundtrip and validation", function()
	local g = AshGrid.new("full")
	local rng = Rng.new(12)
	g:rain(rng, 0.5)
	g:sweep(PX, PZ, 1, 0, { reach = 40, arcDeg = 360, power = 5 }, ALL_ZONES, 1e9, rng, 0)
	local s = g:encode()
	Harness.eq(#s, g.N)
	local c = AshGrid.new("empty")
	Harness.eq(c:decode(s), true)
	Harness.eq(c:encode(), s)
	Harness.eq(c.totalUnits, g.totalUnits)
	for _, z in Layout.zoneIds do
		Harness.eq(c.zoneUnits[z], g.zoneUnits[z])
	end
	Harness.eq(c:zoneClean(3), g:zoneClean(3))
	-- bad snapshots change nothing
	Harness.eq(c:decode("123"), false)
	Harness.eq(c:decode(string.rep("x", g.N)), false)
	Harness.eq(c:decode(string.rep(":", g.N)), false)
	Harness.eq(c:encode(), s)
	local zero = string.rep("0", g.N)
	Harness.eq(string.sub(AshGrid.new("empty"):encode(), 1, 5), "00000")
	Harness.eq(AshGrid.new("full"):encode(), string.rep(tostring(MAX), g.N))
	Harness.eq(c:decode(zero), true)
	Harness.near(c:totalClean(), 1)
end)

Harness.test("dirty tracking batches changes into one flat delta", function()
	local server = AshGrid.new("full")
	local client = AshGrid.new("full")
	Harness.eq(#server:takeDirty(), 0)
	server:set(7, 3)
	server:set(7, 2) -- same cell twice -> one entry, latest level
	server:remove(9, 4)
	server:add(9, 0) -- no change
	server:set(11, MAX) -- already max: no change
	local flat = server:takeDirty()
	Harness.eq(#flat, 4)
	Harness.eq(flat[1], 7)
	Harness.eq(flat[2], 2)
	Harness.eq(flat[3], 9)
	Harness.eq(flat[4], MAX - 4)
	Harness.eq(#server:takeDirty(), 0, "cleared by take")
	Harness.eq(client:applyDelta(flat), 2)
	Harness.eq(client:get(7), 2)
	Harness.eq(client:get(9), MAX - 4)
	-- a cell that goes back to its old value is still reported once (level, not a diff)
	server:set(7, 5)
	server:set(7, 2)
	Harness.eq(#server:takeDirty(), 2)
end)

Harness.test("applyDelta skips nonsense and mirrors a busy server", function()
	local c = AshGrid.new("full")
	local bad: { number } = { 0, 3, c.N + 1, 3, 1.5, 3, 5, 0 / 0, 6, 999, 7, -4, 8 }
	Harness.eq(c:applyDelta(bad), 2, "only the pairs for idx 6 and 7 are valid")
	Harness.eq(c:get(6), MAX, "clamped to max")
	Harness.eq(c:get(7), 0, "clamped to zero")
	Harness.eq(c:get(5), MAX, "nan level ignored")
	-- server -> client mirror stays identical through many operations
	local server = AshGrid.new("full")
	local mirror = AshGrid.new("empty")
	mirror:decode(server:encode())
	local rng = Rng.new(13)
	for round = 1, 60 do
		server:sweep(
			rng:range(-150, 150),
			rng:range(-200, -30),
			rng:range(-1, 1),
			rng:range(-1, 1),
			{ reach = 14, arcDeg = 100, power = 2.5 },
			ALL_ZONES,
			1e9,
			rng,
			0.1
		)
		server:regrow(rng, 5)
		if round % 20 == 0 then
			server:rain(rng, 0.2)
		end
		mirror:applyDelta(server:takeDirty())
		Harness.eq(mirror:encode(), server:encode(), `round {round}`)
	end
end)

Harness.test("clean fractions", function()
	local g = AshGrid.new("full")
	Harness.near(g:zoneClean(4), 0)
	for _, j in Layout.zoneCells[4] do
		g:remove(j, MAX)
	end
	Harness.near(g:zoneClean(4), 1)
	Harness.near(g:zoneClean(3), 0)
	Harness.near(g:totalClean(), Layout.zoneCount[4] / Layout.N, 1e-9)
	for _, j in Layout.zoneCells[3] do
		g:remove(j, MAX / 3) -- 3 of 9 units
	end
	Harness.near(g:zoneClean(3), 1 / 3, 1e-9)
	Harness.eq(g:zoneClean(99), 1)
end)

-- ===== Speed =====

Harness.test("perf: 100000 sweeps", function()
	local g = AshGrid.new("full")
	local rng = Rng.new(14)
	local tool = { reach = 12, arcDeg = 90, power = 1.5 }
	local t0 = os.clock()
	local removed = 0
	for n = 1, 100000 do
		local ang = rng:range(0, 2 * math.pi)
		local r = rng:range(INNER + 5, OUTER - 5)
		local res = g:sweep(
			r * math.cos(ang),
			r * math.sin(ang),
			math.cos(ang + 1),
			math.sin(ang + 1),
			tool,
			ALL_ZONES,
			30,
			rng,
			0.05,
			ZONE_VALUES
		)
		removed += res.removedUnits
		if n % 20 == 0 then
			g:regrow(rng, 120)
		end
		if n % 500 == 0 then
			g:takeDirty()
		end
	end
	local dt = os.clock() - t0
	print(`       100000 sweeps in {string.format("%.2f", dt)} s ({removed} units)`)
	Harness.truthy(dt < 6, `took {dt} s`)
end)
