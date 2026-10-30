--!strict
-- What this player is carrying (piece 42). Written only by LootClientSystem from the server's
-- LootState; read by the touch button (and any HUD Claude Design draws). Never decides anything.

export type State = { healPacks: number, max: number, readyAt: number }

local LootClient = {}

local state: State = { healPacks = 0, max = 3, readyAt = 0 }

function LootClient.get(): State
	return state
end

function LootClient.set(healPacks: number, max: number, readyAt: number)
	state = { healPacks = healPacks, max = max, readyAt = readyAt }
end

-- Is the bag full? (Then walking over a pack does nothing, so the client does not even ask.)
function LootClient.isFull(): boolean
	return state.healPacks >= state.max
end

return LootClient
