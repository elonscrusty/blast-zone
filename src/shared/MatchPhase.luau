--!strict
-- The match lifecycle names and the legal moves between them. Piece 05 runs it; everyone reads it.

local MatchPhase = {}

MatchPhase.Waiting = "Waiting"
MatchPhase.Countdown = "Countdown"
MatchPhase.Spawning = "Spawning"
MatchPhase.Active = "Active"
MatchPhase.FinalPressure = "FinalPressure"
MatchPhase.Finished = "Finished"
MatchPhase.Results = "Results"
MatchPhase.Resetting = "Resetting"

MatchPhase.ORDER = {
	"Waiting",
	"Countdown",
	"Spawning",
	"Active",
	"FinalPressure",
	"Finished",
	"Results",
	"Resetting",
}

-- Legal moves. Any phase may jump to Resetting (abort: everyone left, error, shutdown).
local NEXT: { [string]: { [string]: boolean } } = {
	Waiting = { Countdown = true },
	Countdown = { Waiting = true, Spawning = true }, -- too few players: back to Waiting
	Spawning = { Active = true },
	Active = { FinalPressure = true, Finished = true },
	FinalPressure = { Finished = true },
	Finished = { Results = true },
	Results = { Resetting = true },
	Resetting = { Waiting = true },
}

function MatchPhase.isValid(phase: string): boolean
	return NEXT[phase] ~= nil
end

function MatchPhase.canTransition(from: string, to: string): boolean
	if NEXT[from] == nil or NEXT[to] == nil then
		return false
	end
	if to == "Resetting" and from ~= "Resetting" then
		return true
	end
	return NEXT[from][to] == true
end

-- Fighting is live: shots, slides, pickups, zone damage and upgrade picks are allowed.
function MatchPhase.isCombat(phase: string): boolean
	return phase == "Active" or phase == "FinalPressure"
end

-- Damage may only land in a combat phase. Late hits in Finished and later are dropped.
function MatchPhase.allowsDamage(phase: string): boolean
	return MatchPhase.isCombat(phase)
end

-- Participants exist (and can be placed) from Spawning on, until Resetting clears them.
function MatchPhase.hasParticipants(phase: string): boolean
	return phase ~= "Waiting" and phase ~= "Resetting"
end

return MatchPhase
