--!strict
-- Loot maths with no game objects in it, so Lune can test it (piece 42).
-- `roll` is any function that returns a number in [0, 1).

local LootRules = {}

export type Spot = { x: number, z: number, y: number? }

-- One more heal pack. Returns the new count and whether it was taken (a full pack bag says no).
function LootRules.addPack(count: number, max: number): (number, boolean)
	if count >= max then
		return count, false
	end
	return count + 1, true
end

-- May a fighter use a pack now? Returns true, or false and why:
-- "none" (no pack), "down" (already out), "full" (health is full: do not waste it), "cooling".
function LootRules.canUse(
	count: number,
	health: number,
	maxHealth: number,
	now: number,
	readyAt: number
): (boolean, string?)
	if count <= 0 then
		return false, "none"
	end
	if health <= 0 then
		return false, "down"
	end
	if health >= maxHealth then
		return false, "full"
	end
	if now < readyAt then
		return false, "cooling"
	end
	return true, nil
end

-- Takes up to `wanted` spots from `candidates`, in a random order, keeping each at least
-- `minSeparation` away from the ones already taken (and from `taken`, if given).
function LootRules.pickSpots(
	candidates: { Spot },
	wanted: number,
	minSeparation: number,
	roll: () -> number,
	taken: { Spot }?
): { Spot }
	local pool = table.clone(candidates)
	for i = #pool, 2, -1 do
		local j = math.floor(roll() * i) + 1
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out: { Spot } = {}
	local keep = minSeparation * minSeparation
	local function farFrom(list: { Spot }, c: Spot): boolean
		for _, o in list do
			local dx, dz = o.x - c.x, o.z - c.z
			if dx * dx + dz * dz < keep then
				return false
			end
		end
		return true
	end
	for _, c in pool do
		if #out >= wanted then
			break
		end
		if farFrom(out, c) and (taken == nil or farFrom(taken, c)) then
			table.insert(out, c)
		end
	end
	return out
end

-- A floor gun by weight (equal weights = 1 in 3 each). nil only if no gun has weight.
function LootRules.pickGun(cfg: any, roll: number): string?
	local g = cfg.Loot.floorGuns
	local total = 0
	for _, id in g.order do
		total += g.weights[id] or 0
	end
	if total <= 0 then
		return nil
	end
	local at = roll * total
	local last: string? = nil
	for _, id in g.order do
		local w = g.weights[id] or 0
		if w > 0 then
			last = id
			if at < w then
				return id
			end
			at -= w
		end
	end
	return last
end

-- Where a spot goes for angle step `i` of `n` around a marker at (x, z), `offset` studs away.
function LootRules.ringPoint(
	x: number,
	z: number,
	offset: number,
	i: number,
	n: number,
	phase: number
): Spot
	local a = phase + (i - 1) / n * 2 * math.pi
	return { x = x + math.cos(a) * offset, z = z + math.sin(a) * offset }
end

return LootRules
