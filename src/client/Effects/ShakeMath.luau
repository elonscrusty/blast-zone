--!strict
-- The maths of camera shake. Pure, so the tests can check it. No Roblox services here.
-- Shake is a "trauma" meter from 0 to 1 that falls back to 0 by itself. What you see is trauma squared,
-- so small bumps stay small and big blasts feel big. The field-of-view kick works the same way in degrees.

export type State = { trauma: number, fov: number }

export type ShakeConfig = {
	maxOffsetStuds: number,
	maxRollDegrees: number,
	frequency: number,
	decayPerSecond: number,
}

local ShakeMath = {}

function ShakeMath.new(): State
	return { trauma = 0, fov = 0 }
end

-- `scale` is the player's Camera shake setting times any distance falloff. 0 adds nothing.
function ShakeMath.addTrauma(s: State, amount: number, scale: number)
	local add = amount * math.clamp(scale, 0, 1)
	if add > 0 then
		s.trauma = math.min(1, s.trauma + add)
	end
end

function ShakeMath.addFov(s: State, degrees: number, scale: number, maxDegrees: number)
	local add = degrees * math.clamp(scale, 0, 1)
	if add > 0 then
		s.fov = math.min(maxDegrees, s.fov + add)
	end
end

function ShakeMath.step(
	s: State,
	dt: number,
	traumaDecayPerSecond: number,
	fovDecayPerSecond: number
)
	s.trauma = math.max(0, s.trauma - traumaDecayPerSecond * dt)
	s.fov *= math.exp(-fovDecayPerSecond * dt)
	if s.fov < 0.01 then
		s.fov = 0
	end
end

-- A smooth, bounded wobble between -1 and 1. Not random, so it does not stutter.
local function wobble(t: number, seed: number): number
	return math.sin(t + seed * 12.9898) * 0.6 + math.sin(t * 2.3 + seed * 78.233) * 0.4
end

-- Where to nudge the camera at time `t`: sideways studs, up studs, and roll in degrees.
function ShakeMath.sample(s: State, t: number, cfg: ShakeConfig): (number, number, number)
	local amount = s.trauma * s.trauma
	if amount <= 0 then
		return 0, 0, 0
	end
	local phase = t * cfg.frequency
	return cfg.maxOffsetStuds * amount * wobble(phase, 1),
		cfg.maxOffsetStuds * amount * wobble(phase, 2),
		cfg.maxRollDegrees * amount * wobble(phase, 3)
end

-- 1 when the event is close, 0 when it is far, a straight line between.
function ShakeMath.distanceScale(distance: number, fullStuds: number, noneStuds: number): number
	if distance <= fullStuds then
		return 1
	end
	if distance >= noneStuds then
		return 0
	end
	return 1 - (distance - fullStuds) / (noneStuds - fullStuds)
end

return ShakeMath
