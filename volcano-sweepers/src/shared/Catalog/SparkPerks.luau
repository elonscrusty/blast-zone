--!strict
-- The Spark Shop: permanent perks bought with Sparks. They survive Cool Down.
-- `perLevel` is the effect of one level; Rules/StatsCalc and Rules/Economy read it through
-- SparkPerks.value(). cost(id, currentLevel) is the Spark price of the NEXT level.

export type Perk = {
	id: string,
	name: string,
	desc: string,
	maxLevel: number,
	stat: string,
	perLevel: number,
	label: string,
	costs: { number }, -- costs[n] = Sparks to reach level n
}

local SparkPerks = {}

SparkPerks.list = {
	{
		id = "head_start",
		name = "Head Start",
		desc = "Start every run with a pocket of coins.",
		maxLevel = 8,
		stat = "startCoins",
		perLevel = 250, -- see SparkPerks.value: grows each level
		label = "starting coins",
		costs = { 2, 3, 5, 8, 12, 18, 26, 38 },
	},
	{
		id = "big_pockets",
		name = "Big Pockets",
		desc = "Start with a roomier backpack.",
		maxLevel = 8,
		stat = "capacity",
		perLevel = 10,
		label = "backpack space",
		costs = { 2, 3, 4, 6, 9, 13, 19, 28 },
	},
	{
		id = "free_push",
		name = "Free Push Broom",
		desc = "Every run starts with a Push Broom already in your hand.",
		maxLevel = 1,
		stat = "freePush",
		perLevel = 1,
		label = "free Push Broom",
		costs = { 3 },
	},
	{
		id = "lucky_charm",
		name = "Lucky Charm",
		desc = "Find treasure more often.",
		maxLevel = 10,
		stat = "luck",
		perLevel = 0.1,
		label = "treasure luck",
		costs = { 2, 3, 4, 6, 8, 11, 15, 20, 27, 36 },
	},
	{
		id = "quick_feet",
		name = "Quick Feet",
		desc = "Run a little faster, forever.",
		maxLevel = 8,
		stat = "walkSpeed",
		perLevel = 0.5,
		label = "walk speed",
		costs = { 2, 3, 5, 7, 10, 14, 20, 28 },
	},
	{
		id = "haggler",
		name = "Haggler",
		desc = "Upgrades cost less coins. Up to 15% off!",
		maxLevel = 10,
		stat = "upgradeDiscount",
		perLevel = 0.015,
		label = "cheaper upgrades",
		costs = { 3, 4, 6, 8, 11, 15, 20, 27, 36, 48 },
	},
	{
		id = "bot_boost",
		name = "Bot Boost",
		desc = "Your helper bots sweep faster.",
		maxLevel = 10,
		stat = "helperPower",
		perLevel = 0.1,
		label = "helper power",
		costs = { 2, 3, 4, 6, 8, 11, 15, 20, 27, 36 },
	},
	{
		id = "long_buffs",
		name = "Long Buffs",
		desc = "Party and Perfect Dodge boosts last longer.",
		maxLevel = 8,
		stat = "buffTime",
		perLevel = 0.1,
		label = "longer buffs",
		costs = { 2, 3, 5, 7, 10, 14, 20, 28 },
	},
} :: { Perk }

SparkPerks.byId = {} :: { [string]: Perk }
SparkPerks.order = {} :: { string }
for _, perk in SparkPerks.list do
	SparkPerks.byId[perk.id] = perk
	table.insert(SparkPerks.order, perk.id)
end

local function clampLevel(perk: Perk, level: number): number
	if level ~= level then
		return 0
	end
	return math.clamp(math.floor(level), 0, perk.maxLevel)
end

-- Sparks for the NEXT level when at `currentLevel`, or nil at max / unknown perk.
function SparkPerks.cost(id: string, currentLevel: number): number?
	local perk = SparkPerks.byId[id]
	if not perk or currentLevel ~= currentLevel then
		return nil
	end
	local lv = math.max(0, math.floor(currentLevel))
	if lv >= perk.maxLevel then
		return nil
	end
	return perk.costs[lv + 1]
end

-- Total Sparks already spent to reach these perk levels (so spending Sparks never lowers the
-- permanent coin bonus: the bonus counts unspent + spent Sparks).
function SparkPerks.spent(levels: { [string]: number }): number
	local total = 0
	for _, perk in SparkPerks.list do
		local v = levels[perk.id]
		local lv = if type(v) == "number" and v == v then clampLevel(perk, v) else 0
		for i = 1, lv do
			total += perk.costs[i]
		end
	end
	return total
end

-- Effect at `level`. Head Start is 250 x level x (level + 1) / 2 (250, 750, 1500, 2500 ...).
-- Free Push Broom is 1 at level 1. Everything else is level x perLevel.
function SparkPerks.value(id: string, level: number): number
	local perk = SparkPerks.byId[id]
	if not perk then
		return 0
	end
	local lv = clampLevel(perk, level)
	if id == "head_start" then
		return perk.perLevel * lv * (lv + 1) / 2
	end
	return perk.perLevel * lv
end

-- "+10% treasure luck" style text for the Spark Shop at `level`.
function SparkPerks.effectText(id: string, level: number): string
	local perk = SparkPerks.byId[id]
	if not perk then
		return ""
	end
	local v = SparkPerks.value(id, level)
	if perk.stat == "startCoins" or perk.stat == "capacity" then
		return `+{math.floor(v + 0.5)} {perk.label}`
	elseif perk.stat == "walkSpeed" then
		return `+{math.floor(v * 10 + 0.5) / 10} {perk.label}`
	elseif perk.stat == "freePush" then
		return if clampLevel(perk, level) >= 1 then "Push Broom included" else "No free broom yet"
	end
	return `+{math.floor(v * 1000 + 0.5) / 10}% {perk.label}`
end

return SparkPerks
