--!strict
-- The hop's rules as plain numbers (piece 44), so Lune can test them. The Roblox side (VaultCast)
-- only supplies "what did the ray hit".

local VaultRules = {}

-- Are you walking square-on into the face? `dir` is where you go, `normal` points out of the face.
function VaultRules.headOn(
	dirX: number,
	dirZ: number,
	normalX: number,
	normalZ: number,
	minDot: number
): boolean
	local dl = math.sqrt(dirX * dirX + dirZ * dirZ)
	local nl = math.sqrt(normalX * normalX + normalZ * normalZ)
	if dl < 1e-6 or nl < 1e-6 then
		return false
	end
	return -(dirX * normalX + dirZ * normalZ) / (dl * nl) >= minDot
end

-- Thickness along the way of travel, or nil when it is missing, backwards or too thick.
function VaultRules.depth(entryDist: number, exitDist: number?, maxDepth: number): number?
	if exitDist == nil then
		return nil
	end
	local d = exitDist - entryDist
	if d ~= d or d <= 0 or d > maxDepth then
		return nil
	end
	return d
end

-- Height of the arc over the top: clear it by `clearance`, never flatter than `minPeak`.
function VaultRules.peak(topY: number, feetY: number, clearance: number, maxPeak: number): number
	return math.clamp(topY - feetY + clearance, 1.5, maxPeak)
end

-- Where the body is `u` (0..1) of the way through the hop: a straight line plus a rise that peaks half way.
function VaultRules.arc(
	fromX: number,
	fromY: number,
	fromZ: number,
	toX: number,
	toY: number,
	toZ: number,
	peak: number,
	u: number
): (number, number, number)
	local t = math.clamp(u, 0, 1)
	return fromX + (toX - fromX) * t,
		fromY + (toY - fromY) * t + math.sin(math.pi * t) * peak,
		fromZ + (toZ - fromZ) * t
end

-- After the hop, is the body a believable distance from where it started?
function VaultRules.endPlausible(
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
	return math.sqrt(dx * dx + dz * dz) <= distance + walkSpeed * grace + tolerance
end

return VaultRules
