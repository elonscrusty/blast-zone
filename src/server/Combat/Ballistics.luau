--!strict
-- Shot and blast geometry on the ground plane. Shots fly flat: a bullet is a line, a body is a circle.
-- Pure numbers (no Vector3), so Lune can test it. The Roblox side only supplies "how far until a wall".

local Ballistics = {}

export type Target = { id: string, x: number, z: number, r: number }
export type Hit = { kind: "target" | "wall" | "none", dist: number, id: string? }
export type BlastVictim = { id: string, factor: number, dist: number }

local TINY = 1e-4

local function finite(n: number): boolean
	return n == n and n > -1e9 and n < 1e9
end

-- A client direction (x, y, z) flattened onto the ground and made unit length. nil if it points straight up/down or is junk.
function Ballistics.flatten(x: number, y: number, z: number): (number?, number?)
	if not (finite(x) and finite(y) and finite(z)) then
		return nil, nil
	end
	local len = math.sqrt(x * x + z * z)
	if len < 0.05 then
		return nil, nil
	end
	return x / len, z / len
end

function Ballistics.rotate(dx: number, dz: number, degrees: number): (number, number)
	local a = math.rad(degrees)
	local c, s = math.cos(a), math.sin(a)
	return dx * c - dz * s, dx * s + dz * c
end

-- `count` directions fanned evenly around the aim, `spreadDegrees` apart. One projectile is exactly the aim.
function Ballistics.fan(
	dx: number,
	dz: number,
	count: number,
	spreadDegrees: number
): { { x: number, z: number } }
	local out = {}
	for i = 1, math.max(1, count) do
		local offset = (i - 1 - (count - 1) / 2) * spreadDegrees
		local x, z = Ballistics.rotate(dx, dz, offset)
		table.insert(out, { x = x, z = z })
	end
	return out
end

-- Distance along the segment (unit direction) where it first enters the circle, or nil.
function Ballistics.segmentCircle(
	ox: number,
	oz: number,
	dx: number,
	dz: number,
	maxDist: number,
	cx: number,
	cz: number,
	r: number
): number?
	local px, pz = cx - ox, cz - oz
	local along = px * dx + pz * dz
	local perp2 = px * px + pz * pz - along * along
	if perp2 > r * r then
		return nil
	end
	local enter = along - math.sqrt(math.max(0, r * r - perp2))
	if enter > maxDist then
		return nil
	end
	if along < 0 and px * px + pz * pz > r * r then
		return nil -- the circle is behind the shooter
	end
	return math.max(0, enter)
end

-- What a shot meets first. `wallDist` is how far the nearest wall is (nil = none within range).
-- A body at or beyond the wall is covered by it.
function Ballistics.firstHit(
	ox: number,
	oz: number,
	dx: number,
	dz: number,
	maxDist: number,
	wallDist: number?,
	targets: { Target }
): Hit
	local reach = maxDist
	if wallDist ~= nil and wallDist < reach then
		reach = wallDist
	end
	local bestId: string? = nil
	local bestDist = reach
	for _, t in targets do
		local d = Ballistics.segmentCircle(ox, oz, dx, dz, reach, t.x, t.z, t.r)
		if d ~= nil and (bestId == nil or d < bestDist) and d <= reach then
			bestId, bestDist = t.id, d
		end
	end
	if bestId ~= nil then
		-- A body exactly at the wall distance loses to the wall (strictly in front wins).
		if wallDist ~= nil and bestDist >= wallDist - TINY then
			return { kind = "wall", dist = wallDist }
		end
		return { kind = "target", dist = bestDist, id = bestId }
	end
	if wallDist ~= nil and wallDist <= maxDist then
		return { kind = "wall", dist = wallDist }
	end
	return { kind = "none", dist = maxDist }
end

export type LineHit = { id: string, dist: number }
export type LineResult = {
	hits: { LineHit }, -- bodies the shot passes through, nearest first
	endKind: "target" | "wall" | "none", -- what stopped it: the last body it may hit, a wall, or its range
	endDist: number,
}

-- A shot that can pass through `extra` bodies after the first (the Piercing Rounds power). Walls still
-- stop it. With extra = 0 this is exactly `firstHit`: one body, a wall, or nothing.
function Ballistics.line(
	ox: number,
	oz: number,
	dx: number,
	dz: number,
	maxDist: number,
	wallDist: number?,
	targets: { Target },
	extra: number
): LineResult
	local hits: { LineHit } = {}
	local left = table.clone(targets)
	local allowed = 1 + math.max(0, math.floor(extra))
	while true do
		local h = Ballistics.firstHit(ox, oz, dx, dz, maxDist, wallDist, left)
		if h.kind ~= "target" or h.id == nil then
			return { hits = hits, endKind = h.kind, endDist = h.dist }
		end
		table.insert(hits, { id = h.id, dist = h.dist })
		if #hits >= allowed then
			return { hits = hits, endKind = "target", endDist = h.dist }
		end
		for i, t in left do
			if t.id == h.id then
				table.remove(left, i)
				break
			end
		end
	end
end

-- Damage share at a distance from the middle of a blast (measured from the body's edge).
-- 1 at the centre, `minFactor` at the rim, 0 outside.
function Ballistics.blastFactor(edgeDist: number, radius: number, minFactor: number): number
	if edgeDist > radius then
		return 0
	end
	local t = math.max(0, edgeDist) / radius
	return 1 - (1 - minFactor) * t
end

-- Everyone a blast reaches. `clear(target)` says whether a wall-free line runs from the centre to them.
function Ballistics.blastVictims(
	cx: number,
	cz: number,
	radius: number,
	minFactor: number,
	targets: { Target },
	clear: (Target) -> boolean
): { BlastVictim }
	local out = {}
	for _, t in targets do
		local dist = math.sqrt((t.x - cx) ^ 2 + (t.z - cz) ^ 2)
		local factor = Ballistics.blastFactor(dist - t.r, radius, minFactor)
		if factor > 0 and clear(t) then
			table.insert(out, { id = t.id, factor = factor, dist = dist })
		end
	end
	table.sort(out, function(a: BlastVictim, b: BlastVictim): boolean
		return a.dist < b.dist
	end)
	return out
end

-- Is a client-claimed position close enough to the one the server knows?
function Ballistics.withinDrift(
	ax: number,
	az: number,
	bx: number,
	bz: number,
	maxDrift: number
): boolean
	return (ax - bx) ^ 2 + (az - bz) ^ 2 <= maxDrift * maxDrift
end

return Ballistics
