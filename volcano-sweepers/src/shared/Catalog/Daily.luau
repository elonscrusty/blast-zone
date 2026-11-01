--!strict
-- Daily reward ladder: 7 days, then it starts again at day 1 while the streak keeps counting.
-- The server decides the day (UTC date) and that it was not already claimed today.

export type Reward = { day: number, coins: number, sparks: number }

local Daily = {}

Daily.days = 7

Daily.ladder = {
	{ day = 1, coins = 100, sparks = 0 },
	{ day = 2, coins = 200, sparks = 0 },
	{ day = 3, coins = 350, sparks = 0 },
	{ day = 4, coins = 600, sparks = 0 },
	{ day = 5, coins = 1000, sparks = 0 },
	{ day = 6, coins = 1600, sparks = 0 },
	{ day = 7, coins = 3000, sparks = 3 },
} :: { Reward }

-- Reward for claiming the `streak`-th day in a row (1 = first ever day). Streaks above 7 wrap
-- around. Bad input counts as day 1. `scale` (default 1) multiplies the coins, rounded down.
function Daily.rewardFor(streak: number, scale: number?): Reward
	local s = if streak == streak and streak >= 1 and streak < 1e9 then math.floor(streak) else 1
	local day = (s - 1) % Daily.days + 1
	local base = Daily.ladder[day]
	local mult = if scale and scale == scale and scale > 0 then scale else 1
	return { day = day, coins = math.floor(base.coins * mult), sparks = base.sparks }
end

return Daily
