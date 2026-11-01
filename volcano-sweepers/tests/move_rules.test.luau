--!strict
-- The server's movement check (shared/Player/MoveRules): honest walking and lag spikes pass,
-- teleports and speed hacks only get the trusted spot, and never faster than walking.
local Harness = require("./harness")
local MoveRules = require("../src/shared/Player/MoveRules")

local WALK = 16
local STEP = 0.2 -- MoveWatch looks 5 times a second

Harness.test("move: honest walking and jumping is always ok and trusted", function()
	local tr = MoveRules.new(0, 0, 0)
	local t, x = 0, 0
	for _ = 1, 300 do
		t += STEP
		x += WALK * 1.3 * STEP -- a bit faster than walking (jump momentum)
		Harness.eq(MoveRules.observe(tr, x, 0, t, WALK), "ok")
		Harness.eq(MoveRules.isSuspect(tr, t), false)
	end
	Harness.near(tr.x, x, 1e-6)
	local cx, _, ok = MoveRules.check(tr, x + 2, 0, t + 0.1, WALK)
	Harness.truthy(ok)
	Harness.near(cx, x + 2, 1e-6, "the real spot is used when it is reachable")
end)

Harness.test("move: a lag spike (no updates, then a catch-up jump) is never punished", function()
	local tr = MoveRules.new(0, 0, 0)
	local t, x = 0, 0
	for _ = 1, 20 do
		t += STEP
		x += WALK * STEP
		MoveRules.observe(tr, x, 0, t, WALK)
	end
	-- 3 seconds frozen on the server while the player keeps running
	for _ = 1, 15 do
		t += STEP
		Harness.eq(MoveRules.observe(tr, x, 0, t, WALK), "ok")
	end
	x += WALK * 3
	t += STEP
	Harness.eq(MoveRules.observe(tr, x, 0, t, WALK), "ok", "48 studs of catch-up")
	Harness.eq(MoveRules.isSuspect(tr, t), false)
	Harness.eq(MoveRules.shouldSnap(tr, x, 0, t), false)
end)

Harness.test("move: a teleport to the hut only moves the trusted spot at walking speed", function()
	local tr = MoveRules.new(0, 0, 0)
	local t = 0
	for _ = 1, 20 do -- stand still: the bank is full
		t += STEP
		MoveRules.observe(tr, 0, 0, t, WALK)
	end
	t += STEP
	Harness.eq(MoveRules.observe(tr, 300, 0, t, WALK), "clamped")
	Harness.truthy(MoveRules.isSuspect(tr, t))
	local cx, _, ok = MoveRules.check(tr, 300, 0, t, WALK)
	Harness.eq(ok, false, "rules refuse while suspect")
	Harness.truthy(cx < 120, `trusted x {cx} is still far from the hut`)
	-- how long until the trusted spot reaches the real one: never faster than ~walking
	local arrived: number? = nil
	for i = 1, 200 do
		t += STEP
		MoveRules.observe(tr, 300, 0, t, WALK)
		if tr.x >= 300 - 1e-6 and arrived == nil then
			arrived = i * STEP
		end
	end
	Harness.truthy(arrived ~= nil, "it does catch up when the player waits")
	local bank = MoveRules.allowedSpeed(WALK) * MoveRules.BANK_SECONDS + MoveRules.SLACK
	local minTime = (300 - bank) / WALK
	Harness.truthy((arrived :: number) >= minTime - 0.5, `caught up in {arrived}s, min {minTime}`)
	Harness.eq(MoveRules.isSuspect(tr, t), false)
end)

Harness.test("move: a speed hack never gets ahead of 1.5x walking for long", function()
	local tr = MoveRules.new(0, 0, 0)
	local t, x = 0, 0
	for _ = 1, 150 do -- 30 s at 5x walk speed
		t += STEP
		x += WALK * 5 * STEP
		MoveRules.observe(tr, x, 0, t, WALK)
	end
	local maxDist = MoveRules.allowedSpeed(WALK) * 30 + 200
	Harness.truthy(tr.x < maxDist, `trusted {tr.x} after 30 s (real {x})`)
	Harness.truthy(MoveRules.shouldSnap(tr, x, 0, t), "far from the trusted spot: snap back")
end)

Harness.test("move: repeated jumps snap back; one jump does not", function()
	local tr = MoveRules.new(0, 0, 0)
	local t = 0
	local function jump(to: number)
		for _ = 1, 15 do
			t += STEP
			MoveRules.observe(tr, tr.x, 0, t, WALK)
		end
		t += STEP
		MoveRules.observe(tr, to, 0, t, WALK)
		-- wait until caught up so the next jump is a fresh one
		for _ = 1, 20 do
			t += STEP
			MoveRules.observe(tr, to, 0, t, WALK)
		end
	end
	jump(110)
	Harness.eq(MoveRules.shouldSnap(tr, tr.x, 0, t), false, "one big step is forgiven")
	jump(220)
	jump(330)
	Harness.eq(MoveRules.shouldSnap(tr, tr.x, 0, t), true, "three in 20 s is a pattern")
	Harness.eq(#tr.strikes, 0, "strikes cleared after a snap")
end)

Harness.test("move: respawn grace, reset, and junk input", function()
	local tr = MoveRules.new(0, 0, 0, 3)
	Harness.eq(MoveRules.observe(tr, 500, 500, 1, WALK), "ok", "grace accepts a spawn teleport")
	Harness.eq(MoveRules.observe(tr, 0 / 0, 1, 1.2, WALK), "bad")
	Harness.eq(MoveRules.observe(tr, math.huge, 1, 1.2, WALK), "bad")
	Harness.eq(tr.x, 500)
	MoveRules.reset(tr, -40, 10, 10, 2)
	Harness.eq(MoveRules.observe(tr, 100, 100, 10.5, WALK), "ok", "reset grace")
	local x, z, ok = MoveRules.check(tr, 0 / 0, 5, 20, WALK)
	Harness.eq(ok, false)
	Harness.eq(x, tr.x)
	Harness.eq(z, tr.z)
	Harness.truthy(MoveRules.allowedSpeed(0 / 0) > 0, "bad walk speed falls back")
end)
