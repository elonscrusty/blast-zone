--!strict
-- The words and numbers for the coin strip and track panel, as plain data (no Roblox) so Lune can test them.

-- Takes plain tables (the state from the server, track items from TrackDefs) so it needs no requires.

local ProgressText = {}

export type State = {
	status: string,
	coins: number,
	unlocked: { string },
	equipped: { [string]: string },
	gained: { matchId: number, amount: number }?,
}

export type Item = { id: string, slot: string, name: string, cost: number }

export type Strip = {
	amount: string, -- "+48 Volts" right after a match, else the total
	fill: number, -- 0..1 progress to the next tier
	hint: string,
	action: "unlock" | "track", -- what the right-hand button does
	note: string?, -- shown small when the numbers cannot be trusted (not loaded, not saved)
}

function ProgressText.noteFor(status: string): string?
	if status == "failed" or status == "lost" then
		return "Progress not loaded. No coins were paid."
	elseif status == "loading" or status == "none" then
		return "Loading your coins..."
	elseif status == "temporary" then
		return "Test mode: coins are not saved."
	end
	return nil
end

function ProgressText.strip(state: State, coinName: string, next: Item?): Strip
	local amount = if state.gained
		then `+{state.gained.amount} {coinName}`
		else `{state.coins} {coinName}`
	local note = ProgressText.noteFor(state.status)
	if next == nil then
		return {
			amount = amount,
			fill = 1,
			hint = "All rewards unlocked!",
			action = "track",
			note = note,
		}
	end
	if state.coins >= next.cost then
		return {
			amount = amount,
			fill = 1,
			hint = `{next.name} is ready!`,
			action = "unlock",
			note = note,
		}
	end
	return {
		amount = amount,
		fill = math.clamp(state.coins / next.cost, 0, 1),
		hint = `{next.cost - state.coins} more for {next.name}`,
		action = "track",
		note = note,
	}
end

function ProgressText.denied(reason: string?, coinName: string): string?
	if reason == nil then
		return nil
	elseif reason == "tooPoor" then
		return `Not enough {coinName} yet`
	elseif reason == "notNext" then
		return "Unlock them in order"
	elseif reason == "notOwned" then
		return "Unlock it first"
	elseif reason == "notLoaded" then
		return "Progress not loaded"
	elseif reason == "trackDone" then
		return "All rewards unlocked!"
	end
	return "Could not do that. Try again."
end

-- One line on a track card: how this item stands right now.
function ProgressText.cardStatus(def: Item, state: State, coinName: string): string
	local itemId = def.id
	if state.equipped[def.slot] == itemId then
		return "WORN"
	end
	if def.cost == 0 then
		return "OWNED"
	end
	for _, id in state.unlocked do
		if id == itemId then
			return "OWNED"
		end
	end
	return `{def.cost} {coinName}`
end

return ProgressText
