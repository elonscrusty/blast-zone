--!strict
-- Camera and aim maths as plain numbers (no Roblox types) so Lune can test them.

local CameraRules = {}

-- Where the camera sits relative to the player: (dx, dy, dz). Heading 0 puts it on the +Z side
-- looking toward -Z. The player can turn the heading (see turnedYaw).
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

-- Degrees, wrapped into [-180, 180). Bad numbers (nan, infinity) become 0.
function CameraRules.wrapDegrees(deg: number): number
	if deg ~= deg or deg == math.huge or deg == -math.huge then
		return 0
	end
	return (deg + 180) % 360 - 180
end

-- A swipe or a mouse drag (pixels, right = positive) as degrees to turn the view to the right.
-- `perPixel` is the speed, `maxStep` caps one frame's turn either way.
function CameraRules.dragTurn(pixels: number, perPixel: number, maxStep: number): number
	local deg = pixels * perPixel
	if deg ~= deg or deg == math.huge or deg == -math.huge then
		return 0
	end
	return math.clamp(deg, -maxStep, maxStep)
end

-- The gamepad stick (-1 left .. 1 right) held for `dt` seconds, as degrees to turn right.
function CameraRules.stickTurn(
	stick: number,
	dt: number,
	degreesPerSecond: number,
	maxStep: number
): number
	local deg = stick * dt * degreesPerSecond
	if deg ~= deg or deg == math.huge or deg == -math.huge then
		return 0
	end
	return math.clamp(deg, -maxStep, maxStep)
end

-- The new heading after turning the VIEW `rightDeg` degrees to the right (negative = left).
-- Looking right means the heading shrinks: at -90 the camera looks toward +X.
function CameraRules.turnedYaw(yawDeg: number, rightDeg: number): number
	return CameraRules.wrapDegrees(yawDeg - rightDeg)
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

-- Pitch and distance for the view: the normal play camera, or the chosen spectate style.
-- An unknown style name falls back to the play camera, so a typo never breaks the view.
function CameraRules.viewFor(
	play: { pitchDegrees: number, distance: number },
	spectate: {
		style: string,
		styles: { [string]: { pitchDegrees: number, distance: number } },
	},
	spectating: boolean
): (number, number)
	if spectating then
		local style = spectate.styles[spectate.style]
		if style then
			return style.pitchDegrees, style.distance
		end
	end
	return play.pitchDegrees, play.distance
end

-- Frame-rate independent follow: how much of the gap to close this frame. tau <= 0 closes it all.
function CameraRules.followAlpha(dt: number, tau: number): number
	if tau <= 0 or dt <= 0 then
		return if tau <= 0 then 1 else 0
	end
	return 1 - math.exp(-dt / tau)
end

return CameraRules
