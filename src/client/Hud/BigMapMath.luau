--!strict
-- Big map maths. Pure numbers (world x/z in, 0..1 fractions out) for Lune.
-- The big map shows the whole arena. It is turned with the camera like the minimap, so "up" on the
-- map is always up on the screen. A square turned that way reaches at most FIT-times past the
-- panel's middle line, so the arena square is scaled by FIT and never leaves the panel.

local MinimapMath = require("./MinimapMath")

local BigMapMath = {}

export type Arena = { size: number, centerX: number, centerZ: number }
export type Spot = { x: number, y: number } -- panel fractions, 0 = left / top, 1 = right / bottom
export type Ring = { x: number, y: number, size: number } -- fractions of the arena square; size = width

BigMapMath.FIT = 1 / math.sqrt(2)
BigMapMath.MAX_RING = 4 -- a ring bigger than this is just "everything", drawn at this size

-- Width (and height) of the arena square as a share of the panel.
function BigMapMath.arenaSide(): number
	return BigMapMath.FIT
end

-- Roblox turns clockwise; the world turns the other way so the camera's heading points up.
function BigMapMath.arenaRotation(yawDegrees: number): number
	return -yawDegrees
end

local function clamp01(n: number): number
	return math.clamp(n, 0, 1)
end

-- Where a world point lands on the panel. Points past the arena edge are held on the panel.
function BigMapMath.point(x: number, z: number, arena: Arena, yawDegrees: number): Spot
	local u, v = MinimapMath.toMap(x, z, arena.centerX, arena.centerZ, arena.size / 2, yawDegrees)
	return {
		x = clamp01(0.5 + u * BigMapMath.FIT / 2),
		y = clamp01(0.5 + v * BigMapMath.FIT / 2),
	}
end

-- A circle on the ground (the safe circle, the next one) inside the arena square, as fractions of
-- that square. The square is turned for the camera as a whole, so rings need no turn of their own.
-- Not clamped: the arena square clips them.
function BigMapMath.ring(centerX: number, centerZ: number, radius: number, arena: Arena): Ring
	local half = arena.size / 2
	local u, v = MinimapMath.toMap(centerX, centerZ, arena.centerX, arena.centerZ, half, 0)
	return {
		x = 0.5 + u / 2,
		y = 0.5 + v / 2,
		size = math.clamp(radius / half, 0, BigMapMath.MAX_RING),
	}
end

return BigMapMath
