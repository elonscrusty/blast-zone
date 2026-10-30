--!strict
-- Loudness by distance. Flat ground distance (the view is from above), a clear zone near you, then a
-- smooth fall to silence. Pure, so it is tested.

local AudioMath = {}

AudioMath.audibleBelow = 0.03 -- quieter than this is not worth a voice

export type Point = { X: number, Y: number, Z: number }

function AudioMath.groundDistance(a: Point, b: Point): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- 1 inside `ref`, 0 at `max` and beyond, squared fall-off between.
function AudioMath.scale(distance: number, ref: number, max: number): number
	if distance ~= distance then
		return 0
	end
	if distance <= ref then
		return 1
	end
	if distance >= max or max <= ref then
		return 0
	end
	local t = (distance - ref) / (max - ref)
	return (1 - t) * (1 - t)
end

return AudioMath
