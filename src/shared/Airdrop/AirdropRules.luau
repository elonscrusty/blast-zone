--!strict
-- Airdrop maths with no game objects in it, so Lune can test it. `roll` is any function that
-- returns a number in [0, 1).

local AirdropRules = {}

export type Spot = { x: number, z: number, y: number }

-- When each drop starts, in seconds after the fight began. `count` drops are spread evenly from
-- `firstAt` to `lastAt`, each moved by up to `jitter` either way, then kept sorted and at least
-- `minGap` apart. Never earlier than 0.
function AirdropRules.schedule(
	count: number,
	firstAt: number,
	lastAt: number,
	jitter: number,
	minGap: number,
	roll: () -> number
): { number }
	local out: { number } = {}
	for i = 1, count do
		local base = if count == 1
			then (firstAt + lastAt) / 2
			else firstAt + (lastAt - firstAt) * (i - 1) / (count - 1)
		table.insert(out, math.max(0, base + (roll() * 2 - 1) * jitter))
	end
	table.sort(out)
	for i = 2, #out do
		out[i] = math.max(out[i], out[i - 1] + minGap)
	end
	return out
end

-- How far from the circle's middle a drop may land: inside the circle as it will be, not as it is
-- (the circle may be closing), and `margin` studs in from the line.
function AirdropRules.safeRadius(radius: number, closingTo: number, margin: number): number
	return math.max(0, math.min(radius, closingTo) - margin)
end

-- Tries random points inside a circle until `floorAt(x, z)` says there is open street there (it
-- returns the floor height, or nil). A point nearer than `minApart` to any spot in `avoid` is
-- skipped. Returns nil when every try failed.
function AirdropRules.pickSpot(
	centerX: number,
	centerZ: number,
	radius: number,
	tries: number,
	roll: () -> number,
	floorAt: (number, number) -> number?,
	avoid: { Spot },
	minApart: number
): Spot?
	if radius <= 0 then
		return nil
	end
	local keep = minApart * minApart
	for _ = 1, tries do
		local angle = roll() * 2 * math.pi
		local distance = math.sqrt(roll()) * radius -- sqrt keeps points even across the disc
		local x = centerX + math.cos(angle) * distance
		local z = centerZ + math.sin(angle) * distance
		local near = false
		for _, other in avoid do
			local dx, dz = other.x - x, other.z - z
			if dx * dx + dz * dz < keep then
				near = true
				break
			end
		end
		if not near then
			local y = floorAt(x, z)
			if y ~= nil then
				return { x = x, z = z, y = y }
			end
		end
	end
	return nil
end

-- Where a drop is in its life: "falling", "landed" (shut) or "opened".
function AirdropRules.stage(now: number, landsAt: number, opensAt: number): string
	if now >= opensAt then
		return "opened"
	elseif now >= landsAt then
		return "landed"
	end
	return "falling"
end

-- Height of the crate above the street. Fast at first, slow for the last stretch, 0 once landed.
function AirdropRules.crateHeight(
	now: number,
	startedAt: number,
	landsAt: number,
	startHeight: number
): number
	local span = landsAt - startedAt
	if span <= 0 then
		return 0
	end
	local k = math.clamp((now - startedAt) / span, 0, 1)
	return startHeight * (1 - k) ^ 1.4
end

-- How much of the beam is left, 1 while the drop is shut, down to 0 `fadeSeconds` after it opens.
function AirdropRules.beamStrength(now: number, opensAt: number, fadeSeconds: number): number
	if now < opensAt then
		return 1
	end
	if fadeSeconds <= 0 then
		return 0
	end
	return math.clamp(1 - (now - opensAt) / fadeSeconds, 0, 1)
end

local ARROWS = { "↑", "↗", "→", "↘", "↓", "↙", "←", "↖" }

-- One of eight arrows pointing from the fighter toward the drop, seen from where the camera looks.
-- (dx, dz) = drop minus fighter; (lookX, lookZ) = the way the camera faces. Both on the ground plane.
-- No direction (standing on it, or no camera) gives "".
function AirdropRules.arrow(dx: number, dz: number, lookX: number, lookZ: number): string
	if (dx == 0 and dz == 0) or (lookX == 0 and lookZ == 0) then
		return ""
	end
	-- Angle of the drop, then the angle the camera faces; the turn from one to the other, clockwise
	-- seen from above (Roblox: +X right, -Z forward, so a right turn is positive).
	local drop = math.atan2(dx, -dz)
	local face = math.atan2(lookX, -lookZ)
	local turn = (drop - face) % (2 * math.pi)
	local slot = math.floor(turn / (math.pi / 4) + 0.5) % 8
	return ARROWS[slot + 1]
end

-- Meters-ish text for the hint strip: whole studs, never negative.
function AirdropRules.distanceText(studs: number): string
	return `{math.max(0, math.floor(studs + 0.5))}`
end

return AirdropRules
