--!strict
local Harness = require("./harness")
local CameraRules = require("../src/shared/Movement/CameraRules")
local Config = require("../src/shared/Config")
local MoveRules = require("../src/shared/Movement/MoveRules")
local SlideBook = require("../src/shared/Movement/SlideBook")
local SlideRules = require("../src/shared/Movement/SlideRules")

local test, eq, near = Harness.test, Harness.eq, Harness.near

-- ===== direction =====

test("slide goes the way you move, as a unit vector", function()
	local x, z = SlideRules.direction(3, 4, 0, -1)
	near(x :: number, 0.6)
	near(z :: number, 0.8)
end)

test("standing still slides the way you face", function()
	local x, z = SlideRules.direction(0, 0, 0, -1)
	near(x :: number, 0)
	near(z :: number, -1)
end)

test("garbage directions are rejected, not turned into a slide", function()
	local x = SlideRules.direction(0 / 0, 1, 0, 0)
	eq(x, nil)
	eq((SlideRules.direction(math.huge, 0, 0, 0)), nil)
	eq((SlideRules.direction("a", 0, 0, 0)), nil)
	eq((SlideRules.direction(0, 0, 0, 0)), nil)
end)

-- ===== blocked, ground, bounds =====

test("a wall shortens the slide and leaves a gap", function()
	near(SlideRules.clampToBlock(14, nil, 0.15), 14)
	near(SlideRules.clampToBlock(14, 6, 0.15), 5.85)
	near(SlideRules.clampToBlock(14, 0.05, 0.15), 0)
	near(SlideRules.clampToBlock(14, 50, 0.15), 14)
end)

test("ground samples reach the end of the path", function()
	local s = SlideRules.groundSamples(14, 3.5)
	eq(#s, 4)
	near(s[#s], 14)
	local short = SlideRules.groundSamples(2, 3.5)
	eq(#short, 1)
	near(short[1], 2)
	eq(#SlideRules.groundSamples(0, 3.5), 0)
end)

test("the slide stops before a hole in the floor", function()
	local samples = SlideRules.groundSamples(14, 3.5) -- 3.5, 7, 10.5, 14
	near(SlideRules.clampToGround(14, samples, { true, true, false, true }), 7)
	near(SlideRules.clampToGround(14, samples, { false, true, true, true }), 0)
	near(SlideRules.clampToGround(14, samples, { true, true, true, true }), 14)
end)

test("the slide cannot leave the arena", function()
	-- 10 studs from the east edge, sliding east: only 10 allowed
	near(SlideRules.clampToBounds(100, 0, 1, 0, 14, -110, 110, -110, 110), 10)
	-- diagonal into a corner
	local d = 1 / math.sqrt(2)
	near(SlideRules.clampToBounds(105, 105, d, d, 14, -110, 110, -110, 110), 5 / d)
	-- sliding away from the edge is free
	near(SlideRules.clampToBounds(100, 0, -1, 0, 14, -110, 110, -110, 110), 14)
	-- already outside: no slide
	eq(SlideRules.clampToBounds(120, 0, -1, 0, 14, -110, 110, -110, 110), 0)
end)

-- ===== timing =====

test("the slide covers exactly its distance, fast then easing off", function()
	near(SlideRules.travelled(14, 0.25, 0.25), 14)
	near(SlideRules.travelled(14, 0.25, 0), 0)
	near(SlideRules.travelled(14, 0.25, 9), 14, 1e-6, "clamped after the end")
	-- numeric integral of the speed matches the distance
	local sum, dt = 0, 1 / 1000
	local t = 0
	while t < 0.25 do
		sum += SlideRules.speedAt(14, 0.25, t) * dt
		t += dt
	end
	near(sum, 14, 0.05)
	Harness.truthy(SlideRules.speedAt(14, 0.25, 0.01) > SlideRules.speedAt(14, 0.25, 0.24))
	eq(SlideRules.speedAt(14, 0.25, 0.3), 0)
end)

test("upgrades cannot push the cooldown under the floor", function()
	near(SlideRules.cooldown(5, 1.5), 5)
	near(SlideRules.cooldown(0.2, 1.5), 1.5)
	near(SlideRules.cooldown(0 / 0, 1.5), 1.5)
	near(SlideRules.cooldown(-3, 1.5), 1.5)
end)

-- ===== who may slide =====

test("blocked reasons come in a fixed order", function()
	local base = { now = 10, readyAt = 0, activeUntil = 0, alive = true, gateOpen = true }
	eq(SlideRules.blockedReason(base), nil)
	eq(
		SlideRules.blockedReason({
			now = 10,
			readyAt = 0,
			activeUntil = 0,
			alive = false,
			gateOpen = false,
		}),
		"dead"
	)
	eq(
		SlideRules.blockedReason({
			now = 10,
			readyAt = 0,
			activeUntil = 0,
			alive = true,
			gateOpen = false,
		}),
		"gate"
	)
	eq(
		SlideRules.blockedReason({
			now = 10,
			readyAt = 12,
			activeUntil = 10.2,
			alive = true,
			gateOpen = true,
		}),
		"active"
	)
	eq(
		SlideRules.blockedReason({
			now = 10,
			readyAt = 12,
			activeUntil = 0,
			alive = true,
			gateOpen = true,
		}),
		"cooldown"
	)
	eq(
		SlideRules.blockedReason({
			now = 12,
			readyAt = 12,
			activeUntil = 0,
			alive = true,
			gateOpen = true,
		}),
		nil
	)
end)

test("cooldown cannot be dodged by asking again", function()
	local book = SlideBook.new()
	eq(book:check("p1", 100, true, true), nil)
	book:commit("p1", 100, 0.25, 5)
	eq(book:check("p1", 100.1, true, true), "active")
	eq(book:check("p1", 101, true, true), "cooldown")
	eq(book:check("p1", 104.9, true, true), "cooldown")
	eq(book:check("p1", 105, true, true), nil)
	-- someone else is not held up by p1's cooldown
	eq(book:check("p2", 101, true, true), nil)
end)

test("a cancelled slide keeps its cooldown, so dying does not refresh it", function()
	local book = SlideBook.new()
	local token = book:commit("p1", 100, 0.25, 5)
	book:cancel("p1", 100.1)
	eq(book:isCurrent("p1", token), false)
	eq(book:isActive("p1", 100.2), false)
	eq(book:check("p1", 101, true, true), "cooldown")
end)

test("a late check from an old slide cannot touch the next one", function()
	local book = SlideBook.new()
	local first = book:commit("p1", 100, 0.25, 1.5)
	local second = book:commit("p1", 102, 0.25, 1.5)
	eq(book:isCurrent("p1", first), false)
	eq(book:isCurrent("p1", second), true)
end)

test("a new match or a new body clears the cooldown", function()
	local book = SlideBook.new()
	book:commit("p1", 100, 0.25, 5)
	book:reset("p1")
	eq(book:check("p1", 101, true, true), nil)
	book:commit("p1", 100, 0.25, 5)
	book:clear()
	eq(book:check("p1", 101, true, true), nil)
end)

test("a player far from where a slide could take them is caught", function()
	local g, tol = Config.Slide.endGrace, Config.Slide.endTolerance
	-- slid 14 and walked on a bit: fine
	eq(SlideRules.endPlausible(0, 0, 18, 0, 14, 20, g, tol), true)
	-- 40 studs away after a 14 stud slide: not fine
	eq(SlideRules.endPlausible(0, 0, 40, 0, 14, 20, g, tol), false)
	-- barely moved: fine
	eq(SlideRules.endPlausible(0, 0, 1, 1, 14, 20, g, tol), true)
end)

-- ===== walking =====

test("speed upgrades cannot go past the cap", function()
	near(MoveRules.clampSpeed(20, 20, 1.4), 20)
	near(MoveRules.clampSpeed(40, 20, 1.4), 28)
	near(MoveRules.clampSpeed(-5, 20, 1.4), 0)
	near(MoveRules.clampSpeed(0 / 0, 20, 1.4), 20)
end)

test("up the screen is the direction the camera looks, right is its right", function()
	local x, z = MoveRules.moveToWorld(0, 1, 0)
	near(x, 0)
	near(z, -1)
	x, z = MoveRules.moveToWorld(1, 0, 0)
	near(x, 1)
	near(z, 0)
	-- camera turned 90 degrees (camera on +X looking toward -X): up the screen is -X
	x, z = MoveRules.moveToWorld(0, 1, 90)
	near(x, -1)
	near(z, 0)
	-- diagonal keeps a normal length (no faster diagonals): the controls already give length <= 1
	x, z = MoveRules.moveToWorld(0.7071, 0.7071, 0)
	near(math.sqrt(x * x + z * z), 1, 1e-3)
end)

-- ===== camera =====

test("camera sits above and behind, at the pitch and distance asked for", function()
	local dx, dy, dz = CameraRules.offset(55, 46, 0)
	near(dx, 0)
	near(dy, 46 * math.sin(math.rad(55)))
	near(dz, 46 * math.cos(math.rad(55)))
	near(math.sqrt(dx * dx + dy * dy + dz * dz), 46, 1e-6)
	-- a turned heading keeps the same height and distance
	local ex, ey, ez = CameraRules.offset(55, 46, 90)
	near(ey, dy)
	near(math.sqrt(ex * ex + ez * ez), math.sqrt(dz * dz))
end)

test("narrow screens pull the camera back, wide ones do not", function()
	local c = Config.Camera
	near(
		CameraRules.distanceForAspect(46, 2.1, c.narrowAspect, c.narrowAspectFloor, c.maxWiden),
		46
	)
	near(
		CameraRules.distanceForAspect(
			46,
			c.narrowAspect,
			c.narrowAspect,
			c.narrowAspectFloor,
			c.maxWiden
		),
		46
	)
	near(
		CameraRules.distanceForAspect(
			46,
			c.narrowAspectFloor,
			c.narrowAspect,
			c.narrowAspectFloor,
			c.maxWiden
		),
		46 * (1 + c.maxWiden)
	)
	local mid =
		CameraRules.distanceForAspect(46, 1.0, c.narrowAspect, c.narrowAspectFloor, c.maxWiden)
	Harness.truthy(mid > 46 and mid < 46 * (1 + c.maxWiden))
	-- absurdly thin screens are capped
	near(
		CameraRules.distanceForAspect(46, 0.01, c.narrowAspect, c.narrowAspectFloor, c.maxWiden),
		46 * (1 + c.maxWiden)
	)
end)

test("camera follow does not depend on frame rate", function()
	-- following for 1 second in 60 steps or 30 steps leaves the same gap
	local function gapAfter(steps: number): number
		local gap = 10
		for _ = 1, steps do
			gap *= 1 - CameraRules.followAlpha(1 / steps, 0.06)
		end
		return gap
	end
	near(gapAfter(60), gapAfter(30), 1e-6)
	eq(CameraRules.followAlpha(0.016, 0), 1)
	eq(CameraRules.followAlpha(0, 0.06), 0)
	Harness.truthy(
		CameraRules.followAlpha(0.016, 0.06) > 0 and CameraRules.followAlpha(0.016, 0.06) < 1
	)
end)

test("the camera's forward and right agree with the offset", function()
	for _, h in { 0, 30, 90, 180, 270 } do
		local ox, _, oz = CameraRules.offset(55, 10, h)
		local fx, fz = CameraRules.forward(h)
		-- forward points from the camera toward the player: opposite the offset
		Harness.truthy(ox * fx + oz * fz < 0, "forward opposes offset at " .. h)
		local rx, rz = CameraRules.right(h)
		near(rx * fx + rz * fz, 0, 1e-9, "right is sideways at " .. h)
	end
end)

-- ===== the numbers the brief asks for =====

test("starting numbers match the brief", function()
	eq(Config.Movement.walkSpeed, 20)
	eq(Config.Movement.jumpEnabled, false)
	eq(Config.Slide.distance, 14)
	eq(Config.Slide.duration, 0.25)
	eq(Config.Slide.cooldown, 5)
	eq(Config.Slide.invulnerable, false)
end)

-- ===== spectate camera =====

test("spectate view: play camera normally, chosen style while watching, safe fallback", function()
	local pitch, dist = CameraRules.viewFor(Config.Camera, Config.Spectate, false)
	eq(pitch, Config.Camera.pitchDegrees)
	eq(dist, Config.Camera.distance)
	local wide = { style = "wide", styles = Config.Spectate.styles }
	pitch, dist = CameraRules.viewFor(Config.Camera, wide, true)
	eq(dist, Config.Spectate.styles.wide.distance)
	pitch, dist = CameraRules.viewFor(Config.Camera, { style = "typo", styles = {} }, true)
	eq(pitch, Config.Camera.pitchDegrees)
	eq(dist, Config.Camera.distance)
end)

test("default spectate style is the same view as play", function()
	local style = Config.Spectate.styles[Config.Spectate.style]
	eq(style.pitchDegrees, Config.Camera.pitchDegrees)
	eq(style.distance, Config.Camera.distance)
end)

-- ===== turning the camera =====

test("turning the view right makes the camera look toward +X, and walking follows it", function()
	-- a quarter turn to the right: the heading is -90, forward is +X, the camera sits on the -X side
	local yaw = CameraRules.turnedYaw(0, 90)
	near(yaw, -90)
	local fx, fz = CameraRules.forward(yaw)
	near(fx, 1, 1e-9)
	near(fz, 0, 1e-9)
	local ox = CameraRules.offset(55, 46, yaw)
	Harness.truthy(ox < 0, "camera should be behind the player, on the -X side")
	-- stick up now walks toward +X, stick right walks toward +Z
	local wx, wz = MoveRules.moveToWorld(0, 1, yaw)
	near(wx, 1, 1e-9)
	near(wz, 0, 1e-9)
	wx, wz = MoveRules.moveToWorld(1, 0, yaw)
	near(wx, 0, 1e-9)
	near(wz, 1, 1e-9)
	-- turning left goes the other way
	near(CameraRules.turnedYaw(0, -90), 90)
end)

test("the heading wraps around, so spinning forever never drifts", function()
	local yaw = 0
	for _ = 1, 100 do
		yaw = CameraRules.turnedYaw(yaw, 37)
	end
	Harness.truthy(yaw >= -180 and yaw < 180, "yaw escaped the range: " .. yaw)
	near(CameraRules.wrapDegrees(360), 0)
	near(CameraRules.wrapDegrees(-190), 170)
	near(CameraRules.wrapDegrees(180), -180)
	-- turning a full circle lands back where it started
	near(CameraRules.turnedYaw(25, 360), 25, 1e-9)
end)

test("bad turn numbers never move the camera", function()
	eq(CameraRules.wrapDegrees(0 / 0), 0)
	eq(CameraRules.wrapDegrees(math.huge), 0)
	eq(CameraRules.dragTurn(0 / 0, 0.3, 40), 0)
	eq(CameraRules.dragTurn(math.huge, 0.3, 40), 0)
	eq(CameraRules.stickTurn(0 / 0, 0.016, 150, 40), 0)
	eq(CameraRules.stickTurn(1, math.huge, 150, 40), 0)
end)

test("a drag turns by pixels times speed, and one huge swipe is capped", function()
	local c = Config.Camera
	near(
		CameraRules.dragTurn(100, c.lookDegreesPerPixel, c.maxTurnPerFrame),
		100 * c.lookDegreesPerPixel
	)
	near(
		CameraRules.dragTurn(-20, c.lookDegreesPerPixel, c.maxTurnPerFrame),
		-20 * c.lookDegreesPerPixel
	)
	near(CameraRules.dragTurn(1e6, c.lookDegreesPerPixel, c.maxTurnPerFrame), c.maxTurnPerFrame)
	near(CameraRules.dragTurn(-1e6, c.lookDegreesPerPixel, c.maxTurnPerFrame), -c.maxTurnPerFrame)
	eq(CameraRules.dragTurn(0, c.lookDegreesPerPixel, c.maxTurnPerFrame), 0)
end)

test("the gamepad turn does not depend on frame rate and a long hitch is capped", function()
	local c = Config.Camera
	local one = CameraRules.stickTurn(1, 1 / 60, c.padTurnDegreesPerSecond, c.maxTurnPerFrame)
	local sum = 0
	for _ = 1, 60 do
		sum += one
	end
	near(sum, c.padTurnDegreesPerSecond, 1e-6) -- a full second of full push
	near(CameraRules.stickTurn(0.5, 1 / 60, c.padTurnDegreesPerSecond, c.maxTurnPerFrame), one / 2)
	near(
		CameraRules.stickTurn(-1, 5, c.padTurnDegreesPerSecond, c.maxTurnPerFrame),
		-c.maxTurnPerFrame
	)
end)

test("the turn speeds in Config are sane", function()
	local c = Config.Camera
	Harness.truthy(c.lookDegreesPerPixel > 0 and c.lookDegreesPerPixel < 2)
	Harness.truthy(c.padTurnDegreesPerSecond > 30 and c.padTurnDegreesPerSecond < 720)
	Harness.truthy(c.maxTurnPerFrame >= 10 and c.maxTurnPerFrame <= 90)
end)
