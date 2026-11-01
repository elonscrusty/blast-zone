--!strict
-- The ten coin-sink upgrade lines. Every line has 12-20 levels. Level n costs
-- floor(baseCost * growth^(n-1) + 0.5) coins (growth is 1.25-1.4), always a whole number, always
-- more than the level before. Every level adds `perLevel` to its bonus, so a higher level always
-- helps. How the bonus is used (see Rules/StatsCalc):
--   power       sweep power   x (1 + bonus)
--   speed       swing speed   interval / (1 + bonus)
--   reach       reach         x (1 + bonus)
--   backpack    capacity      x (1 + bonus)
--   walk        walk speed    x (1 + bonus)
--   sell        coin sell mult: + bonus (added to the other sell bonuses)
--   luck        find luck     1 + bonus
--   armor       share of carried ash kept when hit (bonus, max Config.Player.maxArmor)
--   sweetspot   chance a swing clears double
--   lucky_coins chance a sale pays double

local Config = require("../Config")

export type Upgrade = {
	id: string,
	name: string,
	desc: string,
	maxLevel: number,
	stat: string, -- the Derived key it changes
	perLevel: number, -- bonus added per level (0.08 = 8%)
	label: string, -- text after the number in "+8% reach"
	baseCost: number,
	growth: number,
	cap: number?, -- the bonus never goes above this
}

local Upgrades = {}

Upgrades.list = {
	{
		id = "power",
		name = "Sweep Power",
		desc = "Each swing clears more ash from every spot.",
		maxLevel = 16,
		stat = "power",
		perLevel = 0.08,
		label = "sweep power",
		baseCost = 12,
		growth = 1.38,
	},
	{
		id = "backpack",
		name = "Backpack Size",
		desc = "A bigger backpack carries more ash per trip.",
		maxLevel = 20,
		stat = "capacity",
		perLevel = 0.1,
		label = "backpack space",
		baseCost = 15,
		growth = 1.3,
	},
	{
		id = "speed",
		name = "Sweep Speed",
		desc = "Swing your tool faster. Swish swish swish!",
		maxLevel = 15,
		stat = "interval",
		perLevel = 0.05,
		label = "swing speed",
		baseCost = 40,
		growth = 1.36,
	},
	{
		id = "reach",
		name = "Reach",
		desc = "Your tool reaches farther, so you clear more at once.",
		maxLevel = 12,
		stat = "reach",
		perLevel = 0.04,
		label = "reach",
		baseCost = 120,
		growth = 1.4,
	},
	{
		id = "walk",
		name = "Walk Speed",
		desc = "Run faster to the Trade Hut and back.",
		maxLevel = 15,
		stat = "walkSpeed",
		perLevel = 0.025,
		label = "walk speed",
		baseCost = 300,
		growth = 1.33,
	},
	{
		id = "sell",
		name = "Sell Boost",
		desc = "The Trade Hut pays you more coins for your ash.",
		maxLevel = 20,
		stat = "sellBonus",
		perLevel = 0.05,
		label = "coins",
		baseCost = 900,
		growth = 1.37,
	},
	{
		id = "luck",
		name = "Treasure Luck",
		desc = "Spot hidden treasure more often while you sweep.",
		maxLevel = 15,
		stat = "luck",
		perLevel = 0.1,
		label = "treasure luck",
		baseCost = 6000,
		growth = 1.35,
	},
	{
		id = "sweetspot",
		name = "Sweet Spot",
		desc = "Sometimes a swing hits the sweet spot and clears double!",
		maxLevel = 15,
		stat = "sweetChance",
		perLevel = 0.02,
		label = "double-clear chance",
		baseCost = 20000,
		growth = 1.36,
	},
	{
		id = "armor",
		name = "Burp Armor",
		desc = "Drop less ash when a lava pop bounces you.",
		maxLevel = 16,
		stat = "armor",
		perLevel = 0.05,
		label = "burp armor",
		baseCost = 60000,
		growth = 1.35,
		cap = Config.Player.maxArmor,
	},
	{
		id = "lucky_coins",
		name = "Lucky Coins",
		desc = "Sometimes the Trade Hut pays you double!",
		maxLevel = 12,
		stat = "luckyChance",
		perLevel = 0.01,
		label = "double-pay chance",
		baseCost = 150000,
		growth = 1.4,
	},
} :: { Upgrade }

Upgrades.byId = {} :: { [string]: Upgrade }
Upgrades.order = {} :: { string }
for _, up in Upgrades.list do
	Upgrades.byId[up.id] = up
	table.insert(Upgrades.order, up.id)
end

local function clampLevel(up: Upgrade, level: number): number
	if level ~= level then
		return 0
	end
	return math.clamp(math.floor(level), 0, up.maxLevel)
end

-- Bonus at `level` as a fraction (0.08 = 8%). Level is clamped to 0..maxLevel.
function Upgrades.effect(id: string, level: number): number
	local up = Upgrades.byId[id]
	if not up then
		return 0
	end
	local bonus = clampLevel(up, level) * up.perLevel
	if up.cap and bonus > up.cap then
		bonus = up.cap
	end
	return bonus
end

-- Coins for the NEXT level when you are at `currentLevel`, or nil when maxed / unknown id.
function Upgrades.cost(id: string, currentLevel: number): number?
	local up = Upgrades.byId[id]
	if not up or currentLevel ~= currentLevel then
		return nil
	end
	local level = math.max(0, math.floor(currentLevel))
	if level >= up.maxLevel then
		return nil
	end
	return math.floor(up.baseCost * up.growth ^ level + 0.5)
end

-- "+8% reach" for the bonus you have at `level`.
function Upgrades.effectText(id: string, level: number): string
	local up = Upgrades.byId[id]
	if not up then
		return ""
	end
	local pct = math.floor(Upgrades.effect(id, level) * 1000 + 0.5) / 10 -- one decimal at most
	return `+{pct}% {up.label}`
end

return Upgrades
