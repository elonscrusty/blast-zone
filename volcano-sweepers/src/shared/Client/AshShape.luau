--!strict
-- Pure shape maths for the ash MOUNDS the client draws (no Roblox types, Lune tests cover it).
--
-- Each ash cell is drawn as one soft, flattened dome: an ellipsoid whose centre sits a little BELOW
-- the ground (SINK), so only a low cap shows and it meets the ground at a gentle slope. The dome is
-- wider than the cell, so neighbouring domes melt into one continuous drift with no visible grid.
--   * height: the cell's own level blended with the average of its existing neighbours (a smoothed
--     height field), so slopes look natural and swept paths get soft edges
--   * footprint: wider when the cells around are full (covers the corners between 4 cells), narrower
--     next to swept ground (so a swept cell clearly shows the ground), half a cell on the island's
--     edges (nothing spills over the beach, the hub or the volcano)
--   * jitter: deterministic per cell (offset, yaw, footprint, height, lightness), so no two mounds
--     look alike; golden cells are never moved or resized by jitter
-- Peaks never exceed CullLogic.slabHeight(maxLevel), the old slab height (Vfx keeps lava discs above).

local CullLogic = require("./CullLogic")

local AshShape = {}

AshShape.SINK = 0.45 -- the ellipsoid centre is SINK x its vertical half-axis below the ground
AshShape.OWN_WEIGHT = 0.6 -- share of the cell's own height in the smoothed height (rest: neighbours)
AshShape.RADIUS_LONE = 0.6 -- footprint radius / cellSize with no filled neighbour
AshShape.RADIUS_FULL = 0.82 -- footprint radius / cellSize with all 8 neighbours filled (covers corners)
AshShape.RADIUS_EDGE = 0.5 -- footprint radius / cellSize on the island's edges (missing neighbours)
AshShape.JITTER_POS = 1.2 -- studs, largest centre offset
AshShape.JITTER_FOOT = 0.12 -- footprint +-12% per axis
AshShape.JITTER_HEIGHT = 0.1 -- height +-10%
AshShape.LIGHT_JITTER = 0.06 -- per-cell lightness +-6%
AshShape.LIGHT_DUST = 0.12 -- tall mounds up to +6% lighter ("dusted"), low ones up to 6% darker
AshShape.EMBER_ZONE = 4 -- embers only in this zone and deeper (Crater Rim, Lava Heart)
AshShape.EMBER_LEVEL = 6 -- ...on mounds at least this full
AshShape.EMBER_CHANCE = 0.3 -- ...and only on this share of them (deterministic per cell)

local TAU = math.pi * 2

-- ===== deterministic per-cell hash =====

-- (a * b) mod 2^32 without losing precision (every product stays below 2^53).
local function mul32(a: number, b: number): number
	local lo = b % 65536
	local hi = (b - lo) / 65536
	return (a * lo + ((a * hi) % 65536) * 65536) % 4294967296
end

-- Deterministic number in [0, 1) for a cell index and a salt (one stream per salt).
function AshShape.hash01(i: number, salt: number): number
	local h = bit32.bxor(mul32(i % 4294967296, 0x9E3779B1), mul32(salt + 1, 0x85EBCA77))
	h = mul32(bit32.bxor(h, bit32.rshift(h, 16)), 0x85EBCA6B)
	h = mul32(bit32.bxor(h, bit32.rshift(h, 13)), 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

local hash01 = AshShape.hash01

-- ===== heights =====

-- Highest peak any mound can reach (= the old slab height for a full cell).
function AshShape.maxPeak(maxLevel: number): number
	return CullLogic.slabHeight(maxLevel)
end

-- Unsmoothed peak height for a level (0 for empty). Leaves room for the +10% height jitter.
function AshShape.levelHeight(level: number, maxLevel: number): number
	if level <= 0 then
		return 0
	end
	return CullLogic.slabHeight(math.min(level, maxLevel)) / (1 + AshShape.JITTER_HEIGHT)
end

-- Smoothed height: own height blended with the neighbours' average. 0 when own is 0 (an empty cell
-- shows the ground). No neighbours: own height.
function AshShape.blend(own: number, nbSum: number, nbCount: number): number
	if own <= 0 then
		return 0
	end
	if nbCount <= 0 then
		return own
	end
	local w = AshShape.OWN_WEIGHT
	return own * w + (nbSum / nbCount) * (1 - w)
end

-- Footprint radius (studs, before per-axis jitter) from how many of the existing neighbours hold ash.
-- A cell with fewer than 8 neighbours sits on the island's edge and stays inside its own cell.
function AshShape.radius(cellSize: number, filled: number, nbCount: number): number
	if nbCount < 8 then
		return cellSize * AshShape.RADIUS_EDGE
	end
	local k = math.clamp(filled / 8, 0, 1)
	return cellSize * (AshShape.RADIUS_LONE + (AshShape.RADIUS_FULL - AshShape.RADIUS_LONE) * k)
end

-- ===== jitter =====

-- Per-cell variety: centre offset (ox, oz) within JITTER_POS studs, yaw (radians, 0..pi), footprint
-- factors fx, fz (1 +- JITTER_FOOT), height factor hm (1 +- JITTER_HEIGHT), lightness light (-1..1).
-- Golden cells keep their exact centre, size and height (yaw only), so the gold reads clearly.
function AshShape.jitter(
	i: number,
	golden: boolean
): (number, number, number, number, number, number, number)
	local yaw = hash01(i, 3) * math.pi
	if golden then
		return 0, 0, yaw, 1, 1, 1, 0
	end
	local d = AshShape.JITTER_POS * math.sqrt(hash01(i, 1))
	local a = hash01(i, 2) * TAU
	local jf = AshShape.JITTER_FOOT
	local fx = 1 + (hash01(i, 4) * 2 - 1) * jf
	local fz = 1 + (hash01(i, 5) * 2 - 1) * jf
	local hm = 1 + (hash01(i, 6) * 2 - 1) * AshShape.JITTER_HEIGHT
	local light = hash01(i, 7) * 2 - 1
	return d * math.cos(a), d * math.sin(a), yaw, fx, fz, hm, light
end

-- ===== neighbours =====

-- Flat neighbour table: nb[(i - 1) * 8 + k] for k = 1..count[i] are cell i's existing neighbours.
function AshShape.neighbourTable(
	n: number,
	neighbours: (i: number) -> { number }
): ({ number }, { number })
	local nb: { number } = table.create(n * 8, 0)
	local count: { number } = table.create(n, 0)
	for i = 1, n do
		local list = neighbours(i)
		local base = (i - 1) * 8
		local c = math.min(#list, 8)
		for k = 1, c do
			nb[base + k] = list[k]
		end
		count[i] = c
	end
	return nb, count
end

-- Target peak height h and base footprint radius r of cell i (0, 0 when it is empty).
-- h is smoothed and jittered and never above maxPeak; a golden cell is never lower than its own height.
function AshShape.target(
	i: number,
	levels: { number },
	nb: { number },
	nbCount: { number },
	cellSize: number,
	maxLevel: number,
	golden: boolean
): (number, number)
	local level = levels[i] or 0
	if level <= 0 then
		return 0, 0
	end
	local own = AshShape.levelHeight(level, maxLevel)
	local count = nbCount[i] or 0
	local base = (i - 1) * 8
	local sum, filled = 0, 0
	for k = 1, count do
		local l = levels[nb[base + k]] or 0
		if l > 0 then
			filled += 1
			sum += AshShape.levelHeight(l, maxLevel)
		end
	end
	local h = AshShape.blend(own, sum, count)
	local r = AshShape.radius(cellSize, filled, count)
	if golden then
		h = math.max(h, own)
	else
		local _, _, _, _, _, hm = AshShape.jitter(i, false)
		h *= hm
	end
	return math.min(h, AshShape.maxPeak(maxLevel)), r
end

-- ===== ellipsoid =====

-- The ellipsoid that shows a cap of peak height h and ground footprint radius r:
-- horizontal half-axis a, vertical half-axis b, centre height cy (relative to the ground, <= 0).
function AshShape.ellipsoid(h: number, r: number): (number, number, number)
	local s = AshShape.SINK
	local b = h / (1 - s)
	local a = r / math.sqrt(1 - s * s)
	return a, b, -s * b
end

-- Height above the ground of the mound's surface at horizontal distance d from its centre (0 outside).
function AshShape.surfaceAt(h: number, r: number, d: number): number
	if h <= 0 or r <= 0 then
		return 0
	end
	local a, b, cy = AshShape.ellipsoid(h, r)
	local q = d / a
	local y = cy + b * math.sqrt(math.max(0, 1 - q * q))
	return math.max(0, y)
end

-- ===== colour =====

-- Mound colour from the zone ash tint (r, g, b 0..255): a per-cell lightness wobble plus a "dusted"
-- lift for tall mounds (hNorm = h / maxPeak, 0..1). Lightening blends toward white (keeps it soft and
-- unsaturated), darkening scales down. Returns whole numbers 0..255.
function AshShape.tint(
	r: number,
	g: number,
	b: number,
	light: number,
	hNorm: number
): (number, number, number)
	local v = math.clamp(light, -1, 1) * AshShape.LIGHT_JITTER
		+ (math.clamp(hNorm, 0, 1) - 0.5) * AshShape.LIGHT_DUST
	local function ch(c: number): number
		local out = if v >= 0 then c + (255 - c) * v else c * (1 + v)
		return math.clamp(math.floor(out + 0.5), 0, 255)
	end
	return ch(r), ch(g), ch(b)
end

-- ===== embers =====

-- Does cell i get a faint glowing ember speck? Deep zones, tall mounds, some cells only.
function AshShape.hasEmber(i: number, zone: number, level: number): boolean
	return zone >= AshShape.EMBER_ZONE
		and level >= AshShape.EMBER_LEVEL
		and hash01(i, 11) < AshShape.EMBER_CHANCE
end

-- Where the ember sits on the mound: offset (dx, dz) from the mound centre and its distance d.
function AshShape.emberSpot(i: number, r: number): (number, number, number)
	local a = hash01(i, 12) * TAU
	local d = r * (0.12 + 0.2 * hash01(i, 13))
	return d * math.cos(a), d * math.sin(a), d
end

return AshShape
