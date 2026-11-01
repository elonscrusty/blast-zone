--!strict
-- Seed config: only the numbers that EVERY piece must agree on. Per-system tuning lives next to
-- its system (Catalog/*, Burp/BurpTuning, ...). The `rules` piece owns this file after seeding.

local Config = {}

Config.Game = {
	Name = "Volcano Sweepers", -- placeholder title, carter may rename
	MaxPlayers = 24, -- keep default.project.json Players.MaxPlayers the same
	SaveVersion = 1,
}

Config.Net = {
	clientWaitSeconds = 20,
}

-- Island geometry. Everything is centred on world (0, 0). Y = 0 is the ground top.
-- Zone ids are 1..5 from the outside in. `outer`/`inner` are radii in studs (ring between them).
-- The volcano cone itself sits inside zone 5's inner radius and is decor only.
-- Size: the island is 1000 studs across (about 12,000 ash cells, 4x the first build) so a full
-- server of 24 has room. Everything else (ground, gates, volcano, decor, vents, bombs, regrow,
-- storms, gold) is derived from these numbers; tests/world_plan and tests/pacing keep it honest.
Config.World = {
	cellSize = 8, -- studs; one ash cell is cellSize x cellSize
	maxUnitsPerCell = 9,
	groundY = 0,
	seed = 20261101, -- fixed so every server builds the same island decor and cell layout
	zones = {
		{ id = 1, name = "Sunny Beach", outer = 500, inner = 380 },
		{ id = 2, name = "Fern Forest", outer = 380, inner = 280 },
		{ id = 3, name = "Hot Springs", outer = 280, inner = 196 },
		{ id = 4, name = "Crater Rim", outer = 196, inner = 124 },
		{ id = 5, name = "Lava Heart", outer = 124, inner = 60 },
	},
	-- Hub (spawn + Trade Hut) sits on the beach ring at this angle (degrees) and radius.
	hub = { angleDeg = 90, radius = 444, clearRadius = 22 },
	-- One small Trade Post (a sell stall) just inside the outer edge of each zone 2..5, beside that
	-- zone's gate: `inset` studs in from the boundary, `side` studs sideways from the gate line.
	-- The ash layout keeps a `clearRadius` circle around each one empty (like the hub).
	tradePost = { inset = 15, side = 24, clearRadius = 10 },
	sellRange = 16, -- studs from a sell pad centre where SELL works
}

-- Player base numbers. Tools, upgrades and perks are applied on top (see Rules/StatsCalc).
Config.Player = {
	baseWalkSpeed = 16, -- studs per second (Roblox default)
	baseCapacity = 30, -- backpack units before tool bonus and upgrades
	minInterval = 0.1, -- fastest allowed swing, seconds (server clamps)
	maxArmor = 0.8, -- armor never goes above this share of carried ash saved
	-- idealised walk to the nearest sell pad (Trade Hut or a zone's Trade Post) and back, used by
	-- ProgressRules.pace; tests/island_sim measures the real walks on the layout instead
	tripSeconds = 12,
}

-- Economy rules shared by server, client and the balance sim (Rules/*, Catalog/*).
Config.Economy = {
	partyMult = 2.0, -- Island Party buff
	perfectMult = 1.25, -- Perfect Dodge buff (+25% for 2 minutes: worth the dodging)
	sparkBonusEach = 0.05, -- each Spark adds +5% coins (additive) ...
	sparkBonusCap = 9, -- ... but the Spark part can never pass +900% (x10 total with the base 1)
	maxHelpers = 6,
	maxHelperLevel = 15,
	-- Cool Down (prestige) is offered once this run has earned this many coins.
	coolDownMinRunCoins = 7000000,
	-- sparks = floor(sparkScale * sqrt(runCoins / coolDownMinRunCoins)): sublinear on purpose.
	sparkScale = 10,
	maxLevelCap = 50, -- a saved upgrade level above this is treated as a bug
}

-- Sounds are OFF until real ids are pasted in. Never invent ids (see plans/AUDIO-IDS.md).
-- Key = sound name used by Sfx.play(name). Value = "rbxassetid://<number>" or nil.
Config.Audio = {
	ids = {} :: { [string]: string },
	musicId = nil :: string?,
}

return Config
