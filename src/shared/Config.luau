--!strict
-- Every tuning number lives here. Nothing else in the game may hard-code a value from this file.
-- Pure data (no Roblox calls) so Lune can test it. Positions are plain x/z numbers, not Vector3.
-- Label rule from the brief: everything below is PROPOSED tuning, not measured from the reference.

local FIRE_RATE = 5 -- shots per second
local EXPLOSIVE_INTERVAL = 1.6 -- seconds between mortar shots

local Config = {}

-- The game name lives ONLY here (and in the Roblox place itself). Rename it with one edit.
Config.Game = {
	Name = "Circuit District", -- placeholder, not a checked-available name
	Version = "0.1.0",
}

-- Hex strings; UI code turns them into Color3 with Color3.fromHex.
Config.Palette = {
	Navy = "#14243A",
	Cyan = "#36D9E8",
	Pavement = "#C8A675",
	ParkGreen = "#718D57",
	RewardGold = "#FFC44D",
	DangerCoral = "#F15B64",
}

-- Feature gates. A piece that lands before its partners flips its own flag on.
Config.Features = {
	explosiveWeapon = true, -- piece 03: the Arc Mortar works (slot 2)
	healPickup = false, -- piece 07, optional
	bots = true, -- piece 09
	roofFade = true, -- piece 04
	spectate = true, -- piece 05
	devQuickStart = true, -- piece 05: simple way to start a small match; labeled as dev
}

-- Match lifecycle (piece 05). Times in seconds.
Config.Match = {
	targetParticipants = 6,
	maxParticipants = 8,
	minToStart = 2,
	fillWaitSeconds = 12, -- grace after minToStart is met, so friends can join
	countdownSeconds = 5,
	spawnPresentationSeconds = 2.5,
	finishedHoldSeconds = 3,
	resultsSeconds = 20,
	resettingSeconds = 2,
	targetMatchSeconds = 180,
	-- Two final eliminations closer together than this are a draw (both rank 1).
	simultaneousEliminationWindow = 0.1,
	-- Piece 05 extras
	settleSeconds = 0.3, -- after the last rival falls, a shot already in flight can still land
	resultsMinSeconds = 1, -- Results phase lasts at least this long, even if everyone taps Play again at once
	finalPressureAliveCount = 2, -- Final pressure starts when this few are left...
	finalPressureAtSeconds = 150, -- ...or this long after Active begins (the zone's last warning does it too)
	maxActiveSeconds = 210, -- safety net: a match still going then ends as a draw
}

-- Written-down answers to the brief's "define a policy" questions. Code reads these names.
Config.Policies = {
	joinDuringActiveMatch = "spectate-until-next-match",
	disconnect = "eliminated-no-killer-credit",
	disconnectedAttacker = "kills-already-credited-stay; projectiles-in-flight-are-removed",
	environmentalDamage = "no-killer-credit",
	simultaneousFinalElimination = "draw-both-rank-1",
	eliminatedPlayers = "cannot-fire-collect-or-pick-upgrades",
	xpOwnership = "exclusive-first-valid-claim",
	friendlyFire = true, -- free-for-all
}

Config.Health = {
	max = 100,
	regenPerSecond = 0,
}

-- Piece 02. Camera-relative, ground-plane, no jumping.
Config.Movement = {
	walkSpeed = 20, -- studs per second
	jumpEnabled = false,
	maxSpeedUpgradeMultiplier = 1.4, -- hard cap so stacks cannot break the camera
	maxSlopeAngle = 55, -- steeper than this is a wall, not a ramp: no accidental climbing
}

Config.Camera = {
	pitchDegrees = 55,
	distance = 46,
	fieldOfView = 55,
	yawDegrees = 0, -- stable heading (0 = looking toward -Z)
	followSmoothingSeconds = 0.06, -- small on purpose: avoid "disconnected" feel
	aimLookAheadStuds = 0, -- optional framing from aim, off until it proves useful
	snapDistance = 30, -- farther than this (respawn, spectate swap) the view jumps instead of gliding
	narrowAspect = 1.6, -- screens narrower than this (phone held upright) see farther
	narrowAspectFloor = 0.5,
	maxWiden = 0.35, -- most extra distance (a fraction) for the narrowest screens
}

Config.Weapons = {
	startingLoadout = { "volt_pistol", "arc_mortar" }, -- slot 1, slot 2
	Firearm = {
		id = "volt_pistol",
		displayName = "Volt Pistol",
		damage = 10,
		fireRate = FIRE_RATE,
		fireInterval = 1 / FIRE_RATE,
		magazine = 12,
		reloadSeconds = 1.2,
		range = 70, -- hitscan stops here; no unseen long shots
		pellets = 1,
		spreadDegrees = 0,
		muzzleOffset = 2.5, -- studs in front of the body; server rejects shots whose muzzle is in a wall
		maxOriginDrift = 6, -- server accepts a client origin only this close to the character
		autoReload = true, -- trying to fire on an empty magazine starts a reload
		reloadCancelledBySwitch = true,
	},
	Explosive = {
		id = "arc_mortar",
		displayName = "Arc Mortar",
		damage = 45, -- at the center
		radius = 9,
		falloffMin = 0.4, -- share of damage at the edge of the radius
		fireInterval = EXPLOSIVE_INTERVAL,
		magazine = 3,
		reloadSeconds = 2.4,
		projectileSpeed = 55,
		range = 60,
		warnSeconds = 0.5, -- landing marker shows before the blast
		selfDamageScale = 0.5,
	},
}

-- Piece 03 only. Everything about how shots and health behave that is not a weapon stat.
Config.Combat = {
	bodyRadius = 1.8, -- a body is a circle this wide on the ground; shots and blasts test against it
	shotHeight = 0.5, -- studs above the root part that shots fly (cover shorter than this is jumped over by nothing: only BlocksShots blocks)
	fireTolerance = 0.04, -- a shot may arrive this many seconds early (network jitter): one early shot, never a faster average
	switchSeconds = 0.25, -- after switching weapons you cannot fire for this long
	maxPassThrough = 10, -- how many non-blocking parts one shot may fly through before it is cut off
	shellContactPadding = 0.2, -- extra studs around a body for a shell to count as touching it
	shellStepSeconds = 1 / 30, -- longest slice a shell is moved in at once
	maxShells = 12, -- in flight at once, whole server
	hitMarkerSeconds = 0.18,
	incomingHitSeconds = 0.7,
	healthBarSeconds = 3, -- an enemy health bar stays visible this long after it changes
}

-- What blocks what. Arena (04) tags geometry; Combat (03) reads these. Tag names are in Tags.
Config.ShotRules = {
	wallsBlockShots = true, -- parts tagged BlocksShots
	lowCoverBlocksShots = false, -- parts tagged LowCover: block movement, bullets pass over
	fencesBlockShots = false, -- thin fences: block movement only
	participantsBlockShots = true, -- first participant in line takes the hit
	containersBlockShots = true,
	explosionsDamageOwner = true, -- scaled by Explosive.selfDamageScale
	explosionsPassThroughWalls = false, -- splash needs a clear line from the blast center
	roofsAreVisualOnly = true, -- roofs are CanQuery=false and CanCollide=false
}

Config.Slide = {
	distance = 14,
	duration = 0.25,
	cooldown = 5,
	invulnerable = false,
	stationaryFallback = "facing", -- no movement input: slide the way the character faces
	stopsWhenBlocked = true,
	minCooldown = 1.5, -- upgrades can never shave the cooldown below this
	minDistance = 2, -- a wall closer than this: no slide, and no cooldown is spent
	skin = 0.15, -- gap left between the player and the wall
	groundStep = 3.5, -- how often along the path the server checks there is still floor
	maxDrop = 3, -- floor farther below the feet than this counts as a hole
	clearance = 1, -- low curbs under this height do not stop the slide
	bodyWidth = 2.4,
	endGrace = 0.35, -- server checks where the player ended up this long after the slide
	endTolerance = 4,
	trailFadeSeconds = 0.3,
}

Config.Arena = {
	size = 220, -- studs, square, centered on centerX/centerZ
	centerX = 0,
	centerZ = 0,
	minSpawns = 8,
	spawnMinSeparation = 40,
	spawnClearRadius = 4,
	containerSpots = 12,
	parkEntrancesMin = 2,
	-- Piece 04. Which graybox layout is built (A, B or C, see src/server/Arena/Layout*.luau).
	layout = "C", -- carter picked C (Arcade Row); A and B stay as extra maps
	occluderTag = "ArenaOccluder", -- parts the camera may fade for the local player only
	-- Local roof / wall fade (piece 04). Transparency targets, 0 = solid, 1 = gone.
	fade = {
		insideRoof = 1,
		insideWall = 0.8,
		outsideBlocker = 0.65,
		playerPad = 3, -- studs: fade what is near the line of sight, not only exactly on it
		headHeight = 3,
		smoothing = 12, -- bigger is quicker
	},
}

-- CollectionService tags and Workspace folder names that the pieces agree on.
Config.Tags = {
	BlocksShots = "BlocksShots",
	LowCover = "LowCover",
	Roof = "Roof",
	Interior = "Interior",
	Spawn = "ArenaSpawn",
	ContainerSpot = "ContainerSpot",
	SupplyContainer = "SupplyContainer",
	FinalZoneRegion = "FinalZoneRegion",
}

Config.Workspace = {
	ArenaFolder = "Arena",
	ContainersFolder = "Containers",
	PickupsFolder = "Pickups",
	EffectsFolder = "Effects",
}

-- Attributes set on a participant's character model by the server.
Config.Attributes = {
	ParticipantId = "ParticipantId",
	IsBot = "IsBot",
}

Config.CollisionGroups = {
	Participants = "Participants", -- do not collide with each other
	Projectiles = "Projectiles",
}

-- Piece 07. Supply containers come in three loot tiers. The color tells the tier from far away:
-- blue = common, violet = rare, magenta = epic. A ContainerSpot marker can force a tier with its own
-- "Tier" attribute; otherwise the tier is rolled by weight (50 / 35 / 15 percent).
-- Health is in hits of the 10-damage starter gun. Each orb is worth Config.Xp.rewards.orbPickup.
local COMMON_HEALTH = 40
local COMMON_ORBS = 2

Config.Containers = {
	health = COMMON_HEALTH, -- the common tier
	orbsPerContainer = COMMON_ORBS, -- the common tier
	size = 4, -- studs, a cube standing on the marker's bottom face
	tierOrder = { "common", "rare", "epic" },
	tiers = {
		common = { color = "#3FA9F5", health = COMMON_HEALTH, orbs = COMMON_ORBS, weight = 50 },
		rare = { color = "#6B46D6", health = 60, orbs = 3, weight = 35 },
		epic = { color = "#E64FC4", health = 90, orbs = 5, weight = 15 },
	} :: { [string]: { color: string, health: number, orbs: number, weight: number } },
	bandColor = "#FFC44D", -- the glowing belt on every tier
	flashColor = "#FFFFFF", -- what a hit flashes to
}

Config.Pickups = {
	lifetimeSeconds = 25,
	collectRadius = 5, -- server check
	magnetRadius = 9, -- cosmetic pull on the client; never decides ownership
	healAmount = 25, -- when Features.healPickup is on
	maxActive = 60,
	reserveSeconds = 1.5, -- the player who broke the container gets first claim on its orbs for this long
	claimSlack = 1.5, -- extra studs the server forgives for lag when it checks a claim
	scatterRadius = 3.5, -- orbs land on a ring this wide around the container
	orbHeight = 1.5, -- orb center above the floor
	orbSize = 1.4,
	expireCheckSeconds = 0.5,
}

Config.Xp = {
	rewards = {
		containerBreak = 5, -- to whoever lands the breaking hit
		orbPickup = 5,
		elimination = 30,
	},
	levelCosts = { 20, 35, 55 }, -- XP to leave level 1, 2, 3
	costStepAfter = 25, -- each later level costs this much more than the one before
	maxOffersPerMatch = 6,
}

Config.Upgrades = {
	offerSize = 3,
	queueMax = 3, -- extra offers wait in line behind a pending one
	selectionLockSeconds = 0.35, -- blocks accidental double taps
	invulnerableWhileOffered = false,
	desktopKeys = { "One", "Two", "Three" },
}

-- Safe area (piece 06). All times are seconds after Active begins.
-- Each stage: warn, then close to targetRadius over closeSeconds, then hold.
Config.Zone = {
	centerX = 0,
	centerZ = 0,
	centerMode = "fixed",
	initialRadius = 156, -- the whole 220 square, corners included
	tickSeconds = 0.5,
	edgeTolerance = 0.5, -- exactly on the edge counts as inside
	stages = {
		{ warnAt = 35, closeAt = 45, closeSeconds = 20, targetRadius = 105, damagePerSecond = 2 },
		{ warnAt = 75, closeAt = 85, closeSeconds = 20, targetRadius = 68, damagePerSecond = 4 },
		{ warnAt = 115, closeAt = 125, closeSeconds = 15, targetRadius = 38, damagePerSecond = 7 },
		{ warnAt = 150, closeAt = 158, closeSeconds = 12, targetRadius = 14, damagePerSecond = 12 },
	},
	-- Sudden death is a rule, not a banner: the circle keeps closing and hurts much more.
	suddenDeath = { startsAt = 170, closeSeconds = 15, targetRadius = 4, damagePerSecond = 25 },
}

Config.Bots = {
	labelPrefix = "[BOT] ",
	names = { "Volt", "Static", "Ohm", "Relay", "Diode", "Fuse", "Coil", "Spark" },
	devDefaultCount = 3,
	fillToMinimum = true,
	sightRange = 60,
	reactionSeconds = 0.35,
	aimErrorDegrees = 6,
	maxPathfindsPerSecond = 4,
	hiddenStatAdvantage = false, -- must stay false: bots use player rules
}

Config.Rewards = {
	currencyName = "Scrap", -- must match CoinLooks[Config.Progression.look].name (a test checks it)
	participation = 10,
	perElimination = 5,
	placementBonus = { 30, 15, 8 }, -- 1st, 2nd, 3rd
	persist = true, -- piece 18 saves the coins through the profile (piece 17)
}

-- Piece 18: coins and the unlock track. Looks only, no combat power.
Config.Progression = {
	look = "B", -- coin look: "A" Volts, "B" Scrap, "C" Tokens (CoinLooks). carter chose Scrap.
	maxMatchGrant = 200, -- sanity cap for one match's coins; real rewards are far smaller
	-- Player attributes the server sets so every client can draw a player's chosen look.
	attributes = { trail = "CosmeticTrail", tracer = "CosmeticTracer" },
}

-- Piece 25: daily challenges. Three a day (one easy, one medium, one hard), the same for everyone, new at
-- midnight UTC. They pay in the game's coin (Config.Rewards.currencyName). The list is in shared/Daily/DailyDefs.
Config.Daily = {
	resetHourUtc = 0, -- the new day starts at this hour (UTC)
	rewards = { easy = 20, medium = 35, hard = 50 },
	look = "A", -- challenge board look: "A" Sticker Stack, "B" Ticket Row, "C" Big Board (DailyLooks)
}

Config.Settings = {
	defaults = {
		musicVolume = 0.6,
		effectsVolume = 0.8,
		cameraShake = 1.0, -- 0 disables
		aimSensitivity = 1.0,
	},
	minTouchTarget = 48, -- points
}

Config.Perf = {
	maxDamageNumbers = 12,
	maxLiveEffects = 40,
	maxDebrisParts = 0, -- containers burst as particles, not physical parts
}

Config.Net = {
	clientWaitSeconds = 10,
}

return Config
