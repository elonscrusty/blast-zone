--!strict
-- Every number the Burp Director uses. Times are seconds, distances are studs.
-- BurpDirector.new(rng, overrides) lets tests (or live tuning) replace any of these.

export type KindWeights = { pops: number, ashStorm: number, golden: number, geysers: number }

export type Tuning = {
	-- pacing (a "gap" is measured rumble start to next rumble start)
	gapMax: number, -- island dirty (clean = 0)
	gapMin: number, -- island spotless (clean = 1)
	gapJitter: number, -- +- fraction randomly applied to the gap
	minCalm: number, -- calm time between recover end and next rumble, whatever the gap says
	firstBurpDelay: number, -- first rumble no earlier than this after the first player shows up
	firstBurpJitter: number, -- plus 0..this

	-- phases
	rumble: number,
	recover: number,
	kindWeights: KindWeights,
	repeatPenalty: number, -- weight multiplier for the kind that just happened

	-- lava pops
	popsDuration: number,
	bombEvery: number, -- seconds between bomb waves
	bombEveryJitter: number,
	telegraph: number, -- seconds from circle appearing to landing
	minTelegraph: number, -- never shown for less than this, even if the server stepped late
	bombRadius: number,
	bodyRadius: number, -- extra reach in hitTest so near misses on the edge still count as a hit
	bombsPerWaveBase: number,
	playersPerExtraBomb: number,
	bombsPerWaveMax: number,
	maxActiveBombs: number,
	aimOffsetMax: number, -- bombs land within this many studs of the player they chase
	decoyFraction: number, -- share of bombs aimed at a random spot in a player-occupied zone
	hubSafeMargin: number, -- bombs never land closer than clearRadius + this to the hub
	perfectGrace: number, -- seconds after the last bomb lands before "nobody hit" is decided

	-- ash storm
	stormDuration: number,
	stormPulseEvery: number,
	stormFraction: number, -- share of cells that get +1..2 units per pulse

	-- golden burp
	goldenDuration: number,
	goldenBaseCells: number,
	goldenPerPlayer: number,
	goldenMaxCells: number,

	-- gem geysers
	geyserDuration: number,
	geyserWaveEvery: number,
	geyserSpotsBase: number,
	geyserPlayersPerExtraSpot: number,
	geyserSpotsMax: number,
	geyserGemsPerSpot: number, -- pickups per vent (server decides coin value)

	-- perfect dodge
	perfectBuffSeconds: number,
	perfectKinds: { [string]: boolean }, -- only these events can award the buff
}

local BurpTuning: Tuning = {
	gapMax = 140,
	gapMin = 80,
	gapJitter = 0.1,
	minCalm = 20,
	firstBurpDelay = 75,
	firstBurpJitter = 25,

	rumble = 6,
	recover = 8,
	kindWeights = { pops = 40, ashStorm = 25, golden = 20, geysers = 15 },
	repeatPenalty = 0.25,

	popsDuration = 12,
	bombEvery = 1.2,
	bombEveryJitter = 0.25,
	telegraph = 2,
	minTelegraph = 1.5,
	bombRadius = 7,
	bodyRadius = 0.5, -- the client draws the ring at bombRadius: a hit is what the eye sees
	bombsPerWaveBase = 1,
	playersPerExtraBomb = 4,
	bombsPerWaveMax = 4,
	maxActiveBombs = 12,
	aimOffsetMax = 4,
	decoyFraction = 0.25,
	hubSafeMargin = 4,
	perfectGrace = 0.75,

	stormDuration = 25,
	stormPulseEvery = 5,
	stormFraction = 0.3,

	goldenDuration = 45,
	goldenBaseCells = 10, -- 10 + 5 per player: every player gets about 5 gold cells in their
	goldenPerPlayer = 5, -- own best zone (BurpService shares them out), so gold scales with
	goldenMaxCells = 90, -- friends AND with progress

	geyserDuration = 20,
	geyserWaveEvery = 10,
	geyserSpotsBase = 3,
	geyserPlayersPerExtraSpot = 2,
	geyserSpotsMax = 10,
	geyserGemsPerSpot = 3,

	perfectBuffSeconds = 120,
	perfectKinds = { pops = true },
}

return BurpTuning
