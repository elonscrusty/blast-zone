--!strict
-- Piece 03: fire rate, ammo and reload, wall blocking, area damage, health, and the damage door.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local Ballistics = require("../src/server/Combat/Ballistics")
local ShellFlight = require("../src/server/Combat/ShellFlight")
local HealthBook = require("../src/server/Combat/HealthBook")
local WeaponState = require("../src/server/Combat/WeaponState")
local DamageRouter = require("../src/shared/DamageRouter")

local PISTOL = {
	fireInterval = Config.Weapons.Firearm.fireInterval,
	magazine = Config.Weapons.Firearm.magazine,
	reloadSeconds = Config.Weapons.Firearm.reloadSeconds,
}
local MORTAR = {
	fireInterval = Config.Weapons.Explosive.fireInterval,
	magazine = Config.Weapons.Explosive.magazine,
	reloadSeconds = Config.Weapons.Explosive.reloadSeconds,
}
local function statsOf(slot: number): WeaponState.Stats
	return if slot == 1 then PISTOL else MORTAR
end
local TOL = Config.Combat.fireTolerance
local function newState(): WeaponState.State
	return WeaponState.new({ PISTOL.magazine, MORTAR.magazine }, TOL)
end

-- ===== fire rate, ammo, reload =====

Harness.test("fire rate: hammering the trigger cannot beat 5 shots a second", function()
	local s = newState()
	local shots = 0
	for i = 0, 100 do -- one request every 10 ms for one second
		if s:tryFire(i * 0.01, PISTOL).ok then
			shots += 1
		end
	end
	-- one second at 5/s is 5 shots, plus at most the single early shot the tolerance allows
	Harness.truthy(shots <= 6, `fired {shots} in one second`)
	Harness.truthy(shots >= 5, `fired only {shots}`)
end)

Harness.test("fire rate: a client a little fast still averages the server's rate", function()
	local s = newState()
	local shots = 0
	-- requests every 0.18 s for 9 s; the allowed rate is one per 0.2 s, magazine refills ignored by reloading
	local t = 0
	while t < 9 do
		s:update(t, statsOf)
		if s:tryFire(t, PISTOL).ok then
			shots += 1
		end
		t += 0.18
	end
	-- 12 round magazine, 1.2 s reload: 12 rounds take 2.4 s, then 1.2 s reload = 3.6 s per cycle
	Harness.truthy(shots <= 12 * math.ceil(9 / 3.6) + 1, `fired {shots}`)
end)

Harness.test("ammo: twelve rounds, then the last shot starts the reload by itself", function()
	local s = newState()
	local startedAt = -1
	for i = 1, 12 do
		local r = s:tryFire((i - 1) * PISTOL.fireInterval, PISTOL)
		Harness.truthy(r.ok, `shot {i} should fire`)
		if r.startedReload then
			startedAt = i
		end
	end
	Harness.eq(startedAt, 12)
	Harness.eq(s.ammo[1], 0)
	Harness.eq(s:tryFire(5, PISTOL).reason, "reloading")
end)

Harness.test("reload: finishes after exactly the reload time and refills the magazine", function()
	local s = newState()
	for i = 1, 12 do
		s:tryFire((i - 1) * PISTOL.fireInterval, PISTOL)
	end
	local t0 = 11 * PISTOL.fireInterval
	Harness.eq(#s:update(t0 + 1.19, statsOf), 0)
	Harness.eq(s.ammo[1], 0)
	Harness.eq(#s:update(t0 + 1.2, statsOf), 1)
	Harness.eq(s.ammo[1], 12)
	Harness.truthy(s:tryFire(t0 + 1.3, PISTOL).ok)
end)

Harness.test("reload: manual reload on a full magazine does nothing", function()
	local s = newState()
	local ok, why = s:startReload(0, PISTOL)
	Harness.eq(ok, false)
	Harness.eq(why, "full")
end)

Harness.test("reload: switching away cancels it, and it never completes later", function()
	local s = newState()
	s:tryFire(0, PISTOL)
	Harness.truthy(s:startReload(0.5, PISTOL))
	Harness.truthy(s:equip(2, 0.6, 0.25))
	Harness.eq(#s:update(5, statsOf), 0, "cancelled reload must not complete")
	Harness.eq(s.ammo[1], 11)
	Harness.truthy(s:equip(1, 5, 0.25))
	Harness.eq(s.ammo[1], 11, "ammo is unchanged by switching")
end)

Harness.test("switching: each weapon keeps its own ammo and you wait before firing", function()
	local s = newState()
	for i = 1, 3 do
		s:tryFire((i - 1) * 0.2, PISTOL)
	end
	Harness.truthy(s:equip(2, 1, 0.25))
	Harness.eq(s.ammo[2], MORTAR.magazine, "mortar ammo is its own")
	Harness.eq(s:tryFire(1.1, MORTAR).reason, "switching")
	Harness.truthy(s:tryFire(1.26, MORTAR).ok)
	Harness.eq(s.ammo[1], 9)
	Harness.eq(s:equip(2, 2, 0.25), false, "already holding it")
	Harness.eq(s:equip(3, 2, 0.25), false, "no such slot")
end)

Harness.test(
	"eliminated: nothing fires, reloads or switches, and an old reload does not finish",
	function()
		local s = newState()
		s:tryFire(0, PISTOL)
		s:startReload(0.1, PISTOL)
		s:lock()
		Harness.eq(s:tryFire(5, PISTOL).reason, "locked")
		Harness.eq(#s:update(10, statsOf), 0)
		Harness.eq(s:equip(2, 10, 0.25), false)
		Harness.eq(s.ammo[1], 11)
	end
)

Harness.test("mortar: slower than the pistol and holds fewer rounds", function()
	Harness.truthy(MORTAR.fireInterval > PISTOL.fireInterval * 4)
	Harness.truthy(MORTAR.magazine < PISTOL.magazine)
	local s = newState()
	s:equip(2, 0, 0.25)
	Harness.truthy(s:tryFire(1, MORTAR).ok)
	Harness.eq(s:tryFire(1.5, MORTAR).reason, "too-fast")
	Harness.truthy(s:tryFire(2.6, MORTAR).ok)
end)

-- ===== shots, walls, bodies =====

Harness.test(
	"aim: a flat unit direction comes out of any client direction, junk is refused",
	function()
		local x, z = Ballistics.flatten(3, 5, 4)
		Harness.near(x :: number, 0.6)
		Harness.near(z :: number, 0.8)
		Harness.eq(Ballistics.flatten(0, 1, 0), nil, "straight up")
		Harness.eq(Ballistics.flatten(0 / 0, 0, 1), nil, "NaN")
		Harness.eq(Ballistics.flatten(math.huge, 0, 1), nil, "infinity")
	end
)

local function body(id: string, x: number, z: number): Ballistics.Target
	return { id = id, x = x, z = z, r = Config.Combat.bodyRadius }
end

Harness.test(
	"shot: the nearest body in line takes it, bodies beside the line are missed",
	function()
		local targets = { body("far", 40, 0), body("near", 20, 0.5), body("side", 25, 10) }
		local hit = Ballistics.firstHit(0, 0, 1, 0, 70, nil, targets)
		Harness.eq(hit.kind, "target")
		Harness.eq(hit.id, "near")
		Harness.truthy(hit.dist < 20 and hit.dist > 17)
	end
)

Harness.test("shot: a wall in front blocks everything behind it", function()
	local targets = { body("behind", 30, 0) }
	local hit = Ballistics.firstHit(0, 0, 1, 0, 70, 12, targets)
	Harness.eq(hit.kind, "wall")
	Harness.near(hit.dist, 12)
	-- the same body in front of the wall is hit
	Harness.eq(Ballistics.firstHit(0, 0, 1, 0, 70, 50, targets).id, "behind")
end)

Harness.test("shot: range is a hard limit (no unseen long shots)", function()
	local r = Config.Weapons.Firearm.range
	local targets = { body("far", r + 10, 0) }
	Harness.eq(Ballistics.firstHit(0, 0, 1, 0, r, nil, targets).kind, "none")
	Harness.eq(Ballistics.firstHit(0, 0, 1, 0, r, nil, { body("edge", r - 3, 0) }).kind, "target")
end)

Harness.test(
	"shot: a body behind the shooter is not hit, a body on top of the shooter is",
	function()
		Harness.eq(Ballistics.firstHit(0, 0, 1, 0, 70, nil, { body("back", -10, 0) }).kind, "none")
		Harness.eq(Ballistics.firstHit(0, 0, 1, 0, 70, nil, { body("close", 0.5, 0.5) }).dist, 0)
	end
)

Harness.test("extra projectiles fan out evenly around the aim", function()
	local one = Ballistics.fan(1, 0, 1, 7)
	Harness.eq(#one, 1)
	Harness.near(one[1].z, 0)
	local three = Ballistics.fan(1, 0, 3, 10)
	Harness.eq(#three, 3)
	Harness.near(three[2].x, 1)
	Harness.near(three[1].z, -three[3].z)
	Harness.near(math.deg(math.atan2(three[3].z, three[3].x)), 10, 1e-6)
end)

Harness.test("origin: a claimed shot start far from the body is refused", function()
	local drift = Config.Weapons.Firearm.maxOriginDrift
	Harness.eq(Ballistics.withinDrift(0, 0, drift - 0.1, 0, drift), true)
	Harness.eq(Ballistics.withinDrift(0, 0, drift + 0.1, 0, drift), false)
end)

-- ===== shells and blasts =====

Harness.test("shell: flies at its speed and bursts at the end of its range", function()
	local e = Config.Weapons.Explosive
	local shell: ShellFlight.Shell =
		{ x = 0, z = 0, dx = 1, dz = 0, speed = e.projectileSpeed, remaining = e.range }
	local noWall = function()
		return nil
	end
	local t, burst = 0, nil
	while burst == nil and t < 10 do
		burst = ShellFlight.step(shell, 1 / 30, noWall, {})
		t += 1 / 30
	end
	Harness.truthy(burst ~= nil)
	Harness.eq((burst :: ShellFlight.Burst).reason, "range")
	Harness.near((burst :: ShellFlight.Burst).x, e.range, 1e-6)
	Harness.near(t, e.range / e.projectileSpeed, 0.05)
end)

Harness.test("shell: a lag spike cannot make it jump past its range", function()
	local shell: ShellFlight.Shell = { x = 0, z = 0, dx = 1, dz = 0, speed = 55, remaining = 10 }
	local burst = ShellFlight.step(shell, 5, function()
		return nil
	end, {})
	Harness.eq((burst :: ShellFlight.Burst).reason, "range")
	Harness.near((burst :: ShellFlight.Burst).x, 10)
end)

Harness.test("shell: bursts in front of a wall, not inside it", function()
	local shell: ShellFlight.Shell = { x = 0, z = 0, dx = 1, dz = 0, speed = 60, remaining = 60 }
	local burst = ShellFlight.step(shell, 0.5, function(_, _, _, _, dist)
		return if 20 <= dist then 20 else nil
	end, {})
	Harness.eq((burst :: ShellFlight.Burst).reason, "wall")
	Harness.near((burst :: ShellFlight.Burst).x, 20 - ShellFlight.WALL_BACKOFF)
end)

Harness.test(
	"shell: bursts on the first body it touches, a wall in front hides the body",
	function()
		local mk = function(): ShellFlight.Shell
			return { x = 0, z = 0, dx = 1, dz = 0, speed = 60, remaining = 60 }
		end
		local nowall = function()
			return nil
		end
		local b = ShellFlight.step(mk(), 0.5, nowall, { body("a", 15, 0.4) })
		Harness.eq((b :: ShellFlight.Burst).reason, "target")
		Harness.eq((b :: ShellFlight.Burst).targetId, "a")
		local w = ShellFlight.step(mk(), 0.5, function()
			return 10
		end, { body("a", 15, 0) })
		Harness.eq((w :: ShellFlight.Burst).reason, "wall")
	end
)

Harness.test("blast: full damage in the middle, less toward the edge, none outside", function()
	local e = Config.Weapons.Explosive
	Harness.near(Ballistics.blastFactor(0, e.radius, e.falloffMin), 1)
	Harness.near(Ballistics.blastFactor(e.radius, e.radius, e.falloffMin), e.falloffMin)
	Harness.truthy(
		Ballistics.blastFactor(4, e.radius, e.falloffMin)
			> Ballistics.blastFactor(7, e.radius, e.falloffMin)
	)
	Harness.eq(Ballistics.blastFactor(e.radius + 0.1, e.radius, e.falloffMin), 0)
end)

Harness.test("blast: a wall between the centre and a body means no damage", function()
	local e = Config.Weapons.Explosive
	local targets = { body("open", 5, 0), body("covered", -5, 0), body("far", 40, 0) }
	local victims = Ballistics.blastVictims(0, 0, e.radius, e.falloffMin, targets, function(t)
		return t.id ~= "covered"
	end)
	Harness.eq(#victims, 1)
	Harness.eq(victims[1].id, "open")
end)

Harness.test("blast: measured from the body's edge, so the rim is reachable", function()
	local e = Config.Weapons.Explosive
	local r = Config.Combat.bodyRadius
	local v = Ballistics.blastVictims(
		0,
		0,
		e.radius,
		e.falloffMin,
		{ body("rim", e.radius + r - 0.01, 0) },
		function()
			return true
		end
	)
	Harness.eq(#v, 1)
end)

-- ===== health =====

Harness.test("health: ten body shots of ten finish a hundred health, exactly once", function()
	local book = HealthBook.new(100)
	book:add("a")
	local eliminatedCount, last = 0, 0
	for i = 1, 12 do
		local dealt, remaining, dead = book:apply("a", 10, "b")
		if dead then
			eliminatedCount += 1
			last = i
		end
		Harness.truthy(dealt == 10 or i > 10)
		Harness.truthy(remaining >= 0)
	end
	Harness.eq(eliminatedCount, 1, "only one finishing blow")
	Harness.eq(last, 10)
	Harness.eq(book:get("a"), 0)
end)

Harness.test("health: overkill deals only what was left", function()
	local book = HealthBook.new(100)
	book:add("a")
	book:apply("a", 95, "b")
	local dealt, remaining, dead = book:apply("a", 45, "b")
	Harness.eq(dealt, 5)
	Harness.eq(remaining, 0)
	Harness.eq(dead, true)
end)

Harness.test("health: junk amounts and unknown targets change nothing", function()
	local book = HealthBook.new(100)
	book:add("a")
	Harness.eq(select(3, book:apply("a", -5, nil)), false)
	Harness.eq(select(3, book:apply("a", 0 / 0, nil)), false)
	Harness.eq(book:get("a"), 100)
	Harness.eq(select(1, book:apply("nobody", 10, nil)), 0)
end)

Harness.test("health: healing is capped and never revives", function()
	local book = HealthBook.new(100)
	book:add("a")
	book:apply("a", 30, "b")
	Harness.eq(book:heal("a", 25), 25)
	Harness.eq(book:heal("a", 25), 5)
	Harness.eq(book:get("a"), 100)
	book:apply("a", 100, "b")
	Harness.eq(book:heal("a", 50), 0)
	Harness.eq(book:get("a"), 0)
end)

Harness.test("health: 'who hit me' lists attackers by damage, and ignores self-damage", function()
	local book = HealthBook.new(100)
	book:add("a")
	book:apply("a", 10, "x")
	book:apply("a", 30, "y")
	book:apply("a", 10, "x")
	book:apply("a", 5, "a")
	local h = book:hitters("a")
	Harness.eq(#h, 2)
	Harness.eq(h[1].sourceId, "y")
	Harness.eq(h[2].damage, 20)
end)

-- ===== the damage door with our health backend =====

local function makeDoor(): (any, any, { [string]: boolean }, { current: number, combat: boolean })
	local book = HealthBook.new(100)
	book:add("a")
	book:add("b")
	book:add("c")
	local alive = { a = true, b = true, c = true } :: { [string]: boolean }
	local world = { current = 1, combat = true }
	local door = DamageRouter.new({
		getMatchId = function()
			return world.current
		end,
		allowsDamage = function()
			return world.combat
		end,
		isAlive = function(id: string)
			return alive[id] == true
		end,
		markEliminated = function(id: string)
			alive[id] = false
			return true
		end,
		clock = function()
			return 0
		end,
	})
	door:bind(function(req)
		local dealt, remaining, dead = book:apply(req.targetId, req.amount, req.sourceId)
		return { applied = dealt > 0, dealt = dealt, remaining = remaining, eliminated = dead }
	end)
	return door, book, alive, world
end

Harness.test("door: a kill is credited once, to the shooter", function()
	local door = makeDoor()
	local kills = {}
	door.Eliminated:connect(function(e)
		table.insert(kills, e)
	end)
	for _ = 1, 15 do
		door:apply({ matchId = 1, targetId = "a", amount = 10, cause = "bullet", sourceId = "b" })
	end
	Harness.eq(#kills, 1)
	Harness.eq(kills[1].killerId, "b")
	Harness.eq(kills[1].victimId, "a")
end)

Harness.test("door: zone damage kills with no killer credit", function()
	local door = makeDoor()
	local kills = {}
	door.Eliminated:connect(function(e)
		table.insert(kills, e)
	end)
	door:apply({ matchId = 1, targetId = "a", amount = 100, cause = "zone" })
	Harness.eq(#kills, 1)
	Harness.eq(kills[1].killerId, nil)
end)

Harness.test("door: a shot from an old match or after the match ended changes nothing", function()
	local door, book, _, world = makeDoor()
	local stale =
		door:apply({ matchId = 0, targetId = "a", amount = 50, cause = "bullet", sourceId = "b" })
	Harness.eq(stale.applied, false)
	world.combat = false
	local late =
		door:apply({ matchId = 1, targetId = "a", amount = 50, cause = "bullet", sourceId = "b" })
	Harness.eq(late.applied, false)
	Harness.eq(book:get("a"), 100)
end)

Harness.test(
	"door: one explosion finishing two people gives two eliminations, no duplicates",
	function()
		local door = makeDoor()
		local kills = {}
		door.Eliminated:connect(function(e)
			table.insert(kills, e.victimId)
		end)
		for _, id in { "a", "c", "a", "c" } do
			door:apply({
				matchId = 1,
				targetId = id,
				amount = 100,
				cause = "explosion",
				sourceId = "b",
			})
		end
		table.sort(kills)
		Harness.eq(table.concat(kills, ","), "a,c")
	end
)

Harness.test("door: someone eliminated cannot be hurt again", function()
	local door, book = makeDoor()
	door:apply({ matchId = 1, targetId = "a", amount = 100, cause = "bullet", sourceId = "b" })
	local again =
		door:apply({ matchId = 1, targetId = "a", amount = 100, cause = "bullet", sourceId = "c" })
	Harness.eq(again.applied, false)
	Harness.eq(book:get("a"), 0)
	Harness.eq(#book:hitters("a"), 1, "the late attacker is not listed")
end)

-- ===== config sanity =====

Harness.test("combat config: sensible numbers", function()
	local c = Config.Combat
	Harness.truthy(c.bodyRadius > 0.5 and c.bodyRadius < 4)
	Harness.truthy(c.fireTolerance < Config.Weapons.Firearm.fireInterval / 2)
	Harness.truthy(c.maxShells >= 1)
	Harness.truthy(
		Config.Weapons.Explosive.range / Config.Weapons.Explosive.projectileSpeed
			>= Config.Weapons.Explosive.warnSeconds
	)
	Harness.eq(
		Config.Weapons.Firearm.damage * 10,
		Config.Health.max,
		"ten clean shots is the starting estimate"
	)
end)
