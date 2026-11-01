--!strict
-- Seed config: only the numbers that EVERY piece must agree on. Per-system tuning lives next to
-- its system (Catalog/*, Burp/BurpTuning, ...). The `rules` piece owns this file after seeding.

local Config = {}

Config.Game = {
	Name = "Volcano Sweepers", -- placeholder title, carter may rename
	MaxPlayers = 16,
	SaveVersion = 1,
}

Config.Net = {
	clientWaitSeconds = 20,
}

-- Island geometry. Everything is centred on world (0, 0). Y = 0 is the ground top.
-- Zone ids are 1..5 from the outside in. `outer`/`inner` are radii in studs (ring between them).
-- The volcano cone itself sits inside zone 5's inner radius and is decor only.
Config.World = {
	cellSize = 8, -- studs; one ash cell is cellSize x cellSize
	maxUnitsPerCell = 9,
	groundY = 0,
	seed = 20261101, -- fixed so every server builds the same island decor and cell layout
	zones = {
		{ id = 1, name = "Sunny Beach", outer = 250, inner = 190 },
		{ id = 2, name = "Fern Forest", outer = 190, inner = 140 },
		{ id = 3, name = "Hot Springs", outer = 140, inner = 98 },
		{ id = 4, name = "Crater Rim", outer = 98, inner = 62 },
		{ id = 5, name = "Lava Heart", outer = 62, inner = 30 },
	},
	-- Hub (spawn + Trade Hut) sits on the beach ring at this angle (degrees) and radius.
	hub = { angleDeg = 90, radius = 222, clearRadius = 22 },
	sellRange = 16, -- studs from a sell pad centre where SELL works
}

-- Sounds are OFF until real ids are pasted in. Never invent ids (see plans/AUDIO-IDS.md).
-- Key = sound name used by Sfx.play(name). Value = "rbxassetid://<number>" or nil.
Config.Audio = {
	ids = {} :: { [string]: string },
	musicId = nil :: string?,
}

return Config
