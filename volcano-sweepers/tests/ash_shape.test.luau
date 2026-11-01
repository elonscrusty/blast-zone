--!strict
local Harness = require("./harness")
local AshShape = require("../src/shared/Client/AshShape")
local CullLogic = require("../src/shared/Client/CullLogic")
local Config = require("../src/shared/Config")
local Layout = require("../src/shared/Ash/Layout")

local L = Layout
local MAX = Config.World.maxUnitsPerCell
local CS = Config.World.cellSize
local NB, NB_COUNT = AshShape.neighbourTable(L.N, L.neighbours)

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

-- An interior cell (all 8 neighbours exist).
local function interiorCell(): number
	for i = 1, L.N do
		if NB_COUNT[i] == 8 then
			return i
		end
	end
	error("no interior cell")
end

Harness.test("ash shape: neighbour table matches Layout.neighbours", function()
	for _, i in { 1, 2, math.floor(L.N / 2), L.N } do
		local list = L.neighbours(i)
		Harness.eq(NB_COUNT[i], #list)
		for k, j in list do
			Harness.eq(NB[(i - 1) * 8 + k], j)
		end
	end
	Harness.truthy(NB_COUNT[interiorCell()] == 8)
end)

Harness.test(
	"ash shape: level heights are 0 when empty, rise with level, leave room for jitter",
	function()
		Harness.eq(AshShape.levelHeight(0, MAX), 0)
		Harness.eq(AshShape.levelHeight(-3, MAX), 0)
		for level = 2, MAX do
			Harness.truthy(AshShape.levelHeight(level, MAX) > AshShape.levelHeight(level - 1, MAX))
		end
		local top = AshShape.levelHeight(MAX, MAX) * (1 + AshShape.JITTER_HEIGHT)
		Harness.truthy(top <= AshShape.maxPeak(MAX) + 1e-9, "jittered top fits under the peak cap")
		Harness.eq(AshShape.levelHeight(MAX + 5, MAX), AshShape.levelHeight(MAX, MAX), "clamps")
		Harness.near(AshShape.maxPeak(MAX), CullLogic.slabHeight(MAX))
	end
)

Harness.test("ash shape: deterministic, heights within [0, maxPeak], empty cells are 0", function()
	for _, seed in { 1, 7, 99 } do
		local levels = randomLevels(seed, 0.3)
		for i = 1, L.N do
			local h, r = AshShape.target(i, levels, NB, NB_COUNT, CS, MAX, false)
			local h2, r2 = AshShape.target(i, levels, NB, NB_COUNT, CS, MAX, false)
			Harness.eq(h, h2)
			Harness.eq(r, r2)
			Harness.truthy(h >= 0, "never negative")
			Harness.truthy(h <= AshShape.maxPeak(MAX) + 1e-9, "never above the max")
			if levels[i] == 0 then
				Harness.eq(h, 0, "empty cell hides")
				Harness.eq(r, 0)
			else
				Harness.truthy(h > 0, "a cell with ash shows")
				Harness.truthy(r >= CS * AshShape.RADIUS_EDGE - 1e-9)
				Harness.truthy(r <= CS * AshShape.RADIUS_FULL + 1e-9)
			end
		end
	end
end)

Harness.test("ash shape: a mound never pokes above the tallest old slab around it", function()
	-- Vfx keeps lava discs above CullLogic.slabHeight of the cells under them
	local levels = randomLevels(42, 0.2)
	for i = 1, L.N do
		local top = CullLogic.slabHeight(levels[i])
		for k = 1, NB_COUNT[i] do
			top = math.max(top, CullLogic.slabHeight(levels[NB[(i - 1) * 8 + k]]))
		end
		local h = AshShape.target(i, levels, NB, NB_COUNT, CS, MAX, false)
		Harness.truthy(h <= top + 1e-9, "under the tallest slab nearby")
	end
end)

Harness.test("ash shape: raising a neighbour never lowers a mound (monotonic blend)", function()
	local i = interiorCell()
	local levels: { number } = table.create(L.N, 0)
	levels[i] = 5
	local base = (i - 1) * 8
	local last = AshShape.target(i, levels, NB, NB_COUNT, CS, MAX, false)
	for k = 1, 8 do
		local j = NB[base + k]
		for level = 1, MAX do
			levels[j] = level
			local h = AshShape.target(i, levels, NB, NB_COUNT, CS, MAX, false)
			Harness.truthy(h >= last - 1e-12, "non-decreasing")
			last = h
		end
	end
	-- all neighbours at max now: the mound is taller than when alone
	levels = table.create(L.N, 0)
	levels[i] = 5
	local alone = AshShape.target(i, levels, NB, NB_COUNT, CS, MAX, false)
	Harness.truthy(last > alone, "full neighbours lift it")
end)

Harness.test("ash shape: blend stays between own and the neighbour average", function()
	local own = AshShape.levelHeight(4, MAX)
	local avg = AshShape.levelHeight(8, MAX)
	local h = AshShape.blend(own, avg * 8, 8)
	Harness.truthy(h > own and h < avg)
	Harness.near(AshShape.blend(own, 0, 0), own, 1e-12, "no neighbours: own")
	Harness.eq(AshShape.blend(0, avg * 8, 8), 0, "empty stays empty")
	-- a swept neighbour pulls the edge down (soft edge), but never below OWN_WEIGHT x own
	local edge = AshShape.blend(own, own * 7, 8)
	Harness.truthy(edge < own)
	Harness.truthy(AshShape.blend(own, 0, 8) >= own * AshShape.OWN_WEIGHT - 1e-12)
end)

Harness.test(
	"ash shape: footprint covers the corners when full, shrinks by swept ground",
	function()
		local full = AshShape.radius(CS, 8, 8)
		local lone = AshShape.radius(CS, 0, 8)
		local edge = AshShape.radius(CS, 8, 5)
		Harness.truthy(full > CS * math.sqrt(2) * 0.5, "reaches the corner between 4 cells")
		Harness.truthy(lone < full)
		Harness.truthy(lone >= CS * 0.5, "a lone mound still fills its cell")
		Harness.near(edge, CS * 0.5, 1e-9, "edge cells stay in their cell")
		for filled = 1, 8 do
			Harness.truthy(AshShape.radius(CS, filled, 8) >= AshShape.radius(CS, filled - 1, 8))
		end
	end
)

Harness.test("ash shape: jitter is deterministic and within its limits", function()
	local seenX: { [number]: boolean } = {}
	local seenYaw: { [number]: boolean } = {}
	local distinct = 0
	for i = 1, L.N do
		local ox, oz, yaw, fx, fz, hm, light = AshShape.jitter(i, false)
		local ox2, oz2, yaw2, fx2, fz2, hm2, light2 = AshShape.jitter(i, false)
		Harness.truthy(
			ox == ox2
				and oz == oz2
				and yaw == yaw2
				and fx == fx2
				and fz == fz2
				and hm == hm2
				and light == light2,
			"deterministic"
		)
		Harness.truthy(math.sqrt(ox * ox + oz * oz) <= AshShape.JITTER_POS + 1e-9, "offset")
		Harness.truthy(yaw >= 0 and yaw < math.pi + 1e-9, "yaw")
		Harness.truthy(math.abs(fx - 1) <= AshShape.JITTER_FOOT + 1e-9, "foot x")
		Harness.truthy(math.abs(fz - 1) <= AshShape.JITTER_FOOT + 1e-9, "foot z")
		Harness.truthy(math.abs(hm - 1) <= AshShape.JITTER_HEIGHT + 1e-9, "height")
		Harness.truthy(light >= -1 and light <= 1, "light")
		local key = math.floor(ox * 10)
		if not seenX[key] then
			seenX[key] = true
			distinct += 1
		end
		seenYaw[math.floor(yaw * 4)] = true
	end
	Harness.truthy(distinct >= 15, "offsets spread out")
	local yawBins = 0
	for _ in seenYaw do
		yawBins += 1
	end
	Harness.truthy(yawBins >= 4, "yaws spread out")
	-- hash spread: mean near 0.5
	local sum = 0
	for i = 1, 2000 do
		local v = AshShape.hash01(i, 1)
		Harness.truthy(v >= 0 and v < 1)
		sum += v
	end
	Harness.truthy(math.abs(sum / 2000 - 0.5) < 0.05, "hash is not lopsided")
end)

Harness.test("ash shape: golden cells are not moved, resized or lowered", function()
	local i = interiorCell()
	local ox, oz, _, fx, fz, hm, light = AshShape.jitter(i, true)
	Harness.eq(ox, 0)
	Harness.eq(oz, 0)
	Harness.eq(fx, 1)
	Harness.eq(fz, 1)
	Harness.eq(hm, 1)
	Harness.eq(light, 0)
	local levels: { number } = table.create(L.N, 0)
	levels[i] = 6 -- all neighbours swept
	local own = AshShape.levelHeight(6, MAX)
	local hg = AshShape.target(i, levels, NB, NB_COUNT, CS, MAX, true)
	local hp = AshShape.target(i, levels, NB, NB_COUNT, CS, MAX, false)
	Harness.near(hg, own, 1e-12, "gold keeps its own height")
	Harness.truthy(hp < hg, "plain ash relaxes next to swept ground")
	local full: { number } = table.create(L.N, MAX)
	local hf = AshShape.target(i, full, NB, NB_COUNT, CS, MAX, true)
	Harness.truthy(hf <= AshShape.maxPeak(MAX) + 1e-9)
end)

Harness.test("ash shape: ellipsoid shows a cap of the asked height and footprint", function()
	for _, h in { 0.05, 0.6, 2.4 } do
		for _, r in { 4, 5.9 } do
			local a, b, cy = AshShape.ellipsoid(h, r)
			Harness.truthy(a >= r and b >= h and cy <= 0)
			Harness.near(cy + b, h, 1e-9, "peak height")
			Harness.near(AshShape.surfaceAt(h, r, 0), h, 1e-9)
			Harness.near(AshShape.surfaceAt(h, r, r), 0, 1e-9, "meets the ground at r")
			Harness.eq(AshShape.surfaceAt(h, r, r * 2), 0)
			Harness.truthy(AshShape.surfaceAt(h, r, r * 0.5) < h)
			Harness.truthy(AshShape.surfaceAt(h, r, r * 0.5) > 0)
		end
	end
	Harness.eq(AshShape.surfaceAt(0, 5, 0), 0)
end)

Harness.test("ash shape: tint stays soft and in range, tall mounds are lighter", function()
	local r0, g0, b0 = 184, 178, 170
	local lr = AshShape.tint(r0, g0, b0, 0, 1)
	local dr = AshShape.tint(r0, g0, b0, 0, 0)
	Harness.truthy(lr > r0 and dr < r0, "dusted top lighter, low mounds darker")
	for _, light in { -1, -0.3, 0, 0.5, 1 } do
		for _, hn in { 0, 0.5, 1 } do
			local r, g, b = AshShape.tint(r0, g0, b0, light, hn)
			for _, c in { r, g, b } do
				Harness.truthy(c >= 0 and c <= 255 and c == math.floor(c))
			end
			Harness.truthy(math.abs(r - r0) <= 30, "gentle")
		end
	end
	local wr, wg, wb = AshShape.tint(255, 255, 255, 1, 1)
	Harness.truthy(wr == 255 and wg == 255 and wb == 255, "clamps")
end)

Harness.test("ash shape: embers only on tall mounds in the deep zones, a few of them", function()
	local some, deepTall = 0, 0
	for i = 1, L.N do
		Harness.eq(AshShape.hasEmber(i, 1, MAX), false)
		Harness.eq(AshShape.hasEmber(i, 3, MAX), false)
		Harness.eq(AshShape.hasEmber(i, 5, AshShape.EMBER_LEVEL - 1), false)
		deepTall += 1
		if AshShape.hasEmber(i, 5, MAX) then
			some += 1
			local dx, dz, d = AshShape.emberSpot(i, 5)
			Harness.near(math.sqrt(dx * dx + dz * dz), d, 1e-9)
			Harness.truthy(d < 5 * 0.5, "near the top")
		end
	end
	local share = some / deepTall
	Harness.truthy(share > 0.15 and share < 0.45, "a few, not all")
end)
