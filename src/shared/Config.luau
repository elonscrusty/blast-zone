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
	cityArt = true, -- piece 14: Neon Night art pass on the arena (visual only; off = plain graybox)
	dayNight = true, -- piece 14: lighting slides from day to night during a match (client only)
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

-- Piece 33. Players vote on the next map in the lobby between matches. The server counts.
Config.MapVote = {
	-- The vote is open from the results screen until the match countdown ends. A vote after that is dropped.
	maxMapIdLength = 24,
	stateRepeatSeconds = 1, -- the server sends the running count at most this often
	-- Display names for map ids (a map missing here shows its id). The arena piece owns the maps themselves.
	names = {
		A = "Crossroads Park",
		B = "Offset Avenues",
		C = "Arcade Row",
		D = "Neon Plaza",
		E = "Market Hall",
		F = "Canal Docks",
	} :: { [string]: string },
}

-- Piece 39: idle (AFK) check. Server only. A fighter is "active" when they move, shoot, reload, slide,
-- switch guns, grab a pickup or choose an upgrade. Standing still and doing nothing is idle.
Config.Idle = {
	warnSeconds = 25, -- in a fight: a warning after this long doing nothing
	kickSeconds = 40, -- in a fight: removed from the match (no reward) after this long
	lobbyQueuedSeconds = 90, -- queued in the lobby with no input at all: taken off the queue
	lobbyWarnSeconds = 60,
	moveStuds = 3, -- walking farther than this from the last counted spot counts as moving
	sweepSeconds = 1, -- how often the server looks
	shutdownGraceSeconds = 3, -- BindToClose: time for last rewards to reach the saves (allowed 30 total)
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
	yawDegrees = 0, -- starting heading (0 = looking toward -Z); the player can turn it (see below)
	-- Turning the view. The heading is only a client look; the server never uses it.
	lookDegreesPerPixel = 0.3, -- mouse (right-button drag) and touch (drag on the free right side)
	padTurnDegreesPerSecond = 150, -- gamepad: hold L2 and push the right stick sideways
	maxTurnPerFrame = 40, -- one hitch or a huge swipe can never whip the view around
	followSmoothingSeconds = 0.06, -- small on purpose: avoid "disconnected" feel
	aimLookAheadStuds = 0, -- optional framing from aim, off until it proves useful
	snapDistance = 30, -- farther than this (respawn, spectate swap) the view jumps instead of gliding
	narrowAspect = 1.6, -- screens narrower than this (phone held upright) see farther
	narrowAspectFloor = 0.5,
	maxWiden = 0.35, -- most extra distance (a fraction) for the narrowest screens
}

-- Camera while watching someone after you are out. `style` picks one entry of `styles`.
-- A = same (play view), B = wide (far back), C = close (low and near). carter's pick sets `style`.
Config.Spectate = {
	style = "same",
	styles = {
		same = { pitchDegrees = 55, distance = 46 },
		wide = { pitchDegrees = 62, distance = 64 },
		close = { pitchDegrees = 38, distance = 30 },
	},
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
		pierce = 0, -- extra bodies a bullet flies through; only upgrades raise it (Config.Powers)
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
		aftershock = 0, -- 1 = the blast goes off a second time; only an upgrade sets it (Config.Powers)
	},
	-- Guns found in supply containers. Picking one up replaces the slot 1 gun (full magazine) until
	-- another is picked up; the old one (unless it is the Volt Pistol) drops where you stand.
	-- Upgrades scale these the same way they scale the pistol (see Combat/WeaponCatalog).
	Guns = {
		breaker = { -- pump shotgun: huge up close, nothing far away
			id = "breaker",
			displayName = "Breaker",
			damage = 7, -- per pellet
			pellets = 6,
			spreadDegrees = 14,
			fireInterval = 0.9,
			magazine = 6,
			reloadSeconds = 2.2,
			range = 26,
			muzzleOffset = 4.4,
		},
		hornet = { -- SMG: small hits, very fast, a little spray
			id = "hornet",
			displayName = "Hornet",
			damage = 5,
			pellets = 1,
			spreadDegrees = 5,
			fireInterval = 1 / 11,
			magazine = 30,
			reloadSeconds = 1.8,
			range = 45,
			muzzleOffset = 3.6,
		},
		longline = { -- marksman rifle: slow, big hits, longest reach (still on screen)
			id = "longline",
			displayName = "Longline",
			damage = 34,
			pellets = 1,
			spreadDegrees = 0,
			fireInterval = 1.25,
			magazine = 5,
			reloadSeconds = 2.2,
			range = 80,
			muzzleOffset = 6.9,
		},
	} :: {
		[string]: {
			id: string,
			displayName: string,
			damage: number,
			pellets: number,
			spreadDegrees: number,
			fireInterval: number,
			magazine: number,
			reloadSeconds: number,
			range: number,
			muzzleOffset: number,
		},
	},
	-- Gun drops from broken supply containers. Odds: `chance` that a container drops a gun at all,
	-- then each gun by weight (equal weights = 1 in 3 each). Nothing is bought; drops are free.
	Drops = {
		chance = 0.35,
		order = { "breaker", "hornet", "longline" }, -- fixed order so a roll always maps the same way
		weights = { breaker = 1, hornet = 1, longline = 1 } :: { [string]: number },
		lifetimeSeconds = 30,
		maxActive = 6, -- whole server; the oldest goes first
		promptDistance = 7, -- studs: the swap button shows this close
		claimSlack = 1.5, -- extra studs the server forgives for lag
		swapCooldown = 0.6, -- seconds between two swaps by one fighter (no ping-pong)
		height = 1.2, -- gun centre above the floor
		folder = "WeaponDrops", -- Workspace folder for guns on the ground
	},
}

-- Piece 46: heroes. Each hero has its own health, a little speed difference, its own starter gun (slot 1)
-- and its own blast launcher (slot 2). The numbers per hero live in `src/shared/Heroes.luau`; these are the
-- knobs around them. Heroes are all free and never bought: a hero is a sidegrade, never simply stronger.
Config.Heroes = {
	-- How far heroes differ from the plain 100 health / normal speed. 0 = all the same, 1 = as written.
	-- carter picked B Medium (small 0.5, medium 1, big 1.5). Health ends up 80 to 135.
	spread = 1,
	healthMin = 60, -- no hero ends up outside these, whatever the spread says
	healthMax = 160,
	speedMin = 0.85, -- share of normal run speed
	speedMax = 1.12,
	attribute = "HeroId", -- set on the player and on the character so every client can read who is who
	botsUseHeroes = true, -- bots get a hero by their number (the same one every match)
}

-- Piece 43: the big level-up powers. Their on/off stats live in the upgrade catalogue; these are the
-- numbers the shot code uses once a power is on. Placeholders until carter plays.
Config.Powers = {
	pierceFalloff = 0.6, -- each body a bullet passes through takes this share of the one before it
	aftershockDelaySeconds = 0.7, -- the second blast goes off this long after the first
	aftershockDamageShare = 0.5, -- and hurts this share as much
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
	cooldown = 5, -- seconds for ONE charge to come back
	charges = 2, -- piece 45: slides you can chain before waiting (1 = the old single slide)
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

-- Piece 45: sprint. Press the sprint button to start, press again to stop. The server decides: speed,
-- breath and when it may run. Shooting breaks the run for a moment. All placeholders until carter plays.
Config.Sprint = {
	enabled = true,
	speedMultiplier = 1.4, -- on top of normal run speed (and its upgrades)
	staminaSeconds = 3, -- running flat out empties the breath bar in this long
	regenSeconds = 4, -- and filling it from empty takes this long
	regenDelaySeconds = 0.8, -- breath starts to come back this long after the run stops
	restartAt = 0.3, -- after running out, you may start again once breath is at this share
	afterFireSeconds = 0.5, -- a shot slows you to normal speed for this long
	minMoveSpeedShare = 0.2, -- standing still (or nudging the stick) does not use breath
	tickSeconds = 0.1, -- how often the server steps everyone's breath
	sendSeconds = 0.25, -- breath updates go to the player at most this often
}

-- Piece 45: hop over low cover. Pressing Slide against a hoppable thing in front of you hops it
-- (the Slide button does both, so no new button). Server plans the hop and checks where you land.
Config.Vault = {
	enabled = true,
	reach = 3.2, -- studs: the thing must be this close, straight ahead
	maxDepth = 6, -- studs thick at most (a long car sideways is too thick)
	maxHeight = 4.5, -- studs tall at most
	landingPad = 2.4, -- studs past the far side you land
	durationSeconds = 0.42,
	cooldownSeconds = 1.0,
	headOnDot = 0.5, -- how square-on you must face it (1 = perfectly)
	bodyWidth = 2.4,
	bodyHeight = 4, -- the landing spot must be clear this tall
	floorTolerance = 1.2, -- the floor at the landing may differ this much from where you start
	clearance = 1, -- hop this far above the top
	maxPeak = 6.5,
	endGrace = 0.35,
	endTolerance = 4,
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
	-- Piece 28. Maps played in this order, one per match, looping. The first one is built at start.
	-- Any id from src/server/Arena/Layout*.luau works (A-F). One id = no rotation.
	rotation = { "C", "D" },
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
	Vaultable = "Vaultable", -- piece 45: low walls, fences and cars a fighter can hop over
	Roof = "Roof",
	Interior = "Interior",
	Spawn = "ArenaSpawn",
	ContainerSpot = "ContainerSpot",
	SupplyContainer = "SupplyContainer",
	FinalZoneRegion = "FinalZoneRegion",
	ArtNeon = "ArtNeon", -- piece 14: art parts whose glow follows the time of day (client)
	ArtFollower = "ArtFollower", -- piece 14: art parts that copy an occluder's see-through fade
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
	Vaulting = "Vaulting", -- piece 45: a body hopping over cover touches nothing until it lands
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
	-- Calm start (piece 21): when Active begins bots see less, react slower and miss more, then
	-- slide to the full numbers above over `seconds`.
	warmup = {
		seconds = 30,
		sightRange = 30,
		reactionSeconds = 0.9,
		aimErrorDegrees = 14,
	},
	-- Difficulty tiers (piece 35). A tier only changes how well a bot sees, reacts, aims and plays
	-- (cover, grabbing guns, leaving the zone early). Never health, damage, speed or ammo.
	-- Scales multiply the full-strength numbers above; the calm start numbers stay as they are.
	tiers = {
		easy = {
			sightScale = 0.75,
			reactionScale = 1.5,
			aimErrorScale = 1.8,
			coverSkill = 0.2, -- chance (0-1) it ducks behind cover when it needs to reload or heal
			seekGuns = false,
			zoneExtra = 0, -- extra studs of margin from the zone wall
		},
		normal = {
			sightScale = 1,
			reactionScale = 1,
			aimErrorScale = 1,
			coverSkill = 0.7,
			seekGuns = true,
			zoneExtra = 4,
		},
		hard = {
			sightScale = 1.15,
			reactionScale = 0.7,
			aimErrorScale = 0.6,
			coverSkill = 1,
			seekGuns = true,
			zoneExtra = 10,
		},
	} :: {
		[string]: {
			sightScale: number,
			reactionScale: number,
			aimErrorScale: number,
			coverSkill: number,
			seekGuns: boolean,
			zoneExtra: number,
		},
	},
	-- Bot number n gets tierCycle[(n - 1) % #tierCycle + 1]: a mixed lobby, same every match.
	tierCycle = { "normal", "easy", "hard", "normal", "easy", "normal", "hard", "easy" } :: { string },
}

-- Spawn shield (piece 21): everyone alive gets a short shield when the fight starts.
-- Firing your own gun ends it at once, so nobody can attack from behind it.
Config.SpawnShield = {
	seconds = 3,
	dropOnFire = true,
}

-- Kill streaks (piece 36). A kill within windowSeconds of the last one grows the streak.
-- Tiers pay once each when the streak reaches `at`. Values are placeholders until carter picks.
Config.Streaks = {
	enabled = true,
	windowSeconds = 12,
	-- `moment` names the big banner (Config.Moments / shared/Moments/MomentRules); `announceAll` also
	-- tells every other player, so a long streak is a threat they can see coming.
	tiers = {
		{
			at = 2,
			heal = 15,
			speedMultiplier = 1,
			speedSeconds = 0,
			text = "DOUBLE! +15 HP",
			moment = "double",
			announceAll = false,
		},
		{
			at = 3,
			heal = 20,
			speedMultiplier = 1,
			speedSeconds = 0,
			text = "TRIPLE! +20 HP",
			moment = "triple",
			announceAll = false,
		},
		{
			at = 5,
			heal = 30,
			speedMultiplier = 1,
			speedSeconds = 0,
			text = "RAMPAGE! +30 HP",
			moment = "spree",
			announceAll = true,
		},
	},
}

-- Big moments (piece 46): banner call-outs, name plates over every fighter, level-up burst.
-- Logic only; the looks come from Ui/MomentStyles (one of three, until Claude Design sends its own).
Config.Moments = {
	enabled = true,
	style = "C", -- which entry of Ui/MomentStyles is drawn
	bannerSeconds = 2.2, -- how long one banner stays
	minGapSeconds = 0.3, -- quiet time between two banners
	queueMax = 3, -- banners waiting behind the one on screen
	staleSeconds = 4, -- a waiting banner older than this is dropped (it is news no more)
	maxNameLength = 16, -- names on banners are cut to this many letters
}

Config.Plates = {
	enabled = true,
	maxDistance = 90, -- studs; further fighters show no plate
	maxNameLength = 14, -- letters kept on a plate
	showOwnPlate = false, -- your own bar and level are in the HUD
	ownRing = true, -- the ring under your own feet
	enemyRing = false, -- a ring under every other fighter too
	lowHealthFraction = 0.3, -- under this share of health the bar turns the danger colour
	ringDiameter = 5.6, -- studs
	ringThickness = 0.12, -- studs
	ringLift = 0.12, -- how far above the floor the ring floats (no z-fighting)
	plateLift = 3.6, -- studs above the root part
	burst = {
		particles = 22, -- sparks per level-up (halved when the arena is busy or flashes are reduced)
		arrowSeconds = 1.3, -- the arrow over the head
		ringSeconds = 0.7, -- the ring that opens on the floor
		ringDiameter = 14, -- studs when fully open
		maxAtOnce = 4, -- bursts alive at once; more are skipped (cosmetic only)
	},
}

-- Piece 42: loot lying on the street. Heal packs are carried and used on a button (server checks
-- everything). Floor guns are the same guns as crate drops, but they wait on the ground all match.
-- Everything is a placeholder number until carter plays.
Config.Loot = {
	enabled = true,
	heal = {
		amount = 30, -- health a pack gives (never over the max)
		carryMax = 3,
		useCooldownSeconds = 1.2, -- least time between two uses
		floorPacks = 6, -- on the street when a match starts
		lifetimeSeconds = 150, -- a pack nobody takes goes away after this
		maxOnFloor = 14, -- whole server; the oldest goes first (death drops can add more)
		size = 2.2, -- studs, placeholder block
		color = "#4CFF6A",
		crossColor = "#FFFFFF",
		dropOnDeath = true, -- a fighter who falls drops one pack if they carried any
		botUseBelowFraction = 0.5, -- bots use a pack when health is at or under this share of max
		sweepSeconds = 1, -- how often the server lets bots decide
	},
	floorGuns = {
		count = 4, -- on the street when a match starts
		order = { "breaker", "hornet", "longline" }, -- fixed order so a roll always maps the same way
		weights = { breaker = 1, hornet = 1, longline = 1 } :: { [string]: number },
	},
	-- Where floor loot goes: a short walk from a supply crate marker, on open floor only.
	spots = {
		offsetStuds = 7, -- from the crate marker
		angles = 8, -- tries around the marker, at equal steps
		floorTolerance = 1, -- the ground there must be this close to the marker's floor height
		rayHeight = 30, -- the check starts this far above the marker's floor
		minSeparation = 18, -- two loot spots are at least this far apart
	},
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

-- Piece 34: the account level. Run XP from every match (the same XP that fills the in-match upgrade bar) is
-- added to a saved total; milestone levels hand out free gifts (Scrap or looks, never Robux, never power).
-- The levels and gifts are in shared/Level/LevelDefs.
Config.Level = {
	firstCost = 100, -- XP to leave level 1
	costStep = 40, -- each later level costs this much more than the one before
	maxLevel = 50,
	maxXpPerMatch = 600, -- sanity cap for one match's XP; a real match gives far less
}

-- Piece 25: daily challenges. Three a day (one easy, one medium, one hard), the same for everyone, new at
-- midnight UTC. They pay in the game's coin (Config.Rewards.currencyName). The list is in shared/Daily/DailyDefs.
Config.Daily = {
	resetHourUtc = 0, -- the new day starts at this hour (UTC)
	rewards = { easy = 20, medium = 35, hard = 50 },
}

-- Piece 48: weekly missions, achievements and login days. All pay Scrap (Config.Rewards.currencyName), claimed
-- with a button. Weeks start on Monday at Config.Daily.resetHourUtc. Lists: shared/Missions/MissionDefs.
Config.Missions = {
	weeklyRewards = { easy = 60, medium = 90, hard = 120 }, -- the three weekly missions
	weeklyBonus = 100, -- extra Scrap after all three weekly missions are claimed
	-- The login row: one reward per day you come and claim. Missing days never reset it. After the last
	-- one the row starts again. Every number stays under Config.Progression.maxMatchGrant.
	loginRewards = { 10, 15, 20, 25, 30, 40, 100 },
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

-- Piece 20: first-time intro and "your data did not load" messages (client side only).
Config.Onboarding = {
	introFlag = "introSeen", -- must be listed in Config.Profile.flags (piece 17)
	slowLoadSeconds = 12, -- loading longer than this shows "Still loading your save..."
	retryCooldownSeconds = 5, -- the TRY AGAIN button waits this long between taps
}

Config.Perf = {
	maxDamageNumbers = 12,
	maxLiveEffects = 40,
	maxDebrisParts = 0, -- containers burst as particles, not physical parts
}

-- Piece 38: rain. The server picks one level per match; clients only draw it (placeholder look, cheap on phones).
Config.Weather = {
	levels = { "light", "steady", "heavy" },
	odds = { light = 30, steady = 45, heavy = 25 }, -- weights; the level of the match just played is skipped
	-- dropsPerSecond x dropSeconds = drops alive at once. fogAdd / hazeAdd are added to the sky Atmosphere
	-- at full rain. Nothing here darkens the sky: the city time-of-day code owns Lighting.
	look = {
		light = { dropsPerSecond = 110, fogAdd = 0.03, hazeAdd = 0.6, speed = 70 },
		steady = { dropsPerSecond = 200, fogAdd = 0.06, hazeAdd = 1.0, speed = 80 },
		heavy = { dropsPerSecond = 320, fogAdd = 0.1, hazeAdd = 1.5, speed = 95 },
	},
	dropSeconds = 0.9, -- how long one drop lives
	maxLiveDrops = 300, -- hard cap on drops alive at once, after the phone scale
	phoneScale = 0.5, -- touch-only devices get half the drops
	rampSeconds = 4, -- rain fades in and out over this long
	coverStuds = 70, -- the rain sheet above the camera is this wide
	heightStuds = 45, -- and this high above the camera
	applyAtmosphere = false, -- the city's DayNightSystem adds the Lighting attributes to its own Atmosphere; true = rain nudges an Atmosphere itself
	dropColor = "#9FE9FF",
	attributes = { fog = "WeatherFogAdd", haze = "WeatherHazeAdd" }, -- written on Lighting for the day-night code
}

-- Piece 17: saving player progress (DataStore). Read by src/server/Profile only.
Config.Profile = {
	storeName = "BlastZoneProfiles_v1", -- changing this starts everyone from nothing: never rename
	autosaveSeconds = 60, -- also refreshes the session lock
	minSecondsBetweenWrites = 6, -- DataStore allows one write per key about every 6 s
	lockStaleSeconds = 180, -- a lock older than this belongs to a crashed server
	loadLockTries = 6, -- how many times a load waits for another server to let go
	lockRetrySeconds = 3,
	receiptsKept = 100, -- newest once-only grant keys remembered per player
	shutdownSeconds = 25, -- BindToClose allows 30
	flags = { "introSeen" }, -- the only flags a client may set (piece 20)
}

-- Piece 11. Character poses are drawn from code (no animation assets), so these are the only knobs.
Config.Character = {
	defaultLook = "Runner", -- Runner, Courier or Spark (carter's pick is the default, the others are skins)
	lookAttribute = "CharacterLook", -- set on a player or a character to wear another look
	moveSpeedMin = 2, -- studs/s above which a fighter counts as moving
	runForwardMin = 0.55, -- forward share of the movement (0..1) needed to look like running, else strafing
	aimHold = 0.45, -- seconds after a shot that the fighter keeps the gun up
	hitFlinchSeconds = 0.35,
	slideSeconds = 0.75, -- how long the slide pose is held (the move itself is Config.Slide)
	smoothing = 20, -- how fast the body follows the pose (higher = snappier)
	winnerCheerSeconds = 12,
}

-- Piece 13 (effects polish). The look is "Sticker Punch" (carter's pick): chunky, bright, outlined in navy,
-- easy to read on a phone. What each effect is made of lives in `src/client/Effects/EffectRecipes.luau`;
-- the caps and the camera feel live here. Every effect is cosmetic and comes from a fixed pool.
Config.Effects = {
	look = "StickerPunch",
	caps = {
		particles = 220, -- particles that may be alive at once (counted from what each burst asks for)
		parts = Config.Perf.maxLiveEffects, -- tracers, streaks and shells in the air
		numbers = Config.Perf.maxDamageNumbers, -- floating damage and XP numbers
		banners = 2, -- comic words such as KO! and BOOM!
		rings = 8, -- flat rings on the ground
	},
	-- Camera shake is a "trauma" meter from 0 to 1 that decays; the shake you see is trauma squared.
	-- Everything is multiplied by the player's Camera shake setting, so 0 turns it all off.
	shake = { maxOffsetStuds = 0.55, maxRollDegrees = 1.1, frequency = 24, decayPerSecond = 2.2 },
	trauma = {
		shot = 0.03, -- your own shot (tiny kick)
		slide = 0.06,
		hurt = 0.12, -- you were hit
		kill = 0.28, -- you knocked someone out
		crateBreak = 0.2,
		blast = 0.55, -- a blast at your feet; farther blasts shake less (see falloff)
	},
	fovKick = {
		shot = 0.4,
		slide = 2.2,
		kill = 1.0,
		blast = 3.5,
		maxDegrees = 5,
		decayPerSecond = 9,
	},
	falloff = { fullStuds = 25, noneStuds = 90 }, -- blasts shake the camera fully inside fullStuds and not at all past noneStuds
	-- Screen flashes are skipped when the player turns on Fewer flashes.
	flash = { blast = 0.3, kill = 0.12, seconds = 0.18 },
	numbers = { riseStuds = 2.6, seconds = 0.9, spreadStuds = 2.0, bigAmount = 25 }, -- bigAmount: a hit this size gets the BAM! look
	shellStuds = 1.4,
	scorchSeconds = 2.6, -- how long a blast leaves its dark mark on the ground
}

-- Piece 29: emotes in the lobby and the winner pose on the results banner (drawn from code, see Character/Emotes).
Config.Emotes = {
	-- carter picked "all of them": every emote is free and each player picks a winner pose.
	trackUnlocks = false, -- true: emotes open on the coin track instead (see EmoteRules)
	starterSet = "A", -- listed first ("A" Street, "B" Hype, "C" Chill); with track unlocks its first two are free
	defaultWinPose = "A", -- A Gun to the Sky, B Fist Pump, C Arms Crossed (bots always use this one)
	winPoseAttribute = "WinPose", -- set by the server on the Player: the winner pose they picked
	attribute = "Emote", -- set by the server on a character: the emote id it is playing
	startedAttribute = "EmoteAt", -- server time the emote started (clients draw it from there)
	maxSeconds = 8, -- an emote stops by itself after this
	cooldown = 0.6, -- seconds between two emote starts
	stopMoveSpeed = 2, -- studs/s: walking off ends your own emote
	bannerWinner = true, -- show the winner's body doing the winner pose on the results screen
}

Config.Net = {
	clientWaitSeconds = 10,
}

-- Piece 27: the server's watch on where players really are (see server/AntiCheat/MoveCheck).
Config.AntiCheat = {
	speedSlack = 0.3, -- a player may move 30% faster than their walk speed (lag, slopes)
	burstSeconds = 1, -- after standing still, this much walking may arrive in one lump (phone lag)
	leeway = 3, -- studs always forgiven
	graceSeconds = 0.5, -- a move that is too far waits this long for a slide to explain it, then snaps back
	slideCreditSeconds = 1.5, -- a slide's extra distance can be used for this long
	riseSlope = 1.5, -- going up: at most this many studs up per stud across (ramps)
	riseLeeway = 4, -- studs of going up always forgiven (steps, curbs)
	warnEverySeconds = 10,
}

-- Piece 24: lifetime stats (wins, eliminations, matches) and the global top-wins board.
Config.Stats = {
	profileKey = "stats", -- saved inside the player's profile as data.stats (piece 17)
	board = {
		storeName = "TopWins_v1", -- OrderedDataStore; key = userId, value = saved wins
		rows = 10,
		refreshSeconds = 60, -- read the top list this often
		writeSeconds = 30, -- send queued win counts this often
		writesPerFlush = 8,
		spotTag = "LeaderboardSpot", -- optional part (lobby piece) where the board stands, front facing its LookVector
		lobbyOffset = 30, -- studs in front of the first LobbySpawn part when there is no spot
		fallback = { x = 0, z = -40 }, -- used when there is neither (faces +Z)
		modelName = "TopWinsBoard",
		look = "B", -- carter picked B "Neon Tower"; "A" Trophy Wall is a skin (C Street Billboard not built yet)
	},
}

-- Piece 14: Neon Night city art and the day-to-night lighting. Visual only, nothing here changes
-- collision, shots, spawns or the zone.
Config.Art = {
	seed = 1407, -- same seed = same city, every server and every match
	maxParts = 9000, -- phone budget for the whole art pass (tests fail above this)
	maxLights = 30, -- PointLights across the whole city
	lowestFloatingStuds = 5, -- art lower than this must sit flush against a solid or lie flat on the ground
	flushStuds = 0.6, -- how far art may stick out of a solid below that height
	skyline = { towers = 30, innerGap = 8, outerReach = 70 }, -- towers outside the arena wall
	-- Day to night. t runs 0 (day) to 1 (full night), tied to match time: it reaches 1 when
	-- sudden death starts. Outside a match the city is back in daylight.
	dayNight = {
		lobbyT = 0,
		maxChangePerSecond = 0.25, -- the sky glides, even when a new match snaps t back to 0
		glowSteps = 12, -- neon brightness is updated in this many steps, not every frame
	},
}

return Config
