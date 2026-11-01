--!strict
local Harness = require("./harness")
local CullLogic = require("../src/shared/Client/CullLogic")
local Config = require("../src/shared/Config")
local Layout = require("../src/shared/Ash/Layout")

local L = Layout
local MAX = Config.World.maxUnitsPerCell

local function dist(i: number, x: number, z: number): number
	local dx, dz = L.cx[i] - x, L.cz[i] - z
	return math.sqrt(dx * dx + dz * dz)
end

Harness.test(
	"range: first update enters exactly the cells within the radius, nearest first",
	function()
		local range = CullLogic.newRange()
		local x, z = 0, -165
		local entered, left = CullLogic.update(L, range, x, z, 60, 20, 4)
		Harness.eq(#left, 0)
		Harness.truthy(#entered > 20, "some cells")
		Harness.eq(range.count, #entered)
		local expected = L.cellsInRadius(x, z, 60)
		Harness.eq(#entered, #expected)
		local last = -1.0
		for _, i in entered do
			local d = dist(i, x, z)
			Harness.truthy(d <= 60 + 1e-6, "within radius")
			Harness.truthy(d >= last - 1e-9, "sorted nearest first")
			last = d
			Harness.eq(range.active[i], true)
		end
	end
)

Harness.test("range: small moves do nothing", function()
	local range = CullLogic.newRange()
	CullLogic.update(L, range, 0, -165, 60, 20, 4)
	local entered, left = CullLogic.update(L, range, 1.5, -165, 60, 20, 4)
	Harness.eq(#entered, 0)
	Harness.eq(#left, 0)
end)

Harness.test(
	"range: walking enters ahead, leaves behind (with margin), count stays right",
	function()
		local range = CullLogic.newRange()
		CullLogic.update(L, range, 0, -165, 60, 20, 4)
		local entered, left = CullLogic.update(L, range, 40, -165, 60, 20, 4)
		Harness.truthy(#entered > 0, "new cells ahead")
		Harness.truthy(#left > 0, "old cells behind")
		for _, i in left do
			Harness.truthy(dist(i, 40, -165) > 80, "left only beyond radius + margin")
			Harness.eq(range.active[i], nil)
		end
		local n = 0
		for i in range.active do
			n += 1
			Harness.truthy(
				dist(i, 40, -165) <= 80 + 1e-6,
				"active cells are within radius + margin"
			)
		end
		Harness.eq(n, range.count)
		-- every cell within the radius is active
		for _, i in L.cellsInRadius(40, -165, 60) do
			Harness.eq(range.active[i], true)
		end
	end
)

Harness.test("range: hysteresis stops edge flicker", function()
	local range = CullLogic.newRange()
	CullLogic.update(L, range, 0, -165, 60, 20, 1)
	local total = 0
	for step = 1, 20 do
		local x = if step % 2 == 0 then 0 else 6 -- wobble 6 studs
		local e, l = CullLogic.update(L, range, x, -165, 60, 20, 1)
		total += #l
		if step > 1 then
			Harness.eq(#l, 0, "no leaving while wobbling inside the margin")
			Harness.truthy(#e <= #L.cellsInRadius(6, -165, 60), "bounded")
		end
	end
	Harness.eq(total, 0)
end)

Harness.test("range: teleport swaps the whole set", function()
	local range = CullLogic.newRange()
	CullLogic.update(L, range, 0, -165, 40, 10, 4)
	local before = range.count
	local entered, left = CullLogic.update(L, range, 0, 165, 40, 10, 4)
	Harness.eq(#left, before)
	Harness.truthy(#entered > 0)
	Harness.eq(range.count, #entered)
end)

Harness.test("range: NaN centre is ignored", function()
	local range = CullLogic.newRange()
	local e, l = CullLogic.update(L, range, 0 / 0, 0, 40, 10, 4)
	Harness.eq(#e + #l, 0)
	Harness.eq(range.hasCentre, false)
end)

Harness.test("queue: FIFO, de-duplicated, cap per drain", function()
	local q = CullLogic.newQueue()
	for i = 1, 10 do
		q.push(i)
	end
	q.push(3)
	q.push(7)
	Harness.eq(q.size(), 10)
	local got: { number } = {}
	local n = CullLogic.drain(q, 4, function(i)
		table.insert(got, i)
		return nil
	end)
	Harness.eq(n, 4)
	Harness.eq(table.concat(got, ","), "1,2,3,4")
	Harness.eq(q.size(), 6)
	q.push(2) -- popped earlier, may be queued again
	Harness.eq(q.size(), 7)
	n = CullLogic.drain(q, 600, function(i)
		table.insert(got, i)
		return nil
	end)
	Harness.eq(n, 7)
	Harness.eq(got[#got], 2)
	Harness.eq(q.size(), 0)
	Harness.eq(q.pop(), nil)
	Harness.eq(
		CullLogic.drain(q, 5, function()
			return nil
		end),
		0
	)
end)

Harness.test("queue: 5000 pushes drain at 600 per frame", function()
	local q = CullLogic.newQueue()
	for i = 1, 5000 do
		q.push(i)
	end
	local frames, total = 0, 0
	while q.size() > 0 do
		frames += 1
		local n = CullLogic.drain(q, 600, function()
			return nil
		end)
		Harness.truthy(n <= 600)
		total += n
	end
	Harness.eq(total, 5000)
	Harness.eq(frames, 9)
end)

Harness.test("queue: fn returning false stops the drain (time budget)", function()
	local q = CullLogic.newQueue()
	for i = 1, 20 do
		q.push(i)
	end
	local seen = 0
	local n = CullLogic.drain(q, 600, function()
		seen += 1
		return seen < 5
	end)
	Harness.eq(n, 5)
	Harness.eq(q.size(), 15)
	q.clear()
	Harness.eq(q.size(), 0)
	q.push(1)
	Harness.eq(q.pop(), 1)
end)

Harness.test("snapshot: decode good, reject bad", function()
	local lv = CullLogic.decodeSnapshot("0123456789", 10, 9)
	Harness.truthy(lv ~= nil)
	local t = lv :: { number }
	Harness.eq(t[1], 0)
	Harness.eq(t[10], 9)
	Harness.eq(CullLogic.decodeSnapshot("012", 10, 9), nil, "wrong length")
	Harness.eq(CullLogic.decodeSnapshot("01234567:9", 10, 9), nil, "char out of range")
	Harness.eq(CullLogic.decodeSnapshot("0123456 89", 10, 9), nil, "space")
	Harness.eq(CullLogic.decodeSnapshot(nil, 10, 9), nil)
	Harness.eq(CullLogic.decodeSnapshot(12, 10, 9), nil)
end)

Harness.test("delta: applies pairs, reports changes, skips junk", function()
	local levels = { 9, 9, 9, 9 }
	local log: { string } = {}
	local applied = CullLogic.applyDelta(
		levels,
		{ 1, 0, 2, 9, 3, 4.7, 99, 1, 0, 5, 4, 0 / 0, "x", 1, 4 },
		4,
		MAX,
		function(i, old, new)
			table.insert(log, `{i}:{old}>{new}`)
		end
	)
	Harness.eq(levels[1], 0)
	Harness.eq(levels[2], 9)
	Harness.eq(levels[3], 4)
	Harness.eq(levels[4], 9)
	Harness.eq(table.concat(log, " "), "1:9>0 3:9>4")
	Harness.eq(applied, 3, "1, 2 and 3 applied (2 unchanged but valid)")
	Harness.eq(CullLogic.applyDelta(levels, "nope", 4, MAX, nil), 0)
	-- level clamps to the max
	CullLogic.applyDelta(levels, { 1, 50 }, 4, MAX, nil)
	Harness.eq(levels[1], MAX)
	-- odd trailing entry is ignored
	Harness.eq(CullLogic.applyDelta(levels, { 2, 3, 4 }, 4, MAX, nil), 1)
	Harness.eq(levels[2], 3)
end)

Harness.test("looks: slab size and height", function()
	Harness.near(CullLogic.slabSize(8), 7.6)
	Harness.eq(CullLogic.slabHeight(0), 0)
	Harness.near(CullLogic.slabHeight(1), 0.43)
	Harness.near(CullLogic.slabHeight(9), 0.15 + 9 * 0.28)
	for level = 1, MAX do
		Harness.truthy(
			CullLogic.slabHeight(level) > CullLogic.slabHeight(level - 1),
			"taller with more ash"
		)
	end
end)

Harness.test("looks: variation is deterministic, in range, spread out", function()
	local sum, lo, hi = 0.0, 1.0, -1.0
	for i = 1, L.N do
		local v = CullLogic.variation(i)
		Harness.eq(v, CullLogic.variation(i))
		Harness.truthy(v >= -1 and v <= 1, "range")
		sum += v
		lo = math.min(lo, v)
		hi = math.max(hi, v)
	end
	Harness.truthy(math.abs(sum / L.N) < 0.1, "mean near zero")
	Harness.truthy(lo < -0.9 and hi > 0.9, "uses the whole range")
	Harness.truthy(CullLogic.variation(1) ~= CullLogic.variation(2))
end)

Harness.test("looks: hex helpers", function()
	local r, g, b = CullLogic.parseHex("#B8B2AA")
	Harness.eq(r, 0xB8)
	Harness.eq(g, 0xB2)
	Harness.eq(b, 0xAA)
	local br, bg, bb = CullLogic.parseHex("nonsense")
	Harness.eq(br, 128)
	Harness.eq(bg, 128)
	Harness.eq(bb, 128)
	local sr, sg, sb = CullLogic.shade("#808080", 0.5)
	Harness.eq(sr, 192)
	Harness.eq(sg, 192)
	Harness.eq(sb, 192)
	local wr = CullLogic.shade("#FFFFFF", 0.5)
	Harness.eq(wr, 255, "clamped")
	Harness.eq(CullLogic.mixHex("#000000", "#FFFFFF", 0.5), "#808080")
	Harness.eq(CullLogic.mixHex("#102030", "#102030", 0.7), "#102030")
	Harness.eq(CullLogic.mixHex("#000000", "#FFFFFF", 5), "#FFFFFF", "t clamps")
end)

local function fullLevels(value: number): { number }
	return table.create(L.N, value)
end
local ALL: { [number]: boolean } = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }

Harness.test("ashAhead: finds ash in front, ignores behind, respects level 0", function()
	local levels = fullLevels(0)
	local px, pz = 0, -165
	-- the cell right in front (3 studs north... facing -z)
	local front = L.cellOf(px, pz - 6)
	local behind = L.cellOf(px, pz + 6)
	Harness.truthy(front ~= nil and behind ~= nil)
	levels[behind :: number] = 5
	Harness.eq(CullLogic.ashAhead(L, levels, px, pz, 0, -1, 12, 80, ALL), false, "only behind")
	levels[front :: number] = 1
	Harness.eq(CullLogic.ashAhead(L, levels, px, pz, 0, -1, 12, 80, ALL), true)
	levels[front :: number] = 0
	Harness.eq(CullLogic.ashAhead(L, levels, px, pz, 0, -1, 12, 80, ALL), false)
end)

Harness.test("ashAhead: reach limits, zone filter, arc width", function()
	local levels = fullLevels(0)
	local px, pz = 0, -165
	local far = L.cellOf(px, pz - 20) :: number
	levels[far] = 9
	Harness.eq(CullLogic.ashAhead(L, levels, px, pz, 0, -1, 7, 80, ALL), false, "out of reach")
	Harness.eq(CullLogic.ashAhead(L, levels, px, pz, 0, -1, 24, 80, ALL), true, "in reach")
	local zoneOfFar = L.zone[far]
	local none: { [number]: boolean } = {}
	Harness.eq(CullLogic.ashAhead(L, levels, px, pz, 0, -1, 24, 80, none), false, "locked zone")
	local only: { [number]: boolean } = { [zoneOfFar] = true }
	Harness.eq(CullLogic.ashAhead(L, levels, px, pz, 0, -1, 24, 80, only), true)
	-- a cell off to the side is outside a narrow fan but inside a wide one
	local side = L.cellOf(px + 16, pz - 2) :: number
	local lv2 = fullLevels(0)
	lv2[side] = 3
	Harness.eq(CullLogic.ashAhead(L, lv2, px, pz, 0, -1, 24, 60, ALL), false, "narrow fan")
	Harness.eq(CullLogic.ashAhead(L, lv2, px, pz, 0, -1, 24, 360, ALL), true, "full circle")
end)

Harness.test("ashAhead: matches the server cone for a full island", function()
	local AshGrid = require("../src/shared/Ash/AshGrid")
	local grid = AshGrid.new("full")
	local px, pz = 0, -165
	for _, facing in { { 0, -1 }, { 1, 0 }, { 0.7, 0.7 }, { -1, 0.2 } } do
		local cone = grid:queryCone(px, pz, facing[1], facing[2], 13, 110)
		Harness.eq(
			CullLogic.ashAhead(L, grid.levels, px, pz, facing[1], facing[2], 13, 110, ALL),
			#cone > 0
		)
	end
	-- an empty island has no ash anywhere
	local empty = AshGrid.new("empty")
	Harness.eq(CullLogic.ashAhead(L, empty.levels, px, pz, 0, -1, 13, 110, ALL), false)
end)
