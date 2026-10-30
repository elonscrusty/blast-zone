--!strict
-- THE ONE PLACE for sound ids. Empty on purpose: no id has been picked yet, and none are made up.
-- A cue with no id here stays silent (nothing breaks). To turn one on, add a line like
--     fire_pistol = 1234567890,
-- with the number from the sound's page. All cue names are in AudioCatalog.luau and plans/AUDIO-IDS.md.
-- A name that is not a cue, or a number that is not a whole number above 0, is reported when the game starts.

local ids: { [string]: number } = {
	-- fire_pistol = 0,
}

return ids
