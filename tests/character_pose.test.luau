--!strict
local Harness = require("./harness")
local Pose = require("../src/shared/Character/Pose")

local test, eq, near, truthy = Harness.test, Harness.eq, Harness.near, Harness.truthy

local function input(over: { [string]: any }?): Pose.Input
	local base: any = {
		t = 0.37,
		speed = 0,
		forward = 0,
		alive = true,
		won = false,
		deadAge = nil,
		slideAge = nil,
		reloadPhase = nil,
		shotAge = nil,
		hitAge = nil,
	}
	for k, v in over or {} do
		base[k] = v
	end
	return base
end

local function finite(p: Pose.Pose): boolean
	for _, key in Pose.KEYS do
		local v = (p :: any)[key]
		if v ~= v or math.abs(v) == math.huge then
			return false
		end
	end
	return true
end

-- ===== walking =====

test("running swings the legs against each other and the arms against the legs", function()
	local p = Pose.compute(input({ speed = 20, forward = 1 }))
	near(p.lLx, -p.lRx, 1e-9)
	truthy(math.abs(p.lLx) > 0.3, "legs swing")
	truthy(p.lLx * p.aLx < 0, "left arm opposes left leg")
end)

test("backing away or sidestepping uses the gun-up stride, not the run", function()
	local back = Pose.compute(input({ speed = 20, forward = -1 }))
	local side = Pose.compute(input({ speed = 20, forward = 0.1 }))
	local run = Pose.compute(input({ speed = 20, forward = 1 }))
	truthy(math.abs(back.lLz) > 0.05 or math.abs(back.lRz) > 0.05, "legs open sideways")
	near(back.aRx, side.aRx, 1e-9)
	truthy(run.aRx > back.aRx + 0.3, "running carries the gun lower than aiming")
end)

test("running while shooting keeps the gun up", function()
	local p = Pose.compute(input({ speed = 20, forward = 1, shotAge = 0.05 }))
	truthy(p.aRx < -1.5, "gun up and kicked")
end)

test("standing still is calm", function()
	local p = Pose.compute(input())
	near(p.lLx, 0)
	eq(p.flash, 0)
	eq(p.hit, 0)
end)

-- ===== firing =====

test("muzzle flash only shows right after a shot", function()
	truthy(Pose.compute(input({ shotAge = 0.0 })).flash > 0.5)
	eq(Pose.compute(input({ shotAge = 0.1 })).flash, 0)
	eq(Pose.compute(input({ shotAge = nil })).flash, 0)
end)

test("the gun goes back down after the aim hold runs out", function()
	local up = Pose.compute(input({ shotAge = 0.3 }))
	local down = Pose.compute(input({ shotAge = 0.6 }))
	truthy(up.aRx < -1.4)
	truthy(down.aRx > -1.1)
end)

test("recoil repeats with every shot of a 5 per second gun", function()
	local first = Pose.compute(input({ shotAge = 0.0 })).flash
	local second = Pose.compute(input({ shotAge = 0.2 })).flash
	near(first, second, 1e-9)
end)

-- ===== reload =====

test("reload brings the gun in and puts it back up", function()
	local start = Pose.compute(input({ reloadPhase = 0 }))
	local mid = Pose.compute(input({ reloadPhase = 0.45 }))
	local done = Pose.compute(input({ reloadPhase = 1 }))
	near(start.aRx, -1.5, 1e-6)
	truthy(mid.aRx > -1.0, "gun at the chest")
	truthy(mid.eLx < -1.0, "other hand reaches in")
	near(done.aRx, -1.5, 1e-6)
end)

test("reloading on the move keeps the legs running", function()
	local still = Pose.compute(input({ speed = 20, forward = 1 }))
	local reloading = Pose.compute(input({ speed = 20, forward = 1, reloadPhase = 0.4 }))
	near(reloading.lLx, still.lLx, 1e-9)
	truthy(math.abs(reloading.aRx - still.aRx) > 0.1)
end)

test("reload phase out of range is held to the ends, not extrapolated", function()
	near(
		Pose.compute(input({ reloadPhase = -5 })).aRx,
		Pose.compute(input({ reloadPhase = 0 })).aRx,
		1e-9
	)
	near(
		Pose.compute(input({ reloadPhase = 9 })).aRx,
		Pose.compute(input({ reloadPhase = 1 })).aRx,
		1e-9
	)
end)

-- ===== slide =====

test("slide drops the body low in the middle and stands up again", function()
	local low = Pose.compute(input({ slideAge = 0.25 }))
	truthy(low.hy < -0.5, "hips low")
	truthy(low.hrx < -0.5, "leaning back")
	truthy(math.abs(Pose.compute(input({ slideAge = 0.74 })).hy) < 0.3, "up again at the end")
end)

-- ===== hit =====

test("a hit flinches at once and is gone after the flinch time", function()
	local base = Pose.compute(input())
	local hurt = Pose.compute(input({ hitAge = 0.05 }))
	truthy(hurt.hit > 0.4)
	truthy(hurt.hdx < base.hdx - 0.1, "head snaps back")
	local gone = Pose.compute(input({ hitAge = 0.4 }))
	eq(gone.hit, 0)
	near(gone.hdx, base.hdx, 1e-9)
end)

-- ===== defeat and win =====

test("defeat ends flat on the back, and beats every other state", function()
	local p = Pose.compute(input({
		alive = false,
		deadAge = 2,
		won = true,
		slideAge = 0.1,
		reloadPhase = 0.5,
		speed = 20,
	}))
	near(p.hrx, -1.5, 1e-6)
	near(p.hy, -1.6, 1e-6)
	truthy(p.aLz > 1.2 and p.aRz < -1.2, "arms flop out")
end)

test("defeat starts upright", function()
	local p = Pose.compute(input({ alive = false, deadAge = 0 }))
	near(p.hrx, 0, 1e-9)
end)

test("the winner puts both arms up", function()
	local p = Pose.compute(input({ won = true }))
	truthy(p.aRx < -2.5 and p.aLx < -2.5)
end)

-- ===== safety =====

test("every pose over a long run of odd inputs is a finite number", function()
	for i = 0, 400 do
		local t = i * 0.037
		local speeds = { 0, 3, 20, 400 }
		for _, speed in speeds do
			local p = Pose.compute(input({
				t = t,
				speed = speed,
				forward = math.sin(t),
				shotAge = if i % 3 == 0 then t % 0.6 else nil,
				hitAge = if i % 5 == 0 then t % 0.5 else nil,
				reloadPhase = if i % 7 == 0 then (t % 1.2) / 1.2 else nil,
				slideAge = if i % 11 == 0 then t % 0.8 else nil,
			}))
			truthy(finite(p), `pose finite at t={t} speed={speed}`)
		end
	end
	truthy(
		finite(Pose.compute(input({ speed = 0 / 0, forward = 0 / 0 }))),
		"NaN speed is treated as standing"
	)
end)

test("blend eases toward the target and never eases the flashes", function()
	local cur = Pose.zero()
	local target = Pose.zero()
	target.aRx = -2
	target.flash = 1
	Pose.blend(cur, target, 0.016, 20)
	truthy(cur.aRx < 0 and cur.aRx > -2, "partway")
	eq(cur.flash, 1)
	for _ = 1, 200 do
		Pose.blend(cur, target, 0.016, 20)
	end
	near(cur.aRx, -2, 1e-3)
end)
