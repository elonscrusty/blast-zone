--!strict
-- Which music track goes with which match phase. nil = fade to quiet (the win/lose sting plays alone).
-- Pure, so it is tested.

local MusicPlan = {}

MusicPlan.fadeOut = 1.0 -- seconds
MusicPlan.fadeIn = 1.5

local BY_PHASE: { [string]: string? } = {
	Waiting = "music_lobby",
	Countdown = "music_lobby",
	Spawning = "music_match",
	Active = "music_match",
	FinalPressure = "music_final",
	Results = "music_lobby",
	Resetting = "music_lobby",
}

function MusicPlan.forPhase(phase: any): string?
	if type(phase) ~= "string" then
		return nil
	end
	return BY_PHASE[phase]
end

-- Phases where leftover effects must be dropped (new match is coming).
function MusicPlan.isReset(phase: any): boolean
	return phase == "Resetting" or phase == "Waiting"
end

return MusicPlan
