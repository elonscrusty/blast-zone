--!strict
-- Pure logic for the client ash renderer and the auto-sweep check. No Roblox types.
--   * range tracking: which cells are inside the draw radius (with a hysteresis margin so cells at the
--     edge do not flicker in and out), reported as "entered" / "left" lists
--   * a de-duplicating FIFO work queue with a per-frame cap (batching)
--   * snapshot / delta decoding into a plain levels array
--   * slab size, deterministic colour variation, hex colour mixing
--   * `ashAhead`: is there ash in the sweep fan? (same geometry as AshGrid's cone query)

export type LayoutLike = {
	cx: { number },
	cz: { number },
	zone: { number },
	cellSize: number,
	cellsInRadius: (x: number, z: number, radius: number) -> { number },
}

export type Range = {
	active: { [number]: boolean },
	count: number,
	hasCentre: boolean,
	lastX: number,
	lastZ: number,
}

export type Queue = {
	push: (i: number) -> (),
	pop: () -> number?,
	size: () -> number,
	clear: () -> (),
}

local CullLogic = {}

local EMPTY: { number } = table.freeze({})

-- ===== range tracking =====

function CullLogic.newRange(): Range
	return { active = {}, count = 0, hasCentre = false, lastX = 0, lastZ = 0 }
end

-- Sort `list` of cell indices nearest to (x, z) first.
function CullLogic.sortByDistance(layout: LayoutLike, list: { number }, x: number, z: number)
	local cx, cz = layout.cx, layout.cz
	local d2: { [number]: number } = {}
	for _, i in list do
		local dx, dz = cx[i] - x, cz[i] - z
		d2[i] = dx * dx + dz * dz
	end
	table.sort(list, function(a, b)
		return (d2[a] :: number) < (d2[b] :: number)
	end)
end

-- Move the range centre to (x, z). A cell ENTERS when it is within `radius`; an active cell LEAVES
-- only when it is farther than `radius + margin`. When the centre moved less than `minMove` since
-- the last real update nothing is recomputed and two frozen empty lists come back.
-- `entered` is sorted nearest first. The lists are fresh tables unless they are the frozen empties.
function CullLogic.update(
	layout: LayoutLike,
	range: Range,
	x: number,
	z: number,
	radius: number,
	margin: number,
	minMove: number
): ({ number }, { number })
	if x ~= x or z ~= z then
		return EMPTY, EMPTY
	end
	if range.hasCentre then
		local mx, mz = x - range.lastX, z - range.lastZ
		if mx * mx + mz * mz < minMove * minMove then
			return EMPTY, EMPTY
		end
	end
	range.hasCentre = true
	range.lastX, range.lastZ = x, z

	local active = range.active
	local entered: { number } = {}
	for _, i in layout.cellsInRadius(x, z, radius) do
		if not active[i] then
			active[i] = true
			range.count += 1
			table.insert(entered, i)
		end
	end
	if #entered > 1 then
		CullLogic.sortByDistance(layout, entered, x, z)
	end

	local left: { number } = {}
	local keep = radius + margin
	local keep2 = keep * keep
	local cx, cz = layout.cx, layout.cz
	for i in active do
		local dx, dz = cx[i] - x, cz[i] - z
		if dx * dx + dz * dz > keep2 then
			table.insert(left, i)
		end
	end
	for _, i in left do
		active[i] = nil
	end
	range.count -= #left
	return entered, left
end

-- ===== work queue (batching) =====

-- FIFO of cell indices; pushing an index that is already waiting does nothing.
function CullLogic.newQueue(): Queue
	local items: { number } = {}
	local queued: { [number]: boolean } = {}
	local head, tail = 1, 0
	return {
		push = function(i: number)
			if queued[i] then
				return
			end
			queued[i] = true
			tail += 1
			items[tail] = i
		end,
		pop = function(): number?
			if head > tail then
				return nil
			end
			local i = items[head]
			items[head] = nil
			head += 1
			queued[i] = nil
			if head > tail then
				head, tail = 1, 0
			end
			return i
		end,
		size = function(): number
			return tail - head + 1
		end,
		clear = function()
			items = {}
			queued = {}
			head, tail = 1, 0
		end,
	}
end

-- Call fn(i) for up to `maxCount` queued items, oldest first. If fn returns false the loop stops
-- after that item (use it for a time budget). Returns how many items were handed out.
function CullLogic.drain(queue: Queue, maxCount: number, fn: (i: number) -> boolean?): number
	local n = 0
	while n < maxCount do
		local i = queue.pop()
		if i == nil then
			break
		end
		n += 1
		if fn(i) == false then
			break
		end
	end
	return n
end

-- ===== snapshot / delta =====

-- Decode an AshSnapshot string (one char per cell, level = byte - 48) into a new levels array.
-- Returns nil when the length is wrong or a char is out of 0..maxLevel.
function CullLogic.decodeSnapshot(s: any, n: number, maxLevel: number): { number }?
	if type(s) ~= "string" or #s ~= n then
		return nil
	end
	local out = table.create(n, 0)
	for j = 1, n do
		local v = string.byte(s, j) - 48
		if v < 0 or v > maxLevel then
			return nil
		end
		out[j] = v
	end
	return out
end

-- Apply flat pairs {idx, level, ...} to `levels` in place. Bad entries are skipped. Calls
-- onChange(i, old, new) for every cell whose level really changed. Returns the number applied.
function CullLogic.applyDelta(
	levels: { number },
	flat: any,
	n: number,
	maxLevel: number,
	onChange: ((i: number, old: number, new: number) -> ())?
): number
	if type(flat) ~= "table" then
		return 0
	end
	local applied = 0
	local len = #flat
	for k = 1, len - 1, 2 do
		local i, level = flat[k], flat[k + 1]
		if
			type(i) == "number"
			and type(level) == "number"
			and i == math.floor(i)
			and i >= 1
			and i <= n
			and level == level
		then
			local new = math.clamp(math.floor(level), 0, maxLevel)
			local old = levels[i]
			applied += 1
			if old ~= new then
				levels[i] = new
				if onChange ~= nil then
					onChange(i, old, new)
				end
			end
		end
	end
	return applied
end

-- ===== looks =====

-- Slab height in studs for a level 0..9 (0 = flat film, hidden by the renderer).
function CullLogic.slabHeight(level: number): number
	if level <= 0 then
		return 0
	end
	return 0.15 + level * 0.28
end

-- Footprint of one slab: a little smaller than the cell so a thin crack of ground shows.
function CullLogic.slabSize(cellSize: number): number
	return cellSize - 0.4
end

-- Deterministic pseudo-random number in [-1, 1] for a cell index (no rng state needed).
function CullLogic.variation(i: number): number
	local h = (i * 2654435761) % 4294967296
	h = (h + 0x9E3779B9) % 4294967296
	h = (bit32.bxor(h, bit32.rshift(h, 15)) * 2246822519) % 4294967296
	return (h / 4294967296) * 2 - 1
end

-- "#RRGGBB" -> r, g, b (0..255). Bad text gives mid grey.
function CullLogic.parseHex(hex: string): (number, number, number)
	local r, g, b = string.match(hex, "^#?(%x%x)(%x%x)(%x%x)$")
	if r == nil or g == nil or b == nil then
		return 128, 128, 128
	end
	return tonumber(r, 16) :: number, tonumber(g, 16) :: number, tonumber(b, 16) :: number
end

local function toHex(r: number, g: number, b: number): string
	return string.format(
		"#%02X%02X%02X",
		math.clamp(math.floor(r + 0.5), 0, 255),
		math.clamp(math.floor(g + 0.5), 0, 255),
		math.clamp(math.floor(b + 0.5), 0, 255)
	)
end

-- Brighten (v > 0) or darken (v < 0) a colour by a fraction, e.g. shade(hex, 0.05).
function CullLogic.shade(hex: string, v: number): (number, number, number)
	local r, g, b = CullLogic.parseHex(hex)
	local f = 1 + v
	return math.clamp(math.floor(r * f + 0.5), 0, 255),
		math.clamp(math.floor(g * f + 0.5), 0, 255),
		math.clamp(math.floor(b * f + 0.5), 0, 255)
end

-- Blend two hex colours; t = 0 gives a, t = 1 gives b.
function CullLogic.mixHex(a: string, b: string, t: number): string
	local ar, ag, ab = CullLogic.parseHex(a)
	local br, bg, bb = CullLogic.parseHex(b)
	local k = math.clamp(t, 0, 1)
	return toHex(ar + (br - ar) * k, ag + (bg - ag) * k, ab + (bb - ab) * k)
end

-- ===== sweep fan =====

-- True when some cell in the fan in front of (px, pz) facing (dx, dz) has level > 0 and its zone is
-- in `allowed`. Geometry: a cell counts when its centre is within one cell size of the player, or
-- within `reach + half a cell` and inside the fan. That is a slightly generous SUPERSET of the
-- server's cone (AshGrid.queryCone, measured to the centre or to the edge): Auto-Sweep must never
-- miss ash the server would sweep; a rare extra swing that finds nothing costs nothing.
function CullLogic.ashAhead(
	layout: LayoutLike,
	levels: { number },
	px: number,
	pz: number,
	dx: number,
	dz: number,
	reach: number,
	arcDeg: number,
	allowed: { [number]: boolean }
): boolean
	local cs = layout.cellSize
	local cx, cz, zone = layout.cx, layout.cz, layout.zone
	local len = math.sqrt(dx * dx + dz * dz)
	local useArc = arcDeg < 360 and len > 1e-6
	local ndx, ndz, cosHalf = 0, 0, -1
	if useArc then
		ndx, ndz = dx / len, dz / len
		cosHalf = math.cos(math.rad(arcDeg * 0.5))
	end
	local far = reach + cs * 0.5
	local reach2 = far * far
	local near2 = cs * cs
	for _, j in layout.cellsInRadius(px, pz, math.max(far, cs)) do
		local level = levels[j]
		if level ~= nil and level > 0 and allowed[zone[j]] then
			local ddx, ddz = cx[j] - px, cz[j] - pz
			local d2 = ddx * ddx + ddz * ddz
			local ok = d2 <= near2
			if not ok and d2 <= reach2 then
				if useArc then
					ok = ddx * ndx + ddz * ndz >= cosHalf * math.sqrt(d2)
				else
					ok = true
				end
			end
			if ok then
				return true
			end
		end
	end
	return false
end

return CullLogic
