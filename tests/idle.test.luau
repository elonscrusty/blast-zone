--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local MatchPhase = require("../src/shared/MatchPhase")
local IdleWatch = require("../src/server/Match/IdleWatch")
local MatchControllerTest = require("./match_controller.test")

local newRig = MatchControllerTest.newRig
local humans = MatchControllerTest.humans

local LIMITS = { warnSeconds = 25, kickSeconds = 40, moveStuds = 3 }

-- ===== IdleWatch =====

Harness.test("idle: warn once, then remove, each listed once", function()
	local w = IdleWatch.new(LIMITS)
	w.track("p1", 0)
	Harness.eq(#w.sweep(24.9).warn, 0)
	local r = w.sweep(25)
	Harness.eq(r.warn[1], "p1")
	Harness.eq(#w.sweep(30).warn, 0, "warned only once")
	r = w.sweep(40)
	Harness.eq(r.kick[1], "p1")
	Harness.eq(w.isTracked("p1"), false, "forgotten after removal")
	Harness.eq(#w.sweep(50).kick, 0, "never listed twice")
end)

Harness.test("idle: activity resets the clock and the warning", function()
	local w = IdleWatch.new(LIMITS)
	w.track("p1", 0)
	w.sweep(26)
	w.activity("p1", 30)
	Harness.eq(#w.sweep(54).warn, 0, "clock restarted at 30")
	Harness.eq(w.sweep(55).warn[1], "p1", "warns again after another quiet stretch")
	Harness.near(w.secondsUntilKick("p1", 60) :: number, 10)
end)

Harness.test("idle: only a real walk counts, jitter does not", function()
	local w = IdleWatch.new(LIMITS)
	w.track("p1", 0)
	w.position("p1", 0, 0, 0, 0)
	w.position("p1", 10, 1, 0, 1) -- 1.4 studs: nothing
	w.position("p1", 20, -1, 0, 2)
	Harness.eq(w.secondsIdle("p1", 30), 30, "jitter changed nothing")
	w.position("p1", 31, 5, 0, 0) -- 5 studs from the anchor: walking
	Harness.eq(w.secondsIdle("p1", 32), 1)
	w.position("p1", 40, 6, 0, 0) -- only 1 stud from the new anchor
	Harness.eq(w.secondsIdle("p1", 41), 10)
end)

Harness.test("idle: unknown ids and untracked ids are ignored", function()
	local w = IdleWatch.new(LIMITS)
	w.activity("nobody", 5)
	w.position("nobody", 5, 0, 0, 0)
	Harness.eq(w.secondsIdle("nobody", 9), nil)
	w.track("p1", 0)
	w.untrack("p1")
	Harness.eq(#w.sweep(100).kick, 0)
end)

Harness.test("idle: bad limits are refused", function()
	local ok = pcall(IdleWatch.new, { warnSeconds = 30, kickSeconds = 30, moveStuds = 3 })
	Harness.eq(ok, false)
end)

Harness.test(
	"Config.Idle: warning comes before removal, queue wait is longer than a fight's",
	function()
		local c = Config.Idle
		Harness.truthy(c.warnSeconds < c.kickSeconds)
		Harness.truthy(c.lobbyWarnSeconds < c.lobbyQueuedSeconds)
		Harness.truthy(c.kickSeconds <= c.lobbyQueuedSeconds)
		Harness.truthy(c.shutdownGraceSeconds < 30, "BindToClose allows 30 seconds")
	end
)

-- ===== match flow =====

local function intoFight(n: number): (any, { string })
	local rig, ids = humans(n)
	rig.untilPhase("Active")
	return rig, ids
end

Harness.test("idle kick in a fight: out, benched, no reward, others carry on", function()
	local rig, ids = intoFight(3)
	Harness.eq(rig.ctl.forfeitIdle(ids[1]), true)
	Harness.eq(rig.registry:aliveCount(), 2)
	Harness.eq(rig.benched[1], ids[1])
	Harness.eq(rig.ctl.isReady(ids[1]), false, "must press PLAY again")
	Harness.truthy(MatchPhase.isCombat(rig.ctx:getPhase()), "the fight goes on")
	rig.step(1)
	rig.kill(ids[2], ids[3])
	rig.untilPhase("Results")
	local you = rig.results[ids[1]].you
	Harness.eq(you.placement, 3, "the idle player is last")
	Harness.eq(you.reward, 0)
	Harness.eq(rig.results[ids[3]].winnerId, ids[3])
	rig.untilPhase("Waiting")
	for _, r in rig.rewards do
		Harness.truthy(r.id ~= ids[1], "idle player was paid")
	end
end)

Harness.test("idle kick of the second-to-last fighter lets the other win", function()
	local rig, ids = intoFight(2)
	Harness.eq(rig.ctl.forfeitIdle(ids[2]), true)
	rig.untilPhase("Finished")
	Harness.eq(rig.ctl.getResult().winnerId, ids[1])
	Harness.eq(rig.ctl.getResult().outcome, "win")
end)

Harness.test("idle kick twice or for strangers does nothing", function()
	local rig, ids = intoFight(3)
	Harness.eq(rig.ctl.forfeitIdle(ids[1]), true)
	Harness.eq(rig.ctl.forfeitIdle(ids[1]), false)
	Harness.eq(rig.ctl.forfeitIdle("p999"), false)
	Harness.eq(#rig.benched, 1)
end)

Harness.test("idle kick of a fallen player does nothing to the match", function()
	local rig, ids = intoFight(3)
	rig.kill(ids[1], ids[2])
	Harness.eq(rig.ctl.forfeitIdle(ids[1]), false)
	Harness.eq(#rig.benched, 0)
end)

Harness.test("idle in the lobby: leaves the queue, countdown drops them", function()
	local rig, ids = humans(3)
	rig.untilPhase("Countdown")
	Harness.eq(rig.ctl.forfeitIdle(ids[3]), false, "not a fight, nothing removed")
	Harness.eq(rig.ctl.isReady(ids[3]), false)
	rig.untilPhase("Spawning")
	Harness.eq(rig.registry:aliveCount(), 2, "the away player was not enrolled")
end)

-- ===== bots fill empty slots =====

Harness.test("two friends and bots from the top-up: full arena starts", function()
	local rig, ids = humans(2)
	Harness.eq(rig.ctl.requestBots(Config.Match.targetParticipants - 2), 4)
	rig.untilPhase("Spawning")
	Harness.eq(#rig.placed, Config.Match.targetParticipants)
	Harness.eq(rig.registry:aliveCount(), Config.Match.targetParticipants)
	Harness.eq(#ids, 2)
end)

-- ===== shutdown =====

Harness.test("shutdown in the lobby: nothing new starts", function()
	local rig, ids = humans(2)
	rig.ctl.setReady(ids[1], false)
	rig.ctl.beginShutdown()
	rig.step(60)
	Harness.eq(rig.ctx:getPhase(), "Waiting")
	rig.ctl.setReady(ids[1], true)
	Harness.eq(rig.ctl.isReady(ids[1]), false, "no new queueing")
	Harness.eq(rig.ctl.requestBots(3), 0)
	Harness.eq(rig.ctl.isClosing(), true)
end)

Harness.test("shutdown during a countdown goes back to waiting", function()
	local rig = humans(2)
	rig.untilPhase("Countdown")
	rig.ctl.beginShutdown()
	rig.step(1)
	Harness.eq(rig.ctx:getPhase(), "Waiting")
	rig.step(60)
	Harness.eq(rig.ctx:getPhase(), "Waiting", "still closed")
end)

Harness.test("shutdown mid-fight: no result, no reward, no new match", function()
	local rig = intoFight(3)
	rig.ctl.beginShutdown()
	Harness.eq(rig.ctx:getPhase(), "Resetting")
	rig.step(60)
	Harness.eq(rig.ctx:getPhase(), "Waiting")
	Harness.eq(#rig.rewards, 0)
	Harness.eq(rig.ctl.getResult(), nil)
	rig.ctl.beginShutdown() -- twice is fine
end)

Harness.test("shutdown after a win pays everyone once, now", function()
	local rig, ids = intoFight(2)
	rig.kill(ids[2], ids[1])
	rig.untilPhase("Finished")
	Harness.eq(#rig.rewards, 0, "nobody claimed yet")
	rig.ctl.beginShutdown()
	Harness.eq(#rig.rewards, 2, "both paid before the server closes")
	rig.step(60)
	Harness.eq(#rig.rewards, 2, "never paid twice")
end)

return {}
