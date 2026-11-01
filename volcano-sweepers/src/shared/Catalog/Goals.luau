--!strict
-- 14 one-time goals. `stat` is a key of Types.Stats; a goal is done when profile.stats[stat] >= target.
-- Rewards are claimed once (profile.goalsClaimed[id]).

local Types = require("../Types")

export type Goal = {
	id: string,
	name: string,
	stat: string,
	target: number,
	rewardCoins: number,
	rewardSparks: number,
}

local Goals = {}

Goals.list = {
	{
		id = "first_sweeps",
		name = "First Sweeps",
		stat = "ashSwept",
		target = 200,
		rewardCoins = 40,
		rewardSparks = 0,
	},
	{
		id = "tidy_beach",
		name = "Tidy Up",
		stat = "ashSwept",
		target = 2500,
		rewardCoins = 300,
		rewardSparks = 0,
	},
	{
		id = "ash_buster",
		name = "Ash Buster",
		stat = "ashSwept",
		target = 40000,
		rewardCoins = 6000,
		rewardSparks = 0,
	},
	{
		id = "ash_legend",
		name = "Ash Legend",
		stat = "ashSwept",
		target = 1000000,
		rewardCoins = 250000,
		rewardSparks = 2,
	},
	{
		id = "first_sales",
		name = "Open for Business",
		stat = "sellCount",
		target = 5,
		rewardCoins = 30,
		rewardSparks = 0,
	},
	{
		id = "busy_shop",
		name = "Busy Shop",
		stat = "sellCount",
		target = 50,
		rewardCoins = 700,
		rewardSparks = 0,
	},
	{
		id = "trade_titan",
		name = "Trade Titan",
		stat = "sellCount",
		target = 400,
		rewardCoins = 25000,
		rewardSparks = 1,
	},
	{
		id = "treasure_peek",
		name = "Treasure Peek",
		stat = "findsTotal",
		target = 3,
		rewardCoins = 200,
		rewardSparks = 0,
	},
	{
		id = "treasure_fan",
		name = "Treasure Fan",
		stat = "findsTotal",
		target = 12,
		rewardCoins = 3500,
		rewardSparks = 0,
	},
	{
		id = "treasure_boss",
		name = "Treasure Boss",
		stat = "findsTotal",
		target = 40,
		rewardCoins = 50000,
		rewardSparks = 2,
	},
	{
		id = "spotless",
		name = "Spotless",
		stat = "cleared",
		target = 300,
		rewardCoins = 500,
		rewardSparks = 0,
	},
	{
		id = "bounce_buddy",
		name = "Bounce Buddy",
		stat = "burpHits",
		target = 3,
		rewardCoins = 150,
		rewardSparks = 0,
	},
	{
		id = "dodge_dancer",
		name = "Dodge Dancer",
		stat = "burpDodged",
		target = 10,
		rewardCoins = 3000,
		rewardSparks = 0,
	},
	{
		id = "long_play",
		name = "Island Regular",
		stat = "playSeconds",
		target = 3600,
		rewardCoins = 6000,
		rewardSparks = 1,
	},
} :: { Goal }

Goals.byId = {} :: { [string]: Goal }
Goals.order = {} :: { string }
for _, g in Goals.list do
	Goals.byId[g.id] = g
	table.insert(Goals.order, g.id)
end

-- Current value of the goal's stat (0 if missing).
function Goals.progress(goal: Goal, stats: Types.Stats): number
	local v = (stats :: any)[goal.stat]
	if type(v) ~= "number" or v ~= v then
		return 0
	end
	return v
end

-- True when the target is reached (claimed or not).
function Goals.isDone(goal: Goal, stats: Types.Stats): boolean
	return Goals.progress(goal, stats) >= goal.target
end

return Goals
