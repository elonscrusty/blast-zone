--!strict
-- Smarter bots (piece 35): difficulty tiers, cover, leaving the zone early, using found guns.
-- All pure, no Roblox.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local BotBrain = require("../src/server/Bots/BotBrain")
local BotGuns = require("../src/server/Bots/BotGuns")
local BotRunner = require("../src/server/Bots/BotRunner")
local BotTuning = require("../src/server/Bots/BotTuning")
local BotWarmup = require("../src/server/Bots/BotWarmup")

local BASE = BotTuning.from(Config)
local RANGE = Config.Weapons.Firearm.range

local function half(): number
	return 0.5
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
		gunId = nil,
	}
	for k, v in patch or {} do
		(me :: any)[k] = v
	end
	return me
end

local function view(me: BotBrain.Self, tier: string?, patch: { [string]: any }?): BotBrain.View
	local v: BotBrain.View = {
		now = 100,
		me = me,
		others = {},
		pickups = {},
		gunDrops = nil,
		zone = nil,
		range = RANGE,
		canSee = function()
			return true
		end,
		rand = half,
		tuning = BotTuning.forTier(BASE, tier or "normal"),
	}
	for k, val in patch or {} do
		(v :: any)[k] = val
	end
	return v
end

local function enemy(x: number, z: number): BotBrain.Body
	return { id = "p1", pos = { x = x, z = z } }
end

-- ===== tiers =====

Harness.test("bot number picks the tier from the cycle, same every match", function()
	Harness.eq(BotTuning.tierOf(BASE, "b1"), "normal")
	Harness.eq(BotTuning.tierOf(BASE, "b2"), "easy")
	Harness.eq(BotTuning.tierOf(BASE, "b3"), "hard")
	Harness.eq(BotTuning.tierOf(BASE, "b9"), "normal", "wraps around the cycle")
	for n = 1, 20 do
		Harness.truthy(
			BASE.tiers[BotTuning.tierOf(BASE, "b" .. n)] ~= nil,
			"every cycle name is a tier"
		)
	end
end)

Harness.test("tiers change skill only, never health, damage, speed or ammo", function()
	for name, tier in Config.Bots.tiers do
		for key in tier :: any do
			local lower = string.lower(tostring(key))
			for _, banned in { "health", "damage", "speed", "ammo", "cooldown" } do
				Harness.truthy(
					not string.find(lower, banned, 1, true),
					name .. " has " .. tostring(key)
				)
			end
		end
		for key in BotTuning.forTier(BASE, name) :: any do
			local lower = string.lower(tostring(key))
			for _, banned in { "health", "damage", "speed", "ammo", "cooldown" } do
				Harness.truthy(
					not string.find(lower, banned, 1, true),
					"tuning has " .. tostring(key)
				)
			end
		end
	end
end)

Harness.test("harder tiers see farther, react faster and miss less", function()
	local easy = BotTuning.forTier(BASE, "easy")
	local normal = BotTuning.forTier(BASE, "normal")
	local hard = BotTuning.forTier(BASE, "hard")
	Harness.truthy(easy.sightRange < normal.sightRange and normal.sightRange < hard.sightRange)
	Harness.truthy(
		easy.reactionTime > normal.reactionTime and normal.reactionTime > hard.reactionTime
	)
	Harness.truthy(
		easy.aimErrorDegrees > normal.aimErrorDegrees
			and normal.aimErrorDegrees > hard.aimErrorDegrees
	)
	Harness.truthy(easy.coverSkill < hard.coverSkill)
	Harness.eq(normal.sightRange, Config.Bots.sightRange, "normal is the old bot")
	Harness.eq(normal.reactionTime, Config.Bots.reactionSeconds)
end)

Harness.test("every tier starts the match as calm as carter picked (spawn rule kept)", function()
	for name in Config.Bots.tiers do
		local start = BotWarmup.apply(BotTuning.forTier(BASE, name), 0)
		Harness.eq(start.sightRange, Config.Bots.warmup.sightRange, name)
		Harness.eq(start.reactionTime, Config.Bots.warmup.reactionSeconds, name)
		Harness.eq(start.aimErrorDegrees, Config.Bots.warmup.aimErrorDegrees, name)
		local full = BotTuning.forTier(BASE, name)
		Harness.truthy(full.sightRange >= start.sightRange, name .. " never calmer than the start")
		Harness.truthy(full.reactionTime <= start.reactionTime, name)
		Harness.truthy(full.aimErrorDegrees <= start.aimErrorDegrees, name)
	end
end)

Harness.test("the runner gives each bot its own tier", function()
	local world: BotRunner.World = {
		now = function()
			return 0
		end,
		isActive = function()
			return true
		end,
		selfState = function(id)
			return selfAt(0, 0, { id = id })
		end,
		others = function()
			return {}
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
		fire = function() end,
		reload = function() end,
		slide = function() end,
	}
	local runner = BotRunner.new(world, BASE, half)
	runner:add("b1")
	runner:add("b2")
	runner:add("b3")
	Harness.eq(runner:tierName("b1"), "normal")
	Harness.eq(runner:tierName("b2"), "easy")
	Harness.eq(runner:tierName("b3"), "hard")
	Harness.eq(runner:tierName("b99"), nil)
end)

-- ===== leaving the zone wall =====

local ZONE = { center = { x = 0, z = 0 }, radius = 100, shrinking = false }

Harness.test("a bot near the wall heads back in, and keeps going until well inside", function()
	local state = BotBrain.newState()
	-- normal margin is 6 + 4 = 10 studs: at 92 out of 100 it turns around
	local out = BotBrain.think(view(selfAt(92, 0), nil, { zone = ZONE }), state)
	Harness.eq(out.mode, "zone")
	Harness.truthy(out.moveX < -0.9, "heads for the middle")
	-- 86 studs is inside the margin but not 6 studs past it: still heading in (no jitter)
	local still = BotBrain.think(view(selfAt(86, 0), nil, { zone = ZONE }), state)
	Harness.eq(still.mode, "zone")
	-- 70 studs: safely inside, free to roam again
	local free = BotBrain.think(view(selfAt(70, 0), nil, { zone = ZONE }), state)
	Harness.truthy(free.mode ~= "zone")
end)

Harness.test("a closing zone makes bots leave earlier", function()
	local closing = { center = { x = 0, z = 0 }, radius = 100, shrinking = true }
	local calmZone = BotBrain.think(view(selfAt(85, 0), nil, { zone = ZONE }), BotBrain.newState())
	local shrinking =
		BotBrain.think(view(selfAt(85, 0), nil, { zone = closing }), BotBrain.newState())
	Harness.truthy(calmZone.mode ~= "zone", "still fine while the zone holds")
	Harness.eq(shrinking.mode, "zone", "runs while it closes")
end)

Harness.test("hard bots leave the wall earlier than easy bots", function()
	local at = selfAt(88, 0)
	local easy = BotBrain.think(view(at, "easy", { zone = ZONE }), BotBrain.newState())
	local hard = BotBrain.think(view(at, "hard", { zone = ZONE }), BotBrain.newState())
	Harness.truthy(easy.mode ~= "zone")
	Harness.eq(hard.mode, "zone")
end)

Harness.test(
	"a hurt bot outside the zone still runs in (the wall hurts more than the enemy)",
	function()
		local out = BotBrain.think(
			view(selfAt(95, 0, { health = 10 }), nil, { zone = ZONE, others = { enemy(120, 0) } }),
			BotBrain.newState()
		)
		Harness.eq(out.mode, "zone")
		Harness.truthy(out.moveX < 0)
	end
)

Harness.test("a bot keeps shooting while it runs back into the zone", function()
	local state = BotBrain.newState()
	local v = view(selfAt(95, 0), nil, { zone = ZONE, others = { enemy(125, 0) } })
	BotBrain.think(v, state)
	v.now += BASE.reactionTime + 0.01
	local out = BotBrain.think(v, state)
	Harness.eq(out.mode, "zone")
	Harness.eq(out.fire, true)
end)

Harness.test("far outside the wall a bot slides back in", function()
	local out = BotBrain.think(view(selfAt(125, 0), nil, { zone = ZONE }), BotBrain.newState())
	Harness.eq(out.slide, true)
	local near = BotBrain.think(view(selfAt(95, 0), nil, { zone = ZONE }), BotBrain.newState())
	Harness.eq(near.slide, false)
end)

Harness.test("bots do not walk to orbs or guns outside the safe circle", function()
	local v = view(selfAt(0, 0), nil, {
		zone = ZONE,
		pickups = { { id = "o1", pos = { x = 30, z = 0 } } },
		gunDrops = { { id = "1", gunId = "hornet", pos = { x = -30, z = 0 } } },
	})
	Harness.eq(BotBrain.think(v, BotBrain.newState()).mode, "gun", "inside the zone: wanted")
	v.zone = { center = { x = 200, z = 0 }, radius = 100, shrinking = false } -- orbs now outside
	local out = BotBrain.think(v, BotBrain.newState())
	Harness.truthy(out.mode ~= "loot" and out.mode ~= "gun")
end)

-- ===== cover =====

-- One wall: x = 3, from z = 2 to z = 12. canSee is false when a line crosses it.
local function crossesWall(a: BotBrain.Vec2, b: BotBrain.Vec2): boolean
	if (a.x - 3) * (b.x - 3) > 0 then
		return false
	end
	local t = (3 - a.x) / (b.x - a.x)
	local z = a.z + (b.z - a.z) * t
	return z >= 2 and z <= 12
end

local function wallSight(a: BotBrain.Vec2, b: BotBrain.Vec2): boolean
	return not crossesWall(a, b)
end

Harness.test("a reloading bot ducks behind the wall, waits there, and comes back out", function()
	local state = BotBrain.newState()
	local me = selfAt(0, -2, { reloading = true, ammo = 0 })
	local v = view(me, "normal", { others = { enemy(30, -2) }, canSee = wallSight })
	local first = BotBrain.think(v, state)
	Harness.eq(first.mode, "cover")
	Harness.truthy(first.moveZ > 0.5, "goes behind the wall, away from the enemy's line")
	Harness.truthy(state.cover ~= nil)
	-- It arrives; the enemy cannot see it any more but it stays put while reloading.
	local spot = state.cover :: BotBrain.Vec2
	me.pos = { x = spot.x, z = spot.z }
	v.now += 0.5
	v.others = {}
	local hold = BotBrain.think(v, state)
	Harness.eq(hold.mode, "cover")
	Harness.near(hold.moveX, 0)
	Harness.near(hold.moveZ, 0)
	-- Reload done: it leaves cover.
	me.reloading = false
	me.ammo = 12
	v.now += 0.5
	local out = BotBrain.think(v, state)
	Harness.eq(state.cover, nil)
	Harness.truthy(out.mode ~= "cover")
end)

Harness.test("cover never lasts forever", function()
	local state = BotBrain.newState()
	local me = selfAt(0, -2, { reloading = true, ammo = 0 })
	local v = view(me, "normal", { others = { enemy(30, -2) }, canSee = wallSight })
	BotBrain.think(v, state)
	Harness.truthy(state.cover ~= nil)
	v.now += BASE.coverHold + 0.1
	BotBrain.think(v, state)
	Harness.eq(state.cover, nil, "gave up the spot")
end)

Harness.test("easy bots mostly stand and fight; hard bots always duck", function()
	local function ducks(tier: string): boolean
		local state = BotBrain.newState()
		local me = selfAt(0, -2, { reloading = true, ammo = 0 })
		local v = view(me, tier, { others = { enemy(30, -2) }, canSee = wallSight })
		return BotBrain.think(v, state).mode == "cover"
	end
	Harness.eq(ducks("easy"), false)
	Harness.eq(ducks("hard"), true)
end)

Harness.test(
	"no cover to find: a hurt bot flees like before, a reloading bot keeps fighting",
	function()
		local hurt = BotBrain.think(
			view(selfAt(0, 0, { health = 10 }), nil, { others = { enemy(20, 0) } }),
			BotBrain.newState()
		)
		Harness.eq(hurt.mode, "flee")
		Harness.truthy(hurt.moveX < 0)
		local reloading = BotBrain.think(
			view(selfAt(0, 0, { reloading = true }), nil, { others = { enemy(20, 0) } }),
			BotBrain.newState()
		)
		Harness.eq(reloading.mode, "fight")
	end
)

Harness.test("cover spots are never outside the zone", function()
	-- The only hidden spots are north of the wall; put the zone edge just south of them.
	local state = BotBrain.newState()
	local me = selfAt(0, -2, { reloading = true, ammo = 0 })
	local small = { center = { x = 0, z = -60 }, radius = 70, shrinking = false } -- z > 0 is outside
	local v = view(me, "normal", { others = { enemy(30, -2) }, canSee = wallSight, zone = small })
	BotBrain.think(v, state)
	Harness.eq(state.cover, nil)
end)

-- ===== guns =====

Harness.test(
	"gun habits: breaker rushes, longline backs off, pistol keeps its old habits",
	function()
		local function moveXAt(gunId: string?, distance: number, range: number): number
			local v = view(selfAt(0, 0, { gunId = gunId }), nil, {
				others = { enemy(distance, 0) },
				range = range,
			})
			return BotBrain.think(v, BotBrain.newState()).moveX
		end
		local breaker = Config.Weapons.Guns.breaker.range
		local longline = Config.Weapons.Guns.longline.range
		Harness.truthy(moveXAt("breaker", 20, breaker) > 0.5, "shotgun closes in")
		Harness.truthy(
			moveXAt("breaker", 4, breaker) > moveXAt(nil, 4, RANGE),
			"shotgun does not back off a pistol's way"
		)
		Harness.truthy(
			moveXAt("longline", 20, longline) < -0.5,
			"rifle backs away from a close fight"
		)
		Harness.eq(
			moveXAt(nil, 20, RANGE),
			moveXAt("hornet", 20, RANGE) + 0 * 1,
			"same side as before at mid range"
		) -- both hold their line
	end
)

Harness.test("the shotgun does not fire at the edge of its reach", function()
	local range = Config.Weapons.Guns.breaker.range
	local function fires(distance: number): boolean
		local state = BotBrain.newState()
		local v = view(selfAt(0, 0, { gunId = "breaker" }), nil, {
			others = { enemy(distance, 0) },
			range = range,
		})
		BotBrain.think(v, state)
		v.now += BASE.reactionTime + 0.01
		return BotBrain.think(v, state).fire
	end
	Harness.eq(fires(range * 0.5), true)
	Harness.eq(fires(range * 0.9), false)
end)

Harness.test("gun ranking only ever swaps up", function()
	Harness.eq(BotGuns.wants(nil, "breaker"), true)
	Harness.eq(BotGuns.wants(nil, "hornet"), true)
	Harness.eq(BotGuns.wants("breaker", "hornet"), true)
	Harness.eq(BotGuns.wants("hornet", "breaker"), false)
	Harness.eq(BotGuns.wants("breaker", "longline"), false, "equal rank: no ping-pong")
	Harness.eq(BotGuns.wants("longline", "breaker"), false)
	for id in Config.Weapons.Guns do
		Harness.truthy(BotGuns.rank(id) > BotGuns.rank(nil), id .. " beats the pistol")
	end
end)

Harness.test("a bot walks to a found gun it wants, and asks for the swap up close", function()
	local drops = { { id = "7", gunId = "hornet", pos = { x = 20, z = 0 } } }
	local far = BotBrain.think(view(selfAt(0, 0), nil, { gunDrops = drops }), BotBrain.newState())
	Harness.eq(far.mode, "gun")
	Harness.truthy(far.moveX > 0.9)
	Harness.eq(far.grabGunId, nil)
	local close =
		BotBrain.think(view(selfAt(17, 0), nil, { gunDrops = drops }), BotBrain.newState())
	Harness.eq(close.grabGunId, "7")
end)

Harness.test(
	"a bot ignores guns that are not an upgrade, too far, behind walls, or easy-tier",
	function()
		local drops = { { id = "7", gunId = "breaker", pos = { x = 20, z = 0 } } }
		local holding = BotBrain.think(
			view(selfAt(0, 0, { gunId = "hornet" }), nil, { gunDrops = drops }),
			BotBrain.newState()
		)
		Harness.truthy(holding.mode ~= "gun")
		Harness.eq(holding.grabGunId, nil)
		local far = BotBrain.think(
			view(
				selfAt(0, 0),
				nil,
				{ gunDrops = { { id = "8", gunId = "hornet", pos = { x = 200, z = 0 } } } }
			),
			BotBrain.newState()
		)
		Harness.truthy(far.mode ~= "gun")
		local walled = BotBrain.think(
			view(selfAt(0, 0), nil, {
				gunDrops = drops,
				canSee = function()
					return false
				end,
			}),
			BotBrain.newState()
		)
		Harness.truthy(walled.mode ~= "gun")
		local easy =
			BotBrain.think(view(selfAt(0, 0), "easy", { gunDrops = drops }), BotBrain.newState())
		Harness.truthy(easy.mode ~= "gun")
	end
)

Harness.test("the runner asks the world for the swap", function()
	local claimed: { string } = {}
	local state = selfAt(17, 0)
	local clock = 0
	local world: BotRunner.World = {
		now = function()
			return clock
		end,
		isActive = function()
			return true
		end,
		selfState = function()
			return state
		end,
		others = function()
			return {}
		end,
		pickups = function()
			return {}
		end,
		gunDrops = function()
			return { { id = "7", gunId = "hornet", pos = { x = 20, z = 0 } } }
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
		fire = function() end,
		reload = function() end,
		slide = function() end,
		claimGun = function(id, dropId)
			table.insert(claimed, id .. ":" .. dropId)
		end,
	}
	local runner = BotRunner.new(world, BASE, half)
	runner:add("b1") -- normal tier: seeks guns
	runner:step()
	clock += 1
	runner:step()
	Harness.truthy(#claimed >= 1)
	Harness.eq(claimed[1], "b1:7")
end)
