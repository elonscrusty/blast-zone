--!strict
-- Fair spawns (piece 21): spawn shield, the damage-door guard, and the bots' calm start. All pure.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local DamageRouter = require("../src/shared/DamageRouter")
local SpawnShield = require("../src/shared/SpawnShield")
local BotTuning = require("../src/server/Bots/BotTuning")
local BotBrain = require("../src/server/Bots/BotBrain")
local BotRunner = require("../src/server/Bots/BotRunner")
local BotWarmup = require("../src/server/Bots/BotWarmup")

local T = BotTuning.from(Config)
local RANGE = Config.Weapons.Firearm.range

-- ===== config =====

Harness.test("fair spawn numbers make sense", function()
	Harness.truthy(
		Config.SpawnShield.seconds > 0 and Config.SpawnShield.seconds <= 5,
		"short shield"
	)
	local w = Config.Bots.warmup
	Harness.truthy(w.seconds > 0, "warm-up lasts a while")
	Harness.truthy(w.sightRange < Config.Bots.sightRange, "calm bots see less")
	Harness.truthy(
		w.sightRange < Config.Arena.spawnMinSeparation,
		"at the start a bot cannot see the nearest spawn"
	)
	Harness.truthy(w.reactionSeconds > Config.Bots.reactionSeconds, "calm bots react slower")
	Harness.truthy(w.aimErrorDegrees > Config.Bots.aimErrorDegrees, "calm bots miss more")
end)

-- ===== shield book =====

Harness.test("shield lasts its time, then ends", function()
	local clock = { t = 0 }
	local book = SpawnShield.new(function()
		return clock.t
	end)
	book:give("p1", 3)
	Harness.truthy(book:isShielded("p1"))
	Harness.near(book:remaining("p1"), 3)
	clock.t = 2.9
	Harness.truthy(book:isShielded("p1"))
	clock.t = 3
	Harness.eq(book:isShielded("p1"), false)
	Harness.eq(book:remaining("p1"), 0)
	Harness.eq(book:isShielded("b1"), false, "never given")
end)

Harness.test("shield drops on demand and clears", function()
	local book = SpawnShield.new(function()
		return 0
	end)
	book:give("p1", 3)
	book:give("b1", 3)
	Harness.eq(book:drop("p1"), true)
	Harness.eq(book:drop("p1"), false, "second drop does nothing")
	Harness.eq(book:isShielded("p1"), false)
	book:clear()
	Harness.eq(book:isShielded("b1"), false)
	book:give("b2", 0)
	Harness.eq(book:isShielded("b2"), false, "zero seconds = no shield")
end)

-- ===== damage door =====

local function newRouter(book: SpawnShield.Book)
	local router = DamageRouter.new({
		getMatchId = function()
			return 1
		end,
		allowsDamage = function()
			return true
		end,
		isAlive = function()
			return true
		end,
		markEliminated = function()
			return true
		end,
		clock = function()
			return 0
		end,
	})
	router:bind(function(req)
		return {
			applied = true,
			dealt = req.amount,
			remaining = 100 - req.amount,
			eliminated = false,
		}
	end)
	router:addGuard(book:guard())
	return router
end

Harness.test("damage door drops hits on a shielded target only", function()
	local clock = { t = 0 }
	local book = SpawnShield.new(function()
		return clock.t
	end)
	local router = newRouter(book)
	book:give("p1", 3)
	local hit = { matchId = 1, targetId = "p1", amount = 10, cause = "bullet", sourceId = "b1" }
	local r = router:apply(hit)
	Harness.eq(r.applied, false)
	Harness.eq(r.reason, "shielded")
	Harness.eq(
		router:apply({ matchId = 1, targetId = "b1", amount = 10, cause = "bullet" }).applied,
		true
	)
	clock.t = 3.1
	Harness.eq(router:apply(hit).applied, true, "shield over")
end)

Harness.test("a broken guard never blocks damage", function()
	local router = newRouter(SpawnShield.new(os.clock))
	router:addGuard(function(): string?
		error("boom")
	end)
	Harness.eq(
		router:apply({ matchId = 1, targetId = "p1", amount = 5, cause = "zone" }).applied,
		true
	)
end)

-- ===== calm start =====

Harness.test("warm-up starts calm and ends at full strength", function()
	local start = BotWarmup.apply(T, 0)
	Harness.eq(start.sightRange, Config.Bots.warmup.sightRange)
	Harness.eq(start.reactionTime, Config.Bots.warmup.reactionSeconds)
	Harness.eq(start.aimErrorDegrees, Config.Bots.warmup.aimErrorDegrees)
	local half = BotWarmup.apply(T, T.warmupSeconds / 2)
	Harness.near(half.sightRange, (T.warmupSightRange + T.sightRange) / 2)
	Harness.eq(BotWarmup.apply(T, T.warmupSeconds), T, "done = same table")
	Harness.eq(BotWarmup.apply(T, math.huge), T)
	Harness.eq(T.sightRange, Config.Bots.sightRange, "the base tuning is not changed")
end)

Harness.test("no warm-up in Config means full strength at once", function()
	local cfg = table.clone(Config) :: any
	cfg.Bots = table.clone(Config.Bots)
	cfg.Bots.warmup = nil
	local t = BotTuning.from(cfg)
	Harness.eq(BotWarmup.progress(t, 0), 1)
	Harness.eq(BotWarmup.apply(t, 0), t)
end)

-- ===== bots and shields =====

local function view(others: { BotBrain.Body }): BotBrain.View
	return {
		now = 10,
		me = {
			id = "b1",
			pos = { x = 0, z = 0 },
			health = 100,
			maxHealth = 100,
			ammo = 12,
			magazine = 12,
			reloading = false,
			canFire = true,
			slideReady = true,
		},
		others = others,
		pickups = {},
		zone = nil,
		range = RANGE,
		canSee = function()
			return true
		end,
		rand = function()
			return 0.5
		end,
		tuning = T,
	}
end

Harness.test("bots ignore a shielded enemy", function()
	local state = BotBrain.newState()
	local v = view({ { id = "p1", pos = { x = 10, z = 0 }, shielded = true } })
	BotBrain.think(v, state)
	v.now += 1
	local intent = BotBrain.think(v, state)
	Harness.eq(intent.fire, false)
	Harness.truthy(intent.mode ~= "fight", "not fighting")
	Harness.eq(state.targetId, nil)
end)

local function runFor(fightSeconds: number?): number
	local clock = { t = 0 }
	local fires = 0
	local world: BotRunner.World = {
		now = function()
			return clock.t
		end,
		isActive = function()
			return true
		end,
		fightSeconds = if fightSeconds
			then function()
				return fightSeconds + clock.t
			end
			else nil,
		selfState = function()
			return view({}).me
		end,
		others = function()
			-- An enemy at the closest spawn distance, standing still.
			return { { id = "p1", pos = { x = Config.Arena.spawnMinSeparation, z = 0 } } }
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
		move = function() end,
		fire = function()
			fires += 1
		end,
		reload = function() end,
		slide = function() end,
	}
	local runner = BotRunner.new(world, T, function()
		return 0.5
	end)
	runner:add("b1")
	for _ = 1, 30 do -- 3 seconds
		clock.t += 0.1
		runner:step()
	end
	return fires
end

Harness.test("calm bots do not shoot a fresh spawn 40 studs away", function()
	Harness.eq(runFor(0), 0, "first seconds of the fight")
	Harness.truthy(runFor(60) > 0, "late in the fight they do")
	Harness.truthy(runFor(nil) > 0, "a world without fightSeconds keeps full strength")
end)
