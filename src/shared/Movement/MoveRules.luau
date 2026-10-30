--!strict
-- Walking maths as plain numbers (no Roblox types) so Lune can test it.

local CameraRules = require("./CameraRules")

local MoveRules = {}

-- What the stat sheet says, held between zero and the hard cap so a stack of upgrades cannot
-- make the camera or the collision misbehave.
function MoveRules.clampSpeed(value: number, base: number, maxMultiplier: number): number
	if value ~= value then
		return base
	end
	return math.clamp(value, 0, base * maxMultiplier)
end

-- The controls give (right, forward) with length <= 1, forward = up the screen. Returns the
-- ground direction (x, z) for Humanoid:Move; the length is kept so a gentle push walks slower.
function MoveRules.moveToWorld(right: number, forward: number, headingDeg: number): (number, number)
	local rx, rz = CameraRules.right(headingDeg)
	local fx, fz = CameraRules.forward(headingDeg)
	return rx * right + fx * forward, rz * right + fz * forward
end

return MoveRules
