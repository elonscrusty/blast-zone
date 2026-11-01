--!strict
-- Deterministic island layout: which ash cells exist and where. Pure maths from Config.World, so
-- the server and every client compute the identical layout (only ash LEVELS travel the network).
--
-- Cells are cellSize x cellSize squares on a regular grid centred on world (0, 0). A cell exists when
-- its centre lies between the inner edge of the innermost zone and the outer edge of the outermost
-- zone, and outside the hub clear circle. Existing cells get a compact index 1..N, row-major over the
-- bounding square (z rows first, x columns inside a row).
--
-- Spatial hash: `lookup` buckets every grid coordinate (ix, iz) to its cell index (0 = no cell), so
-- cellOf / neighbour / radius queries are O(cells touched), never O(N).

local Config = require("../Config")

export type World = typeof(Config.World)

export type LayoutData = {
	N: number,
	cx: { number }, -- cell centre x by index
	cz: { number }, -- cell centre z by index
	zone: { number }, -- zone id 1..5 by index
	cellSize: number,
	cols: number, -- grid columns (and rows) of the bounding square
	x0: number, -- world x of the bounding square's left edge
	z0: number,
	lookup: { number }, -- (iz * cols + ix + 1) -> cell index, 0 when no cell there
	zoneCells: { { number } }, -- zone id -> list of cell indices
	zoneCount: { number }, -- zone id -> number of cells
	zoneIds: { number }, -- zone ids in order (1..5)
	hubX: number,
	hubZ: number,
	innerRadius: number,
	outerRadius: number,
	cellOf: (x: number, z: number) -> number?,
	zoneAt: (x: number, z: number) -> number?, -- zone id of a world point (nil outside all rings)
	neighbours: (i: number) -> { number }, -- up to 8 surrounding cells that exist
	cellsInRadius: (x: number, z: number, radius: number) -> { number }, -- unsorted
	build: (world: World) -> LayoutData,
}

local Layout = {}

local function hubPoint(world: World): (number, number)
	local a = math.rad(world.hub.angleDeg)
	return world.hub.radius * math.cos(a), world.hub.radius * math.sin(a)
end

function Layout.build(world: World): LayoutData
	local cs = world.cellSize
	local zonesCfg = world.zones
	local outerRadius = 0
	local innerRadius = math.huge
	for _, z in zonesCfg do
		outerRadius = math.max(outerRadius, z.outer)
		innerRadius = math.min(innerRadius, z.inner)
	end
	local half = math.ceil(outerRadius / cs)
	local cols = half * 2
	local x0 = -half * cs
	local z0 = -half * cs
	local hubX, hubZ = hubPoint(world)
	local clear2 = world.hub.clearRadius * world.hub.clearRadius

	local function zoneAt(x: number, z: number): number?
		local r = math.sqrt(x * x + z * z)
		for _, zc in zonesCfg do
			-- the very outer edge belongs to the outermost zone
			if r >= zc.inner and (r < zc.outer or (r == zc.outer and zc.outer == outerRadius)) then
				return zc.id
			end
		end
		return nil
	end

	local cx, cz, zone = {}, {}, {}
	local lookup = table.create(cols * cols, 0)
	local zoneCells: { { number } } = {}
	local zoneCount: { number } = {}
	local zoneIds: { number } = {}
	for _, zc in zonesCfg do
		zoneCells[zc.id] = {}
		zoneCount[zc.id] = 0
		table.insert(zoneIds, zc.id)
	end
	table.sort(zoneIds)

	local n = 0
	for iz = 0, cols - 1 do
		local z = z0 + (iz + 0.5) * cs
		for ix = 0, cols - 1 do
			local x = x0 + (ix + 0.5) * cs
			local zid = zoneAt(x, z)
			if zid ~= nil then
				local hx, hz = x - hubX, z - hubZ
				if hx * hx + hz * hz > clear2 then
					n += 1
					cx[n], cz[n], zone[n] = x, z, zid
					lookup[iz * cols + ix + 1] = n
					table.insert(zoneCells[zid], n)
					zoneCount[zid] += 1
				end
			end
		end
	end

	local function cellAtGrid(ix: number, iz: number): number
		if ix < 0 or iz < 0 or ix >= cols or iz >= cols then
			return 0
		end
		return lookup[iz * cols + ix + 1]
	end

	local function cellOf(x: number, z: number): number?
		if x ~= x or z ~= z then
			return nil
		end
		local ix = math.floor((x - x0) / cs)
		local iz = math.floor((z - z0) / cs)
		local i = cellAtGrid(ix, iz)
		if i == 0 then
			return nil
		end
		return i
	end

	local function neighbours(i: number): { number }
		local out: { number } = {}
		local ix = math.floor((cx[i] - x0) / cs)
		local iz = math.floor((cz[i] - z0) / cs)
		for dz = -1, 1 do
			for dx = -1, 1 do
				if dx ~= 0 or dz ~= 0 then
					local j = cellAtGrid(ix + dx, iz + dz)
					if j ~= 0 then
						table.insert(out, j)
					end
				end
			end
		end
		return out
	end

	local function cellsInRadius(x: number, z: number, radius: number): { number }
		local out: { number } = {}
		local r2 = radius * radius
		local ixLo = math.max(0, math.floor((x - radius - x0) / cs))
		local ixHi = math.min(cols - 1, math.floor((x + radius - x0) / cs))
		local izLo = math.max(0, math.floor((z - radius - z0) / cs))
		local izHi = math.min(cols - 1, math.floor((z + radius - z0) / cs))
		for iz = izLo, izHi do
			for ix = ixLo, ixHi do
				local j = lookup[iz * cols + ix + 1]
				if j ~= 0 then
					local ddx, ddz = cx[j] - x, cz[j] - z
					if ddx * ddx + ddz * ddz <= r2 then
						table.insert(out, j)
					end
				end
			end
		end
		return out
	end

	return {
		N = n,
		cx = cx,
		cz = cz,
		zone = zone,
		cellSize = cs,
		cols = cols,
		x0 = x0,
		z0 = z0,
		lookup = lookup,
		zoneCells = zoneCells,
		zoneCount = zoneCount,
		zoneIds = zoneIds,
		hubX = hubX,
		hubZ = hubZ,
		innerRadius = innerRadius,
		outerRadius = outerRadius,
		cellOf = cellOf,
		zoneAt = zoneAt,
		neighbours = neighbours,
		cellsInRadius = cellsInRadius,
		build = Layout.build,
	}
end

-- The layout for the real island. Built once on first require.
return Layout.build(Config.World)
