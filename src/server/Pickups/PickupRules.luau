--!strict
-- Who may take an XP orb, with no game objects in it, so Lune can test it.
-- Times are os.clock seconds. `reservedFor` is a ParticipantId or nil.

local PickupRules = {}

export type Pickup = {
	id: string,
	matchId: number,
	expiresAt: number,
	reservedFor: string?,
	reservedUntil: number,
	claimed: boolean,
}

-- Returns true, or false and the reason. The rule is "first valid claim wins": the first claim that
-- passes these checks marks the orb claimed, so a second claim finds it taken.
function PickupRules.check(
	pickup: Pickup,
	claimantId: string,
	now: number,
	distance: number,
	radius: number,
	slack: number,
	currentMatchId: number
): (boolean, string?)
	if pickup.matchId ~= currentMatchId then
		return false, "stale-match"
	end
	if pickup.claimed then
		return false, "claimed"
	end
	if now >= pickup.expiresAt then
		return false, "expired"
	end
	if
		pickup.reservedFor ~= nil
		and pickup.reservedFor ~= claimantId
		and now < pickup.reservedUntil
	then
		return false, "reserved"
	end
	if distance ~= distance or distance > radius + slack then
		return false, "too-far"
	end
	return true, nil
end

return PickupRules
