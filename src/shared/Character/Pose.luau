--!strict
-- The body poses, as plain numbers (no Roblox types) so Lune can test them. Nothing here moves a part:
-- `compute` turns "what is this fighter doing" into joint angles, and the client applies them to the rig.
--
-- Angles are radians in the preview's convention (the figure faces +Z, a positive X turn swings a hanging
-- limb backwards). The client converts once, in CharacterRig, to Roblox's (-Z facing) convention.
-- Layers: legs and torso come from how the fighter moves, the arms from what the hands are doing,
-- then the one-shot extras (recoil, hit flinch) are added on top. Defeat and win replace everything.

local Pose = {}

export type Pose = {
	hy: number, -- hips height offset (studs)
	hrx: number, -- hips lean forward/back
	hrz: number, -- hips lean sideways
	tx: number, -- torso bend
	ty: number, -- torso twist
	hdx: number, -- head nod
	hdy: number, -- head turn
	aRx: number, -- right (gun) arm swing
	aRz: number,
	eRx: number, -- right elbow
	aLx: number,
	aLz: number,
	eLx: number,
	lRx: number, -- right leg swing
	lRz: number,
	sRx: number, -- right knee
	lLx: number,
	lLz: number,
	sLx: number,
	flash: number, -- muzzle flash strength, 0 when off
	hit: number, -- hit flash strength, 0 when off
}

export type Input = {
	t: number, -- clock seconds (any steady clock)
	speed: number, -- studs per second on the ground
	forward: number, -- share of the movement along the facing, -1 (backwards) .. 1 (forwards)
	alive: boolean,
	won: boolean,
	deadAge: number?, -- seconds since defeat started
	slideAge: number?, -- seconds since the slide started, nil when not sliding
	reloadPhase: number?, -- 0..1 through the reload, nil when not reloading
	shotAge: number?, -- seconds since the last shot was fired, nil if none lately
	hitAge: number?, -- seconds since the last hit taken, nil if none lately
}

Pose.KEYS = {
	"hy",
	"hrx",
	"hrz",
	"tx",
	"ty",
	"hdx",
	"hdy",
	"aRx",
	"aRz",
	"eRx",
	"aLx",
	"aLz",
	"eLx",
	"lRx",
	"lRz",
	"sRx",
	"lLx",
	"lLz",
	"sLx",
}

-- Tuning that belongs to the drawing, not the game rules.
local RUN_RATE = 11 -- steps per second at run speed
local FIRE_PERIOD = 0.2 -- recoil spacing, matches a 5 shot/s gun

local function clamp(x: number, a: number, b: number): number
	return math.max(a, math.min(b, x))
end

local function smooth(x: number): number
	x = clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Pose.zero(): Pose
	return {
		hy = 0,
		hrx = 0,
		hrz = 0,
		tx = 0,
		ty = 0,
		hdx = 0,
		hdy = 0,
		aRx = 0,
		aRz = 0,
		eRx = 0,
		aLx = 0,
		aLz = 0,
		eLx = 0,
		lRx = 0,
		lRz = 0,
		sRx = 0,
		lLx = 0,
		lLz = 0,
		sLx = 0,
		flash = 0,
		hit = 0,
	}
end

-- ===== layers =====

-- Standing, gun carried low.
local function idle(p: Pose, t: number)
	p.hy = math.sin(t * 2) * 0.03
	p.aRx, p.eRx, p.aRz = -1.0, -0.5, 0.15
	p.aLx, p.aLz, p.eLx = 0.1, 0.1, -0.3
	p.tx = 0.03
end

-- Gun up and pointing: bladed stance, off hand back.
local function aim(p: Pose, t: number)
	p.aRx, p.eRx, p.aRz = -1.5, -0.05, 0.12
	p.aLx, p.aLz, p.eLx = 0.45, 0.15, -1.0
	p.ty, p.hdy = 0.32, -0.28
	p.lRx, p.lLx = 0.2, -0.3
	p.hy = math.sin(t * 2) * 0.02
end

local function run(p: Pose, t: number)
	local ph = t * RUN_RATE
	local s = math.sin(ph)
	p.lLx, p.lRx = s * 0.95, -s * 0.95
	p.sLx = math.max(0, math.sin(ph + 1.3)) * 1.2
	p.sRx = math.max(0, math.sin(ph + 1.3 + math.pi)) * 1.2
	p.aRx, p.eRx, p.aRz = -1.0 + s * 0.12, -0.6, 0.12
	p.aLx, p.eLx, p.aLz = -s * 0.85, -0.5 - math.max(0, -s) * 0.5, 0.08
	p.tx, p.ty, p.hdy = 0.2, s * 0.2, -s * 0.1
	p.hy = -math.abs(math.cos(ph)) * 0.1 - 0.05
end

-- Side steps and backpedalling while the gun stays up.
local function strafe(p: Pose, t: number)
	aim(p, t)
	local ph = t * 10
	local s = math.sin(ph)
	p.lLz, p.lRz = 0.12 + s * 0.45, -0.12 + s * 0.45
	p.lLx, p.lRx = -0.15, 0.1
	p.sLx = math.max(0, math.sin(ph + 1.0)) * 0.9
	p.sRx = math.max(0, math.sin(ph + 1.0 + math.pi)) * 0.9
	p.hrz = -0.1
	p.hy = -math.abs(math.cos(ph)) * 0.08 - 0.08
end

-- Feet planted, shooting.
local function firing(p: Pose, t: number)
	aim(p, t)
	p.lRx, p.lLx, p.lLz, p.lRz, p.hy = 0.35, -0.35, 0.12, -0.12, -0.1
end

-- Arms only: the gun comes to the chest, the other hand fetches a new magazine, the gun goes back up.
local function reloadArms(p: Pose, phase: number)
	local a = smooth(phase / 0.15)
	local c = smooth((phase - 0.78) / 0.22)
	local b = math.sin(clamp((phase - 0.18) / 0.5, 0, 1) * math.pi * 2)
	local k = a * (1 - c)
	p.aRx, p.eRx = lerp(-1.5, -0.85, k), lerp(-0.05, -1.3, k)
	p.aLx = lerp(0.45, -1.1, k) + b * 0.18
	p.eLx = lerp(-1.0, -1.7, k) + b * 0.45
	p.aLz = lerp(0.15, -0.5, k)
	p.tx, p.hdx = k * 0.16, k * 0.38
	p.ty, p.hdy = lerp(0.32, 0.1, k), lerp(-0.28, -0.1, k)
end

local function slide(p: Pose, age: number)
	local k = smooth(age / 0.1) * (1 - smooth((age - 0.5) / 0.25))
	p.hrx, p.hy = -1.05 * k, -1.0 * k
	p.lLx, p.lRx, p.sRx, p.sLx = -0.55 * k, 0.2 * k, 1.5 * k, 0.05 * k
	p.aRx, p.eRx = lerp(-1.0, -1.5, k), lerp(-0.5, -0.05, k)
	p.aLx, p.aLz = lerp(0.1, 0.9, k), lerp(0.1, 0.6, k)
	p.hdx, p.tx = 0.9 * k, 0.5 * k
end

local function defeat(p: Pose, t: number, age: number)
	idle(p, t)
	local f = smooth(age / 0.7)
	local bounce = if age > 0.7 and age < 1.0
		then math.sin((age - 0.7) / 0.3 * math.pi) * 0.12
		else 0
	p.hrx = -1.5 * f
	p.hy = -1.6 * f + bounce
	p.aRx, p.eRx, p.aRz = lerp(-1.0, -0.35, f), lerp(-0.5, -0.2, f), -1.35 * f
	p.aLz, p.aLx = 1.35 * f, 0.1 * (1 - f)
	p.lLz, p.lRz = 0.3 * f, -0.3 * f
	p.hdx, p.hdy = -0.35 * f, 0.3 * f
	p.hit = math.exp(-age * 8) * 0.8
end

local function win(p: Pose, t: number)
	local h = math.abs(math.sin(t * 4.5))
	p.hy = h * 0.6
	p.aRx, p.aRz, p.eRx = -3.0 + math.sin(t * 9) * 0.22, -0.3, -0.25
	p.aLx, p.aLz, p.eLx = -2.9, 0.35, -0.2
	p.lRx, p.lLx = -0.25, 0.25
	p.sRx, p.sLx = 0.5 * (1 - h), 0.7 * (1 - h)
	p.hdx, p.ty, p.tx = -0.25, math.sin(t * 2.2) * 0.35, -0.1
end

-- ===== the one door =====

function Pose.compute(input: Input): Pose
	local p = Pose.zero()
	local t = input.t

	if not input.alive then
		defeat(p, t, input.deadAge or 0)
		return p
	end
	if input.won then
		win(p, t)
		return p
	end

	local moving = input.speed >= 2
	local shotAge = input.shotAge
	local gunUp = shotAge ~= nil and shotAge < 0.45

	if input.slideAge ~= nil then
		idle(p, t)
		slide(p, input.slideAge)
		return p
	end

	-- legs and torso
	if moving then
		if input.forward >= 0.55 and not gunUp then
			run(p, t)
		else
			strafe(p, t)
		end
	elseif gunUp then
		firing(p, t)
	else
		idle(p, t)
	end

	-- arms
	if input.reloadPhase ~= nil then
		reloadArms(p, clamp(input.reloadPhase, 0, 1))
	end

	-- recoil rides on the aim stance
	if shotAge ~= nil and gunUp and input.reloadPhase == nil then
		local k = math.exp(-(shotAge % FIRE_PERIOD) * 28)
		p.aRx -= k * 0.2
		p.hrx -= k * 0.07
		p.tx -= k * 0.08
		p.flash = if k > 0.35 then k else 0
	end

	-- hit flinch
	local hitAge = input.hitAge
	if hitAge ~= nil and hitAge < 0.35 then
		local k = math.exp(-hitAge * 6) * math.min(1, hitAge / 0.02)
		p.hrx -= 0.4 * k
		p.hdx -= 0.55 * k
		p.tx -= 0.3 * k
		p.aRx -= 0.3 * k
		p.aLx += 0.8 * k
		p.aLz += 0.6 * k
		p.hy -= 0.12 * k
		p.hit = k
	end
	return p
end

-- Moves `current` toward `target` (frame time `dt`). `rate` is Config.Character.smoothing.
function Pose.blend(current: Pose, target: Pose, dt: number, rate: number)
	local a = 1 - math.exp(-dt * rate)
	local cur = current :: any
	local tar = target :: any
	for _, key in Pose.KEYS do
		cur[key] += (tar[key] - cur[key]) * a
	end
	current.flash = target.flash -- these two are drawn as they are, never eased
	current.hit = target.hit
end

return Pose
