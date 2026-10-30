--!strict
-- Checks on a compiled arena layout: walk grid, flood fill, and line of sight. Used by the arena
-- tests and by tools/arena-export. Stays out of src/ because the game does not need it at runtime.

local Layout = require("../src/server/Arena/Layout")

local Analysis = {}

Analysis.CELL = 2
Analysis.RADIUS = 2.5 -- how far a player sticks out from the middle of their body

export type Grid = { n: number, cell: number, half: number, blocked: { boolean } }

local function idx(g: Grid, col: number, row: number): number
	return row * g.n + col + 1
end

local function cellOf(g: Grid, x: number, z: number): (number, number)
	return math.floor((x + g.half) / g.cell), math.floor((z + g.half) / g.cell)
end

-- Cells a player centre cannot stand in. `extra` adds temporary blockers (a shut door, say).
function Analysis.walkGrid(layout: Layout.Layout, extra: { { number } }?): Grid
	local half, cell = layout.half, Analysis.CELL
	local n = (half * 2) // cell
	local g: Grid = { n = n, cell = cell, half = half, blocked = table.create(n * n, false) }
	local function block(x0: number, z0: number, x1: number, z1: number)
		local r = Analysis.RADIUS
		local c0, r0 = cellOf(g, x0 - r, z0 - r)
		local c1, r1 = cellOf(g, x1 + r, z1 + r)
		for row = math.max(r0, 0), math.min(r1, n - 1) do
			for col = math.max(c0, 0), math.min(c1, n - 1) do
				local cx = -half + (col + 0.5) * cell
				local cz = -half + (row + 0.5) * cell
				if cx >= x0 - r and cx <= x1 + r and cz >= z0 - r and cz <= z1 + r then
					g.blocked[idx(g, col, row)] = true
				end
			end
		end
	end
	for _, s in layout.solids do
		if s.blocksMove then
			block(s.x0, s.z0, s.x1, s.z1)
		end
	end
	for _, e in extra or {} do
		block(e[1], e[2], e[3], e[4])
	end
	return g
end

function Analysis.walkable(g: Grid, x: number, z: number): boolean
	local col, row = cellOf(g, x, z)
	if col < 0 or row < 0 or col >= g.n or row >= g.n then
		return false
	end
	return not g.blocked[idx(g, col, row)]
end

-- Cells reachable from (x, z) on foot (4 neighbours). `inside` can limit it to a region.
function Analysis.flood(g: Grid, x: number, z: number, inside: ((number, number) -> boolean)?): { [number]: boolean }
	local seen: { [number]: boolean } = {}
	local col, row = cellOf(g, x, z)
	if col < 0 or row < 0 or col >= g.n or row >= g.n or g.blocked[idx(g, col, row)] then
		return seen
	end
	local stack = { idx(g, col, row) }
	seen[stack[1]] = true
	while #stack > 0 do
		local i = table.remove(stack) :: number
		local c, r = (i - 1) % g.n, (i - 1) // g.n
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local nc, nr = c + d[1], r + d[2]
			if nc >= 0 and nr >= 0 and nc < g.n and nr < g.n then
				local j = idx(g, nc, nr)
				if not g.blocked[j] and not seen[j] then
					local ok = true
					if inside then
						ok = inside(-g.half + (nc + 0.5) * g.cell, -g.half + (nr + 0.5) * g.cell)
					end
					if ok then
						seen[j] = true
						table.insert(stack, j)
					end
				end
			end
		end
	end
	return seen
end

function Analysis.reaches(g: Grid, fromX: number, fromZ: number, toX: number, toZ: number): boolean
	local seen = Analysis.flood(g, fromX, fromZ)
	local col, row = cellOf(g, toX, toZ)
	return seen[idx(g, col, row)] == true
end

-- Number of walkable cells, and the sizes of the separate pieces they form, inside a disc.
function Analysis.pieces(g: Grid, cx: number, cz: number, radius: number): { number }
	local function inside(x: number, z: number): boolean
		return (x - cx) ^ 2 + (z - cz) ^ 2 <= radius * radius
	end
	local done: { [number]: boolean } = {}
	local sizes = {}
	for row = 0, g.n - 1 do
		for col = 0, g.n - 1 do
			local i = idx(g, col, row)
			local x, z = -g.half + (col + 0.5) * g.cell, -g.half + (row + 0.5) * g.cell
			if not g.blocked[i] and not done[i] and inside(x, z) then
				local seen = Analysis.flood(g, x, z, inside)
				local count = 0
				for j in seen do
					done[j] = true
					count += 1
				end
				table.insert(sizes, count)
			end
		end
	end
	table.sort(sizes, function(a, b)
		return a > b
	end)
	return sizes
end

-- How much of the area within `range` can be seen from (x, z): 0..1. Walks 72 rays.
function Analysis.exposure(layout: Layout.Layout, x: number, z: number, range: number): number
	local seen, total = 0, 0
	local rays = 72
	for k = 0, rays - 1 do
		local a = (k / rays) * math.pi * 2
		local dx, dz = math.cos(a), math.sin(a)
		-- find how far this ray goes before a shot-blocker
		local reach = range
		for _, s in layout.solids do
			if s.blocksShots then
				local hit = Layout.segmentHitsBox(x, z, x + dx * range, z + dz * range, s.x0, s.z0, s.x1, s.z1)
				if hit then
					local lo, hi = 0, range
					for _ = 1, 10 do
						local mid = (lo + hi) / 2
						if Layout.segmentHitsBox(x, z, x + dx * mid, z + dz * mid, s.x0, s.z0, s.x1, s.z1) then
							hi = mid
						else
							lo = mid
						end
					end
					reach = math.min(reach, hi)
				end
			end
		end
		seen += reach * reach
		total += range * range
	end
	return seen / total
end

-- Is a shot-blocker within `d` studs of this spot (something to hide or lean on)?
function Analysis.nearBlocker(layout: Layout.Layout, x: number, z: number, d: number): boolean
	for _, s in layout.solids do
		if s.blocksShots and s.kind ~= "boundary" then
			if x >= s.x0 - d and x <= s.x1 + d and z >= s.z0 - d and z <= s.z1 + d then
				return true
			end
		end
	end
	return false
end

return Analysis
