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

function Layout.compile(spec: Spec): Layout
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
	local H, T = Layout.HALF, Layout.BOUNDARY
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
