--!strict
-- Goals: claimed once, only when the stat reached the target.
local Harness = require("./harness")
local Types = require("../src/shared/Types")
local Goals = require("../src/shared/Catalog/Goals")
local ProfileSchema = require("../src/shared/Profile/ProfileSchema")
local GoalRules = require("../src/shared/Player/GoalRules")
local Wallet = require("../src/shared/Player/Wallet")

local function fresh(): Types.Profile
	return ProfileSchema.default()
end

Harness.test("goal: not reached means no reward and no change", function()
	local p = fresh()
	p.stats.ashSwept = 199
	local paid, why = GoalRules.claim(p, "first_sweeps")
	Harness.eq(paid, nil)
	Harness.truthy(why ~= nil)
	Harness.eq(p.coins, 0)
	Harness.eq(p.goalsClaimed["first_sweeps"], nil)
	Harness.eq(GoalRules.status(Goals.byId["first_sweeps"], p), "locked")
end)

Harness.test("goal: reaching the target pays once", function()
	local p = fresh()
	p.stats.ashSwept = 200
	Harness.eq(GoalRules.status(Goals.byId["first_sweeps"], p), "ready")
	local paid = GoalRules.claim(p, "first_sweeps") :: GoalRules.Paid
	Harness.eq(paid.coins, 40)
	Harness.eq(paid.sparks, 0)
	Harness.eq(p.coins, 40)
	Harness.eq(p.runCoins, 40)
	Harness.eq(p.lifetimeCoins, 40)
	Harness.eq(p.goalsClaimed["first_sweeps"], true)
	Harness.eq(GoalRules.status(Goals.byId["first_sweeps"], p), "claimed")
	local again, why = GoalRules.claim(p, "first_sweeps")
	Harness.eq(again, nil)
	Harness.eq(why, "Already claimed!")
	Harness.eq(p.coins, 40)
end)

Harness.test("goal: exactly the target counts, Spark goals pay Sparks", function()
	local p = fresh()
	p.stats.ashSwept = 1000000
	local paid = GoalRules.claim(p, "ash_legend") :: GoalRules.Paid
	Harness.eq(paid.sparks, 2)
	Harness.eq(p.sparks, 2)
	Harness.eq(paid.coins, 250000)
	-- claiming one goal does not claim the others that are also done
	Harness.eq(p.goalsClaimed["first_sweeps"], nil)
	Harness.eq(GoalRules.readyCount(p), 3) -- first_sweeps, tidy_beach, ash_buster
end)

Harness.test("goal: junk ids", function()
	local p = fresh()
	local junk: { any } = { "", "nope", "FIRST_SWEEPS", 5, true, {}, "__index" }
	for _, id in junk do
		local paid = GoalRules.claim(p, id)
		Harness.eq(paid, nil)
	end
	Harness.eq(GoalRules.claim(p, nil), nil)
	Harness.eq(p.coins, 0)
	Harness.eq(next(p.goalsClaimed), nil)
end)

Harness.test("goal: every goal can be claimed once and the profile stays valid", function()
	local p = fresh()
	for _, goal in Goals.list do
		(p.stats :: any)[goal.stat] = goal.target
	end
	local coins, sparks = 0, 0
	for _, goal in Goals.list do
		local paid = GoalRules.claim(p, goal.id) :: GoalRules.Paid
		coins += paid.coins
		sparks += paid.sparks
		Harness.eq(GoalRules.claim(p, goal.id), nil)
	end
	Harness.eq(p.coins, coins)
	Harness.eq(p.sparks, sparks)
	Harness.eq(GoalRules.readyCount(p), 0)
	local ok, why = ProfileSchema.isValid(p)
	Harness.truthy(ok, tostring(why))
end)

Harness.test("goal: a NaN stat is never done", function()
	local p = fresh()
	p.stats.cleared = 0 / 0
	Harness.eq(GoalRules.status(Goals.byId["spotless"], p), "locked")
end)

Harness.test("wallet: pays whole numbers, ignores junk, respects the saved caps", function()
	local p = fresh()
	local c, s = Wallet.earn(p, 10.9, 1.5)
	Harness.eq(c, 10)
	Harness.eq(s, 1)
	Harness.eq(p.coins, 10)
	Harness.eq(p.sparks, 1)
	c, s = Wallet.earn(p, -5, 0 / 0)
	Harness.eq(c, 0)
	Harness.eq(s, 0)
	c, s = Wallet.earn(p, math.huge, math.huge)
	Harness.eq(c, 0)
	Harness.eq(s, 0)
	p.coins = ProfileSchema.MAX.coins - 3
	c = Wallet.earn(p, 100, 0)
	Harness.eq(c, 3)
	Harness.eq(p.coins, ProfileSchema.MAX.coins)
	Harness.truthy(p.runCoins <= ProfileSchema.MAX.coins)
end)
