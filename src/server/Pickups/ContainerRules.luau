--!strict
-- Container health, loot tiers and drop layout with no game objects in it, so Lune can test it.

local ContainerRules = {}

export type Offset = { x: number, z: number }

-- Takes damage off a container. Returns the new health and whether THIS hit broke it.
-- A container at 0 can never break again. Bad numbers do nothing.
function ContainerRules.applyDamage(health: number, amount: number): (number, boolean)
	if health <= 0 then
		return 0, false
	end
	if amount ~= amount or amount <= 0 or amount == math.huge then
		return health, false
	end
	local left = math.max(0, health - amount)
	return left, left <= 0
end

-- Picks a tier by weight (`weightOf` answers for a tier id). `roll` is a random number from 0 up to (not including) 1; it is passed in
-- so tests can aim it. A bad roll, or weights that add up to nothing, gives the first tier.
function ContainerRules.pickTier(
	order: { string },
	weightOf: (string) -> number,
	roll: number
): string
	local total = 0
	for _, id in order do
		total += math.max(0, weightOf(id))
	end
	if total <= 0 or roll ~= roll then
		return order[1]
	end
	local target = math.clamp(roll, 0, 0.999999) * total
	local run = 0
	for _, id in order do
		run += math.max(0, weightOf(id))
		if target < run then
			return id
		end
	end
	return order[#order]
end

-- Spreads `count` drops evenly on a ring around the container. `phase` turns the whole ring.
function ContainerRules.scatter(count: number, radius: number, phase: number): { Offset }
	local out: { Offset } = {}
	for i = 1, count do
		local angle = phase + (i - 1) * (2 * math.pi / count)
		out[i] = { x = math.cos(angle) * radius, z = math.sin(angle) * radius }
	end
	return out
end

return ContainerRules
