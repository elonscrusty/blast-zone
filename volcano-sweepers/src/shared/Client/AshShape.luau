--!strict
-- Pure geometry and colour for the ash LAYER the client draws (no Roblox types, Lune tests cover it).
--
-- The look: the whole island is under ONE flat, continuous blanket of ash with a real thickness.
-- Sweeping carves it away: a clean trench down to the bright zone ground, with a visible cut wall.
--   * thickness: grows with the level (a part-swept cell is a thinner, slightly darker layer), never
--     above CullLogic.slabHeight(level) (Vfx keeps lava discs above that)
--   * plan shape: marching squares on the cell centres, so trench edges are straight or 45 degrees,
--     never a staircase of squares. Each cell is cut into 4 quadrants; each quadrant into an INNER
--     triangle (next to the cell centre: the cell's own level) and an OUTER triangle (next to the cell
--     corner P). The outer triangle's level comes from the 4 cells around P (outerLevel below), so a
--     swept cell's corners keep a fillet of ash and a lone ash cell's corners are chamfered off.
--   * parts per cell: a full cell is ONE block; a cell on an edge is up to 2 blocks + 1 diamond
--     (a 45-degree block made of the 4 inner triangles) + one flat WedgePart per odd outer triangle
--   * seams: pieces reach OVERLAP studs past their cell, and edge neighbours differ in height by
--     PARITY studs (checkerboard), so overlaps never z-fight and no hairline gap shows
--   * colour: the zone ash tint, blended across zone borders, with a soft low-frequency noise (no
--     per-cell speckle, so no visible grid)
--
-- Pieces are written into a flat number array, STRIDE numbers each:
--   kind, x, z, a, b, top, level, extra
--   KIND_BLOCK   centre (x, z), size a (along x) by b (along z)
--   KIND_DIAMOND centre (x, z), side a (= b), turned 45 degrees about the vertical axis
--   KIND_WEDGE   right-angle corner (x, z), legs running along a * x and b * z (a, b = +-1), leg
--                length extra; drawn with a WedgePart lying flat (see wedgeFrame)
--   top = studs above the ground of the piece's flat top; level = ash level for its colour.

local AshShape = {}

AshShape.T_MIN = 0.35 -- layer thickness at level 1 (studs)
AshShape.T_FULL = 1.4 -- ...at the top level: a cut wall you can see from the follow camera
AshShape.PARITY = 0.012 -- checkerboard height offset between edge neighbours (no z-fighting)
AshShape.OVERLAP = 0.05 -- studs every piece reaches past its cell (no hairline gaps)
AshShape.INNER_OVERLAP = 0.08 -- extra reach of a wedge over its own cell's diamond
AshShape.DIAMOND_DROP = 0.006 -- the diamond sits this much under its own cell's blocks
AshShape.GOLD_LIFT = 0.05 -- golden ash stands a hair above the layer (and never z-fights it)
AshShape.BURY = 0.1 -- pieces start this far under the ground top (no sparkle at the wall foot)
AshShape.DEPTH_DARK = 0.1 -- a level-1 film is 10% darker than a full layer (depth reads)
AshShape.NOISE_AMP = 0.035 -- lightness wobble +-3.5%, over...
AshShape.NOISE_CELL = 44 -- ...this many studs (much wider than a cell: no grid)
AshShape.ZONE_BLEND = 12 -- studs either side of a zone border where the two tints blend
AshShape.FAR_MIN_SHARE = 0.25 -- a far tile shows when at least this share of its cells has ash
AshShape.EMBER_ZONE = 4 -- embers only in this zone and deeper (Crater Rim, Lava Heart)
AshShape.EMBER_LEVEL = 6 -- ...on cells at least this full
AshShape.EMBER_CHANCE = 0.3 -- ...and only on this share of them (deterministic per cell)

AshShape.STRIDE = 8
AshShape.KIND_BLOCK = 1
AshShape.KIND_DIAMOND = 2
AshShape.KIND_WEDGE = 3
AshShape.MAX_PIECES = 8 -- most pieces one cell can need (2 blocks + diamond + 4 wedges = 7)

local TAU = math.pi * 2
local SQRT2 = math.sqrt(2)

-- Neighbour slots 1..8: (dx, dz) offsets in cells.
AshShape.DX = table.freeze({ -1, 0, 1, -1, 1, -1, 0, 1 })
AshShape.DZ = table.freeze({ -1, -1, -1, 0, 0, 1, 1, 1 })

-- Quadrants 1..4: (-,-), (+,-), (-,+), (+,+).
local Q_DX = { -1, 1, -1, 1 }
local Q_DZ = { -1, -1, 1, 1 }

-- Slot 1..8 of the neighbour at (dx, dz) (not 0, 0).
function AshShape.slot(dx: number, dz: number): number
	local k = (dz + 1) * 3 + (dx + 1)
	return if k < 4 then k + 1 else k
end

local slot = AshShape.slot

-- ===== deterministic hash =====

-- (a * b) mod 2^32 without losing precision (every product stays below 2^53).
local function mul32(a: number, b: number): number
	local lo = b % 65536
	local hi = (b - lo) / 65536
	return (a * lo + ((a * hi) % 65536) * 65536) % 4294967296
end

-- Deterministic number in [0, 1) for an integer key and a salt (one stream per salt).
function AshShape.hash01(i: number, salt: number): number
	local h = bit32.bxor(mul32(i % 4294967296, 0x9E3779B1), mul32(salt + 1, 0x85EBCA77))
	h = mul32(bit32.bxor(h, bit32.rshift(h, 16)), 0x85EBCA6B)
	h = mul32(bit32.bxor(h, bit32.rshift(h, 13)), 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

local hash01 = AshShape.hash01

-- ===== thickness =====

-- Layer thickness (studs) for a level: 0 when empty, T_MIN at level 1 up to T_FULL at maxLevel.
function AshShape.thickness(level: number, maxLevel: number): number
	if level <= 0 then
		return 0
	end
	local l = math.min(level, maxLevel)
	if maxLevel <= 1 then
		return AshShape.T_FULL
	end
	return AshShape.T_MIN + (AshShape.T_FULL - AshShape.T_MIN) * (l - 1) / (maxLevel - 1)
end

local thickness = AshShape.thickness

-- Highest top any piece can reach (full layer + parity + gold lift).
function AshShape.maxTop(maxLevel: number): number
	return thickness(maxLevel, maxLevel) + AshShape.PARITY + AshShape.GOLD_LIFT
end

-- Checkerboard 0 / 1 for the cell whose centre is (x, z) (edge neighbours always differ).
function AshShape.parity(x: number, z: number, cellSize: number): number
	return (math.floor(x / cellSize) + math.floor(z / cellSize)) % 2
end

-- ===== neighbours =====

-- Flat neighbour table by direction: dir[(i - 1) * 8 + s] is the cell in slot s (0 = none).
function AshShape.dirTable(
	n: number,
	cellOf: (x: number, z: number) -> number?,
	cx: { number },
	cz: { number },
	cellSize: number
): { number }
	local dir: { number } = table.create(n * 8, 0)
	local DX, DZ = AshShape.DX, AshShape.DZ
	for i = 1, n do
		local base = (i - 1) * 8
		for s = 1, 8 do
			local j = cellOf(cx[i] + DX[s] * cellSize, cz[i] + DZ[s] * cellSize)
			if j ~= nil and j ~= i then
				dir[base + s] = j
			end
		end
	end
	return dir
end

local function nbLevel(levels: { number }, dir: { number }, base: number, s: number): number
	local j = dir[base + s]
	if j == nil or j == 0 then
		return 0
	end
	return levels[j] or 0
end

-- Level of the outer triangle of cell A's quadrant at corner P, from A's own level a, its two edge
-- neighbours e, f around P and the diagonal one g (marching squares, one threshold per level):
-- ash at level k reaches the outer triangle when A and an edge neighbour both hold k, or when all
-- three others hold k (that is the fillet in a swept corner). A lone diagonal pair stays apart, so
-- swept ground always connects (a diagonal sweep is one smooth stripe).
function AshShape.outerLevel(a: number, e: number, f: number, g: number): number
	return math.max(math.min(a, math.max(e, f)), math.min(e, f, g))
end

local outerLevel = AshShape.outerLevel

-- A number that changes whenever cell i's pieces would (its level, its 8 neighbours', gold).
function AshShape.signature(
	i: number,
	levels: { number },
	dir: { number },
	maxLevel: number,
	golden: boolean
): number
	local radix = maxLevel + 1
	local s = levels[i] or 0
	local base = (i - 1) * 8
	for k = 1, 8 do
		s = s * radix + nbLevel(levels, dir, base, k)
	end
	return s * 2 + (if golden then 1 else 0)
end

-- ===== pieces =====

local scratchOuter = { 0, 0, 0, 0 }
local scratchFull = { false, false, false, false }
local scratchUsed = { false, false, false, false }

local function put(
	out: { number },
	n: number,
	kind: number,
	x: number,
	z: number,
	a: number,
	b: number,
	top: number,
	level: number,
	extra: number
): number
	local k = n * AshShape.STRIDE
	out[k + 1], out[k + 2], out[k + 3], out[k + 4] = kind, x, z, a
	out[k + 5], out[k + 6], out[k + 7], out[k + 8] = b, top, level, extra
	return n + 1
end

-- Write cell i's pieces into `out` (centre x, z; parity 0/1). Returns how many were written
-- (0 for a swept cell with no ash reaching into its corners).
function AshShape.pieces(
	out: { number },
	i: number,
	levels: { number },
	dir: { number },
	x: number,
	z: number,
	cellSize: number,
	maxLevel: number,
	parity: number,
	golden: boolean
): number
	local a = math.clamp(levels[i] or 0, 0, maxLevel)
	local base = (i - 1) * 8
	local h = cellSize * 0.5
	local ov = AshShape.OVERLAP
	local lift = parity * AshShape.PARITY
	local outer, full = scratchOuter, scratchFull
	local allFull = a > 0
	for q = 1, 4 do
		local dx, dz = Q_DX[q], Q_DZ[q]
		local e = nbLevel(levels, dir, base, slot(dx, 0))
		local f = nbLevel(levels, dir, base, slot(0, dz))
		local g = nbLevel(levels, dir, base, slot(dx, dz))
		local o = math.clamp(outerLevel(a, e, f, g), 0, maxLevel)
		outer[q] = o
		full[q] = a > 0 and o == a
		if not full[q] then
			allFull = false
		end
	end

	local n = 0
	local ownTop = 0
	if a > 0 then
		ownTop = thickness(a, maxLevel) + lift + (if golden then AshShape.GOLD_LIFT else 0)
	end
	local edge = h + ov -- centre to the outer side of a block
	if allFull then
		return put(out, n, AshShape.KIND_BLOCK, x, z, 2 * edge, 2 * edge, ownTop, a, 0)
	end

	if a > 0 then
		-- the full quadrants as at most 2 blocks: halves first, then single quadrants
		local used1, used2, used3, used4 = false, false, false, false
		local f1, f2, f3, f4 = full[1], full[2], full[3], full[4]
		if f1 and f2 then
			n = put(out, n, AshShape.KIND_BLOCK, x, z - edge / 2, 2 * edge, edge, ownTop, a, 0)
			used1, used2 = true, true
		end
		if f3 and f4 then
			n = put(out, n, AshShape.KIND_BLOCK, x, z + edge / 2, 2 * edge, edge, ownTop, a, 0)
			used3, used4 = true, true
		end
		if f1 and f3 and not used1 and not used3 then
			n = put(out, n, AshShape.KIND_BLOCK, x - edge / 2, z, edge, 2 * edge, ownTop, a, 0)
			used1, used3 = true, true
		end
		if f2 and f4 and not used2 and not used4 then
			n = put(out, n, AshShape.KIND_BLOCK, x + edge / 2, z, edge, 2 * edge, ownTop, a, 0)
			used2, used4 = true, true
		end
		local usedQ = scratchUsed
		usedQ[1], usedQ[2], usedQ[3], usedQ[4] = used1, used2, used3, used4
		for q = 1, 4 do
			if full[q] and not usedQ[q] then
				local qx = x + Q_DX[q] * edge / 2
				local qz = z + Q_DZ[q] * edge / 2
				n = put(out, n, AshShape.KIND_BLOCK, qx, qz, edge, edge, ownTop, a, 0)
			end
		end
		-- the 4 inner triangles: one diamond (corners on the cell's edge midpoints)
		local side = edge * SQRT2
		n = put(
			out,
			n,
			AshShape.KIND_DIAMOND,
			x,
			z,
			side,
			side,
			ownTop - AshShape.DIAMOND_DROP,
			a,
			0
		)
	end

	-- outer triangles that differ from the cell's own level: one flat wedge each
	for q = 1, 4 do
		local o = outer[q]
		if not full[q] and o > 0 then
			local dx, dz = Q_DX[q], Q_DZ[q]
			local px, pz = x + dx * edge, z + dz * edge
			local leg = h + 2 * ov + AshShape.INNER_OVERLAP
			local top = thickness(o, maxLevel) + lift
			n = put(out, n, AshShape.KIND_WEDGE, px, pz, -dx, -dz, top, o, leg)
		end
	end
	return n
end

-- Level of the layer at a point inside cell i (dx, dz = offset from the cell centre), from the
-- marching-squares rule alone. The reference the tests hold `pieces` to.
function AshShape.levelInside(
	i: number,
	levels: { number },
	dir: { number },
	maxLevel: number,
	cellSize: number,
	dx: number,
	dz: number
): number
	local a = math.clamp(levels[i] or 0, 0, maxLevel)
	local h = cellSize * 0.5
	if math.abs(dx) + math.abs(dz) < h then
		return a
	end
	local sx = if dx < 0 then -1 else 1
	local sz = if dz < 0 then -1 else 1
	local base = (i - 1) * 8
	local e = nbLevel(levels, dir, base, slot(sx, 0))
	local f = nbLevel(levels, dir, base, slot(0, sz))
	local g = nbLevel(levels, dir, base, slot(sx, sz))
	return math.clamp(outerLevel(a, e, f, g), 0, maxLevel)
end

-- ===== the flat wedge =====

-- A Roblox WedgePart's solid, in its own space (size X, Y, Z): the bottom face (-Y) and the back
-- face (+Z) are full rectangles and the slope runs from the top-back edge down to the bottom-front
-- edge, so its Y-Z cross-section is the right triangle with the right angle at (y, z) = (-Y/2, +Z/2).
-- Laid flat (its X axis vertical) that cross-section becomes a horizontal triangle and X its
-- thickness. For a right triangle with its right angle at (cx, cz) and legs of length `leg` along
-- sx * world x and sz * world z (sx, sz = +-1) this gives the part's centre (x, z) and its axes:
--   X axis (0, upY, 0), Y axis (yx, 0, 0), Z axis (0, 0, zz) -- for CFrame.fromMatrix(pos, X, Y, Z)
-- with Size = (thickness, leg, leg). X = Y x Z, so the frame is a proper rotation.
function AshShape.wedgeFrame(
	cx: number,
	cz: number,
	sx: number,
	sz: number,
	leg: number
): (number, number, number, number, number)
	local yx = sx -- the Y axis runs along the x leg (away from the right angle)
	local zz = -sz -- the z leg runs toward -Z, so the Z axis points the other way
	-- X = Y x Z = (yx, 0, 0) x (0, 0, zz) = (0, -yx * zz, 0): straight up or straight down
	local upY = -yx * zz
	return cx + sx * leg / 2, cz + sz * leg / 2, upY, yx, zz
end

-- Is the horizontal point (px, pz) inside the flat wedge piece? Uses the WedgePart model above
-- (tests use it to check that the wedges cover exactly the triangles they should).
function AshShape.insideWedge(
	px: number,
	pz: number,
	cx: number,
	cz: number,
	sx: number,
	sz: number,
	leg: number
): boolean
	local mx, mz, _, yx, zz = AshShape.wedgeFrame(cx, cz, sx, sz, leg)
	local ly = (px - mx) * yx -- local Y
	local lz = (pz - mz) * zz -- local Z
	local hl = leg / 2
	if math.abs(ly) > hl + 1e-9 or math.abs(lz) > hl + 1e-9 then
		return false
	end
	return ly <= lz + 1e-9
end

-- Is (px, pz) inside piece k (0-based) of `out`? Blocks, diamonds and wedges.
function AshShape.insidePiece(out: { number }, k: number, px: number, pz: number): boolean
	local o = k * AshShape.STRIDE
	local kind, x, z, a, b = out[o + 1], out[o + 2], out[o + 3], out[o + 4], out[o + 5]
	if kind == AshShape.KIND_BLOCK then
		return math.abs(px - x) <= a / 2 + 1e-9 and math.abs(pz - z) <= b / 2 + 1e-9
	elseif kind == AshShape.KIND_DIAMOND then
		local u = ((px - x) + (pz - z)) / SQRT2
		local v = ((px - x) - (pz - z)) / SQRT2
		return math.abs(u) <= a / 2 + 1e-9 and math.abs(v) <= a / 2 + 1e-9
	end
	return AshShape.insideWedge(px, pz, x, z, a, b, out[o + 8])
end

-- ===== colour =====

local function smooth(t: number): number
	local k = math.clamp(t, 0, 1)
	return k * k * (3 - 2 * k)
end

-- Smooth value noise in [-1, 1] at a world point (bilinear between hashed lattice points spaced
-- NOISE_CELL studs apart, plus a finer octave at half the spacing). Deterministic.
function AshShape.noise(x: number, z: number): number
	local function octave(cell: number, salt: number): number
		local gx, gz = x / cell, z / cell
		local ix, iz = math.floor(gx), math.floor(gz)
		local fx, fz = smooth(gx - ix), smooth(gz - iz)
		local function at(ax: number, az: number): number
			return hash01((ax + 4096) * 8192 + (az + 4096), salt) * 2 - 1
		end
		local top = at(ix, iz) + (at(ix + 1, iz) - at(ix, iz)) * fx
		local bottom = at(ix, iz + 1) + (at(ix + 1, iz + 1) - at(ix, iz + 1)) * fx
		return top + (bottom - top) * fz
	end
	local c = AshShape.NOISE_CELL
	return octave(c, 21) * 0.7 + octave(c * 0.5, 22) * 0.3
end

-- Lighten (v > 0, toward white) or darken (v < 0) a colour by a share; whole numbers 0..255.
function AshShape.lighten(r: number, g: number, b: number, v: number): (number, number, number)
	local function ch(c: number): number
		local out = if v >= 0 then c + (255 - c) * v else c * (1 + v)
		return math.clamp(math.floor(out + 0.5), 0, 255)
	end
	return ch(r), ch(g), ch(b)
end

export type Ring = { inner: number, outer: number, r: number, g: number, b: number }

-- The layer's own colour at a world point: the zone ash tints, blended over ZONE_BLEND studs either
-- side of each zone border (so the border is a soft band, not a staircase of cells), with the soft
-- noise on top. `rings` are the zones (any order). Whole numbers 0..255.
function AshShape.baseColour(x: number, z: number, rings: { Ring }): (number, number, number)
	local rad = math.sqrt(x * x + z * z)
	local bl = AshShape.ZONE_BLEND
	local sw, sr, sg, sb = 0, 0, 0, 0
	local nearest: Ring? = nil
	local nearestD = math.huge
	for _, ring in rings do
		local rise = math.clamp((rad - (ring.inner - bl)) / (2 * bl), 0, 1)
		local fall = math.clamp(((ring.outer + bl) - rad) / (2 * bl), 0, 1)
		local w = math.min(rise, fall)
		if w > 0 then
			sw += w
			sr += ring.r * w
			sg += ring.g * w
			sb += ring.b * w
		end
		local d = math.max(ring.inner - rad, rad - ring.outer, 0)
		if d < nearestD then
			nearestD = d
			nearest = ring
		end
	end
	local r, g, b = 128, 128, 128
	if sw > 1e-9 then
		r, g, b = sr / sw, sg / sw, sb / sw
	elseif nearest ~= nil then
		r, g, b = nearest.r, nearest.g, nearest.b
	end
	return AshShape.lighten(r, g, b, AshShape.noise(x, z) * AshShape.NOISE_AMP)
end

-- A thinner (part-swept) layer is a little darker; a full one keeps the base colour.
function AshShape.depthShade(
	r: number,
	g: number,
	b: number,
	level: number,
	maxLevel: number
): (number, number, number)
	local k = math.clamp(level / math.max(maxLevel, 1), 0, 1)
	return AshShape.lighten(r, g, b, -AshShape.DEPTH_DARK * (1 - k))
end

-- ===== far tiles =====

-- How a far chunk is drawn from its totals: shown?, the level its tile stands at (rounded mean of
-- the cells that hold ash) and how far its colour leans to the clean ground (0 = pure ash).
function AshShape.farLook(
	ashCells: number,
	cellCount: number,
	levelSum: number,
	maxLevel: number
): (boolean, number, number)
	if cellCount <= 0 or ashCells <= 0 then
		return false, 0, 1
	end
	local share = ashCells / cellCount
	if share < AshShape.FAR_MIN_SHARE then
		return false, 0, 1
	end
	local level = math.clamp(math.floor(levelSum / ashCells + 0.5), 1, maxLevel)
	return true, level, math.clamp((1 - share) * 0.9, 0, 1)
end

-- Blend two colours (t = 0 gives the first); whole numbers.
function AshShape.mix(
	r1: number,
	g1: number,
	b1: number,
	r2: number,
	g2: number,
	b2: number,
	t: number
): (number, number, number)
	local k = math.clamp(t, 0, 1)
	return math.floor(r1 + (r2 - r1) * k + 0.5),
		math.floor(g1 + (g2 - g1) * k + 0.5),
		math.floor(b1 + (b2 - b1) * k + 0.5)
end

-- ===== embers =====

-- Does cell i get a faint glowing ember speck? Deep zones, nearly full cells, some cells only.
function AshShape.hasEmber(i: number, zone: number, level: number): boolean
	return zone >= AshShape.EMBER_ZONE
		and level >= AshShape.EMBER_LEVEL
		and hash01(i, 11) < AshShape.EMBER_CHANCE
end

-- Where the ember sits: offset (dx, dz) from the cell centre (inside the inner diamond) and its
-- distance d.
function AshShape.emberSpot(i: number, cellSize: number): (number, number, number)
	local a = hash01(i, 12) * TAU
	local d = cellSize * (0.05 + 0.25 * hash01(i, 13))
	return d * math.cos(a), d * math.sin(a), d
end

return AshShape
