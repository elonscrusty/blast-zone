--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local ZoneModel = require("../src/server/Zone/ZoneModel")
local ZoneView = require("../src/client/Zone/ZoneView")

-- the first 220-stud version: these checks use its numbers (the live zone is stretched by Config.Arena.scale)
local cfg: any = Config.zoneAt(1)
local timeline = ZoneModel.build(cfg)

local function at(t: number)
	return ZoneModel.sample(timeline, t)
end

Harness.test("circle rests, warns, closes, rests", function()
	Harness.eq(at(10).phase, "Holding")
	Harness.eq(at(10).stage, 0)
	Harness.near(at(10).radius, cfg.initialRadius)
	Harness.eq(at(40).phase, "Warning")
	Harness.near(at(40).radius, cfg.initialRadius, 1e-9, "does not move during a warning")
	Harness.near(at(40).toRadius, 105)
	Harness.near(at(40).secondsToNext, 5)
	Harness.eq(at(50).phase, "Closing")
	Harness.truthy(at(50).radius < cfg.initialRadius and at(50).radius > 105)
	Harness.eq(at(70).phase, "Holding")
	Harness.near(at(70).radius, 105)
	Harness.eq(at(70).stage, 1)
end)

Harness.test("radius only gets smaller and never jumps", function()
	local last = at(0).radius
	for i = 0, 2500 do
		local r = at(i * 0.1).radius
		Harness.truthy(r <= last + 1e-9, `radius grew at {i * 0.1}`)
		Harness.truthy(last - r < 0.5, `radius jumped at {i * 0.1}`)
		last = r
	end
	Harness.near(last, cfg.suddenDeath.targetRadius)
end)

Harness.test("outside damage: none at first, then each stage, then sudden death", function()
	Harness.near(at(10).outsideDamagePerSecond, 0)
	Harness.near(at(40).outsideDamagePerSecond, 0, 1e-9, "warning of stage 1 still hurts nothing")
	Harness.near(at(50).outsideDamagePerSecond, 2)
	Harness.near(at(80).outsideDamagePerSecond, 2, 1e-9, "warning of stage 2 keeps stage 1 damage")
	Harness.near(at(90).outsideDamagePerSecond, 4)
	Harness.near(at(160).outsideDamagePerSecond, 12)
	Harness.near(at(171).outsideDamagePerSecond, cfg.suddenDeath.damagePerSecond)
end)

Harness.test("sudden death is its own stage that keeps closing", function()
	Harness.eq(at(169).suddenDeath, false)
	Harness.eq(at(171).suddenDeath, true)
	Harness.eq(at(171).stage, ZoneModel.SUDDEN_DEATH_STAGE)
	Harness.eq(at(171).phase, "Closing")
	Harness.eq(at(200).phase, "Holding")
	Harness.near(at(200).radius, cfg.suddenDeath.targetRadius)
end)

Harness.test("final pressure begins with the last warning", function()
	Harness.eq(at(149).finalPressure, false)
	Harness.eq(at(150).finalPressure, true)
end)

Harness.test("edge: exactly on the line is safe, tolerance extends it, beyond is not", function()
	local s = at(10)
	local r = s.radius
	Harness.eq(ZoneModel.isInside(s, r, 0, 0), true, "on the line")
	Harness.eq(ZoneModel.isInside(s, r + 0.4, 0, 0), false, "past the line, no tolerance")
	Harness.eq(ZoneModel.isInside(s, r + 0.4, 0, 0.5), true, "inside tolerance")
	Harness.eq(ZoneModel.isInside(s, r + 0.6, 0, 0.5), false, "past tolerance")
	Harness.eq(ZoneModel.isInside(s, 0 / 0, 0, 0.5), false, "NaN is never safe")
end)

Harness.test("nearestSafePoint pulls outside points in and leaves inside points alone", function()
	local s = at(70) -- radius 105
	local x, z = ZoneModel.nearestSafePoint(s, 200, 0, 5)
	Harness.near(x, 100)
	Harness.near(z, 0)
	local x2, z2 = ZoneModel.nearestSafePoint(s, 10, 10, 5)
	Harness.eq(x2, 10)
	Harness.eq(z2, 10)
end)

Harness.test("a bad config is refused", function()
	local function broken(change: (any) -> ()): boolean
		local copy: any = table.clone(cfg)
		copy.suddenDeath = table.clone(cfg.suddenDeath)
		copy.stages = {}
		for i, stage in cfg.stages do
			copy.stages[i] = table.clone(stage)
		end
		change(copy)
		return (pcall(ZoneModel.build, copy))
	end
	Harness.eq(broken(function() end), true, "untouched copy is fine")
	Harness.eq(
		broken(function(c)
			c.stages[2].targetRadius = 500
		end),
		false,
		"growing circle"
	)
	Harness.eq(
		broken(function(c)
			c.stages[1].closeAt = c.stages[1].warnAt
		end),
		false,
		"no warning"
	)
	Harness.eq(
		broken(function(c)
			c.initialRadius = 0 / 0
		end),
		false,
		"NaN"
	)
	Harness.eq(
		broken(function(c)
			c.stages[2].warnAt = 50
		end),
		false,
		"warning while the last circle is still closing"
	)
	Harness.eq(
		broken(function(c)
			c.suddenDeath.startsAt = 100
		end),
		false,
		"sudden death too early"
	)
end)

-- ---------------------------------------------------------------------------------------------
-- Runner
-- ---------------------------------------------------------------------------------------------

type Hit = { id: string, amount: number, stage: number }

local function setup(targets: { ZoneModel.Target })
	local clock = { t = 1000 }
	local hits: { Hit } = {}
	local events: { ZoneModel.Event } = {}
	local sent: { ZoneModel.StatePayload } = {}
	local state = { targets = targets }
	local runner = ZoneModel.newRunner({
		config = cfg,
		now = function()
			return clock.t
		end,
		getTargets = function()
			return state.targets
		end,
		applyDamage = function(id, amount, stage)
			table.insert(hits, { id = id, amount = amount, stage = stage })
		end,
		publish = function(s)
			table.insert(sent, s)
		end,
		onEvent = function(e)
			table.insert(events, e)
		end,
	})
	local function run(seconds: number)
		for _ = 1, math.round(seconds * 10) do
			clock.t += 0.1
			runner:step()
		end
	end
	return runner, run, hits, events, sent, state, clock
end

local function kinds(events: { ZoneModel.Event }): string
	local out = {}
	for _, e in events do
		table.insert(out, e.kind)
	end
	return table.concat(out, ",")
end

Harness.test("nothing is damaged before start or after stop", function()
	local runner, run, hits = setup({ { id = "p1", x = 5000, z = 0 } })
	run(100)
	Harness.eq(#hits, 0, "not started")
	runner:start(1)
	run(60)
	local before = #hits
	runner:stop()
	run(60)
	Harness.eq(#hits, before, "stopped")
end)

Harness.test("start sends the first circle with the match id and server times", function()
	local runner, _, _, _, sent, _, clock = setup({})
	runner:start(7)
	Harness.eq(#sent, 1)
	Harness.eq(sent[1].matchId, 7)
	Harness.eq(sent[1].stage, 0)
	Harness.near(sent[1].fromRadius, cfg.initialRadius)
	Harness.near(sent[1].startedAt, clock.t)
end)

Harness.test("only those outside are damaged, by the current stage", function()
	local runner, run, hits = setup({
		{ id = "p1", x = 0, z = 0 },
		{ id = "p2", x = 100, z = 0 },
		{ id = "p3", x = 130, z = 0 },
	})
	runner:start(1)
	run(30)
	Harness.eq(#hits, 0, "nothing hurts before the first closing")
	run(30) -- now 60 s: stage 1 closed to 105, p3 is outside since the circle passed 130
	Harness.truthy(#hits > 0)
	for _, h in hits do
		Harness.eq(h.id, "p3")
		Harness.eq(h.stage, 1)
		Harness.near(h.amount, 2 * cfg.tickSeconds)
	end
end)

Harness.test("the edge tolerance spares a player just past the line", function()
	local runner, run, hits =
		setup({ { id = "p1", x = 105.3, z = 0 }, { id = "p2", x = 106, z = 0 } })
	runner:start(1)
	run(75)
	for _, h in hits do
		Harness.eq(h.id, "p2")
	end
	Harness.truthy(#hits > 0)
end)

Harness.test("only the live list is hurt: someone removed stops taking damage", function()
	local runner, run, hits, _, _, state =
		setup({ { id = "p1", x = 5000, z = 0 }, { id = "p2", x = 5000, z = 0 } })
	runner:start(1)
	run(50)
	state.targets = { { id = "p2", x = 5000, z = 0 } }
	local before = #hits
	run(5)
	for i = before + 1, #hits do
		Harness.eq(hits[i].id, "p2")
	end
end)

Harness.test("events and ZoneState messages come once each, in order", function()
	local runner, run, _, events, sent = setup({})
	runner:start(1)
	run(90)
	Harness.eq(
		kinds(events),
		"WarningStarted,ClosingStarted,ClosingEnded,WarningStarted,ClosingStarted"
	)
	Harness.near(events[1].elapsed, 35, 0.15)
	Harness.eq(events[1].stage, 1)
	Harness.eq(#sent, 5, "start + 2 warnings + 2 closings")
	Harness.truthy(sent[2].warningEndsAt ~= nil, "warning message has warningEndsAt")
	Harness.eq(sent[3].warningEndsAt, nil)
end)

Harness.test("final pressure fires once, with the last warning", function()
	local runner, run, _, events = setup({})
	runner:start(1)
	run(175)
	local count = 0
	for _, e in events do
		if e.kind == "FinalPressure" then
			count += 1
			Harness.near(e.elapsed, 150, 0.15)
		end
	end
	Harness.eq(count, 1)
	Harness.eq(events[#events].kind, "SuddenDeath")
end)

Harness.test("sudden death hurts far more outside", function()
	local runner, run, hits = setup({ { id = "p1", x = 5000, z = 0 } })
	runner:start(1)
	run(172)
	local last = hits[#hits]
	Harness.eq(last.stage, ZoneModel.SUDDEN_DEATH_STAGE)
	Harness.near(last.amount, cfg.suddenDeath.damagePerSecond * cfg.tickSeconds)
end)

Harness.test("a long server hitch does not pay out missed ticks", function()
	local runner, run, hits, _, _, _, clock = setup({ { id = "p1", x = 5000, z = 0 } })
	runner:start(1)
	run(50)
	local before = #hits
	clock.t += 20
	runner:step()
	Harness.eq(#hits - before, 1)
end)

Harness.test("starting again is a clean new match", function()
	local runner, run, hits, events, sent = setup({ { id = "p1", x = 0, z = 0 } })
	runner:start(1)
	run(50)
	local eventCount = #events
	runner:start(2)
	Harness.eq(sent[#sent].matchId, 2)
	Harness.eq(sent[#sent].stage, 0)
	Harness.near(sent[#sent].fromRadius, cfg.initialRadius)
	run(5)
	Harness.eq(#events, eventCount, "no old-match events")
	local s = runner:getSample() :: ZoneModel.Sample
	Harness.eq(s.stage, 0)
	Harness.eq(#hits, 0)
end)

Harness.test("getState gives a late joiner the live circle", function()
	local runner, run = setup({})
	Harness.eq(runner:getState(), nil, "no zone yet")
	runner:start(3)
	run(50)
	local s = runner:getState() :: ZoneModel.StatePayload
	Harness.eq(s.matchId, 3)
	Harness.eq(s.stage, 1)
	runner:stop()
	Harness.eq(runner:getState(), nil, "stopped")
end)

-- ---------------------------------------------------------------------------------------------
-- Client view
-- ---------------------------------------------------------------------------------------------

Harness.test("the client circle matches the server circle at every moment", function()
	local runner, run, _, _, _, _, clock = setup({})
	runner:start(1)
	local start = clock.t
	local latest: ZoneModel.StatePayload = runner:getState() :: ZoneModel.StatePayload
	for i = 1, 1800 do
		clock.t += 0.1
		runner:step()
		local fresh = runner:getState() :: ZoneModel.StatePayload
		-- a client only ever has the newest message; take it when the stage or phase moved on
		if
			fresh.stage ~= latest.stage
			or (fresh.warningEndsAt == nil) ~= (latest.warningEndsAt == nil)
		then
			latest = fresh
		end
		local server = (runner:getSample() :: ZoneModel.Sample).radius
		local client = ZoneView.radiusAt(latest :: any, clock.t)
		Harness.near(client, server, 1e-6, `radius differs at {i * 0.1} (start {start})`)
	end
	run(0)
end)

Harness.test("view reports warning and closing countdowns", function()
	local state: any = {
		matchId = 1,
		centerX = 0,
		centerZ = 0,
		fromRadius = 156,
		toRadius = 105,
		startedAt = 145,
		endsAt = 165,
		warningEndsAt = 145,
		damagePerSecond = 0,
		stage = 1,
	}
	local v = ZoneView.viewOf(state, 140)
	Harness.eq(v.phase, "Warning")
	Harness.near(v.secondsToClose :: number, 5)
	Harness.near(v.radius, 156)
	state.warningEndsAt = nil
	local c = ZoneView.viewOf(state, 155)
	Harness.eq(c.phase, "Closing")
	Harness.near(c.radius, 130.5)
	Harness.near(c.secondsToSettle :: number, 10)
	Harness.eq(ZoneView.viewOf(state, 170).phase, "Holding")
end)

Harness.test("the client shows the ring only for the live match", function()
	ZoneView.clear()
	local state: any = {
		matchId = 2,
		centerX = 0,
		centerZ = 0,
		fromRadius = 156,
		toRadius = 156,
		startedAt = 10,
		endsAt = 10,
		damagePerSecond = 0,
		stage = 0,
	}
	ZoneView.setState(state)
	Harness.eq(ZoneView.get(11), nil, "not live yet")
	ZoneView.setLive(true, 1)
	Harness.eq(ZoneView.get(11), nil, "old match")
	ZoneView.setLive(true, 2)
	Harness.truthy(ZoneView.get(11) ~= nil)
	ZoneView.setLive(false, 2)
	Harness.eq(ZoneView.get(11), nil, "match left combat")
	ZoneView.setLive(true, 3)
	Harness.eq(ZoneView.get(11), nil, "new match, old circle dropped")
	ZoneView.setState(state)
	ZoneView.setLive(true, 3)
	Harness.eq(ZoneView.get(11), nil, "a stale ZoneState cannot show in a newer match")
	ZoneView.clear()
end)

-- A fighter standing on the old edge must be able to walk to the new circle well inside the warning and the
-- closing time, at the slowest hero's pace (video-feel pass: the run is 11 studs/s, so this is checked).
Harness.test(
	"zone: the slowest hero on the old edge reaches the next circle in a third of the window",
	function()
		local pace = Config.Movement.walkSpeed * Config.Heroes.speedMin
		local previous = Config.Zone.initialRadius
		for i, stage in Config.Zone.stages do
			local travelSeconds = (previous - stage.targetRadius) / pace
			local window = stage.closeAt + stage.closeSeconds - stage.warnAt
			Harness.truthy(
				travelSeconds <= window / 3,
				`stage {i}: {travelSeconds} s of walking in a {window} s window`
			)
			previous = stage.targetRadius
		end
	end
)
