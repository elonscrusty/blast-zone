--!strict
-- What the player is told when their saved data is not ready. Pure words, no Roblox calls.
-- Statuses come from piece 17 (Profiles.status): "loading" | "ready" | "failed" | "lost".
-- "none" means the game has no save system installed, so there is nothing to say.
--
-- Rules the words must keep true:
--   * failed: nothing is wiped. The player can play, but nothing earned now is saved.
--   * lost: the save is open on another server. Saving stopped; rejoin to keep progress.

export type Status = "none" | "loading" | "ready" | "failed" | "lost"

export type Notice = {
	kind: "wait" | "bad",
	headline: string,
	body: string,
	button: string?, -- label of the one button, if any
}

local DataNotice = {}

function DataNotice.isStatus(v: any): boolean
	return v == "loading" or v == "ready" or v == "failed" or v == "lost"
end

-- slow: loading has gone on longer than Config.Onboarding.slowLoadSeconds.
function DataNotice.forStatus(status: Status, slow: boolean): Notice?
	if status == "failed" then
		return {
			kind = "bad",
			headline = "SAVING IS OFF FOR NOW.",
			body = "Your saved stuff is safe. You can still play.",
			button = "TRY AGAIN",
		}
	elseif status == "lost" then
		return {
			kind = "bad",
			headline = "SAVING STOPPED.",
			body = "You joined from another place. Rejoin to save.",
			button = nil,
		}
	elseif status == "loading" and slow then
		return {
			kind = "wait",
			headline = "STILL LOADING YOUR SAVE...",
			body = "You can wait or play now.",
			button = nil,
		}
	end
	return nil
end

return DataNotice
