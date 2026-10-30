--!strict
-- Minimap and zone maths. Pure numbers (x/z studs in, unit-circle coordinates out) for Lune.
-- The minimap is centred on the player and shows `range` studs from the centre to its edge.
-- Screen "up" is world -Z when the camera yaw is 0 (Config.Camera.yawDegrees).

local MinimapMath = {}

export type ZoneLike = {
	centerX: number,
	centerZ: number,
	fromRadius: number,
	toRadius: number,
	startedAt: number,
	endsAt: number,
}

-- World offset to minimap coordinates: u to the right, v DOWN, both -1..1 at the circle's rim.
function MinimapMath.toMap(
	x: number,
	z: number,
	centerX: number,
	centerZ: number,
	range: number,
	yawDegrees: number
): (number, number)
	local a = math.rad(yawDegrees)
	local dx, dz = x - centerX, z - centerZ
	local right = dx * math.cos(a) + dz * math.sin(a)
	local forward = dx * math.sin(a) - dz * math.cos(a)
	return right / range, -forward / range
end

-- The safe circle's radius right now. Closes in a straight line from fromRadius to toRadius
-- between startedAt and endsAt, the same way the server does (display only; the server owns damage).
function MinimapMath.currentRadius(zone: ZoneLike, now: number): number
	if now <= zone.startedAt then
		return zone.fromRadius
	end
	if now >= zone.endsAt or zone.endsAt <= zone.startedAt then
		return zone.toRadius
	end
	local t = (now - zone.startedAt) / (zone.endsAt - zone.startedAt)
	return zone.fromRadius + (zone.toRadius - zone.fromRadius) * t
end

-- The player is outside only when strictly past the edge (+tolerance). Exactly on it counts as
-- inside, like the server (Config.Zone.edgeTolerance).
function MinimapMath.isOutside(
	px: number,
	pz: number,
	zoneX: number,
	zoneZ: number,
	radius: number,
	tolerance: number?
): boolean
	local dx, dz = px - zoneX, pz - zoneZ
	local r = radius + (tolerance or 0)
	return dx * dx + dz * dz > r * r
end

export type Circle = { u: number, v: number, r: number }

-- Safe circle drawn on the minimap, in minimap units (rim = 1).
function MinimapMath.safeCircle(
	px: number,
	pz: number,
	zoneX: number,
	zoneZ: number,
	radius: number,
	range: number,
	yawDegrees: number
): Circle
	local u, v = MinimapMath.toMap(zoneX, zoneZ, px, pz, range, yawDegrees)
	return { u = u, v = v, r = radius / range }
end

-- Dots farther than the rim are pinned to it (used for the "zone is that way" pointer).
function MinimapMath.clampToRim(u: number, v: number, margin: number?): (number, number, boolean)
	local limit = 1 - (margin or 0)
	local mag = math.sqrt(u * u + v * v)
	if mag <= limit or mag == 0 then
		return u, v, false
	end
	return u / mag * limit, v / mag * limit, true
end

return MinimapMath
