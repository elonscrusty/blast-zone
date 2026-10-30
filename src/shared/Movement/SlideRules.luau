--!strict
-- The slide's rules as plain numbers (no Roblox types) so Lune can test them. The server and the
-- client both use these, so "how far can I slide" has one answer.

local SlideRules = {}

function SlideRules.isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- Unit length 2D vector, or nil when the input is not finite or too small to have a direction.
function SlideRules.normalize(x: any, z: any): (number?, number?)
	if not SlideRules.isFinite(x) or not SlideRules.isFinite(z) then
		return nil, nil
	end
	local len = math.sqrt(x * x + z * z)
	if len < 1e-3 then
		return nil, nil
	end
	return x / len, z / len
end

-- Slide direction: where the player is moving, else where they face. nil if neither is usable.
function SlideRules.direction(moveX: any, moveZ: any, faceX: any, faceZ: any): (number?, number?)
	local x, z = SlideRules.normalize(moveX, moveZ)
	if x ~= nil then
		return x, z
	end
	return SlideRules.normalize(faceX, faceZ)
end

-- How far the slide may go. `blockedAt` is how far a body-sized sweep travelled before touching
-- something (nil = nothing in the way). Leaves a small gap so the player does not end inside a wall.
function SlideRules.clampToBlock(wanted: number, blockedAt: number?, skin: number): number
	if blockedAt == nil then
		return wanted
	end
	return math.clamp(blockedAt - skin, 0, wanted)
end

-- Distances along the path to check for floor: every `step`, and always the very end.
function SlideRules.groundSamples(distance: number, step: number): { number }
	local out = {}
	if distance <= 0 then
		return out
	end
	local d = step
	while d < distance do
		table.insert(out, d)
		d += step
	end
	table.insert(out, distance)
	return out
end

-- Stops the slide at the last sample that still had floor (and every sample before it too).
function SlideRules.clampToGround(
	distance: number,
	samples: { number },
	hasGround: { boolean }
): number
	local safe = 0
	for i, d in samples do
		if not hasGround[i] then
			return math.min(safe, distance)
		end
		safe = d
	end
	return distance
end

-- How far along (ox,oz) + t*(dx,dz) stays inside the box. 0 if the start is already outside.
function SlideRules.clampToBounds(
	ox: number,
	oz: number,
	dx: number,
	dz: number,
	distance: number,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number
): number
	if ox < minX or ox > maxX or oz < minZ or oz > maxZ then
		return 0
	end
	local limit = distance
	if dx > 1e-6 then
		limit = math.min(limit, (maxX - ox) / dx)
	elseif dx < -1e-6 then
		limit = math.min(limit, (minX - ox) / dx)
	end
	if dz > 1e-6 then
		limit = math.min(limit, (maxZ - oz) / dz)
	elseif dz < -1e-6 then
		limit = math.min(limit, (minZ - oz) / dz)
	end
	return math.max(0, limit)
end

-- Speed (studs/s) `t` seconds into the slide: fast start that eases off. Covers exactly `distance`.
function SlideRules.speedAt(distance: number, duration: number, t: number): number
	if duration <= 0 or t < 0 or t > duration then
		return 0
	end
	return (distance / duration) * (1.5 - t / duration)
end

-- Distance covered `t` seconds in (the integral of speedAt).
function SlideRules.travelled(distance: number, duration: number, t: number): number
	if duration <= 0 then
		return distance
	end
	local u = math.clamp(t / duration, 0, 1)
	return distance * (1.5 * u - 0.5 * u * u)
end

-- Cooldown after upgrades: whatever the stat sheet says, never below the floor.
function SlideRules.cooldown(value: number, floor: number): number
	if not SlideRules.isFinite(value) then
		return floor
	end
	return math.max(floor, value)
end

export type CanStart = {
	now: number,
	readyAt: number,
	activeUntil: number,
	alive: boolean,
	gateOpen: boolean,
}

-- Why a slide may not start, or nil when it may.
function SlideRules.blockedReason(s: CanStart): string?
	if not s.alive then
		return "dead"
	end
	if not s.gateOpen then
		return "gate"
	end
	if s.now < s.activeUntil then
		return "active"
	end
	if s.now < s.readyAt then
		return "cooldown"
	end
	return nil
end

-- After the slide, was the player a believable distance from where it started? Covers the slide
-- plus a little walking while the network catches up. Too far means the client lied.
function SlideRules.endPlausible(
	startX: number,
	startZ: number,
	nowX: number,
	nowZ: number,
	distance: number,
	walkSpeed: number,
	grace: number,
	tolerance: number
): boolean
	local dx, dz = nowX - startX, nowZ - startZ
	local moved = math.sqrt(dx * dx + dz * dz)
	return moved <= distance + walkSpeed * grace + tolerance
end

return SlideRules
