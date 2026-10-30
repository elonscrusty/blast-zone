--!strict
-- Keeps every effect inside its cap. Pure: the clock is passed in, so tests can run it.
-- An effect asks for what it wants ("30 particles for 0.9 seconds") and gets back what it may have.
-- It can be less than it asked for, or nothing, when the arena is already full of effects.

export type Caps = { [string]: number }
export type Take = { cost: number, expiresAt: number }
export type Budget = {
	caps: Caps,
	live: { [string]: { Take } },
}

local FxBudget = {}

function FxBudget.new(caps: Caps): Budget
	return { caps = caps, live = {} }
end

local function prune(b: Budget, category: string, now: number): { Take }
	local list = b.live[category]
	if list == nil then
		list = {}
		b.live[category] = list
	end
	local kept = {}
	for _, take in list :: { Take } do
		if take.expiresAt > now then
			table.insert(kept, take)
		end
	end
	b.live[category] = kept
	return kept
end

-- How much of this category is in use right now.
function FxBudget.used(b: Budget, category: string, now: number): number
	local total = 0
	for _, take in prune(b, category, now) do
		total += take.cost
	end
	return total
end

-- Asks for `want` of a category for `seconds`. Returns how much was granted (0 up to want).
-- Whole numbers only, because particles and parts are counted one by one.
function FxBudget.tryTake(
	b: Budget,
	category: string,
	want: number,
	now: number,
	seconds: number
): number
	local cap = b.caps[category]
	if cap == nil then
		error("FxBudget: unknown category '" .. category .. "'", 2)
	end
	want = math.floor(want)
	if want <= 0 then
		return 0
	end
	local room = cap - FxBudget.used(b, category, now)
	local granted = math.max(0, math.min(want, math.floor(room)))
	if granted > 0 then
		table.insert(b.live[category], { cost = granted, expiresAt = now + math.max(seconds, 0) })
	end
	return granted
end

-- Forgets every take (the match reset, so nothing is still on screen).
function FxBudget.clear(b: Budget)
	table.clear(b.live)
end

return FxBudget
