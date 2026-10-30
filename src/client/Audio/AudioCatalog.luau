--!strict
-- Every sound the game can make, with its rules. Ids live in AudioIds.luau. No Roblox services here,
-- so the tests can run it.
--   group     which volume slider owns it (the SoundGroups made by Settings)
--   volume    base loudness 0..1 before the slider
--   maxVoices at most this many of this cue at once; minGap seconds between two starts of it
--   priority  1 = the player's own, never starved; 2 = near world sounds; 3 = far ambience, first to drop
--   distance  { ref, max }: full volume inside ref studs, silent past max. nil = same loudness anywhere
--   seconds   longest it can play; the voice is released then even if the sound never ends
--   idFrom    use another cue's id (one file fills several cues)
--   brief     what to look for, shown in plans/AUDIO-IDS.md

local AudioCatalog = {}

export type Cue = {
	group: "Effects" | "Music",
	volume: number,
	maxVoices: number,
	minGap: number,
	priority: number,
	distance: { ref: number, max: number }?,
	pitchSpread: number?, -- +- fraction of playback speed, so repeats do not sound identical
	seconds: number,
	loop: boolean?,
	idFrom: string?,
	brief: string,
}

AudioCatalog.cues = {
	-- Weapons
	fire_pistol = {
		group = "Effects",
		volume = 0.7,
		maxVoices = 4,
		minGap = 0.05,
		priority = 1,
		pitchSpread = 0.05,
		seconds = 1.5,
		brief = "Your pistol shot: short sci-fi zap or laser pop, under 0.5 s",
	},
	fire_pistol_other = {
		group = "Effects",
		volume = 0.45,
		maxVoices = 3,
		minGap = 0.09,
		priority = 3,
		distance = { ref = 12, max = 85 },
		pitchSpread = 0.08,
		seconds = 1.5,
		idFrom = "fire_pistol",
		brief = "Someone else's shot (uses the pistol sound, quieter with distance)",
	},
	fire_mortar = {
		group = "Effects",
		volume = 0.8,
		maxVoices = 2,
		minGap = 0.2,
		priority = 1,
		distance = { ref = 20, max = 110 },
		seconds = 2,
		brief = "Mortar launch: low thump with a whistle, under 1 s",
	},
	explosion = {
		group = "Effects",
		volume = 0.9,
		maxVoices = 3,
		minGap = 0.15,
		priority = 2,
		distance = { ref = 18, max = 120 },
		pitchSpread = 0.06,
		seconds = 3,
		brief = "Mortar blast: punchy explosion boom, 1 to 2 s",
	},
	reload_start = {
		group = "Effects",
		volume = 0.6,
		maxVoices = 1,
		minGap = 0.3,
		priority = 1,
		seconds = 1.5,
		brief = "Reload begins: magazine slide out, click",
	},
	reload_end = {
		group = "Effects",
		volume = 0.65,
		maxVoices = 1,
		minGap = 0.3,
		priority = 1,
		seconds = 1.5,
		brief = "Reload done: magazine in, slide clack",
	},
	-- Feedback
	hit_confirm = {
		group = "Effects",
		volume = 0.55,
		maxVoices = 2,
		minGap = 0.06,
		priority = 1,
		pitchSpread = 0.04,
		seconds = 1,
		brief = "You hit someone: short tick or ping, under 0.2 s",
	},
	kill_confirm = {
		group = "Effects",
		volume = 0.8,
		maxVoices = 1,
		minGap = 0.2,
		priority = 1,
		seconds = 1.5,
		brief = "You knocked someone out: rising ping or crunchy ding",
	},
	damage_taken = {
		group = "Effects",
		volume = 0.7,
		maxVoices = 2,
		minGap = 0.12,
		priority = 1,
		pitchSpread = 0.05,
		seconds = 1.5,
		brief = "You got hurt: dull thud or buzz, under 0.4 s",
	},
	-- Moves and world
	slide = {
		group = "Effects",
		volume = 0.6,
		maxVoices = 2,
		minGap = 0.25,
		priority = 2,
		seconds = 1.5,
		brief = "Slide: quick whoosh or skid, about 0.4 s",
	},
	slide_other = {
		group = "Effects",
		volume = 0.4,
		maxVoices = 2,
		minGap = 0.3,
		priority = 3,
		distance = { ref = 10, max = 60 },
		seconds = 1.5,
		idFrom = "slide",
		brief = "Someone else's slide (uses the slide sound, quieter with distance)",
	},
	container_hit = {
		group = "Effects",
		volume = 0.55,
		maxVoices = 3,
		minGap = 0.08,
		priority = 2,
		distance = { ref = 10, max = 60 },
		pitchSpread = 0.1,
		seconds = 1,
		brief = "Box takes a hit: plastic crack or tap",
	},
	container_break = {
		group = "Effects",
		volume = 0.75,
		maxVoices = 3,
		minGap = 0.1,
		priority = 2,
		distance = { ref = 14, max = 80 },
		pitchSpread = 0.06,
		seconds = 2,
		brief = "Box bursts: crack and sparkly burst, under 1 s",
	},
	pickup = {
		group = "Effects",
		volume = 0.6,
		maxVoices = 3,
		minGap = 0.05,
		priority = 1,
		pitchSpread = 0.08,
		seconds = 1,
		brief = "You grab an XP orb: bright blip or coin-like chime, under 0.3 s",
	},
	-- Progress
	level_up = {
		group = "Effects",
		volume = 0.8,
		maxVoices = 1,
		minGap = 0.5,
		priority = 1,
		seconds = 3,
		brief = "Level up: short happy rising jingle, about 1 s",
	},
	upgrade_pick = {
		group = "Effects",
		volume = 0.7,
		maxVoices = 1,
		minGap = 0.3,
		priority = 1,
		seconds = 2,
		brief = "You choose an upgrade card: confident power-up click",
	},
	-- Match
	zone_warning = {
		group = "Effects",
		volume = 0.75,
		maxVoices = 1,
		minGap = 5,
		priority = 1,
		seconds = 4,
		brief = "Safe zone will shrink: low alarm pulse, 2 to 3 s",
	},
	sudden_death = {
		group = "Effects",
		volume = 0.85,
		maxVoices = 1,
		minGap = 10,
		priority = 1,
		seconds = 5,
		brief = "Sudden death: dramatic hit and siren sweep",
	},
	eliminated_self = {
		group = "Effects",
		volume = 0.8,
		maxVoices = 1,
		minGap = 1,
		priority = 1,
		seconds = 3,
		brief = "You are out: falling power-down",
	},
	eliminated_other = {
		group = "Effects",
		volume = 0.35,
		maxVoices = 2,
		minGap = 0.4,
		priority = 3,
		seconds = 2,
		brief = "Someone else is out: soft low thump",
	},
	victory = {
		group = "Effects",
		volume = 0.9,
		maxVoices = 1,
		minGap = 5,
		priority = 1,
		seconds = 8,
		brief = "You win: bright fanfare, 3 to 5 s",
	},
	defeat = {
		group = "Effects",
		volume = 0.8,
		maxVoices = 1,
		minGap = 5,
		priority = 1,
		seconds = 8,
		brief = "You lose: sad but short descending sting, 2 to 4 s",
	},
	-- Music (loops)
	music_lobby = {
		group = "Music",
		volume = 0.5,
		maxVoices = 1,
		minGap = 0,
		priority = 1,
		seconds = 600,
		loop = true,
		brief = "Lobby music: calm night-city neon synth, loops cleanly",
	},
	music_match = {
		group = "Music",
		volume = 0.55,
		maxVoices = 1,
		minGap = 0,
		priority = 1,
		seconds = 600,
		loop = true,
		brief = "Match music: driving neon synth beat, loops cleanly",
	},
	music_final = {
		group = "Music",
		volume = 0.6,
		maxVoices = 1,
		minGap = 0,
		priority = 1,
		seconds = 600,
		loop = true,
		brief = "Last minutes: tense and faster than the match music, loops cleanly",
	},
} :: { [string]: Cue }

-- Stable order for lists (tables have none).
function AudioCatalog.names(): { string }
	local out = {}
	for name in AudioCatalog.cues do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

function AudioCatalog.get(name: string): Cue?
	return AudioCatalog.cues[name]
end

local function isId(v: any): boolean
	return type(v) == "number" and v > 0 and v == math.floor(v) and v < 2 ^ 53
end

-- The number to play for a cue, or nil (silent). Follows idFrom once.
function AudioCatalog.assetId(name: string, ids: { [string]: number }): number?
	local cue = AudioCatalog.cues[name]
	if cue == nil then
		return nil
	end
	local own = ids[name]
	if own ~= nil and isId(own) then
		return own
	end
	if cue.idFrom ~= nil then
		local other = ids[cue.idFrom]
		if other ~= nil and isId(other) then
			return other
		end
	end
	return nil
end

-- Mistakes in the ids table: a name that is no cue, or a bad number. Empty list = fine.
function AudioCatalog.problems(ids: { [string]: any }): { string }
	local out = {}
	for name, value in ids do
		if AudioCatalog.cues[name] == nil then
			table.insert(out, `'{name}' is not a sound name`)
		elseif not isId(value) then
			table.insert(out, `'{name}' needs a whole number above 0`)
		end
	end
	table.sort(out)
	return out
end

return AudioCatalog
