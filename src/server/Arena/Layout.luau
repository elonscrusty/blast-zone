--!strict
-- Graybox city arena data. A layout file is a short spec (ground rects, walls with door gaps,
-- cover, spawn and container points). `compile` turns it into plain boxes that both the server
-- builder and the Lune tests read. Pure: no Roblox types, so Lune can test it.
--
-- Axes: x is east, z is south (so -z is north), y is up. Origin is the middle of the arena.
-- Every box is axis-aligned: x0 < x1, z0 < z1.

local Layout = {}

Layout.HALF = 110 -- arena is 220 x 220
Layout.WALL = 2 -- building wall thickness
Layout.FENCE = 0.6
Layout.BOUNDARY = 4

export type Door = { side: string, from: number, to: number } -- side: "N" "S" "E" "W"; from/to are x (N/S) or z (E/W)
export type Pt = { number } -- { x, z }

export type WallLine = {
	axis: string, -- "h" runs along x at z = at, "v" runs along z at x = at
	at: number,
	from: number,
	to: number,
	gaps: { { number } }?,
	h: number?,
}

export type BoxSpec = {
	id: string,
	kind: string, -- mass | cover | prop | water | rail
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	h: number?,
}

export type GroundSpec = {
	id: string,
	kind: string, -- sidewalk | road | park | alley | lot
	x0: number,
	z0: number,
	x1: number,
	z1: number,
}

export type BuildingSpec = {
	id: string,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	h: number,
	doors: { Door },
	inner: { WallLine }?,
}

export type ParkSpec = {
	id: string,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	gates: { Door },
}

export type Encounter = { kind: string, name: string, x: number, z: number, r: number, note: string }

export type Spec = {
	id: string,
	name: string,
	blurb: string,
	ground: { GroundSpec },
	intersections: { GroundSpec },
	alleys: { GroundSpec },
	buildings: { BuildingSpec },
	parks: { ParkSpec },
	boxes: { BoxSpec },
	spawns: { Pt },
	containers: { Pt },
	encounters: { Encounter },
}

-- Crowd options (piece 47). All optional: with none, `compile` builds the map exactly as written.
export type Options = {
	scale: number?, -- stretch the map: streets, buildings and spacing grow, props keep their size
	minSpawns: number?, -- top the spawn points up to this many (spread out over free, reachable floor)
	minContainers: number?, -- top the crate points up to this many
	spawnClear: number?, -- studs a spawn keeps from every solid
	zoneRadius: number?, -- extra spawns stay inside this circle around the middle
}

export type Solid = {
	id: string,
	kind: string, -- wall | partition | fence | boundary | mass | cover | prop | water | rail
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	h: number,
	blocksMove: boolean,
	blocksShots: boolean,
	occluder: boolean, -- the camera may fade it locally (never affects collision)
	building: string?,
}

export type Roof = {
	id: string,
	building: string,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	h: number,
}
export type Gate = {
	id: string,
	park: string,
	side: string,
	from: number,
	to: number,
	x: number,
	z: number,
}
export type Point = { id: string, x: number, z: number }

export type Layout = {
	id: string,
	name: string,
	blurb: string,
	half: number,
	ground: { GroundSpec },
	solids: { Solid },
	roofs: { Roof },
	buildings: { BuildingSpec },
	gates: { Gate },
	alleys: { GroundSpec },
	intersections: { GroundSpec },
	spawns: { Point },
	containers: { Point },
	encounters: { Encounter },
}

-- Shot and move rules per box kind. These are THE rules: thin fences and rails stop walking but
-- not shots; water stops walking only; everything else stops both. Shots are flat, so height does
-- not matter for them. Explosions use the same blocksShots flag.
local KINDS: { [string]: { h: number, move: boolean, shots: boolean } } = {
	mass = { h = 16, move = true, shots = true },
	cover = { h = 4, move = true, shots = true },
	prop = { h = 8, move = true, shots = true },
	water = { h = 0.5, move = true, shots = false },
	rail = { h = 3, move = true, shots = false },
}

local function addSolid(out: { Solid }, s: Solid)
	table.insert(out, s)
end

-- Walls along a line, leaving the gaps open.
local function wallLine(
	out: { Solid },
	id: string,
	kind: string,
	line: WallLine,
	thick: number,
	h: number,
	shots: boolean,
	building: string?,
	occluder: boolean
)
	local gaps: { { number } } = {}
	for _, g in line.gaps or {} do
		table.insert(gaps, g)
	end
	table.sort(gaps, function(a, b)
		return a[1] < b[1]
	end)
	local n = 0
	local function seg(a: number, b: number)
		if b - a < 0.01 then
			return
		end
		n += 1
		local x0, z0, x1, z1
		if line.axis == "h" then
			x0, x1, z0, z1 = a, b, line.at - thick / 2, line.at + thick / 2
		else
			x0, x1, z0, z1 = line.at - thick / 2, line.at + thick / 2, a, b
		end
		addSolid(out, {
			id = `{id}-{n}`,
			kind = kind,
			x0 = x0,
			z0 = z0,
			x1 = x1,
			z1 = z1,
			h = line.h or h,
			blocksMove = true,
			blocksShots = shots,
			occluder = occluder,
			building = building,
		})
	end
	local cursor = line.from
	for _, g in gaps do
		seg(cursor, g[1])
		cursor = g[2]
	end
	seg(cursor, line.to)
end

local function doorGaps(doors: { Door }, side: string): { { number } }
	local gaps = {}
	for _, d in doors do
		if d.side == side then
			table.insert(gaps, { d.from, d.to })
		end
	end
	return gaps
end

-- Four sides of a rectangle as wall lines, each with its own gaps.
local function ringLines(
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	t: number,
	doors: { Door }
): { WallLine }
	return {
		{ axis = "h", at = z0 + t / 2, from = x0, to = x1, gaps = doorGaps(doors, "N") },
		{ axis = "h", at = z1 - t / 2, from = x0, to = x1, gaps = doorGaps(doors, "S") },
		{ axis = "v", at = x0 + t / 2, from = z0 + t, to = z1 - t, gaps = doorGaps(doors, "W") },
		{ axis = "v", at = x1 - t / 2, from = z0 + t, to = z1 - t, gaps = doorGaps(doors, "E") },
	}
end

-- ---------------------------------------------------------------------------------------------
-- Crowd helpers (piece 47)

local function round1(n: number): number
	return math.floor(n * 10 + 0.5) / 10
end

local function scaleRect(r: any, s: number)
	r.x0, r.z0, r.x1, r.z1 = round1(r.x0 * s), round1(r.z0 * s), round1(r.x1 * s), round1(r.z1 * s)
end

local function scaleDoors(doors: { Door }, s: number): { Door }
	local out: { Door } = {}
	for _, d in doors do
		table.insert(out, { side = d.side, from = round1(d.from * s), to = round1(d.to * s) })
	end
	return out
end

-- A copy of the spec stretched by `s` around the middle. Ground, buildings, doors, gates, big
-- blocks and every point move out. Small things (cars, crates, pillars, trees) move out but keep
-- their size, and a long thin one (a hedge, a bench) only grows along its long side, so the cover
-- count stays the same and the streets just get longer. Heights never change.
function Layout.scaleSpec(spec: Spec, s: number): Spec
	if s == 1 then
		return spec
	end
	local function rects(list: { GroundSpec }): { GroundSpec }
		local out: { GroundSpec } = {}
		for _, g in list do
			local c = table.clone(g)
			scaleRect(c, s)
			table.insert(out, c)
		end
		return out
	end
	local buildings: { BuildingSpec } = {}
	for _, b in spec.buildings do
		local c = table.clone(b)
		scaleRect(c, s)
		c.doors = scaleDoors(b.doors, s)
		if b.inner then
			local inner: { WallLine } = {}
			for _, line in b.inner do
				local l = table.clone(line)
				l.at, l.from, l.to = round1(line.at * s), round1(line.from * s), round1(line.to * s)
				if line.gaps then
					local gaps: { { number } } = {}
					for _, g in line.gaps do
						table.insert(gaps, { round1(g[1] * s), round1(g[2] * s) })
					end
					l.gaps = gaps
				end
				table.insert(inner, l)
			end
			c.inner = inner
		end
		table.insert(buildings, c)
	end
	local parks: { ParkSpec } = {}
	for _, p in spec.parks do
		local c = table.clone(p)
		scaleRect(c, s)
		c.gates = scaleDoors(p.gates, s)
		table.insert(parks, c)
	end
	local boxes: { BoxSpec } = {}
	for _, b in spec.boxes do
		local c = table.clone(b)
		-- big blocks and ponds grow; a small mass (kiosk, gazebo, bandstand) is a prop and keeps its size
		local big = math.min(b.x1 - b.x0, b.z1 - b.z0) >= 20
		if b.kind == "water" or (b.kind == "mass" and big) then
			scaleRect(c, s)
		else
			local cx, cz = (b.x0 + b.x1) / 2 * s, (b.z0 + b.z1) / 2 * s
			local w, d = b.x1 - b.x0, b.z1 - b.z0
			if w >= d * 1.8 then
				w *= s
			elseif d >= w * 1.8 then
				d *= s
			end
			c.x0, c.x1 = round1(cx - w / 2), round1(cx + w / 2)
			c.z0, c.z1 = round1(cz - d / 2), round1(cz + d / 2)
		end
		table.insert(boxes, c)
	end
	local function points(list: { Pt }): { Pt }
		local out: { Pt } = {}
		for _, p in list do
			table.insert(out, { round1(p[1] * s), round1(p[2] * s) })
		end
		return out
	end
	local encounters: { Encounter } = {}
	for _, e in spec.encounters do
		local c = table.clone(e)
		c.x, c.z, c.r = round1(e.x * s), round1(e.z * s), round1(e.r * s)
		table.insert(encounters, c)
	end
	local out = table.clone(spec)
	out.ground = rects(spec.ground)
	out.intersections = rects(spec.intersections)
	out.alleys = rects(spec.alleys)
	out.buildings = buildings
	out.parks = parks
	out.boxes = boxes
	out.spawns = points(spec.spawns)
	out.containers = points(spec.containers)
	out.encounters = encounters
	return out
end

local CELL = 2
local WALK_RADIUS = 2.5 -- how far a fighter sticks out from the middle of their body

type Floor = { seen: { boolean }, n: number, half: number }

-- Floor cells a fighter can stand on AND walk to from (fx, fz).
local function walkableFloor(solids: { Solid }, half: number, fx: number, fz: number): Floor
	local n = (half * 2) // CELL
	local blocked = table.create(n * n, false)
	for _, s in solids do
		if s.blocksMove then
			local c0 = math.max(math.floor((s.x0 - WALK_RADIUS + half) / CELL), 0)
			local c1 = math.min(math.floor((s.x1 + WALK_RADIUS + half) / CELL), n - 1)
			local r0 = math.max(math.floor((s.z0 - WALK_RADIUS + half) / CELL), 0)
			local r1 = math.min(math.floor((s.z1 + WALK_RADIUS + half) / CELL), n - 1)
			for row = r0, r1 do
				for col = c0, c1 do
					local cx, cz = -half + (col + 0.5) * CELL, -half + (row + 0.5) * CELL
					if
						cx >= s.x0 - WALK_RADIUS
						and cx <= s.x1 + WALK_RADIUS
						and cz >= s.z0 - WALK_RADIUS
						and cz <= s.z1 + WALK_RADIUS
					then
						blocked[row * n + col + 1] = true
					end
				end
			end
		end
	end
	local seen = table.create(n * n, false)
	local col0 = math.clamp(math.floor((fx + half) / CELL), 0, n - 1)
	local row0 = math.clamp(math.floor((fz + half) / CELL), 0, n - 1)
	local first = row0 * n + col0 + 1
	local stack: { number } = {}
	if not blocked[first] then
		seen[first] = true
		stack = { first }
	end
	while #stack > 0 do
		local i = table.remove(stack) :: number
		local row, col = (i - 1) // n, (i - 1) % n
		for k = 1, 4 do
			local nc = col + (if k == 1 then 1 elseif k == 2 then -1 else 0)
			local nr = row + (if k == 3 then 1 elseif k == 4 then -1 else 0)
			if nc >= 0 and nr >= 0 and nc < n and nr < n then
				local j = nr * n + nc + 1
				if not blocked[j] and not seen[j] then
					seen[j] = true
					table.insert(stack, j)
				end
			end
		end
	end
	return { seen = seen, n = n, half = half }
end

local function standable(floor: Floor, x: number, z: number): boolean
	local col = math.floor((x + floor.half) / CELL)
	local row = math.floor((z + floor.half) / CELL)
	if col < 0 or row < 0 or col >= floor.n or row >= floor.n then
		return false
	end
	return floor.seen[row * floor.n + col + 1] == true
end

local function nearSolid(solids: { Solid }, x: number, z: number, pad: number): boolean
	for _, s in solids do
		if
			s.blocksMove
			and s.kind ~= "boundary"
			and x >= s.x0 - pad
			and x <= s.x1 + pad
			and z >= s.z0 - pad
			and z <= s.z1 + pad
		then
			return true
		end
	end
	return false
end

local function insideBuilding(buildings: { BuildingSpec }, x: number, z: number): boolean
	for _, b in buildings do
		if x >= b.x0 and x <= b.x1 and z >= b.z0 and z <= b.z1 then
			return true
		end
	end
	return false
end

-- Adds points until `list` holds `want`. Each new point is the free, reachable spot that sits
-- farthest from every point already chosen (farthest-point sampling), so the crowd spreads out
-- evenly. Same map in, same points out: nothing random.
local function topUp(
	list: { Point },
	want: number,
	prefix: string,
	candidates: { { number } },
	extraAvoid: { Point }
)
	if #list >= want then
		return
	end
	local nearest = table.create(#candidates, math.huge)
	local function include(px: number, pz: number)
		for i, c in candidates do
			local d = math.sqrt((c[1] - px) ^ 2 + (c[2] - pz) ^ 2)
			if d < nearest[i] then
				nearest[i] = d
			end
		end
	end
	for _, p in list do
		include(p.x, p.z)
	end
	for _, p in extraAvoid do
		include(p.x, p.z)
	end
	while #list < want do
		local best, bestD = 0, 0
		for i = 1, #candidates do
			if nearest[i] > bestD then
				best, bestD = i, nearest[i]
			end
		end
		if best == 0 then
			return -- no free floor left
		end
		local c = candidates[best]
		table.insert(list, { id = `{prefix}{#list + 1}`, x = c[1], z = c[2] })
		include(c[1], c[2])
	end
end

function Layout.compile(source: Spec, opts: Options?): Layout
	local options: Options = opts or {}
	local scale = options.scale or 1
	local spec = Layout.scaleSpec(source, scale)
	local solids: { Solid } = {}
	local roofs: { Roof } = {}
	local gates: { Gate } = {}
	local ground: { GroundSpec } = {}
	for _, g in spec.ground do
		table.insert(ground, g)
	end

	for _, b in spec.buildings do
		table.insert(
			ground,
			{ id = `{b.id}-floor`, kind = "floor", x0 = b.x0, z0 = b.z0, x1 = b.x1, z1 = b.z1 }
		)
		for i, line in ringLines(b.x0, b.z0, b.x1, b.z1, Layout.WALL, b.doors) do
			wallLine(solids, `{b.id}-wall{i}`, "wall", line, Layout.WALL, b.h, true, b.id, true)
		end
		for i, line in b.inner or {} do
			wallLine(solids, `{b.id}-part{i}`, "partition", line, Layout.WALL, 7, true, b.id, false)
		end
		table.insert(roofs, {
			id = `{b.id}-roof`,
			building = b.id,
			x0 = b.x0,
			z0 = b.z0,
			x1 = b.x1,
			z1 = b.z1,
			h = b.h,
		})
	end

	for _, p in spec.parks do
		for i, line in ringLines(p.x0, p.z0, p.x1, p.z1, Layout.FENCE, p.gates) do
			wallLine(solids, `{p.id}-fence{i}`, "fence", line, Layout.FENCE, 4, false, nil, false)
		end
		for i, d in p.gates do
			local gx, gz
			if d.side == "N" then
				gx, gz = (d.from + d.to) / 2, p.z0
			elseif d.side == "S" then
				gx, gz = (d.from + d.to) / 2, p.z1
			elseif d.side == "W" then
				gx, gz = p.x0, (d.from + d.to) / 2
			else
				gx, gz = p.x1, (d.from + d.to) / 2
			end
			table.insert(gates, {
				id = `{p.id}-gate{i}`,
				park = p.id,
				side = d.side,
				from = d.from,
				to = d.to,
				x = gx,
				z = gz,
			})
		end
	end

	for _, b in spec.boxes do
		local k = KINDS[b.kind]
		assert(k, `unknown box kind {b.kind}`)
		addSolid(solids, {
			id = b.id,
			kind = b.kind,
			x0 = b.x0,
			z0 = b.z0,
			x1 = b.x1,
			z1 = b.z1,
			h = b.h or k.h,
			blocksMove = k.move,
			blocksShots = k.shots,
			occluder = b.kind == "mass",
		})
	end

	-- Invisible-to-play boundary walls just outside the arena.
	local H, T = Layout.HALF * scale, Layout.BOUNDARY
	local edges = {
		{ "n", -H - T, -H - T, H + T, -H },
		{ "s", -H - T, H, H + T, H + T },
		{ "w", -H - T, -H, -H, H },
		{ "e", H, -H, H + T, H },
	}
	for _, e in edges do
		addSolid(solids, {
			id = `boundary-{e[1]}`,
			kind = "boundary",
			x0 = e[2] :: number,
			z0 = e[3] :: number,
			x1 = e[4] :: number,
			z1 = e[5] :: number,
			h = 40,
			blocksMove = true,
			blocksShots = true,
			occluder = false,
		})
	end

	local spawns: { Point } = {}
	for i, p in spec.spawns do
		table.insert(spawns, { id = `{spec.id}-spawn{i}`, x = p[1], z = p[2] })
	end
	local containers: { Point } = {}
	for i, p in spec.containers do
		table.insert(containers, { id = `{spec.id}-box{i}`, x = p[1], z = p[2] })
	end

	-- Crowd top-up (piece 47): more spawns and crate points on free, reachable floor.
	local wantSpawns = options.minSpawns or 0
	local wantContainers = options.minContainers or 0
	if (wantSpawns > #spawns or wantContainers > #containers) and #spawns > 0 then
		local floor = walkableFloor(solids, H, spawns[1].x, spawns[1].z)
		local spawnClear = options.spawnClear or 4
		local zoneRadius = options.zoneRadius or H * math.sqrt(2)
		local spawnSpots: { { number } } = {}
		local boxSpots: { { number } } = {}
		for x = -H + 6, H - 6, 4 do
			for z = -H + 6, H - 6, 4 do
				if standable(floor, x, z) and not nearSolid(solids, x, z, spawnClear) then
					if
						not insideBuilding(spec.buildings, x, z)
						and math.sqrt(x * x + z * z) < zoneRadius - 6
					then
						table.insert(spawnSpots, { x, z })
					end
					if not nearSolid(solids, x, z, 4.5) then
						table.insert(boxSpots, { x, z })
					end
				end
			end
		end
		topUp(spawns, wantSpawns, `{spec.id}-spawn`, spawnSpots, {})
		-- crates keep a little away from spawn points so nobody wakes up beside a free box
		topUp(containers, wantContainers, `{spec.id}-box`, boxSpots, spawns)
	end

	return {
		id = spec.id,
		name = spec.name,
		blurb = spec.blurb,
		half = H,
		ground = ground,
		solids = solids,
		roofs = roofs,
		buildings = spec.buildings,
		gates = gates,
		alleys = spec.alleys,
		intersections = spec.intersections,
		spawns = spawns,
		containers = containers,
		encounters = spec.encounters,
	}
end

-- Does the flat segment a->b cross this box? (slab test)
local function segmentHitsBox(
	ax: number,
	az: number,
	bx: number,
	bz: number,
	x0: number,
	z0: number,
	x1: number,
	z1: number
): boolean
	local t0, t1 = 0, 1
	local dx, dz = bx - ax, bz - az
	local function slab(p: number, d: number, lo: number, hi: number): boolean
		if math.abs(d) < 1e-9 then
			return p >= lo and p <= hi
		end
		local ta, tb = (lo - p) / d, (hi - p) / d
		if ta > tb then
			ta, tb = tb, ta
		end
		t0, t1 = math.max(t0, ta), math.min(t1, tb)
		return t0 <= t1
	end
	return slab(ax, dx, x0, x1) and slab(az, dz, z0, z1)
end

Layout.segmentHitsBox = segmentHitsBox

-- True when a shot (or line of sight) from a to b is stopped by a solid.
function Layout.shotBlocked(layout: Layout, ax: number, az: number, bx: number, bz: number): boolean
	for _, s in layout.solids do
		if s.blocksShots and segmentHitsBox(ax, az, bx, bz, s.x0, s.z0, s.x1, s.z1) then
			return true
		end
	end
	return false
end

return Layout
