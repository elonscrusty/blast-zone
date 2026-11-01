--!strict
local Harness = require("./harness")
local AshShape = require("../src/shared/Client/AshShape")
local AshChunks = require("../src/shared/Client/AshChunks")
local CullLogic = require("../src/shared/Client/CullLogic")
local Config = require("../src/shared/Config")
local Layout = require("../src/shared/Ash/Layout")

local L = Layout
local MAX = Config.World.maxUnitsPerCell
local CS = Config.World.cellSize
local DIR = AshShape.dirTable(L.N, L.cellOf, L.cx, L.cz, CS)
local STRIDE = AshShape.STRIDE

-- Tiny deterministic generator for test fields (no global rng state).
local function lcg(seed: number): () -> number
	local s = seed
	return function(): number
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

local function randomLevels(seed: number, emptyShare: number): { number }
	local rnd = lcg(seed)
	local levels: { number } = table.create(L.N, 0)
	for i = 1, L.N do
		if rnd() >= emptyShare then
			levels[i] = 1 + math.floor(rnd() * MAX)
		end
	end
	return levels
end

-- Cells with all 8 neighbours, spread over the island.
local function interiorCells(count: number): { number }
	local out: { number } = {}
	local step = math.max(1, math.floor(L.N / (count * 3)))
	for i = 1, L.N, step do
		local ok = true
		for s = 1, 8 do
			if DIR[(i - 1) * 8 + s] == 0 then
				ok = false
			end
		end
		if ok then
			table.insert(out, i)
			if #out >= count then
				break
			end
		end
	end
	return out
end

local INTERIOR = interiorCells(120)

local function piecesOf(levels: { number }, i: number, golden: boolean?): ({ number }, number)
	local out: { number } = {}
	local par = AshShape.parity(L.cx[i], L.cz[i], CS)
	local n = AshShape.pieces(out, i, levels, DIR, L.cx[i], L.cz[i], CS, MAX, par, golden == true)
	return out, n
end

-- Highest piece (by top) of cells i and its neighbours covering world point (px, pz):
-- returns its level (0 when nothing covers it) and its top.
local function renderedAt(levels: { number }, i: number, px: number, pz: number): (number, number)
	local bestTop, bestLevel = -1, 0
	local list = { i }
	for s = 1, 8 do
		local j = DIR[(i - 1) * 8 + s]
		if j ~= 0 then
			table.insert(list, j)
		end
	end
	for _, j in list do
		local out, n = piecesOf(levels, j)
		for k = 0, n - 1 do
			if AshShape.insidePiece(out, k, px, pz) then
				local top = out[k * STRIDE + 6]
				if top > bestTop then
					bestTop, bestLevel = top, out[k * STRIDE + 7]
				end
			end
		end
	end
	return bestLevel, bestTop
end

Harness.test("ash layer: direction table matches Layout.neighbours", function()
	for _, i in { 1, 2, math.floor(L.N / 2), L.N } do
		local set: { [number]: boolean } = {}
		for _, j in L.neighbours(i) do
			set[j] = true
		end
		local count = 0
		for s = 1, 8 do
			local j = DIR[(i - 1) * 8 + s]
			if j ~= 0 then
				count += 1
				Harness.truthy(set[j], "a real neighbour")
				Harness.near(L.cx[j] - L.cx[i], AshShape.DX[s] * CS, 1e-9)
				Harness.near(L.cz[j] - L.cz[i], AshShape.DZ[s] * CS, 1e-9)
			end
		end
		Harness.eq(count, #L.neighbours(i))
	end
	for s = 1, 8 do
		Harness.eq(AshShape.slot(AshShape.DX[s], AshShape.DZ[s]), s)
	end
	Harness.truthy(#INTERIOR >= 60, "enough interior cells to test")
end)

Harness.test(
	"ash layer: thickness is 0 when empty, rises with level, stays under the old slab",
	function()
		Harness.eq(AshShape.thickness(0, MAX), 0)
		Harness.eq(AshShape.thickness(-2, MAX), 0)
		Harness.near(AshShape.thickness(1, MAX), AshShape.T_MIN)
		Harness.near(AshShape.thickness(MAX, MAX), AshShape.T_FULL)
		Harness.eq(AshShape.thickness(MAX + 4, MAX), AshShape.thickness(MAX, MAX), "clamps")
		for level = 1, MAX do
			local t = AshShape.thickness(level, MAX)
			if level > 1 then
				-- carve depth is monotonic: every unit swept makes the layer visibly thinner
				Harness.truthy(
					t - AshShape.thickness(level - 1, MAX) > 0.1,
					"a visible step per level"
				)
			end
			-- lava discs (Vfx) sit on CullLogic.slabHeight: the layer (with every lift) stays below it
			Harness.truthy(
				t + AshShape.PARITY + AshShape.GOLD_LIFT <= CullLogic.slabHeight(level) + 1e-9,
				"under the old slab"
			)
		end
		Harness.truthy(AshShape.maxTop(MAX) <= CullLogic.slabHeight(MAX))
	end
)

Harness.test("ash layer: outer level follows marching squares", function()
	-- full field: full
	Harness.eq(AshShape.outerLevel(9, 9, 9, 9), 9)
	-- a swept corner keeps a fillet when the other 3 hold ash
	Harness.eq(AshShape.outerLevel(0, 9, 9, 9), 9)
	Harness.eq(AshShape.outerLevel(0, 9, 9, 0), 0, "two diagonal cells stay apart")
	Harness.eq(AshShape.outerLevel(0, 9, 0, 9), 0)
	-- a lone cell's corner is chamfered off
	Harness.eq(AshShape.outerLevel(9, 0, 0, 0), 0)
	Harness.eq(AshShape.outerLevel(9, 0, 0, 9), 0, "a diagonal pair does not join")
	-- along a straight edge the corner stays full
	Harness.eq(AshShape.outerLevel(9, 9, 0, 0), 9)
	Harness.eq(AshShape.outerLevel(9, 0, 9, 0), 9)
	-- level steps: a corner between a full cell and scraped ones steps down to the higher of them
	Harness.eq(AshShape.outerLevel(9, 6, 3, 3), 6)
	Harness.eq(AshShape.outerLevel(3, 9, 9, 9), 9, "a scraped dip gets filleted by the full layer")
	local rnd = lcg(5)
	for _ = 1, 2000 do
		local a, e, f, g =
			math.floor(rnd() * 10),
			math.floor(rnd() * 10),
			math.floor(rnd() * 10),
			math.floor(rnd() * 10)
		local o = AshShape.outerLevel(a, e, f, g)
		Harness.eq(o, AshShape.outerLevel(a, f, e, g), "symmetric in the two edge neighbours")
		Harness.truthy(o >= 0 and o <= math.max(a, e, f, g))
		Harness.truthy(o >= math.min(a, e, f, g))
		-- raising any cell never lowers the corner (no holes appear when ash regrows)
		Harness.truthy(AshShape.outerLevel(math.min(a + 1, 9), e, f, g) >= o)
		Harness.truthy(AshShape.outerLevel(a, e, f, math.min(g + 1, 9)) >= o)
	end
end)

Harness.test("ash layer: a full cell is ONE block slightly bigger than the cell", function()
	local full: { number } = table.create(L.N, MAX)
	for _, i in INTERIOR do
		local out, n = piecesOf(full, i)
		Harness.eq(n, 1)
		Harness.eq(out[1], AshShape.KIND_BLOCK)
		Harness.near(out[4], CS + 2 * AshShape.OVERLAP, 1e-9)
		Harness.near(out[5], CS + 2 * AshShape.OVERLAP, 1e-9)
	end
end)

Harness.test("ash layer: a full layer has no gaps, edges and corners included", function()
	local full: { number } = table.create(L.N, MAX)
	for _, i in INTERIOR do
		local x, z = L.cx[i], L.cz[i]
		local h = CS / 2
		for _, ox in { -h, -h / 2, 0, h / 2, h } do
			for _, oz in { -h, -h / 2, 0, h / 2, h } do
				local level = renderedAt(full, i, x + ox, z + oz)
				Harness.eq(level, MAX, "covered")
			end
		end
	end
end)

Harness.test("ash layer: neighbours overlap but never share a top (no z-fighting)", function()
	local full: { number } = table.create(L.N, MAX)
	for _, i in INTERIOR do
		local out = piecesOf(full, i)
		for _, s in { 2, 4, 5, 7 } do -- edge neighbours
			local j = DIR[(i - 1) * 8 + s]
			local other = piecesOf(full, j)
			Harness.truthy(math.abs(out[6] - other[6]) >= AshShape.PARITY - 1e-9, "tops differ")
			-- the two blocks overlap along the shared edge
			local gap = math.abs(L.cx[i] - L.cx[j]) + math.abs(L.cz[i] - L.cz[j])
			Harness.truthy((out[4] + other[4]) / 2 > gap, "footprints overlap")
		end
	end
end)

Harness.test(
	"ash layer: pieces match the marching-squares rule everywhere inside a cell",
	function()
		for _, seed in { 3, 11, 29 } do
			for _, emptyShare in { 0.15, 0.5, 0.8 } do
				local levels = randomLevels(seed + math.floor(emptyShare * 100), emptyShare)
				for _, i in INTERIOR do
					local x, z = L.cx[i], L.cz[i]
					-- sample points away from the cell edge and the diamond line (exact edges are the
					-- overlap's job, tested above)
					for _, ox in { -3.6, -2.7, -1.3, -0.4, 0.4, 1.3, 2.7, 3.6 } do
						for _, oz in { -3.6, -2.7, -1.3, -0.4, 0.4, 1.3, 2.7, 3.6 } do
							if math.abs(math.abs(ox) + math.abs(oz) - CS / 2) > 0.3 then
								local want = AshShape.levelInside(i, levels, DIR, MAX, CS, ox, oz)
								local got, top = renderedAt(levels, i, x + ox, z + oz)
								Harness.eq(got, want, `cell {i} at ({ox}, {oz})`)
								if want > 0 then
									Harness.truthy(top > 0 and top <= AshShape.maxTop(MAX) + 1e-9)
								end
							end
						end
					end
				end
			end
		end
	end
)

Harness.test("ash layer: a swept row is a clean straight stripe with pointed ends", function()
	local i = INTERIOR[#INTERIOR // 2]
	local levels: { number } = table.create(L.N, MAX)
	-- sweep i and its left/right neighbours (a 3-cell row)
	local left, right = DIR[(i - 1) * 8 + 4], DIR[(i - 1) * 8 + 5]
	levels[i], levels[left], levels[right] = 0, 0, 0
	local x, z = L.cx[i], L.cz[i]
	-- the middle cell is clean right across
	for _, ox in { -3.9, -2, 0, 2, 3.9 } do
		for _, oz in { -3.8, -2, 0, 2, 3.8 } do
			Harness.eq(renderedAt(levels, i, x + ox, z + oz), 0, "trench floor")
		end
	end
	-- the rows above and below stay full right up to the trench edge
	Harness.eq(renderedAt(levels, i, x, z + 4.3), MAX, "straight wall")
	Harness.eq(renderedAt(levels, i, x, z - 4.3), MAX, "straight wall")
	-- the far end of the stripe is chamfered: its outer corners keep a fillet of ash
	Harness.eq(renderedAt(levels, right, L.cx[right] + 3.7, L.cz[right] + 3.7), MAX, "fillet")
	Harness.eq(
		renderedAt(levels, right, L.cx[right], L.cz[right]),
		0,
		"the end cell's centre is clean"
	)
end)

Harness.test(
	"ash layer: a diagonal sweep is one connected stripe, not a chain of squares",
	function()
		local i = INTERIOR[#INTERIOR // 3]
		local levels: { number } = table.create(L.N, MAX)
		local j = DIR[(i - 1) * 8 + 8] -- (+1, +1)
		levels[i], levels[j] = 0, 0
		-- the shared corner between the two swept cells is clean ground
		local px, pz = L.cx[i] + CS / 2, L.cz[i] + CS / 2
		Harness.eq(renderedAt(levels, i, px - 0.2, pz - 0.2), 0, "corner open")
		Harness.eq(renderedAt(levels, i, px + 0.2, pz + 0.2), 0, "corner open")
		-- and the two unswept cells beside that corner are chamfered back from it
		Harness.eq(renderedAt(levels, i, px + 0.5, pz - 0.5), 0)
		Harness.eq(renderedAt(levels, i, px + 3, pz - 3), MAX, "their centres keep ash")
	end
)

Harness.test("ash layer: part-swept cells are thinner and the step is chamfered too", function()
	local i = INTERIOR[#INTERIOR // 4]
	local levels: { number } = table.create(L.N, MAX)
	levels[i] = 4
	local out, n = piecesOf(levels, i)
	-- a dip in a full layer: its corners are filleted up to the full level by wedges
	local wedges, lowTop = 0, math.huge
	for k = 0, n - 1 do
		if out[k * STRIDE + 1] == AshShape.KIND_WEDGE then
			wedges += 1
			Harness.eq(out[k * STRIDE + 7], MAX)
		else
			lowTop = math.min(lowTop, out[k * STRIDE + 6])
		end
	end
	Harness.eq(wedges, 4)
	Harness.truthy(lowTop < AshShape.thickness(MAX, MAX), "the dip is lower than the layer")
	Harness.truthy(lowTop > AshShape.thickness(3, MAX), "...but still holds level 4")
end)

Harness.test("ash layer: pieces are sane (sizes, bounds, determinism, count cap)", function()
	local levels = randomLevels(77, 0.4)
	for i = 1, L.N, 3 do
		local gold = AshShape.hash01(i, 99) < 0.05
		local out, n = piecesOf(levels, i, gold)
		local out2, n2 = piecesOf(levels, i, gold)
		Harness.eq(n, n2)
		Harness.truthy(n <= AshShape.MAX_PIECES, "piece cap")
		for k = 0, n * STRIDE - 1 do
			Harness.eq(out[k + 1], out2[k + 1], "deterministic")
		end
		for k = 0, n - 1 do
			local o = k * STRIDE
			local kind, x, z, a, b, top =
				out[o + 1], out[o + 2], out[o + 3], out[o + 4], out[o + 5], out[o + 6]
			Harness.truthy(top > 0, "no zero or negative heights")
			Harness.truthy(top <= AshShape.maxTop(MAX) + 1e-9)
			local reach: number
			if kind == AshShape.KIND_WEDGE then
				Harness.truthy(math.abs(a) == 1 and math.abs(b) == 1, "wedge directions")
				Harness.truthy(out[o + 8] > 0 and out[o + 8] < CS, "wedge leg")
				reach = math.max(math.abs(x - L.cx[i]), math.abs(z - L.cz[i]))
			else
				Harness.truthy(a > 0 and b > 0, "no negative sizes")
				reach = math.max(math.abs(x - L.cx[i]) + a / 2, math.abs(z - L.cz[i]) + b / 2)
				if kind == AshShape.KIND_DIAMOND then
					reach = a / math.sqrt(2)
				end
			end
			Harness.truthy(reach <= CS / 2 + AshShape.OVERLAP + 1e-9, "stays in its cell + overlap")
		end
		if levels[i] == 0 then
			for k = 0, n - 1 do
				Harness.eq(
					out[k * STRIDE + 1],
					AshShape.KIND_WEDGE,
					"a swept cell only keeps fillets"
				)
			end
		end
	end
	local sigA = AshShape.signature(5, levels, DIR, MAX, false)
	Harness.eq(sigA, AshShape.signature(5, levels, DIR, MAX, false))
	Harness.truthy(sigA ~= AshShape.signature(5, levels, DIR, MAX, true), "gold changes it")
	local j = DIR[4 * 8 + 5]
	if j ~= 0 then
		local keep = levels[j]
		levels[j] = (keep + 1) % (MAX + 1)
		Harness.truthy(
			sigA ~= AshShape.signature(5, levels, DIR, MAX, false),
			"a neighbour changes it"
		)
		levels[j] = keep
	end
end)

Harness.test("ash layer: golden cells stand a hair above the layer", function()
	local full: { number } = table.create(L.N, MAX)
	local i = INTERIOR[1]
	local plain = piecesOf(full, i, false)
	local gold = piecesOf(full, i, true)
	Harness.near(gold[6] - plain[6], AshShape.GOLD_LIFT, 1e-9)
end)

Harness.test("ash layer: wedge frame maps the WedgePart triangle onto the asked corner", function()
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local cx, cz, leg = 10, -6, 4
			local mx, mz, upY, yx, zz = AshShape.wedgeFrame(cx, cz, sx, sz, leg)
			Harness.eq(math.abs(upY), 1)
			-- proper rotation: X = Y x Z
			Harness.eq(upY, -(yx * zz))
			-- the part-space right angle (y = -leg/2, z = +leg/2) lands on the corner
			Harness.near(mx + yx * (-leg / 2), cx, 1e-9)
			Harness.near(mz + zz * (leg / 2), cz, 1e-9)
			-- the two other triangle corners lie along the legs
			Harness.near(mx + yx * (leg / 2), cx + sx * leg, 1e-9)
			Harness.near(mz + zz * (-leg / 2), cz + sz * leg, 1e-9)
			Harness.truthy(AshShape.insideWedge(cx + sx * 0.5, cz + sz * 0.5, cx, cz, sx, sz, leg))
			Harness.truthy(
				not AshShape.insideWedge(cx + sx * 3.5, cz + sz * 3.5, cx, cz, sx, sz, leg)
			)
			Harness.truthy(
				not AshShape.insideWedge(cx - sx * 0.5, cz + sz * 0.5, cx, cz, sx, sz, leg)
			)
		end
	end
end)

Harness.test(
	"ash layer: colour is soft, blends across zones and has no per-cell speckle",
	function()
		local rings: { AshShape.Ring } = {
			{ inner = 100, outer = 200, r = 180, g = 180, b = 180 },
			{ inner = 50, outer = 100, r = 100, g = 90, b = 90 },
		}
		local maxStep = 0
		for k = 0, 400 do
			local x = 52 + k * 0.37 * 2
			local r1 = AshShape.baseColour(x, 7, rings)
			local r2 = AshShape.baseColour(x + CS, 7, rings)
			maxStep = math.max(maxStep, math.abs(r1 - r2))
			local r, g, b = AshShape.baseColour(x, 7, rings)
			for _, c in { r, g, b } do
				Harness.truthy(c >= 0 and c <= 255 and c == math.floor(c))
			end
		end
		-- one cell over, the colour moves only a little (no visible grid), even across a zone border
		Harness.truthy(maxStep <= 30, `gentle steps ({maxStep})`)
		local inside = AshShape.baseColour(150, 0, rings)
		local deep = AshShape.baseColour(75, 0, rings)
		Harness.truthy(
			math.abs(inside - 180) <= 10 and math.abs(deep - 100) <= 6,
			"zone tints kept"
		)
		local border = AshShape.baseColour(100, 0, rings)
		Harness.truthy(border > 110 and border < 170, "blended at the border")
		-- noise: deterministic, bounded, smooth
		for k = 1, 300 do
			local x, z = k * 3.1, k * -1.7
			local v = AshShape.noise(x, z)
			Harness.eq(v, AshShape.noise(x, z))
			Harness.truthy(v >= -1 and v <= 1)
			Harness.truthy(math.abs(AshShape.noise(x + 1, z) - v) < 0.2, "smooth")
		end
		-- thinner layer is a little darker, never brighter
		local fr = AshShape.depthShade(180, 170, 160, MAX, MAX)
		local lr = AshShape.depthShade(180, 170, 160, 1, MAX)
		Harness.eq(fr, 180)
		Harness.truthy(lr < fr and lr >= 180 * (1 - AshShape.DEPTH_DARK) - 1)
	end
)

Harness.test("ash layer: embers only on full-ish cells in the deep zones, a few of them", function()
	local some, total = 0, 0
	for i = 1, L.N do
		Harness.eq(AshShape.hasEmber(i, 1, MAX), false)
		Harness.eq(AshShape.hasEmber(i, 3, MAX), false)
		Harness.eq(AshShape.hasEmber(i, 5, AshShape.EMBER_LEVEL - 1), false)
		total += 1
		if AshShape.hasEmber(i, 5, MAX) then
			some += 1
			local dx, dz, d = AshShape.emberSpot(i, CS)
			Harness.near(math.sqrt(dx * dx + dz * dz), d, 1e-9)
			Harness.truthy(math.abs(dx) + math.abs(dz) < CS / 2, "on the cell's own level")
		end
	end
	local share = some / total
	Harness.truthy(share > 0.15 and share < 0.45, "a few, not all")
end)

-- ===== chunks =====

local CH = AshChunks.build(L, 4)

Harness.test("ash chunks: every cell is in exactly one chunk, inside its square", function()
	local seen: { [number]: number } = {}
	for c = 1, CH.count do
		for _, i in CH.cells[c] do
			Harness.eq(seen[i], nil, "once")
			seen[i] = c
			Harness.eq(CH.chunkOf[i], c)
			Harness.truthy(math.abs(L.cx[i] - CH.cx[c]) < CH.cellSize / 2)
			Harness.truthy(math.abs(L.cz[i] - CH.cz[c]) < CH.cellSize / 2)
		end
		Harness.truthy(#CH.cells[c] >= 1 and #CH.cells[c] <= 16)
	end
	for i = 1, L.N do
		Harness.truthy(seen[i] ~= nil)
	end
	Harness.near(CH.cellSize, CS * 4, 1e-9)
end)

Harness.test("ash chunks: far tiles cover exactly the chunk's cells", function()
	for c = 1, CH.count do
		local runs = CH.runs[c]
		Harness.truthy(#runs % 4 == 0 and #runs >= 4)
		local area = 0
		for k = 1, #runs, 4 do
			Harness.truthy(runs[k + 2] > 0 and runs[k + 3] > 0)
			area += runs[k + 2] * runs[k + 3]
		end
		Harness.near(area, #CH.cells[c] * CS * CS, 1e-6, "no overlap, no spill")
		for _, i in CH.cells[c] do
			local hits = 0
			for k = 1, #runs, 4 do
				if
					math.abs(L.cx[i] - runs[k]) < runs[k + 2] / 2
					and math.abs(L.cz[i] - runs[k + 1]) < runs[k + 3] / 2
				then
					hits += 1
				end
			end
			Harness.eq(hits, 1, "each cell under one block")
		end
	end
	-- most chunks are one block
	local single = 0
	for c = 1, CH.count do
		if #CH.runs[c] == 4 then
			single += 1
		end
	end
	Harness.truthy(single / CH.count > 0.75, "cheap")
end)

Harness.test("ash chunks: radius query and far look", function()
	local x, z = L.cx[1], L.cz[1]
	local list = CH.cellsInRadius(x, z, 120)
	Harness.truthy(#list > 0)
	for _, c in list do
		local dx, dz = CH.cx[c] - x, CH.cz[c] - z
		Harness.truthy(dx * dx + dz * dz <= 120 * 120)
	end
	for c = 1, CH.count do
		for k = 1, 4 do
			local j = c + k
			if
				j <= CH.count
				and math.abs(CH.cx[j] - CH.cx[c]) + math.abs(CH.cz[j] - CH.cz[c]) == CH.cellSize
			then
				Harness.truthy(CH.parity[j] ~= CH.parity[c], "edge neighbours differ")
			end
		end
	end
	local show, level, lean = AshShape.farLook(16, 16, 16 * MAX, MAX)
	Harness.truthy(show and level == MAX and lean == 0)
	show = AshShape.farLook(1, 16, 9, MAX)
	Harness.eq(show, false, "a nearly clean chunk shows the ground")
	show = AshShape.farLook(0, 16, 0, MAX)
	Harness.eq(show, false)
	local _, l2, lean2 = AshShape.farLook(8, 16, 8 * 3, MAX)
	Harness.eq(l2, 3)
	Harness.truthy(lean2 > 0.3 and lean2 < 0.6, "half swept leans toward the ground")
end)

Harness.test("ash layer: part budget per cell (fresh layer 1, scraped patchwork < 1.5)", function()
	local buf: { number } = {}
	local function cost(levels: { number }): number
		local parts, cells = 0, 0
		for _, i in L.cellsInRadius(0, L.outerRadius * 0.6, 124) do
			cells += 1
			parts += AshShape.pieces(buf, i, levels, DIR, L.cx[i], L.cz[i], CS, MAX, 0, false)
		end
		return parts / math.max(cells, 1)
	end
	local full: { number } = table.create(L.N, MAX)
	Harness.near(cost(full), 1, 0.02, "one block per full cell")
	-- 600 random sweep fans, half to the ground, half part-way
	local rnd = lcg(17)
	local scraped: { number } = table.create(L.N, MAX)
	for _ = 1, 600 do
		local i = 1 + math.floor(rnd() * L.N)
		local depth = if rnd() < 0.5 then MAX else math.floor(rnd() * MAX)
		for _, j in L.cellsInRadius(L.cx[i], L.cz[i], 8 + rnd() * 12) do
			scraped[j] = math.max(0, scraped[j] - depth)
		end
	end
	local c = cost(scraped)
	Harness.truthy(c < 1.5, `scraped: {c} Parts per cell`)
end)
