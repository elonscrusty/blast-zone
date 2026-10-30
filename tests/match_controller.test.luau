--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local Ids = require("../src/shared/Ids")
local MatchPhase = require("../src/shared/MatchPhase")
local MatchContext = require("../src/shared/MatchContext")
local ParticipantRegistry = require("../src/shared/ParticipantRegistry")
local DamageRouter = require("../src/shared/DamageRouter")
local MatchRules = require("../src/server/Match/MatchRules")
local MatchController = require("../src/server/Match/MatchController")

-- A whole server in miniature: real context, roster and damage door, fake world, hand-cranked clock.
export type Rig = {
	ctl: MatchController.Controller,
	ctx: any,
	registry: any,
	router: any,
	now: () -> number,
	step: (seconds: number) -> (),
	untilPhase: (phase: string, limit: number?) -> (),
	kill: (victim: string, killer: string?, cause: string?) -> any,
	join: (userId: number, name: string?) -> string,
	ready: (id: string) -> (),
	placed: { { id: string, point: MatchController.Point } },
	cleanups: number,
	eliminated: { any },
	results: { [string]: any },
	spectate: { [string]: string? },
	rewards: { { id: string, amount: number, place: number } },
	announcements: { string },
	published: { any },
}

local function newRig(matchOverrides: { [string]: any }?): Rig
	local t = 0
	local function clock(): number
		return t
	end
	local config: any = table.clone(Config :: any)
	local match: any = table.clone(Config.Match :: any)
	for k, v in matchOverrides or {} do
		match[k] = v
	end
	config.Match = match

	local ctx = MatchContext.new(clock)
	local registry = ParticipantRegistry.new(clock)
	local router = DamageRouter.new({
		getMatchId = function()
			return ctx:getMatchId()
		end,
		allowsDamage = function()
			return MatchPhase.allowsDamage(ctx:getPhase())
		end,
		isAlive = function(id: string)
			return registry:isAlive(id)
		end,
		markEliminated = function(id: string)
			return registry:markEliminated(id)
		end,
		clock = clock,
	})
	router:bind(function(req: any)
		return { applied = true, dealt = req.amount, remaining = 0, eliminated = true }
	end)

	local rig: Rig = {
		ctl = nil :: any,
		ctx = ctx,
		registry = registry,
		router = router,
		now = clock,
		step = nil :: any,
		untilPhase = nil :: any,
		kill = nil :: any,
		join = nil :: any,
		ready = nil :: any,
		placed = {},
		cleanups = 0,
		eliminated = {},
		results = {},
		spectate = {},
		rewards = {},
		announcements = {},
		published = {},
	}

	local world: MatchController.World = {
		getSpawnPoints = function()
			return {
				{ x = -90, y = 3, z = -90 },
				{ x = 90, y = 3, z = -90 },
				{ x = -90, y = 3, z = 90 },
				{ x = 90, y = 3, z = 90 },
				{ x = 0, y = 3, z = -90 },
				{ x = 0, y = 3, z = 90 },
				{ x = -90, y = 3, z = 0 },
				{ x = 90, y = 3, z = 0 },
			}
		end,
		getCenter = function()
			return { x = 0, y = 3, z = 0 }
		end,
		place = function(participant, point)
			table.insert(rig.placed, { id = participant.id, point = point })
		end,
		cleanup = function()
			rig.cleanups += 1
		end,
		publish = function(state)
			table.insert(rig.published, state)
		end,
		announce = function(_, text)
			table.insert(rig.announcements, text)
		end,
		sendEliminated = function(payload)
			table.insert(rig.eliminated, payload)
		end,
		sendResults = function(id, payload)
			rig.results[id] = payload
		end,
		sendSpectate = function(id, targetId)
			rig.spectate[id] = targetId
		end,
		grantReward = function(id, amount, place)
			table.insert(rig.rewards, { id = id, amount = amount, place = place })
		end,
		toServerTime = function(x)
			return x
		end,
		random = function()
			return 1
		end,
	}

	local ctl = MatchController.new({
		config = config,
		rules = MatchRules,
		ctx = ctx,
		registry = registry,
		phases = MatchPhase,
		ids = Ids,
		clock = clock,
		world = world,
	})
	router.Eliminated:connect(function(e: any)
		ctl.onEliminated(e)
	end)
	rig.ctl = ctl

	function rig.step(seconds: number)
		local target = t + seconds
		while t < target - 1e-9 do
			t += 0.05
			ctl.update()
		end
	end
	function rig.untilPhase(phase: string, limit: number?)
		local stop = t + (limit or 120)
		while ctx:getPhase() ~= phase and t < stop do
			t += 0.05
			ctl.update()
		end
		Harness.eq(ctx:getPhase(), phase, "reached phase")
	end
	function rig.kill(victim: string, killer: string?, cause: string?)
		return router:apply({
			matchId = ctx:getMatchId(),
			targetId = victim,
			amount = 999,
			cause = cause or "bullet",
			sourceId = killer,
		})
	end
	function rig.join(userId: number, name: string?): string
		ctl.addHuman({ UserId = userId }, userId, name or `Player{userId}`)
		return Ids.player(userId)
	end
	function rig.ready(id: string)
		ctl.setReady(id, true)
	end
	return rig
end

-- N humans, all ready, no bots. Returns the rig and their ids.
local function humans(n: number, overrides: { [string]: any }?): (Rig, { string })
	local rig = newRig(overrides)
	local ids = {}
	for i = 1, n do
		local id = rig.join(i)
		table.insert(ids, id)
		rig.ready(id)
	end
	return rig, ids
end

Harness.test(
	"full match with bots: phases in order, spawns apart, one winner, paid once",
	function()
		local rig = newRig()
		local phases: { string } = {}
		rig.ctx.PhaseChanged:connect(function(p: string)
			table.insert(phases, p)
		end)
		local a = rig.join(1, "Alice")
		rig.ready(a)
		rig.step(30)
		Harness.eq(rig.ctx:getPhase(), "Waiting", "one human alone does not start")
		Harness.eq(rig.ctl.requestBots(3), 3)
		rig.untilPhase("Countdown")
		Harness.eq(rig.ctx:getMatchId(), 1)
		rig.untilPhase("Spawning")
		Harness.eq(#rig.placed, 4)
		Harness.eq(rig.registry:aliveCount(), 4)
		local seen: { [string]: boolean } = {}
		for _, s in rig.placed do
			local key = `{s.point.x},{s.point.z}`
			Harness.truthy(not seen[key], "all spawns different")
			seen[key] = true
		end
		local botNames = 0
		for _, p in rig.registry:list() do
			if p.kind == "bot" then
				botNames += 1
				Harness.eq(
					string.sub(p.displayName, 1, #Config.Bots.labelPrefix),
					Config.Bots.labelPrefix,
					"bots are labeled"
				)
			end
		end
		Harness.eq(botNames, 3)
		Harness.eq(rig.kill(a, nil).applied, false, "no damage while spawning")
		rig.untilPhase("Active")
		Harness.eq(rig.kill("b1", a).applied, true)
		Harness.eq(rig.kill("b2", "b3").applied, true)
		rig.step(0.05)
		rig.untilPhase("FinalPressure", 1) -- two left
		Harness.eq(rig.kill("b3", a).applied, true)
		rig.untilPhase("Finished", 2)
		local res = rig.ctl.getResult() :: MatchController.Result
		Harness.eq(res.outcome, "win")
		Harness.eq(res.winnerId, a)
		Harness.eq(res.rows[1].participantId, a)
		Harness.eq(res.rows[1].eliminations, 2)
		rig.untilPhase("Results")
		rig.step(1)
		Harness.eq(rig.results[a].you.placement, 1)
		local expected = MatchRules.rewardFor(1, 2, Config.Rewards)
		Harness.eq(rig.results[a].you.reward, expected)
		Harness.eq(#rig.results[a].rows, 4)
		Harness.eq(#rig.rewards, 0, "not paid until claimed or reset")
		rig.ctl.setReady(a, false)
		rig.untilPhase("Resetting")
		Harness.eq(#rig.rewards, 1, "bots earn nothing, the human is paid once")
		Harness.eq(rig.rewards[1].amount, expected)
		Harness.eq(rig.cleanups, 1)
		Harness.eq(rig.registry:aliveCount(), 0, "roster cleared")
		rig.untilPhase("Waiting")
		Harness.eq(
			table.concat(phases, ","),
			"Countdown,Spawning,Active,FinalPressure,Finished,Results,Resetting,Waiting"
		)
	end
)

Harness.test("not enough players: stays waiting; a friend arriving starts it", function()
	local rig = newRig()
	local a = rig.join(1)
	rig.ready(a)
	rig.step(40)
	Harness.eq(rig.ctx:getPhase(), "Waiting")
	Harness.eq(rig.published[#rig.published].note, "waiting_players")
	local b = rig.join(2)
	rig.ready(b)
	rig.untilPhase("Countdown", 2)
end)

Harness.test(
	"lobby waits for friends who have not pressed Play, but only for fillWaitSeconds",
	function()
		local rig = newRig()
		local a, b = rig.join(1), rig.join(2)
		local c = rig.join(3)
		rig.ready(a)
		rig.ready(b)
		rig.step(Config.Match.fillWaitSeconds - 1)
		Harness.eq(rig.ctx:getPhase(), "Waiting", "c is still in the menu, so wait a little")
		rig.untilPhase("Countdown", 3)
		rig.untilPhase("Spawning")
		Harness.eq(rig.registry:get(c), nil, "c did not press Play and is not in")
		Harness.eq(rig.registry:aliveCount(), 2)
	end
)

Harness.test(
	"player leaves during countdown: too few goes back to waiting and asks bots again",
	function()
		local rig, ids = humans(2)
		rig.untilPhase("Countdown", 2)
		rig.ctl.removeHuman(ids[2])
		rig.step(0.1)
		Harness.eq(rig.ctx:getPhase(), "Waiting")
		local sawAbort = false
		for _, st in rig.published do
			if st.note == "aborted_too_few" then
				sawAbort = true
			end
		end
		Harness.eq(sawAbort, true, "players were told why")
		Harness.eq(rig.ctl.getBotsRequested(), 0)
		Harness.eq(#rig.placed, 0)
	end
)

Harness.test("countdown with bots aborts when the last human leaves", function()
	local rig = newRig()
	local a = rig.join(1)
	rig.ready(a)
	rig.ctl.requestBots(3)
	rig.untilPhase("Countdown", 2)
	rig.ctl.removeHuman(a)
	rig.step(0.1)
	Harness.eq(rig.ctx:getPhase(), "Waiting")
end)

Harness.test("someone presses Play during the countdown and gets in", function()
	local rig, _ = humans(2)
	rig.untilPhase("Countdown", 2)
	local c = rig.join(3)
	rig.ready(c)
	rig.untilPhase("Spawning")
	Harness.eq(rig.registry:aliveCount(), 3)
	Harness.eq(#rig.placed, 3)
end)

Harness.test(
	"a leaver during spawn is out; the last one standing wins once Active starts",
	function()
		local rig, ids = humans(2)
		rig.untilPhase("Spawning")
		rig.ctl.removeHuman(ids[2])
		Harness.eq(rig.registry:aliveCount(), 1)
		rig.untilPhase("Active")
		rig.untilPhase("Finished", 3)
		local res = rig.ctl.getResult() :: MatchController.Result
		Harness.eq(res.winnerId, ids[1])
		Harness.eq(res.rows[2].participantId, ids[2], "the leaver still shows in the results")
	end
)

Harness.test("everyone leaves during spawn: reset without results", function()
	local rig, ids = humans(2)
	rig.untilPhase("Spawning")
	rig.ctl.removeHuman(ids[1])
	rig.ctl.removeHuman(ids[2])
	rig.step(0.1)
	Harness.eq(rig.ctx:getPhase(), "Resetting")
	Harness.eq(rig.cleanups, 1)
	rig.untilPhase("Waiting")
end)

Harness.test("no double elimination, kill credit once, zone gives none", function()
	local rig, ids = humans(3)
	rig.untilPhase("Active")
	Harness.eq(rig.kill(ids[2], ids[1]).applied, true)
	Harness.eq(rig.kill(ids[2], ids[3]).applied, false, "already dead")
	Harness.eq(rig.kill(ids[3], nil, "zone").applied, true)
	rig.untilPhase("Finished", 2)
	local res = rig.ctl.getResult() :: MatchController.Result
	local kills: { [string]: number } = {}
	for _, row in res.rows do
		kills[row.participantId] = row.eliminations
	end
	Harness.eq(kills[ids[1]], 1)
	Harness.eq(kills[ids[3]], 0)
	Harness.eq(res.winnerId, ids[1])
end)

Harness.test("a disconnected attacker keeps credit for a kill already made", function()
	local rig, ids = humans(3)
	rig.untilPhase("Active")
	rig.kill(ids[2], ids[1])
	rig.ctl.removeHuman(ids[1]) -- the killer leaves afterwards
	rig.step(0.5)
	local sentKiller: string? = nil
	for _, e in rig.eliminated do
		if e.victimId == ids[2] then
			sentKiller = e.killerId
		end
	end
	Harness.eq(sentKiller, ids[1])
	rig.untilPhase("Finished", 3)
	local res = rig.ctl.getResult() :: MatchController.Result
	for _, row in res.rows do
		if row.participantId == ids[1] then
			Harness.eq(row.eliminations, 1)
		end
	end
end)

Harness.test("last two eliminate each other together: draw, both first", function()
	local rig, ids = humans(2)
	rig.untilPhase("Active")
	rig.kill(ids[1], ids[2])
	rig.step(0.05)
	rig.kill(ids[2], ids[1])
	Harness.eq(rig.ctx:getPhase(), "Finished")
	local res = rig.ctl.getResult() :: MatchController.Result
	Harness.eq(res.outcome, "draw")
	Harness.eq(res.winnerId, nil)
	Harness.eq(res.rows[1].placement, 1)
	Harness.eq(res.rows[2].placement, 1)
	rig.untilPhase("Results", 4)
	Harness.eq(rig.results[ids[1]].draw, true)
	Harness.eq(rig.results[ids[1]].you.placement, 1)
end)

Harness.test(
	"a second elimination well after the first: the later one lasted longer and wins",
	function()
		local rig, ids = humans(2)
		rig.untilPhase("Active")
		rig.kill(ids[1], ids[2])
		rig.step(0.2) -- inside the settle window, outside the tie window
		rig.kill(ids[2], ids[1])
		Harness.eq(rig.ctx:getPhase(), "Finished")
		local res = rig.ctl.getResult() :: MatchController.Result
		Harness.eq(res.outcome, "win")
		Harness.eq(res.winnerId, ids[2])
	end
)

Harness.test("a shot after the settle window is dropped by the damage door", function()
	local rig, ids = humans(2)
	rig.untilPhase("Active")
	rig.kill(ids[1], ids[2])
	rig.step(0.5)
	Harness.eq(rig.ctx:getPhase(), "Finished")
	local late = rig.kill(ids[2], ids[1])
	Harness.eq(late.applied, false)
	Harness.eq((rig.ctl.getResult() :: MatchController.Result).winnerId, ids[2])
end)

Harness.test("the only survivor leaves just after the last kill: nobody is crowned", function()
	local rig, ids = humans(3)
	rig.untilPhase("Active")
	rig.kill(ids[3], ids[2])
	rig.step(1)
	rig.kill(ids[2], ids[1])
	rig.step(0.2)
	rig.ctl.removeHuman(ids[1])
	Harness.eq(rig.ctx:getPhase(), "Finished")
	local res = rig.ctl.getResult() :: MatchController.Result
	Harness.eq(res.outcome, "abandoned")
	Harness.eq(res.winnerId, nil)
end)

Harness.test("all participants disappear: clean reset, then waiting", function()
	local rig, ids = humans(3)
	rig.untilPhase("Active")
	for _, id in ids do
		rig.ctl.removeHuman(id)
	end
	rig.step(0.1)
	Harness.eq(rig.ctx:getPhase(), "Resetting")
	rig.untilPhase("Waiting")
	Harness.eq(rig.registry:aliveCount(), 0)
end)

Harness.test(
	"humans all leave but bots remain: match is called off, bots do not play on",
	function()
		local rig = newRig()
		local a = rig.join(1)
		rig.ready(a)
		rig.ctl.requestBots(3)
		rig.untilPhase("Active")
		rig.ctl.removeHuman(a)
		rig.step(0.1)
		Harness.eq(rig.ctx:getPhase(), "Resetting")
		Harness.eq(rig.ctl.getBotsRequested(), 0)
	end
)

Harness.test("pressure: Final pressure by time, and a draw when the clock runs out", function()
	local rig, _ = humans(
		3,
		{ finalPressureAliveCount = 0, finalPressureAtSeconds = 20, maxActiveSeconds = 40 }
	)
	rig.untilPhase("Active")
	rig.step(10)
	Harness.eq(rig.ctx:getPhase(), "Active")
	rig.untilPhase("FinalPressure", 15)
	rig.untilPhase("Finished", 30)
	local res = rig.ctl.getResult() :: MatchController.Result
	Harness.eq(res.reason, "timeout")
	Harness.eq(res.outcome, "draw")
	Harness.eq(#res.rows, 3)
end)

Harness.test("old match ids are ignored: stale events never touch the next match", function()
	local rig, ids = humans(2)
	rig.untilPhase("Active")
	local old = rig.ctx:getMatchId()
	rig.kill(ids[1], ids[2])
	rig.untilPhase("Waiting", 60)
	rig.ready(ids[1])
	rig.ready(ids[2])
	rig.untilPhase("Active", 30)
	Harness.eq(rig.ctx:getMatchId(), old + 1)
	local late = rig.router:apply({
		matchId = old,
		targetId = ids[1],
		amount = 999,
		cause = "bullet",
		sourceId = ids[2],
	})
	Harness.eq(late.applied, false)
	Harness.eq(late.reason, "stale-match")
	Harness.eq(rig.registry:aliveCount(), 2)
	-- A direct stale event is ignored too.
	rig.ctl.onEliminated({ matchId = old, victimId = ids[1], killerId = ids[2], cause = "bullet" })
	Harness.eq(rig.ctx:getPhase(), "Active")
end)

Harness.test("several matches in a row: nothing leaks, everyone paid once per match", function()
	local rig, ids = humans(2)
	for round = 1, 4 do
		rig.untilPhase("Active", 60)
		Harness.eq(rig.ctx:getMatchId(), round)
		Harness.eq(rig.registry:aliveCount(), 2, "everyone starts alive")
		rig.kill(
			if round % 2 == 1 then ids[2] else ids[1],
			if round % 2 == 1 then ids[1] else ids[2]
		)
		rig.untilPhase("Results", 10)
		Harness.eq(
			(rig.ctl.getResult() :: MatchController.Result).winnerId,
			if round % 2 == 1 then ids[1] else ids[2]
		)
		rig.ctl.setReady(ids[1], true) -- Play again
		rig.ctl.setReady(ids[2], true)
		rig.untilPhase("Resetting", 10)
		rig.untilPhase("Waiting", 10)
		Harness.eq(rig.registry:aliveCount(), 0)
	end
	Harness.eq(rig.cleanups, 4)
	Harness.eq(#rig.rewards, 8)
end)

Harness.test("ClaimResults: pays once, rejects a wrong match and too-early claims", function()
	local rig, ids = humans(2)
	rig.untilPhase("Active")
	local matchId = rig.ctx:getMatchId()
	Harness.eq(rig.ctl.claimResults(ids[1], matchId), false, "no results yet")
	rig.kill(ids[2], ids[1])
	rig.untilPhase("Results", 5)
	Harness.eq(rig.ctl.claimResults(ids[1], matchId + 1), false)
	Harness.eq(rig.ctl.claimResults(ids[1], matchId), true)
	Harness.eq(rig.ctl.claimResults(ids[1], matchId), false, "repeat pays nothing")
	rig.ctl.setReady(ids[1], false)
	rig.ctl.setReady(ids[2], false)
	rig.untilPhase("Waiting", 10)
	local paid: { [string]: number } = {}
	for _, r in rig.rewards do
		paid[r.id] = (paid[r.id] or 0) + 1
	end
	Harness.eq(paid[ids[1]], 1)
	Harness.eq(paid[ids[2]], 1, "the one who never tapped Claim is paid at reset")
end)

Harness.test(
	"a player who left while alive earns nothing; one who left after being out still does",
	function()
		local rig, ids = humans(3)
		rig.untilPhase("Active")
		rig.kill(ids[3], ids[1])
		rig.ctl.removeHuman(ids[3]) -- out already, then leaves
		rig.ctl.removeHuman(ids[2]) -- leaves while alive: forfeit
		rig.untilPhase("Results", 10)
		rig.untilPhase("Waiting", 30)
		local paid: { [string]: boolean } = {}
		for _, r in rig.rewards do
			paid[r.id] = true
		end
		Harness.eq(paid[ids[1]], true)
		Harness.eq(paid[ids[2]], nil)
	end
)

Harness.test("results close early once everyone chose, never before the minimum", function()
	local rig, ids = humans(2)
	rig.untilPhase("Active")
	rig.kill(ids[1], ids[2])
	rig.untilPhase("Results", 5)
	local startedAt = rig.now()
	rig.ctl.setReady(ids[1], true)
	rig.step(1)
	Harness.eq(rig.ctx:getPhase(), "Results", "waits for the other player")
	rig.ctl.setReady(ids[2], false)
	rig.untilPhase("Resetting", 10)
	Harness.truthy(
		rig.now() - startedAt >= Config.Match.resultsMinSeconds - 0.1,
		"shown the minimum time"
	)
	Harness.truthy(
		rig.now() - startedAt < Config.Match.resultsSeconds,
		"did not wait for the full timer"
	)
end)

Harness.test("results fall back to the timer when someone never chooses", function()
	local rig, ids = humans(2)
	rig.untilPhase("Active")
	rig.kill(ids[1], ids[2])
	rig.untilPhase("Results", 5)
	local startedAt = rig.now()
	rig.untilPhase("Resetting", 40)
	Harness.truthy(rig.now() - startedAt >= Config.Match.resultsSeconds - 0.2)
end)

Harness.test("going back to the lobby means you are not queued for the next match", function()
	local rig, ids = humans(2)
	rig.untilPhase("Active")
	rig.kill(ids[1], ids[2])
	rig.untilPhase("Results", 5)
	rig.ctl.setReady(ids[1], true)
	rig.ctl.setReady(ids[2], false)
	rig.untilPhase("Waiting", 20)
	Harness.eq(rig.ctl.isReady(ids[1]), true)
	Harness.eq(rig.ctl.isReady(ids[2]), false)
	rig.step(40)
	Harness.eq(rig.ctx:getPhase(), "Waiting", "one player alone does not start")
end)

Harness.test(
	"spectating: only eliminated players and late joiners; the server picks the target",
	function()
		local rig, ids = humans(3)
		rig.untilPhase("Spawning")
		local late = rig.join(9, "Late")
		rig.untilPhase("Active")
		Harness.eq(rig.spectate[ids[1]], nil, "living players are never sent a target")
		Harness.truthy(rig.spectate[late] ~= nil, "a late joiner may watch")
		rig.kill(ids[1], ids[2])
		Harness.truthy(rig.spectate[ids[1]] ~= nil, "the fallen start watching")
		local target = rig.spectate[ids[1]]
		Harness.truthy(target == ids[2] or target == ids[3])
		rig.ctl.cycleSpectate(ids[1], 1)
		Harness.truthy(rig.spectate[ids[1]] ~= target, "cycling moves to the other survivor")
		-- The watched player dies: the watcher is moved on at once.
		local watching = rig.spectate[ids[1]] :: string
		rig.kill(watching, if watching == ids[2] then ids[3] else ids[2])
		Harness.truthy(rig.spectate[ids[1]] ~= watching)
		-- A living player cannot ask to watch.
		rig.ctl.cycleSpectate(ids[2], 1)
		Harness.eq(rig.spectate[ids[2]], nil)
		rig.untilPhase("Results", 6)
		Harness.eq(rig.spectate[ids[1]], nil, "spectating ends when results show")
		Harness.eq(rig.spectate[late], nil)
	end
)

Harness.test("spectating: the fallen first watch whoever eliminated them", function()
	local rig, ids = humans(3)
	rig.untilPhase("Active")
	rig.kill(ids[1], ids[3])
	Harness.eq(rig.spectate[ids[1]], ids[3], "killer is watched first, not the first in line")
end)

Harness.test("a late joiner is not in the match and cannot be hurt", function()
	local rig, _ = humans(2)
	rig.untilPhase("Active")
	local z = rig.join(7)
	Harness.eq(rig.registry:get(z), nil)
	Harness.eq(rig.kill(z, nil).applied, false)
end)

Harness.test("public state shows survivors and the phase end time", function()
	local rig, ids = humans(3)
	rig.untilPhase("Active")
	local s = rig.published[#rig.published]
	Harness.eq(s.phase, "Active")
	Harness.eq(s.aliveCount, 3)
	Harness.eq(s.totalCount, 3)
	rig.kill(ids[3], nil, "zone")
	s = rig.published[#rig.published]
	Harness.eq(s.aliveCount, 2)
	local pub: any = nil
	for _, st in rig.published do
		if st.phase == "Countdown" then
			pub = st
		end
	end
	Harness.truthy(pub.phaseEndsAt ~= nil, "countdown has an end time")
end)

Harness.test("defeat info reaches everyone: who, by whom, place so far", function()
	local rig, ids = humans(3)
	rig.untilPhase("Active")
	rig.kill(ids[1], ids[2])
	local e = rig.eliminated[1]
	Harness.eq(e.victimId, ids[1])
	Harness.eq(e.killerId, ids[2])
	Harness.eq(e.killerName, "Player2")
	Harness.eq(e.placement, 3)
	Harness.eq(e.cause, "bullet")
	Harness.truthy(#rig.announcements >= 1)
end)

Harness.test("Final pressure starts when two are left", function()
	local rig, ids = humans(3)
	rig.untilPhase("Active")
	rig.kill(ids[3], ids[1])
	rig.step(0.1)
	Harness.eq(rig.ctx:getPhase(), "FinalPressure")
end)

Harness.test(
	"the zone's last warning starts Final pressure, once, only for the current match",
	function()
		local rig, _ = humans(3)
		rig.untilPhase("Active")
		local id = rig.ctx:getMatchId()
		rig.ctl.enterFinalPressure(id - 1)
		Harness.eq(rig.ctx:getPhase(), "Active", "old match ignored")
		rig.ctl.enterFinalPressure(id)
		Harness.eq(rig.ctx:getPhase(), "FinalPressure")
		rig.ctl.enterFinalPressure(id)
		Harness.eq(rig.ctx:getPhase(), "FinalPressure")
	end
)

Harness.test("a self-kill (own blast) gives no kill credit and shows no killer", function()
	local rig, ids = humans(2)
	rig.untilPhase("Active")
	rig.kill(ids[1], ids[1], "blast")
	local e = rig.eliminated[1]
	Harness.eq(e.victimId, ids[1])
	Harness.eq(e.killerId, nil)
	rig.untilPhase("Finished", 3)
	for _, row in (rig.ctl.getResult() :: MatchController.Result).rows do
		Harness.eq(row.eliminations, 0)
	end
end)

Harness.test("results go out as soon as the match ends, so the banner shows at once", function()
	local rig, ids = humans(2)
	rig.untilPhase("Active")
	rig.kill(ids[2], ids[1])
	rig.untilPhase("Finished", 2)
	Harness.eq(rig.results[ids[1]].you.placement, 1)
	Harness.eq(rig.results[ids[2]].you.placement, 2)
	Harness.truthy(rig.results[ids[1]].endsAt > rig.now(), "close time is in the future")
end)

-- ===== piece 26: friends who join =====

Harness.test("a friend who joins during a full countdown takes a bot's seat", function()
	local rig = newRig()
	local host = rig.join(1, "Host")
	rig.ready(host)
	Harness.eq(
		rig.ctl.requestBots(Config.Match.maxParticipants - 1),
		Config.Match.maxParticipants - 1
	)
	rig.untilPhase("Countdown", 1)
	local friend = rig.join(2, "Friend")
	rig.ready(friend)
	rig.untilPhase("Spawning")
	local seen: { [string]: boolean } = {}
	for _, s in rig.placed do
		seen[s.id] = true
	end
	Harness.truthy(seen[host] and seen[friend], "host and friend are both in")
	Harness.eq(#rig.placed, Config.Match.maxParticipants, "still a full match")
end)

Harness.test("a friend who joins a match full of people waits, then plays the next one", function()
	local rig = newRig({ maxParticipants = 2 })
	local a = rig.join(1, "A")
	local b = rig.join(2, "B")
	rig.ready(a)
	rig.ready(b)
	rig.untilPhase("Countdown")
	local friend = rig.join(3, "Friend")
	rig.ready(friend)
	rig.untilPhase("Spawning")
	Harness.eq(#rig.placed, 2)
	Harness.eq(rig.registry:get(friend), nil, "friend waits")
	rig.untilPhase("Active")
	Harness.eq(rig.spectate[friend] ~= nil, true, "friend watches")
	rig.kill(b, a)
	rig.untilPhase("Results", 5)
	rig.ready(a)
	rig.ctl.setReady(b, false)
	rig.untilPhase("Waiting", 40)
	Harness.eq(rig.ctl.isReady(friend), true, "friend still queued")
	rig.untilPhase("Countdown", 20)
	rig.untilPhase("Spawning")
	Harness.truthy(rig.registry:get(friend) ~= nil, "friend plays the next match")
	Harness.truthy(rig.registry:get(a) ~= nil, "with the host")
end)

return { newRig = newRig, humans = humans }
