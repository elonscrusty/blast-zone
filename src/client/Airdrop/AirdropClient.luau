--!strict
-- What airdrops are running right now, for the hint strip (AirdropHintSystem). Written only by
-- AirdropClientSystem from the server's AirdropState; never decides anything.

export type Drop = { pos: Vector3, landsAt: number, opensAt: number, opened: boolean }

local AirdropClient = {}

local drops: { Drop } = {}

function AirdropClient.set(list: { Drop })
	drops = list
end

-- The shut (not yet opened) drop that opens soonest, or nil.
function AirdropClient.nextToOpen(): Drop?
	local best: Drop? = nil
	for _, d in drops do
		if not d.opened and (best == nil or d.opensAt < best.opensAt) then
			best = d
		end
	end
	return best
end

return AirdropClient
