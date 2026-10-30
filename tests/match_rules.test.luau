--!strict
local Harness = require("./harness")
local MatchRules = require("../src/server/Match/MatchRules")
local Config = require("../src/shared/Config")

local function entry(id: string, alive: boolean, at: number?, left: boolean?): MatchRules.RankEntry
	return { id = id, alive = alive, left = left == true, eliminatedAt = at }
end

Harness.test("rank: last one alive wins", function()
	local r = MatchRules.rank(
		{ entry("a", false, 10), entry("b", true, nil), entry("c", false, 20) },
		30,
		0.35
	)
	Harness.eq(r.outcome, "win")
	Harness.eq(r.winnerId, "b")
	Harness.eq(r.place.b, 1)
	Harness.eq(r.place.c, 2)
	Harness.eq(r.place.a, 3)
end)

Harness.test("rank: last two eliminate each other together is a draw", function()
	local r = MatchRules.rank(
		{ entry("a", false, 50), entry("b", false, 50.2), entry("c", false, 10) },
		51,
		0.35
	)
	Harness.eq(r.outcome, "draw")
	Harness.eq(r.place.a, 1)
	Harness.eq(r.place.b, 1)
	Harness.eq(r.place.c, 3, "ties skip a number")
	Harness.eq(r.winnerId, nil)
end)

Harness.test("rank: far apart finishes are not a tie", function()
	local r = MatchRules.rank({ entry("a", false, 50), entry("b", false, 51) }, 52, 0.35)
	Harness.eq(r.outcome, "win")
	Harness.eq(r.winnerId, "b")
end)

Harness.test("rank: several survivors at timeout share first (draw)", function()
	local r = MatchRules.rank(
		{ entry("a", true, nil), entry("b", true, nil), entry("c", false, 5) },
		60,
		0.35
	)
	Harness.eq(r.outcome, "draw")
	Harness.eq(#r.topIds, 2)
	Harness.eq(r.place.c, 3)
end)

Harness.test("rank: survivor beats someone who died a hair before the end", function()
	local r = MatchRules.rank({ entry("a", false, 59.9), entry("b", true, nil) }, 60, 0.35)
	Harness.eq(r.winnerId, "b")
end)

Harness.test("rank: a leaver nobody beat means abandoned, no winner", function()
	local r = MatchRules.rank({ entry("a", false, 40), entry("b", false, 50, true) }, 55, 0.1)
	Harness.eq(r.outcome, "abandoned")
	Harness.eq(r.winnerId, nil)
	Harness.eq(r.place.b, 1)
	Harness.eq(r.place.a, 2)
end)

Harness.test("rank: same input always gives the same order", function()
	local a = MatchRules.rank(
		{ entry("x", false, 5), entry("y", false, 5), entry("z", false, 5) },
		9,
		0.35
	)
	Harness.eq(a.order[1], "x")
	Harness.eq(a.order[3], "z")
end)

local corners: { MatchRules.Point } = {
	{ x = 0, y = 0, z = 0 },
	{ x = 200, y = 0, z = 0 },
	{ x = 0, y = 0, z = 200 },
	{ x = 200, y = 0, z = 200 },
	{ x = 10, y = 0, z = 10 },
}
local center: MatchRules.Point = { x = 100, y = 0, z = 100 }

Harness.test("pickSpawns: picks far-apart distinct spawns", function()
	for _ = 1, 20 do
		local pick = MatchRules.pickSpawns(corners, 4, center, 60, function(n: number)
			return math.random(1, n)
		end)
		Harness.eq(#pick.points, 4)
		Harness.eq(pick.usedFallback, false)
		-- If the near-corner decoy (10,10) is picked first, farthest-point still must not pair it with (0,0).
		Harness.truthy(pick.minDistance >= 100, "spawns stay apart")
	end
end)

Harness.test("pickSpawns: too few points adds a ring and says so", function()
	local pick = MatchRules.pickSpawns({ corners[1] }, 3, center, 60, function()
		return 1
	end)
	Harness.eq(#pick.points, 3)
	Harness.eq(pick.usedFallback, true)
	Harness.near(MatchRules.distance(pick.points[2], center), 60, 1e-6)
end)

Harness.test("pickSpawns: no spawn points at all still gives a full ring", function()
	local pick = MatchRules.pickSpawns({}, 4, center, 60, function()
		return 1
	end)
	Harness.eq(#pick.points, 4)
	Harness.truthy(pick.minDistance > 50, "ring spawns are separated")
end)

Harness.test("rewardFor: participation + place + kills", function()
	local r = Config.Rewards
	Harness.eq(
		MatchRules.rewardFor(1, 3, r),
		r.participation + r.placementBonus[1] + 3 * r.perElimination
	)
	Harness.eq(MatchRules.rewardFor(2, 0, r), r.participation + r.placementBonus[2])
	Harness.eq(MatchRules.rewardFor(7, 1, r), r.participation + r.perElimination)
end)

Harness.test("ledger: a reward commits once per match and player", function()
	local l = MatchRules.newLedger()
	Harness.eq(l:commit(1, "a", 50), true)
	Harness.eq(l:commit(1, "a", 50), false, "repeat pays nothing")
	Harness.eq(l:commit(2, "a", 50), true, "next match is separate")
	Harness.eq(l:commit(1, "b", 50), true)
	l:forgetBefore(2)
	Harness.eq(l:has(1, "a"), false)
	Harness.eq(l:has(2, "a"), true)
end)

Harness.test("cycleTarget: next, previous, wraps, unknown start", function()
	local ids = { "a", "b", "c" }
	Harness.eq(MatchRules.cycleTarget(ids, "a", 1), "b")
	Harness.eq(MatchRules.cycleTarget(ids, "c", 1), "a")
	Harness.eq(MatchRules.cycleTarget(ids, "a", -1), "c")
	Harness.eq(MatchRules.cycleTarget(ids, "gone", 1), "a")
	Harness.eq(MatchRules.cycleTarget({}, "a", 1), nil)
end)

Harness.test("formatTime", function()
	Harness.eq(MatchRules.formatTime(125.4), "2:05")
	Harness.eq(MatchRules.formatTime(0), "0:00")
	Harness.eq(MatchRules.formatTime(-3), "0:00")
end)
