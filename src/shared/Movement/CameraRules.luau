--!strict
-- Camera and aim maths as plain numbers (no Roblox types) so Lune can test them.

local CameraRules = {}

-- Where the camera sits relative to the player: (dx, dy, dz). Heading 0 puts it on the +Z side
-- looking toward -Z; the heading never changes during play.
function CameraRules.offset(
	pitchDeg: number,
	distance: number,
	headingDeg: number
): (number, number, number)
	local pitch, heading = math.rad(pitchDeg), math.rad(headingDeg)
	local flat = distance * math.cos(pitch)
	return math.sin(heading) * flat, distance * math.sin(pitch), math.cos(heading) * flat
end

-- The camera's forward direction on the ground: (x, z).
function CameraRules.forward(headingDeg: number): (number, number)
	local heading = math.rad(headingDeg)
	return -math.sin(heading), -math.cos(heading)
end

-- The camera's right direction on the ground: (x, z).
function CameraRules.right(headingDeg: number): (number, number)
	local heading = math.rad(headingDeg)
	return math.cos(heading), -math.sin(heading)
end

-- A screen that is narrow (phone held upright) sees less sideways, so pull the camera back.
function CameraRules.distanceForAspect(
	base: number,
	aspect: number,
	narrowAspect: number,
	floorAspect: number,
	maxWiden: number
): number
	if aspect >= narrowAspect or narrowAspect <= floorAspect then
		return base
	end
	local t = math.clamp((narrowAspect - aspect) / (narrowAspect - floorAspect), 0, 1)
	return base * (1 + maxWiden * t)
end

-- Frame-rate independent follow: how much of the gap to close this frame. tau <= 0 closes it all.
function CameraRules.followAlpha(dt: number, tau: number): number
	if tau <= 0 or dt <= 0 then
		return if tau <= 0 then 1 else 0
	end
	return 1 - math.exp(-dt / tau)
end

return CameraRules
