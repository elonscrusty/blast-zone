--!strict
-- Daily reward: UTC days, streaks, missed days, double claims.
local Harness = require("./harness")
local Types = require("../src/shared/Types")
local Daily = require("../src/shared/Catalog/Daily")
local ProfileSchema = require("../src/shared/Profile/ProfileSchema")
local DailyRules = require("../src/shared/Player/DailyRules")

local DAY = 86400
local D0 = 20000 -- some UTC day

local function fresh(): Types.Profile
	return ProfileSchema.default()
end

Harness.test("daily: dayOf is the UTC date", function()
	Harness.eq(DailyRules.dayOf(0), 0)
	Harness.eq(DailyRules.dayOf(DAY - 1), 0)
	Harness.eq(DailyRules.dayOf(DAY), 1)
	Harness.eq(DailyRules.dayOf(D0 * DAY + 86399), D0)
	Harness.eq(DailyRules.dayOf(D0 * DAY + 86399.9), D0)
	Harness.eq(DailyRules.dayOf((D0 + 1) * DAY), D0 + 1)
	Harness.eq(DailyRules.dayOf(-5), 0)
	Harness.eq(DailyRules.dayOf(0 / 0), 0)
	Harness.eq(DailyRules.dayOf(math.huge), 0)
end)

Harness.test("daily: seconds to the next UTC midnight", function()
	Harness.eq(DailyRules.secondsToNextDay(D0 * DAY), DAY)
	Harness.eq(DailyRules.secondsToNextDay(D0 * DAY + 1), DAY - 1)
	Harness.eq(DailyRules.secondsToNextDay(D0 * DAY + 86399), 1)
	Harness.eq(DailyRules.secondsToNextDay(0 / 0), DAY)
end)

Harness.test("daily: first ever claim is day 1 of the ladder", function()
	local p = fresh()
	local plan = DailyRules.plan(p.daily, D0)
	Harness.eq(plan.canClaim, true)
	Harness.eq(plan.streak, 1)
	Harness.eq(plan.reset, false)
	Harness.eq(plan.reward.coins, Daily.ladder[1].coins)
	local paid = DailyRules.apply(p, D0)
	Harness.truthy(paid ~= nil)
	local got = paid :: DailyRules.Paid
	Harness.eq(got.coins, 100)
	Harness.eq(got.streak, 1)
	Harness.eq(p.coins, 100)
	Harness.eq(p.runCoins, 100)
	Harness.eq(p.lifetimeCoins, 100)
	Harness.eq(p.daily.lastDay, D0)
	Harness.eq(p.daily.streak, 1)
	Harness.truthy(ProfileSchema.isValid(p))
end)

Harness.test("daily: a second claim the same day pays nothing", function()
	local p = fresh()
	DailyRules.apply(p, D0)
	local coins = p.coins
	Harness.eq(DailyRules.apply(p, D0), nil)
	Harness.eq(DailyRules.canClaim(p.daily, D0), false)
	Harness.eq(p.coins, coins)
	Harness.eq(p.daily.streak, 1)
	Harness.truthy(#DailyRules.plan(p.daily, D0).reason > 0)
end)

Harness.test("daily: one second before and after UTC midnight", function()
	local p = fresh()
	local lateOnD0 = DailyRules.dayOf(D0 * DAY + 86399)
	local justAfter = DailyRules.dayOf((D0 + 1) * DAY)
	Harness.truthy(DailyRules.apply(p, lateOnD0) ~= nil)
	Harness.eq(DailyRules.apply(p, lateOnD0), nil) -- still the same day
	local next = DailyRules.apply(p, justAfter)
	Harness.truthy(next ~= nil)
	Harness.eq((next :: DailyRules.Paid).streak, 2)
	Harness.eq((next :: DailyRules.Paid).coins, Daily.ladder[2].coins)
end)

Harness.test(
	"daily: the whole 7 day ladder, then it wraps and the streak keeps counting",
	function()
		local p = fresh()
		local total = 0
		for n = 1, 7 do
			local paid = DailyRules.apply(p, D0 + n - 1) :: DailyRules.Paid
			Harness.eq(paid.streak, n)
			Harness.eq(paid.ladderDay, n)
			Harness.eq(paid.coins, Daily.ladder[n].coins)
			Harness.eq(paid.sparks, Daily.ladder[n].sparks)
			total += paid.coins
		end
		Harness.eq(p.sparks, 3) -- day 7 gives Sparks
		Harness.eq(p.coins, total)
		local eight = DailyRules.apply(p, D0 + 7) :: DailyRules.Paid
		Harness.eq(eight.streak, 8)
		Harness.eq(eight.ladderDay, 1)
		Harness.eq(eight.coins, Daily.ladder[1].coins)
		Harness.truthy(ProfileSchema.isValid(p))
	end
)

Harness.test("daily: missing a day starts again at day 1", function()
	local p = fresh()
	DailyRules.apply(p, D0)
	DailyRules.apply(p, D0 + 1)
	DailyRules.apply(p, D0 + 2)
	Harness.eq(p.daily.streak, 3)
	local plan = DailyRules.plan(p.daily, D0 + 4) -- skipped D0+3
	Harness.eq(plan.canClaim, true)
	Harness.eq(plan.reset, true)
	Harness.eq(plan.streak, 1)
	local paid = DailyRules.apply(p, D0 + 4) :: DailyRules.Paid
	Harness.eq(paid.streak, 1)
	Harness.eq(paid.coins, Daily.ladder[1].coins)
	Harness.eq(p.daily.lastDay, D0 + 4)
	Harness.eq(p.daily.streak, 1)
	-- a month away is the same
	Harness.eq(DailyRules.plan(p.daily, D0 + 40).streak, 1)
end)

Harness.test("daily: a clock that goes backwards can't claim", function()
	local p = fresh()
	DailyRules.apply(p, D0 + 5)
	local coins = p.coins
	Harness.eq(DailyRules.apply(p, D0 + 4), nil)
	Harness.eq(DailyRules.apply(p, D0), nil)
	Harness.eq(DailyRules.apply(p, 0), nil)
	Harness.eq(p.coins, coins)
	Harness.eq(p.daily.lastDay, D0 + 5)
end)

Harness.test("daily: a 40 day run pays exactly one reward per day", function()
	local p = fresh()
	local claims = 0
	for step = 0, 39 do
		local day = D0 + step
		for _ = 1, 3 do -- three taps a day
			if DailyRules.apply(p, day) ~= nil then
				claims += 1
			end
		end
	end
	Harness.eq(claims, 40)
	Harness.eq(p.daily.streak, 40)
end)

Harness.test("daily: broken saved values behave like never claimed", function()
	local daily = { lastDay = 0 / 0, streak = -4 }
	local plan = DailyRules.plan(daily, D0)
	Harness.eq(plan.canClaim, true)
	Harness.eq(plan.streak, 1)
	local weird = { lastDay = D0, streak = 0 } -- lastDay set but streak lost: start over
	Harness.eq(DailyRules.plan(weird, D0 + 1).streak, 1)
	Harness.eq(DailyRules.plan({ lastDay = 0, streak = 0 }, 0).canClaim, false)
	Harness.eq(DailyRules.plan({ lastDay = 0, streak = 0 }, 0 / 0).canClaim, false)
end)

Harness.test("daily: the streak never passes the saved cap", function()
	local p = fresh()
	p.daily = { lastDay = D0, streak = ProfileSchema.MAX.streak }
	local paid = DailyRules.apply(p, D0 + 1) :: DailyRules.Paid
	Harness.eq(paid.streak, ProfileSchema.MAX.streak)
	Harness.truthy(ProfileSchema.isValid(p))
end)
