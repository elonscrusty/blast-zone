--!strict
-- Daily reward rules. The day is the UTC date: days since 1970 = floor(unix seconds / 86400).
--   * one claim per UTC day (a second claim the same day pays nothing)
--   * claiming the day after your last claim keeps the streak going (+1)
--   * missing a whole day (or more) starts again at day 1
--   * the 7-day ladder comes from Catalog/Daily; day 8 wraps to day 1's reward but the streak keeps counting
--   * a clock that went backwards (today < lastDay) can never claim
-- Pure: the caller passes the day in (os.time() lives in the service).

local Types = require("../Types")
local Daily = require("../Catalog/Daily")
local ProfileSchema = require("../Profile/ProfileSchema")
local Wallet = require("./Wallet")

local DailyRules = {}

export type Plan = {
	canClaim: boolean,
	reason: string, -- "" when canClaim
	streak: number, -- the streak this claim would make (or the current one when it can't be claimed)
	reset: boolean, -- true when a missed day sends the streak back to 1
	reward: Daily.Reward,
}

export type Paid = { coins: number, sparks: number, streak: number, day: number, ladderDay: number }

local SECONDS_PER_DAY = 86400

-- UTC day number for a unix time. Bad input gives 0.
function DailyRules.dayOf(unixSeconds: number): number
	if unixSeconds ~= unixSeconds or unixSeconds < 0 or unixSeconds == math.huge then
		return 0
	end
	return math.floor(unixSeconds / SECONDS_PER_DAY)
end

-- Seconds until the next UTC midnight (1..86400).
function DailyRules.secondsToNextDay(unixSeconds: number): number
	if unixSeconds ~= unixSeconds or unixSeconds < 0 or unixSeconds == math.huge then
		return SECONDS_PER_DAY
	end
	return SECONDS_PER_DAY - math.floor(unixSeconds % SECONDS_PER_DAY)
end

local function cleanInt(v: any): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return math.max(0, math.floor(v))
end

-- What would happen if this player claimed on UTC day `today`.
function DailyRules.plan(daily: { lastDay: number, streak: number }, today: number): Plan
	local last = cleanInt(daily.lastDay)
	local streak = cleanInt(daily.streak)
	local day = cleanInt(today)

	if day <= 0 then
		return {
			canClaim = false,
			reason = "The clock is sleepy. Try again soon!",
			streak = streak,
			reset = false,
			reward = Daily.rewardFor(math.max(1, streak)),
		}
	end
	if last > 0 and day == last then
		return {
			canClaim = false,
			reason = "You got today's gift! Come back tomorrow.",
			streak = streak,
			reset = false,
			reward = Daily.rewardFor(math.max(1, streak)),
		}
	end
	if last > day then
		return {
			canClaim = false,
			reason = "Come back tomorrow!",
			streak = streak,
			reset = false,
			reward = Daily.rewardFor(math.max(1, streak)),
		}
	end

	local reset = false
	local nextStreak: number
	if last == 0 or streak <= 0 then
		nextStreak = 1
	elseif day == last + 1 then
		nextStreak = streak + 1
	else
		nextStreak = 1
		reset = true
	end
	nextStreak = math.min(nextStreak, ProfileSchema.MAX.streak)
	return {
		canClaim = true,
		reason = "",
		streak = nextStreak,
		reset = reset,
		reward = Daily.rewardFor(nextStreak),
	}
end

-- True when a reward is waiting.
function DailyRules.canClaim(daily: { lastDay: number, streak: number }, today: number): boolean
	return DailyRules.plan(daily, today).canClaim
end

-- Pays the reward into `profile` and records the claim. Returns nil (and changes nothing) when it
-- can't be claimed today.
function DailyRules.apply(profile: Types.Profile, today: number): Paid?
	local plan = DailyRules.plan(profile.daily, today)
	if not plan.canClaim then
		return nil
	end
	local coins, sparks = Wallet.earn(profile, plan.reward.coins, plan.reward.sparks)
	profile.daily = { lastDay = cleanInt(today), streak = plan.streak }
	return {
		coins = coins,
		sparks = sparks,
		streak = plan.streak,
		day = cleanInt(today),
		ladderDay = plan.reward.day,
	}
end

return DailyRules
