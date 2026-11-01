--!strict
-- The ash on the island: one level (0..maxUnitsPerCell) per cell of Ash/Layout. Pure logic, no
-- Roblox types. The server is the only writer; clients mirror it with decode / applyDelta.
--
-- Everything that changes a level goes through `write`, which keeps the per-zone unit totals, the
-- dirty list (for network deltas) and the golden flags consistent.

local Config = require("../Config")
local Layout = require("./Layout")
local Rng = require("../Rng")

type Rng = Rng.Rng
type LayoutData = Layout.LayoutData

export type Tool = { reach: number, arcDeg: number, power: number }

export type SweepResult = {
	changed: { number }, -- cell indices whose level dropped (nearest first)
	perCell: { number }, -- units removed from changed[k]
	removedUnits: number, -- total units taken into the backpack
	valueUnits: number, -- sum of units x zoneValue (x goldenMult on golden cells)
	clearedCells: { number }, -- cells this sweep took to bare ground (level 0)
	goldenCleared: number, -- golden cells emptied by this sweep
	sweetHits: number, -- cells that got the sweet-spot double clear
	full: boolean, -- capacity ran out
}

export type AshGrid = {
	layout: LayoutData,
	N: number,
	max: number,
	levels: { number },
	zoneUnits: { number }, -- zone id -> units on the ground now
	totalUnits: number,
	goldenSet: { [number]: boolean },
	goldenCount: number,
	goldenMult: number,
	dirtyFlag: { boolean },
	dirtyList: { number },

	get: (self: AshGrid, i: number) -> number,
	set: (self: AshGrid, i: number, level: number) -> boolean,
	remove: (self: AshGrid, i: number, n: number) -> number,
	add: (self: AshGrid, i: number, n: number) -> number,
	queryCone: (
		self: AshGrid,
		px: number,
		pz: number,
		dx: number,
		dz: number,
		reach: number,
		arcDeg: number
	) -> { number },
	sweep: (
		self: AshGrid,
		px: number,
		pz: number,
		dx: number,
		dz: number,
		tool: Tool,
		allowedZones: { [number]: boolean },
		capacityLeft: number,
		rng: Rng,
		sweetSpot: number,
		zoneValues: { [number]: number }?
	) -> SweepResult,
	regrow: (self: AshGrid, rng: Rng, count: number, zonesBias: { [number]: number }?) -> number,
	rain: (self: AshGrid, rng: Rng, fraction: number) -> number,
	spawnGolden: (
		self: AshGrid,
		rng: Rng,
		count: number,
		allowedZones: { [number]: boolean }?
	) -> { number },
	clearGolden: (self: AshGrid) -> { number },
	isGolden: (self: AshGrid, i: number) -> boolean,
	encode: (self: AshGrid) -> string,
	decode: (self: AshGrid, s: string) -> boolean,
	applyDelta: (self: AshGrid, flat: { number }) -> number,
	takeDirty: (self: AshGrid) -> { number },
	zoneClean: (self: AshGrid, zone: number) -> number,
	totalClean: (self: AshGrid) -> number,
}

local AshGrid = {}

local MAX_UNITS: number = Config.World.maxUnitsPerCell
local GOLDEN_MULT = 5
local GOLDEN_MIN_LEVEL = 6 -- a freshly flagged golden cell is topped up to at least this

local CHARS: { string } = {}
for level = 0, MAX_UNITS do
	CHARS[level] = string.char(48 + level)
end

-- scratch buffers for cone queries (reused; results are copied out before returning)
local scratchIdx: { number } = {}
local scratchD2: { number } = {}

local function clampLevel(level: number, max: number): number
	if level ~= level then
		return 0
	end
	return math.clamp(math.floor(level), 0, max)
end

-- The one place a level changes. Returns true when it actually changed.
local function write(self: AshGrid, i: number, new: number): boolean
	local old = self.levels[i]
	if old == new then
		return false
	end
	self.levels[i] = new
	local diff = new - old
	local z = self.layout.zone[i]
	self.zoneUnits[z] += diff
	self.totalUnits += diff
	if not self.dirtyFlag[i] then
		self.dirtyFlag[i] = true
		table.insert(self.dirtyList, i)
	end
	if new == 0 and self.goldenSet[i] then
		self.goldenSet[i] = nil
		self.goldenCount -= 1
	end
	return true
end

-- Fill the scratch buffers with every cell in the cone, sorted nearest first. Returns the count.
local function collectCone(
	self: AshGrid,
	px: number,
	pz: number,
	dx: number,
	dz: number,
	reach: number,
	arcDeg: number
): number
	local L = self.layout
	local cs = L.cellSize
	local cols = L.cols
	local x0, z0 = L.x0, L.z0
	local lookup, cx, cz = L.lookup, L.cx, L.cz
	local searchR = math.max(reach, cs)
	local reach2 = reach * reach
	local near2 = cs * cs

	local len = math.sqrt(dx * dx + dz * dz)
	local useArc = arcDeg < 360 and len > 1e-6
	local ndx, ndz, cosHalf = 0, 0, -1
	if useArc then
		ndx, ndz = dx / len, dz / len
		cosHalf = math.cos(math.rad(arcDeg * 0.5))
	end

	local ixLo = math.max(0, math.floor((px - searchR - x0) / cs))
	local ixHi = math.min(cols - 1, math.floor((px + searchR - x0) / cs))
	local izLo = math.max(0, math.floor((pz - searchR - z0) / cs))
	local izHi = math.min(cols - 1, math.floor((pz + searchR - z0) / cs))

	local n = 0
	for iz = izLo, izHi do
		local rowBase = iz * cols + 1
		for ix = ixLo, ixHi do
			local j = lookup[rowBase + ix]
			if j ~= 0 then
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
					-- insertion sort by distance
					local k = n
					while k >= 1 and scratchD2[k] > d2 do
						scratchD2[k + 1] = scratchD2[k]
						scratchIdx[k + 1] = scratchIdx[k]
						k -= 1
					end
					scratchD2[k + 1] = d2
					scratchIdx[k + 1] = j
					n += 1
				end
			end
		end
	end
	return n
end

local methods = {}

function methods.get(self: AshGrid, i: number): number
	return self.levels[i] or 0
end

function methods.set(self: AshGrid, i: number, level: number): boolean
	if i ~= i or i < 1 or i > self.N or i ~= math.floor(i) then
		return false
	end
	return write(self, i, clampLevel(level, self.max))
end

function methods.remove(self: AshGrid, i: number, n: number): number
	if i ~= i or i < 1 or i > self.N or n ~= n or n <= 0 then
		return 0
	end
	local old = self.levels[i]
	local take = math.min(old, math.floor(n))
	if take > 0 then
		write(self, i, old - take)
	end
	return take
end

function methods.add(self: AshGrid, i: number, n: number): number
	if i ~= i or i < 1 or i > self.N or n ~= n or n <= 0 then
		return 0
	end
	local old = self.levels[i]
	local put = math.min(self.max - old, math.floor(n))
	if put > 0 then
		write(self, i, old + put)
	end
	return put
end

function methods.queryCone(
	self: AshGrid,
	px: number,
	pz: number,
	dx: number,
	dz: number,
	reach: number,
	arcDeg: number
): { number }
	local n = collectCone(self, px, pz, dx, dz, reach, arcDeg)
	local out = table.create(n)
	for k = 1, n do
		out[k] = scratchIdx[k]
	end
	return out
end

function methods.sweep(
	self: AshGrid,
	px: number,
	pz: number,
	dx: number,
	dz: number,
	tool: Tool,
	allowedZones: { [number]: boolean },
	capacityLeft: number,
	rng: Rng,
	sweetSpot: number,
	zoneValues: { [number]: number }?
): SweepResult
	local result: SweepResult = {
		changed = {},
		perCell = {},
		removedUnits = 0,
		valueUnits = 0,
		clearedCells = {},
		goldenCleared = 0,
		sweetHits = 0,
		full = false,
	}
	local room = capacityLeft ~= capacityLeft and 0 or math.floor(capacityLeft)
	if room <= 0 then
		result.full = true
		return result
	end
	local power = tool.power
	if power ~= power or power <= 0 then
		return result
	end
	local whole = math.floor(power)
	local frac = power - whole

	local n = collectCone(self, px, pz, dx, dz, tool.reach, tool.arcDeg)
	local levels, zoneOf = self.levels, self.layout.zone
	local changed, perCell, cleared = result.changed, result.perCell, result.clearedCells
	local removedTotal, value = 0, 0
	for k = 1, n do
		local j = scratchIdx[k]
		local level = levels[j]
		local z = zoneOf[j]
		if level > 0 and allowedZones[z] then
			local amount = whole
			if frac > 0 and rng:next() < frac then
				amount += 1
			end
			if sweetSpot > 0 and rng:next() < sweetSpot then
				amount *= 2
				result.sweetHits += 1
			end
			if amount > 0 then
				local take = math.min(amount, level, room)
				local wasGolden = self.goldenSet[j] == true
				write(self, j, level - take)
				room -= take
				removedTotal += take
				local unitValue = zoneValues and zoneValues[z] or 1
				if wasGolden then
					unitValue *= self.goldenMult
					if level - take == 0 then
						result.goldenCleared += 1
					end
				end
				value += take * unitValue
				table.insert(changed, j)
				table.insert(perCell, take)
				if level - take == 0 then
					table.insert(cleared, j)
				end
				if room <= 0 then
					result.full = true
					break
				end
			end
		end
	end
	result.removedUnits = removedTotal
	result.valueUnits = value
	return result
end

function methods.regrow(
	self: AshGrid,
	rng: Rng,
	count: number,
	zonesBias: { [number]: number }?
): number
	local L = self.layout
	-- zone weights: emptier zones (more room to grow) get picked more often
	local ids, weights = {}, {}
	local totalW = 0
	for _, z in L.zoneIds do
		local cells = L.zoneCount[z]
		local fill = if cells > 0 then self.zoneUnits[z] / (cells * self.max) else 1
		if fill < 1 then
			local w = (1 - fill) + 0.05
			if zonesBias and zonesBias[z] then
				w *= math.max(0, zonesBias[z])
			end
			if w > 0 then
				table.insert(ids, z)
				table.insert(weights, w)
				totalW += w
			end
		end
	end
	if totalW <= 0 then
		return 0
	end
	local added = 0
	for _ = 1, math.floor(count) do
		local r = rng:next() * totalW
		local z = ids[#ids]
		for k, w in weights do
			r -= w
			if r < 0 then
				z = ids[k]
				break
			end
		end
		local list = L.zoneCells[z]
		for _ = 1, 8 do
			local j = list[rng:int(1, #list)]
			if self.levels[j] < self.max then
				write(self, j, self.levels[j] + 1)
				added += 1
				break
			end
		end
	end
	return added
end

function methods.rain(self: AshGrid, rng: Rng, fraction: number): number
	local added = 0
	if fraction ~= fraction or fraction <= 0 then
		return 0
	end
	local levels, max = self.levels, self.max
	for j = 1, self.N do
		if rng:next() < fraction then
			local level = levels[j]
			if level < max then
				local put = math.min(max - level, rng:int(1, 2))
				write(self, j, level + put)
				added += put
			end
		end
	end
	return added
end

-- Flag `count` random cells in allowed zones as golden (worth goldenMult x). Each is topped up so it
-- is worth racing for. The caller owns the expiry: call clearGolden() when the event ends.
function methods.spawnGolden(
	self: AshGrid,
	rng: Rng,
	count: number,
	allowedZones: { [number]: boolean }?
): { number }
	local picked: { number } = {}
	local tries = 0
	local want = math.floor(count)
	while #picked < want and tries < want * 20 + 40 do
		tries += 1
		local j = rng:int(1, self.N)
		if not self.goldenSet[j] and (allowedZones == nil or allowedZones[self.layout.zone[j]]) then
			self.goldenSet[j] = true
			self.goldenCount += 1
			if self.levels[j] < GOLDEN_MIN_LEVEL then
				write(self, j, GOLDEN_MIN_LEVEL)
			end
			table.insert(picked, j)
		end
	end
	return picked
end

function methods.clearGolden(self: AshGrid): { number }
	local out: { number } = {}
	for j in self.goldenSet do
		table.insert(out, j)
	end
	table.sort(out)
	self.goldenSet = {}
	self.goldenCount = 0
	return out
end

function methods.isGolden(self: AshGrid, i: number): boolean
	return self.goldenSet[i] == true
end

function methods.encode(self: AshGrid): string
	local parts = table.create(self.N)
	local levels = self.levels
	for j = 1, self.N do
		parts[j] = CHARS[levels[j]]
	end
	return table.concat(parts)
end

-- Replace every level from a snapshot string. Returns false (and changes nothing) if it is invalid.
function methods.decode(self: AshGrid, s: string): boolean
	if type(s) ~= "string" or #s ~= self.N then
		return false
	end
	local lv = table.create(self.N)
	for j = 1, self.N do
		local v = string.byte(s, j) - 48
		if v < 0 or v > self.max then
			return false
		end
		lv[j] = v
	end
	for j = 1, self.N do
		write(self, j, lv[j])
	end
	return true
end

-- Apply {idx, level, idx, level, ...}. Bad entries are skipped. Returns how many were applied.
function methods.applyDelta(self: AshGrid, flat: { number }): number
	local applied = 0
	for k = 1, #flat - 1, 2 do
		local i, level = flat[k], flat[k + 1]
		if
			type(i) == "number"
			and type(level) == "number"
			and i == math.floor(i)
			and i >= 1
			and i <= self.N
			and level == level
		then
			write(self, i, clampLevel(level, self.max))
			applied += 1
		end
	end
	return applied
end

-- Everything that changed since the last call, as {idx, level, idx, level, ...}; clears the list.
function methods.takeDirty(self: AshGrid): { number }
	local list = self.dirtyList
	local flat = table.create(#list * 2)
	local levels, flags = self.levels, self.dirtyFlag
	for k, j in list do
		flat[k * 2 - 1] = j
		flat[k * 2] = levels[j]
		flags[j] = false
	end
	self.dirtyList = {}
	return flat
end

-- Share of ash removed: 1 = bare ground, 0 = every cell full. Unknown zone counts as clean.
function methods.zoneClean(self: AshGrid, zone: number): number
	local cells = self.layout.zoneCount[zone]
	if cells == nil or cells == 0 then
		return 1
	end
	return math.clamp(1 - self.zoneUnits[zone] / (cells * self.max), 0, 1)
end

function methods.totalClean(self: AshGrid): number
	if self.N == 0 then
		return 1
	end
	return math.clamp(1 - self.totalUnits / (self.N * self.max), 0, 1)
end

-- initialFill: "full" | "empty" | a level 0..max. `layout` is only passed by tests with a small island.
function AshGrid.new(initialFill: string | number, layout: LayoutData?): AshGrid
	local L = layout or Layout
	local level = 0
	if initialFill == "full" then
		level = MAX_UNITS
	elseif type(initialFill) == "number" then
		level = clampLevel(initialFill, MAX_UNITS)
	end
	local levels = table.create(L.N, level)
	local zoneUnits: { number } = {}
	for _, z in L.zoneIds do
		zoneUnits[z] = L.zoneCount[z] * level
	end
	local self = {
		layout = L,
		N = L.N,
		max = MAX_UNITS,
		levels = levels,
		zoneUnits = zoneUnits,
		totalUnits = L.N * level,
		goldenSet = {},
		goldenCount = 0,
		goldenMult = GOLDEN_MULT,
		dirtyFlag = table.create(L.N, false),
		dirtyList = {},
	}
	return setmetatable(self, { __index = methods }) :: any
end

return AshGrid
