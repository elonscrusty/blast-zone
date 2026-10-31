--!strict
-- Pure aim help for the phone stick (feel pass 2). A thumb is not a mouse, so when the aim points close
-- to a rival the aim leans toward them. Flat maths on x/z only. The client uses it to choose the
-- direction it asks to shoot; the server still decides every hit, so this gives no new power over the rules.

export type Config = {
	enabled: boolean,
	coneDegrees: number, -- a rival this close to the aim (either side) pulls it
	strength: number, -- 0 = no pull, 1 = snaps all the way onto the rival
	maxStuds: number?, -- only rivals this close can pull (nil = just the gun's range)
}

export type Target = { x: number, z: number }

local AimAssist = {}

-- `visible` (optional) says whether a rival can be seen from here; a rival it refuses never pulls.
-- Returns the new aim (a unit vector) and whether a rival pulled it. `dx`,`dz` need not be unit length.
function AimAssist.adjust(
	cfg: Config,
	ox: number,
	oz: number,
	dx: number,
	dz: number,
	targets: { Target },
	range: number,
	visible: ((Target) -> boolean)?
): (number, number, boolean)
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then
		return dx, dz, false
	end
	local ax, az = dx / len, dz / len
	if not cfg.enabled or cfg.strength <= 0 then
		return ax, az, false
	end
	local cone = math.rad(cfg.coneDegrees)
	local reach = math.min(range, cfg.maxStuds or range)
	local bestAngle: number? = nil
	for _, t in targets do
		local tx, tz = t.x - ox, t.z - oz
		local dist = math.sqrt(tx * tx + tz * tz)
		if dist >= 0.5 and dist <= reach then
			-- Signed angle from the aim to the rival (positive = counter-clockwise on the x/z plane).
			local angle = math.atan2(ax * tz - az * tx, ax * tx + az * tz)
			if
				math.abs(angle) <= cone
				and (bestAngle == nil or math.abs(angle) < math.abs(bestAngle))
				and (visible == nil or visible(t))
			then
				bestAngle = angle
			end
		end
	end
	if bestAngle == nil then
		return ax, az, false
	end
	local turn = bestAngle * math.min(cfg.strength, 1)
	local c, s = math.cos(turn), math.sin(turn)
	return ax * c - az * s, ax * s + az * c, true
end

return AimAssist
