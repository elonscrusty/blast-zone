--!strict
-- Test bots (piece 09): thinking, running, auto-fill. All pure, no Roblox.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local BotTuning = require("../src/server/Bots/BotTuning")
local BotBrain = require("../src/server/Bots/BotBrain")
local BotRoster = require("../src/server/Bots/BotRoster")
local BotRunner = require("../src/server/Bots/BotRunner")

local T = BotTuning.from(Config)
local RANGE = Config.Weapons.Firearm.range

local function noRand(): number
	return 0.5 -- zero aim error, no surprises
end

local function selfAt(x: number, z: number, patch: { [string]: any }?): BotBrain.Self
	local me: BotBrain.Self = {
		id = "b1",
		pos = { x = x, z = z },
		health = 100,
		maxHealth = 100,
		ammo = 12,
		magazine = 12,
		reloading = false,
		canFire = true,
		slideReady = true,
	}
	for k, v in patch or {} do
		(me :: any)[k] = v
	end
	return me
end

local function view(me: BotBrain.Self, patch: { [string]: any }?): BotBrain.View
	local v: BotBrain.View = {
		now = 10,
		me = me,
		others = {},
		pickups = {},
		zone = nil,
		range = RANGE,
		canSee = function()
			return true
		end,
		rand = noRand,
		tuning = T,
	}
	for k, val in patch or {} do
		(v :: any)[k] = val
	end
	return v
end

local function enemy(id: string, x: number, z: number): BotBrain.Body
	return { id = id, pos = { x = x, z = z } }
end

-- Think once to "see" the enemy, then again after the reaction delay.
local function thinkAfterReaction(v: BotBrain.View, state: BotBrain.State): BotBrain.Intent
	BotBrain.think(v, state)
	v.now += T.reactionTime + 0.01
	return BotBrain.think(v, state)
end

-- ===== tuning =====

Harness.test("bot tuning follows Config and has no stat advantages", function()
	Harness.eq(T.sightRange, Config.Bots.sightRange)
	Harness.eq(T.reactionTime, Config.Bots.reactionSeconds)
	Harness.eq(T.aloneBelow, Config.Match.minToStart)
	for key in T :: any do
		local lower = string.lower(tostring(key))
		for _, banned in { "health", "damage", "speed", "ammo", "cooldown" } do
			Harness.truthy(
				not string.find(lower, banned, 1, true),
				"bots must not carry their own " .. banned .. " numbers: " .. tostring(key)
			)
		end
	end
end)

Harness.test("tuning refuses a config that gives bots hidden advantages", function()
	local bad = table.clone(Config.Bots)
	bad.hiddenStatAdvantage = true
	local ok = pcall(BotTuning.from, { Bots = bad, Match = Config.Match } :: any)
	Harness.eq(ok, false)
end)

-- ===== brain: seeing and shooting =====

Harness.test("bot shoots an enemy in the clear, but only after the reaction delay", function()
	local state = BotBrain.newState()
	local v = view(selfAt(0, 0), { others = { enemy("p1", 30, 0) } })
	local first = BotBrain.think(v, state)
	Harness.eq(first.fire, false, "no instant snap shot")
	Harness.eq(first.mode, "fight")
	v.now += T.reactionTime + 0.01
	local second = BotBrain.think(v, state)
	Harness.eq(second.fire, true)
	Harness.near(second.aimX, 1, 1e-6, "aims at the enemy")
	Harness.near(second.aimZ, 0, 1e-6)
end)

Harness.test("bot cannot see or shoot through a wall", function()
	local v = view(selfAt(0, 0), {
		others = { enemy("p1", 30, 0) },
		canSee = function()
			return false
		end,
	})
	local intent = thinkAfterReaction(v, BotBrain.newState())
	Harness.eq(intent.fire, false)
	Harness.truthy(intent.mode ~= "fight", "walled-off enemy is not a target")
end)

Harness.test(
	"bot ignores enemies past its sight range and never fires past weapon range",
	function()
		local far = view(selfAt(0, 0), { others = { enemy("p1", T.sightRange + 5, 0) } })
		Harness.eq(thinkAfterReaction(far, BotBrain.newState()).fire, false)

		-- Seen (inside sight) but beyond the gun's range: it closes in instead of firing.
		local shortGun = view(selfAt(0, 0), { range = 20, others = { enemy("p1", 40, 0) } })
		local intent = thinkAfterReaction(shortGun, BotBrain.newState())
		Harness.eq(intent.fire, false)
		Harness.truthy(intent.moveX > 0.3, "moves toward the enemy")
	end
)

Harness.test("bot does not fire while reloading or when the server would refuse", function()
	local others = { enemy("p1", 30, 0) }
	local reloading = view(selfAt(0, 0, { reloading = true }), { others = others })
	Harness.eq(thinkAfterReaction(reloading, BotBrain.newState()).fire, false)
	local cooling = view(selfAt(0, 0, { canFire = false }), { others = others })
	Harness.eq(thinkAfterReaction(cooling, BotBrain.newState()).fire, false)
end)

Harness.test("bot reloads when empty, and early when nobody is around", function()
	local empty = BotBrain.think(view(selfAt(0, 0, { ammo = 0 })), BotBrain.newState())
	Harness.eq(empty.reload, true)
	local lowQuiet = BotBrain.think(view(selfAt(0, 0, { ammo = 3 })), BotBrain.newState())
	Harness.eq(lowQuiet.reload, true)
	local lowButBusy = BotBrain.think(
		view(selfAt(0, 0, { ammo = 3 }), { others = { enemy("p1", 30, 0) } }),
		BotBrain.newState()
	)
	Harness.eq(lowButBusy.reload, false, "keeps fighting with a partial magazine")
	local alreadyReloading =
		BotBrain.think(view(selfAt(0, 0, { ammo = 0, reloading = true })), BotBrain.newState())
	Harness.eq(alreadyReloading.reload, false)
end)

-- ===== brain: moving =====

Harness.test("bot backs away when an enemy is too close and strafes at range", function()
	local close =
		BotBrain.think(view(selfAt(0, 0), { others = { enemy("p1", 8, 0) } }), BotBrain.newState())
	Harness.truthy(close.moveX < -0.3, "backs off")

	local ideal = RANGE * T.idealRangeFraction
	local mid = BotBrain.think(
		view(selfAt(0, 0), { others = { enemy("p1", ideal, 0) } }),
		BotBrain.newState()
	)
	Harness.near(mid.moveX, 0, 1e-6, "no radial movement at ideal range")
	Harness.truthy(math.abs(mid.moveZ) > 0.9, "moves sideways")
end)

Harness.test("bot heads for the safe area when outside it", function()
	local zone: BotBrain.Zone = { center = { x = 0, z = 0 }, radius = 50 }
	local intent = BotBrain.think(view(selfAt(80, 0), { zone = zone }), BotBrain.newState())
	Harness.eq(intent.mode, "zone")
	Harness.near(intent.moveX, -1, 1e-6)
end)

Harness.test("bot keeps shooting while it runs into the zone", function()
	local zone: BotBrain.Zone = { center = { x = 0, z = 0 }, radius = 50 }
	local v = view(selfAt(80, 0), { zone = zone, others = { enemy("p1", 80, 30) } })
	local intent = thinkAfterReaction(v, BotBrain.newState())
	Harness.eq(intent.mode, "zone")
	Harness.truthy(intent.moveX < -0.9)
	Harness.eq(intent.fire, true)
end)

Harness.test("bot at low health runs away and slides only when the slide is ready", function()
	local others = { enemy("p1", 25, 0) }
	local hurt = view(selfAt(0, 0, { health = 20 }), { others = others })
	local intent = BotBrain.think(hurt, BotBrain.newState())
	Harness.eq(intent.mode, "flee")
	Harness.truthy(intent.moveX < -0.3, "away from the enemy")
	Harness.eq(intent.slide, true)

	local noSlide = view(selfAt(0, 0, { health = 20, slideReady = false }), { others = others })
	Harness.eq(BotBrain.think(noSlide, BotBrain.newState()).slide, false)
end)

Harness.test("bot walks to a pickup it can see, ignores one behind a wall", function()
	local pickups: { BotBrain.Pickup } = { { id = "o1", pos = { x = 0, z = 20 } } }
	local seen = BotBrain.think(view(selfAt(0, 0), { pickups = pickups }), BotBrain.newState())
	Harness.eq(seen.mode, "loot")
	Harness.near(seen.moveZ, 1, 1e-6)

	local hidden = BotBrain.think(
		view(selfAt(0, 0), {
			pickups = pickups,
			canSee = function()
				return false
			end,
		}),
		BotBrain.newState()
	)
	Harness.eq(hidden.mode, "roam")

	local tooFar: { BotBrain.Pickup } = { { id = "o2", pos = { x = 0, z = T.pickupRange + 10 } } }
	Harness.eq(
		BotBrain.think(view(selfAt(0, 0), { pickups = tooFar }), BotBrain.newState()).mode,
		"roam"
	)
end)

Harness.test("bot that is stuck drops its goal and steps sideways", function()
	local state = BotBrain.newState()
	local v = view(selfAt(0, 0))
	local first = BotBrain.think(v, state)
	Harness.truthy(first.moveX ~= 0 or first.moveZ ~= 0, "roams")
	local goal = state.goal
	-- A second later it has not moved at all.
	v.now += T.stuckCheck + 0.1
	local after = BotBrain.think(v, state)
	Harness.truthy(state.goal ~= goal, "new goal after being stuck")
	-- sidestep is perpendicular to what it wanted
	local wanted = BotBrain.think(view(selfAt(0, 0), { now = v.now + 5 }), BotBrain.newState())
	Harness.truthy(after.moveX ~= 0 or after.moveZ ~= 0)
	Harness.truthy(wanted ~= nil)
	Harness.truthy(state.sideUntil > v.now, "sidestep timer set")
end)

Harness.test("bot remembers where it last saw a target for a moment, then gives up", function()
	local state = BotBrain.newState()
	local seen = view(selfAt(0, 0), { others = { enemy("p1", 40, 0) } })
	BotBrain.think(seen, state)
	local hidden = view(selfAt(0, 0), {
		now = seen.now + 0.5,
		others = { enemy("p1", 40, 0) },
		canSee = function()
			return false
		end,
	})
	local searching = BotBrain.think(hidden, state)
	Harness.eq(searching.mode, "search")
	Harness.truthy(searching.moveX > 0.9)
	hidden.now = seen.now + T.memoryTime + 1
	Harness.truthy(BotBrain.think(hidden, state).mode ~= "search")
end)

-- ===== roster / auto-fill =====

Harness.test("bots top the match up to the target and never past the maximum", function()
	Harness.eq(BotRoster.botsToAdd(T, 1, 0), T.fillTo - 1)
	Harness.eq(BotRoster.botsToAdd(T, 1, 2), T.fillTo - 3)
	Harness.eq(BotRoster.botsToAdd(T, 3, T.fillTo), 0)
	local big = table.clone(T)
	big.fillTo = 50
	Harness.eq(BotRoster.botsToAdd(big, 1, 0), T.maxParticipants - 1)
end)

Harness.test("a lone player gets a countdown, then bots join once", function()
	local fill = BotRoster.newFill()
	local r = BotRoster.updateFill(T, fill, 100, true, 1)
	Harness.eq(r.action, "countdown")
	Harness.eq(r.secondsLeft, T.autoFillDelay)
	r = BotRoster.updateFill(T, fill, 100 + T.autoFillDelay - 3.2, true, 1)
	Harness.eq(r.action, "countdown")
	Harness.eq(r.secondsLeft, 4)
	r = BotRoster.updateFill(T, fill, 100 + T.autoFillDelay, true, 1)
	Harness.eq(r.action, "fill")
	r = BotRoster.updateFill(T, fill, 100 + T.autoFillDelay + 1, true, 1)
	Harness.eq(r.action, "none", "fills only once per wait")
end)

Harness.test("auto-fill resets when a friend joins or the match starts", function()
	local fill = BotRoster.newFill()
	BotRoster.updateFill(T, fill, 100, true, 1)
	Harness.eq(BotRoster.updateFill(T, fill, 105, true, T.fillTo).action, "none")
	-- friend left again: the count restarts from full
	local r = BotRoster.updateFill(T, fill, 106, true, 1)
	Harness.eq(r.secondsLeft, T.autoFillDelay)
	BotRoster.updateFill(T, fill, 200, true, 1)
	BotRoster.updateFill(T, fill, 300, true, 1) -- fills
	Harness.eq(fill.filled, true)
	BotRoster.updateFill(T, fill, 301, false, 1) -- match began
	Harness.eq(fill.filled, false, "ready for the next wait")
	Harness.eq(
		BotRoster.updateFill(T, fill, 400, true, 0).action,
		"none",
		"nobody here is not alone"
	)
end)

Harness.test(
	"a part-full lobby is topped up after the shorter wait, with no alone banner",
	function()
		local fill = BotRoster.newFill()
		local r = BotRoster.updateFill(T, fill, 100, true, T.aloneBelow)
		Harness.eq(r.action, "countdown")
		Harness.eq(r.alone, false)
		Harness.eq(r.secondsLeft, T.topUpDelay)
		r = BotRoster.updateFill(T, fill, 100 + T.topUpDelay, true, T.aloneBelow)
		Harness.eq(r.action, "fill")
		Harness.eq(BotRoster.botsToAdd(T, T.aloneBelow, 0), T.fillTo - T.aloneBelow)
		Harness.eq(
			BotRoster.updateFill(T, BotRoster.newFill(), 1, true, T.fillTo).action,
			"none",
			"a full lobby needs no bots"
		)
	end
)

Harness.test("Add bots now: only when alone and waiting, with a cooldown", function()
	local ok = BotRoster.checkAddNow(T, true, 1, 50, nil)
	Harness.eq(ok, true)
	Harness.eq(BotRoster.checkAddNow(T, false, 1, 50, nil), false, "not while a match runs")
	Harness.eq(
		BotRoster.checkAddNow(T, true, T.aloneBelow, 50, nil),
		false,
		"not when others are here"
	)
	Harness.eq(BotRoster.checkAddNow(T, true, 1, 50, 49), false, "cooldown")
	Harness.eq(BotRoster.checkAddNow(T, true, 1, 50 + T.tapGap, 50), true)
end)

-- ===== runner =====

type Log = { string }

local function fakeWorld(log: Log, opts: { [string]: any }?)
	local o = opts or {}
	local clock = { t = 0 }
	local state: { [string]: BotBrain.Self } = o.states or { b1 = selfAt(0, 0) }
	local world: BotRunner.World = {
		now = function()
			return clock.t
		end,
		isActive = function()
			return if o.active == nil then true else o.active
		end,
		selfState = function(id)
			return state[id]
		end,
		others = function(id)
			local out = {}
			for other, s in state do
				if other ~= id then
					table.insert(out, { id = other, pos = s.pos })
				end
			end
			for _, extra in o.extraOthers or {} do
				table.insert(out, extra)
			end
			return out
		end,
		pickups = function()
			return {}
		end,
		zone = function()
			return nil
		end,
		weaponRange = function()
			return RANGE
		end,
		canSee = function()
			return true
		end,
		move = function(id, x, z)
			table.insert(log, `move {id} {x == 0 and z == 0}`)
		end,
		fire = function(id)
			table.insert(log, `fire {id}`)
		end,
		reload = function(id)
			table.insert(log, `reload {id}`)
		end,
		slide = function(id)
			table.insert(log, `slide {id}`)
		end,
	}
	return world, clock, state
end

local function count(log: Log, prefix: string): number
	local n = 0
	for _, line in log do
		if string.sub(line, 1, #prefix) == prefix then
			n += 1
		end
	end
	return n
end

Harness.test("runner thinks on its interval and fires through the world", function()
	local log: Log = {}
	local world, clock = fakeWorld(log, { extraOthers = { enemy("p1", 30, 0) } })
	local runner = BotRunner.new(world, T, noRand)
	runner:add("b1")
	for _ = 1, 100 do
		clock.t += 0.05
		runner:step()
	end
	-- 5 seconds of play: it must have fired, but no faster than the interval allows
	local shots = count(log, "fire")
	Harness.truthy(shots > 10, "fires")
	Harness.truthy(shots <= 5 / T.thinkInterval, "never faster than it thinks")
end)

Harness.test("runner holds bots still outside combat and stops them once", function()
	local log: Log = {}
	local world, clock = fakeWorld(log, { active = false })
	local runner = BotRunner.new(world, T, noRand)
	runner:add("b1")
	for _ = 1, 20 do
		clock.t += 0.1
		runner:step()
	end
	Harness.eq(count(log, "fire"), 0)
	Harness.eq(count(log, "move"), 0, "already stopped, nothing to send")
end)

Harness.test("runner stops a bot when combat ends", function()
	local log: Log = {}
	local active = { v = true }
	local world, clock = fakeWorld(log)
	world.isActive = function()
		return active.v
	end
	local runner = BotRunner.new(world, T, noRand)
	runner:add("b1")
	for _ = 1, 10 do
		clock.t += 0.1
		runner:step()
	end
	active.v = false
	clock.t += 0.1
	runner:step()
	Harness.eq(log[#log], "move b1 true", "ends with a stop")
	local before = #log
	runner:step()
	Harness.eq(#log, before, "stop sent once")
end)

Harness.test("runner drops an eliminated bot and sends nothing for it again", function()
	local log: Log = {}
	local world, clock, states = fakeWorld(log, { extraOthers = { enemy("p1", 30, 0) } })
	local runner = BotRunner.new(world, T, noRand)
	runner:add("b1")
	for _ = 1, 20 do
		clock.t += 0.1
		runner:step()
	end
	states.b1 = nil :: any
	clock.t += 0.1
	runner:step()
	Harness.eq(runner:count(), 0)
	local before = #log
	for _ = 1, 10 do
		clock.t += 0.1
		runner:step()
	end
	Harness.eq(#log, before, "a dead bot cannot fire")
end)

Harness.test("one bot that errors does not stop the others", function()
	local log: Log = {}
	local world, clock, states = fakeWorld(log, {
		states = { b1 = selfAt(0, 0), b2 = selfAt(100, 0) },
		extraOthers = { enemy("p1", 130, 0) },
	})
	local errors = {}
	local realOthers = world.others
	world.others = function(id)
		if id == "b1" then
			error("boom")
		end
		return realOthers(id)
	end
	local runner = BotRunner.new(world, T, noRand, function(id, msg)
		table.insert(errors, id .. ":" .. msg)
	end)
	runner:add("b1")
	runner:add("b2")
	for _ = 1, 30 do
		clock.t += 0.1
		runner:step()
	end
	Harness.truthy(#errors > 0, "error reported")
	Harness.truthy(count(log, "fire b2") > 0, "b2 kept fighting")
	Harness.eq(count(log, "fire b1"), 0)
	Harness.truthy(states.b2 ~= nil)
end)

Harness.test("clear removes every bot and stops them", function()
	local log: Log = {}
	local world = fakeWorld(log, { states = { b1 = selfAt(0, 0), b2 = selfAt(50, 0) } })
	local runner = BotRunner.new(world, T, noRand)
	runner:add("b1")
	runner:add("b2")
	runner:add("b1")
	Harness.eq(runner:count(), 2, "adding twice does not duplicate")
	runner:clear()
	Harness.eq(runner:count(), 0)
	Harness.eq(count(log, "move"), 2)
end)
