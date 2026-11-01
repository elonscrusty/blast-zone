--!strict
-- Pure chunking of the ash cells for the client renderer (no Roblox types, Lune tests cover it).
--
-- The island is cut into square chunks of PER x PER cells. The renderer works per chunk:
--   * NEAR chunks (centre within the near radius) draw every cell in full detail
--   * FAR chunks (within the far radius, not near) draw one flat "tile" per chunk, a few blocks that
--     cover exactly the chunk's cells, so the blanket of ash reaches the horizon for a handful of
--     Parts instead of stopping at the detail radius
-- A chunk "layout" has the same shape as an ash Layout (cx, cz, zone, cellSize, cellsInRadius), so
-- CullLogic.update can track the near and far chunk sets exactly like it tracks cells.

export type CellLayout = {
	N: number,
	cx: { number },
	cz: { number },
	zone: { number },
	cellSize: number,
	x0: number,
	z0: number,
}

export type Chunks = {
	count: number,
	per: number,
	cx: { number }, -- chunk centre x
	cz: { number }, -- chunk centre z
	zone: { number }, -- most common zone of the chunk's cells
	cellSize: number, -- chunk side in studs
	parity: { number }, -- 0 / 1 checkerboard (edge neighbours differ)
	cells: { { number } }, -- chunk -> its cell indices
	chunkOf: { number }, -- cell -> chunk
	runs: { { number } }, -- chunk -> flat { x, z, sizeX, sizeZ, ... }: blocks covering its cells
	cellsInRadius: (x: number, z: number, radius: number) -> { number }, -- chunks, by centre
}

local AshChunks = {}

-- Cut `layout` into chunks of `per` x `per` cells.
function AshChunks.build(layout: CellLayout, per: number): Chunks
	local cs = layout.cellSize
	local side = cs * per
	local keyOf: { [number]: number } = {}
	local cx, cz, zone, parity = {}, {}, {}, {}
	local cells: { { number } } = {}
	local chunkOf: { number } = table.create(layout.N, 0)
	local gridX: { number } = {}
	local gridZ: { number } = {}
	local count = 0
	for i = 1, layout.N do
		local ix = math.floor((layout.cx[i] - layout.x0) / cs)
		local iz = math.floor((layout.cz[i] - layout.z0) / cs)
		local kx, kz = ix // per, iz // per
		local key = kz * 65536 + kx
		local c = keyOf[key]
		if c == nil then
			count += 1
			c = count
			keyOf[key] = c
			cx[c] = layout.x0 + (kx + 0.5) * side
			cz[c] = layout.z0 + (kz + 0.5) * side
			parity[c] = (kx + kz) % 2
			cells[c] = {}
			gridX[c], gridZ[c] = kx, kz
		end
		table.insert(cells[c], i)
		chunkOf[i] = c
	end

	local runs: { { number } } = {}
	for c = 1, count do
		-- most common zone
		local tally: { [number]: number } = {}
		local best, bestN = 0, -1
		for _, i in cells[c] do
			local zid = layout.zone[i]
			tally[zid] = (tally[zid] or 0) + 1
			if tally[zid] > bestN or (tally[zid] == bestN and zid < best) then
				best, bestN = zid, tally[zid]
			end
		end
		zone[c] = best

		-- rows of local columns, as bit masks (per <= 16)
		local rowMask: { number } = table.create(per, 0)
		for _, i in cells[c] do
			local lx = math.floor((layout.cx[i] - layout.x0) / cs) - gridX[c] * per
			local lz = math.floor((layout.cz[i] - layout.z0) / cs) - gridZ[c] * per
			rowMask[lz + 1] = bit32.bor(rowMask[lz + 1], bit32.lshift(1, lx))
		end
		-- each row's contiguous runs; identical runs in consecutive rows merge into one block
		local list: { number } = {}
		local open: { [number]: { number } } = {} -- (lo * 64 + hi) -> { lo, hi, z0row, rows }
		local function flush(key: number)
			local o = open[key]
			open[key] = nil
			local lo, hi, row0, rows = o[1], o[2], o[3], o[4]
			local bx0 = layout.x0 + (gridX[c] * per + lo) * cs
			local bz0 = layout.z0 + (gridZ[c] * per + row0) * cs
			local w, d = (hi - lo + 1) * cs, rows * cs
			table.insert(list, bx0 + w / 2)
			table.insert(list, bz0 + d / 2)
			table.insert(list, w)
			table.insert(list, d)
		end
		for lz = 0, per - 1 do
			local mask = rowMask[lz + 1]
			local here: { [number]: boolean } = {}
			local lx = 0
			while lx < per do
				if bit32.btest(mask, bit32.lshift(1, lx)) then
					local lo = lx
					while lx + 1 < per and bit32.btest(mask, bit32.lshift(1, lx + 1)) do
						lx += 1
					end
					local key = lo * 64 + lx
					here[key] = true
					local o = open[key]
					if o ~= nil and o[3] + o[4] == lz then
						o[4] += 1
					else
						if o ~= nil then
							flush(key)
						end
						open[key] = { lo, lx, lz, 1 }
					end
				end
				lx += 1
			end
			local stale: { number } = {}
			for key in open do
				if not here[key] then
					table.insert(stale, key)
				end
			end
			table.sort(stale)
			for _, key in stale do
				flush(key)
			end
		end
		local rest: { number } = {}
		for key in open do
			table.insert(rest, key)
		end
		table.sort(rest)
		for _, key in rest do
			flush(key)
		end
		runs[c] = list
	end

	local function cellsInRadius(x: number, z: number, radius: number): { number }
		local out: { number } = {}
		local r2 = radius * radius
		for c = 1, count do
			local dx, dz = cx[c] - x, cz[c] - z
			if dx * dx + dz * dz <= r2 then
				table.insert(out, c)
			end
		end
		return out
	end

	return {
		count = count,
		per = per,
		cx = cx,
		cz = cz,
		zone = zone,
		cellSize = side,
		parity = parity,
		cells = cells,
		chunkOf = chunkOf,
		runs = runs,
		cellsInRadius = cellsInRadius,
	}
end

return AshChunks
