--!strict
-- Where a flying chunk is at time t (piece 43). Pure maths so Lune can test it. A chunk is thrown
-- from (x, y, z) with a speed, falls under gravity, tumbles, lands on the floor and then shrinks away.

local ChunkFlight = {}

export type Throw = {
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	floorY: number, -- the chunk rests with its middle this high
}

-- Position at t seconds. After landing a chunk stops sliding (it just sits where it came down).
function ChunkFlight.position(c: Throw, gravity: number, t: number): (number, number, number)
	local tt = math.max(0, t)
	-- time of landing: y0 + vy t - g t^2 / 2 = floorY
	local drop = c.y - c.floorY
	local landT = (c.vy + math.sqrt(c.vy * c.vy + 2 * gravity * math.max(0, drop))) / gravity
	local flown = math.min(tt, landT)
	local y = c.y + c.vy * flown - 0.5 * gravity * flown * flown
	return c.x + c.vx * flown, math.max(c.floorY, y), c.z + c.vz * flown
end

function ChunkFlight.landTime(c: Throw, gravity: number): number
	local drop = c.y - c.floorY
	return (c.vy + math.sqrt(c.vy * c.vy + 2 * gravity * math.max(0, drop))) / gravity
end

-- Size multiplier: 1 until the last `fade` seconds of its life, then down to nothing.
function ChunkFlight.scale(t: number, life: number, fade: number): number
	if t >= life then
		return 0
	end
	if t <= life - fade then
		return 1
	end
	return (life - t) / fade
end

-- A throw away from the prop's middle. `angle` in radians, `speed01` and `lift01` from 0 to 1.
function ChunkFlight.throw(
	x: number,
	y: number,
	z: number,
	floorY: number,
	angle: number,
	speed01: number,
	lift01: number,
	sideSpeed: number,
	upSpeed: number
): Throw
	local side = sideSpeed * (0.35 + 0.65 * speed01)
	return {
		x = x,
		y = y,
		z = z,
		vx = math.cos(angle) * side,
		vy = upSpeed * (0.5 + 0.5 * lift01),
		vz = math.sin(angle) * side,
		floorY = floorY,
	}
end

return ChunkFlight
