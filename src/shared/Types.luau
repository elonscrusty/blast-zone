--!strict
-- Shared type names. No runtime content: `require` it only for `Types.X` type access.

export type MatchId = number -- grows by one per match; stale events carry an old one
export type ParticipantId = string -- see Ids.luau: "p<userId>" or "b<n>"
export type ParticipantKind = "player" | "bot"

export type MatchPhase =
	"Waiting"
	| "Countdown"
	| "Spawning"
	| "Active"
	| "FinalPressure"
	| "Finished"
	| "Results"
	| "Resetting"

-- One entry per fighter in one match. Server only (holds the Player).
export type Participant = {
	id: ParticipantId,
	kind: ParticipantKind,
	matchId: MatchId,
	displayName: string, -- bots already carry the "[BOT] " prefix
	userId: number?, -- players only
	player: any?, -- the Player instance (players only)
	alive: boolean,
	eliminatedAt: number?, -- os.clock when eliminated
}

export type DamageCause = "bullet" | "explosion" | "zone" | "disconnect" | "other"

export type DamageRequest = {
	matchId: MatchId,
	targetId: ParticipantId,
	amount: number, -- decided by the server, never by a client
	cause: DamageCause,
	sourceId: ParticipantId?, -- nil for the zone and other environment damage
	weaponId: string?,
	hitPosition: any?, -- Vector3
}

export type DamageResult = {
	applied: boolean,
	reason: string?, -- why not applied
	dealt: number,
	remaining: number,
	eliminated: boolean,
}

export type DamageEvent = {
	request: DamageRequest,
	result: DamageResult,
}

export type EliminationEvent = {
	matchId: MatchId,
	victimId: ParticipantId,
	killerId: ParticipantId?,
	cause: DamageCause,
	weaponId: string?,
	at: number, -- os.clock
}

export type WeaponStats = {
	damage: number,
	fireInterval: number,
	magazine: number,
	reloadSeconds: number,
	range: number,
	pellets: number,
	spreadDegrees: number,
	pierce: number, -- extra bodies one bullet passes through (0 = stops at the first)
}

export type ExplosiveStats = {
	damage: number,
	radius: number,
	fireInterval: number,
	magazine: number,
	reloadSeconds: number,
	range: number,
	projectileSpeed: number,
	aftershock: number, -- 1 = a second, weaker blast follows the first
}

-- What the rest of the game reads. Piece 08 builds this from base Config + upgrade stacks.
export type StatSheet = {
	moveSpeed: number,
	slideDistance: number,
	slideDuration: number,
	slideCooldown: number,
	firearm: WeaponStats,
	explosive: ExplosiveStats,
}

export type XpState = {
	level: number, -- starts at 1
	xp: number, -- progress toward the next level
	xpToNext: number,
	totalXp: number,
	pendingOffers: number, -- level-ups waiting for an upgrade pick
	offersGranted: number,
}

-- Sent to every client when the phase or survivor count changes.
export type PublicMatchState = {
	matchId: MatchId,
	phase: MatchPhase,
	phaseEndsAt: number?, -- server time (workspace:GetServerTimeNow)
	aliveCount: number,
	totalCount: number,
	serverNow: number,
	note: string?, -- short code for the HUD: press_play, waiting_players, match_starting, aborted_too_few, get_ready, fight, final_pressure, match_over, results, resetting
}

export type ZoneState = {
	matchId: MatchId,
	centerX: number,
	centerZ: number,
	fromRadius: number,
	toRadius: number,
	startedAt: number, -- server time
	endsAt: number,
	warningEndsAt: number?, -- set while a closure is announced but not started
	damagePerSecond: number,
	stage: number, -- 0 = before the first warning, 99 = sudden death
}

export type UpgradeOption = {
	id: string,
	name: string,
	description: string,
	icon: string,
	stacks: number, -- how many the player already has
	maxStacks: number,
	change: string?, -- the real numbers this pick changes, e.g. "Reload 1.2s → 0.96s" (piece 08)
	kind: string?, -- "weapon" or "move": picks the card accent (piece 08)
}

export type UpgradeOffer = {
	offerId: string,
	matchId: MatchId,
	options: { UpgradeOption },
}

export type ResultsRow = {
	participantId: ParticipantId,
	displayName: string,
	isBot: boolean,
	placement: number,
	eliminations: number,
	survivedSeconds: number,
}

export type ResultsPayload = {
	matchId: MatchId,
	rows: { ResultsRow },
	draw: boolean, -- true unless exactly one winner
	outcome: string?, -- "win" | "draw" | "abandoned" (abandoned: the best finisher left, so nobody is crowned)
	winnerId: ParticipantId?,
	endsAt: number?, -- server time the results screen closes
	you: { placement: number, eliminations: number, survivedSeconds: number, reward: number }?,
}

-- Piece 18: what the server tells one player about their coins and unlocks (never the other way round).
export type ProgressState = {
	status: string, -- "ready" | "loading" | "failed" | "lost" | "temporary" (temporary = works, but is not being saved)
	coins: number,
	totalEarned: number,
	unlocked: { string }, -- item ids bought from the track (defaults are always owned)
	equipped: { [string]: string }, -- slot -> item id
	gained: { matchId: number, amount: number }?, -- set once, right after a match reward was paid
	denied: string?, -- why the last unlock/equip request was refused
	-- Piece 34 (account level)
	level: number,
	intoLevel: number, -- XP earned toward the next level
	forNext: number?, -- XP the next level needs (nil at the top)
	gifts: { string }, -- level gifts owned (looks from TrackDefs.gifts); kept apart from `unlocked`
	levelUp: LevelUp?, -- set once, right after a match's XP was added
}

export type LevelUp = {
	matchId: number,
	fromLevel: number,
	toLevel: number,
	rewards: { LevelReward },
}
export type LevelReward = { level: number, kind: string, amount: number?, itemId: string? }

-- Piece 24: a player's own lifetime stats. saved = false while some of them are not written yet.
export type StatsPayload = {
	wins: number,
	eliminations: number,
	matches: number,
	saved: boolean,
}

-- Video 3 gap #16: a player's own power rating (server to client only). Parts are in PowerRules.PART_IDS order.
export type PowerPayload = {
	power: number,
	band: number,
	toNext: number?,
	parts: { { id: string, count: number, points: number, capped: boolean } },
}

-- Piece 25: today's daily challenges for one player (server to client only).
export type DailyChallengeView = {
	id: string,
	tier: string, -- "easy" | "medium" | "hard"
	kind: string, -- what counts: "elims" | "crates" | "orbs" | "matches" | "top3" | "wins"
	goal: number,
	progress: number,
	reward: number,
	paid: boolean,
}

export type DailyState = {
	status: string, -- "ready" | "temporary" | "loading" | "failed" | ...
	day: number, -- days since 1970 (UTC, moved by Config.Daily.resetHourUtc)
	secondsLeft: number, -- until the next day starts
	challenges: { DailyChallengeView },
	justPaid: string?, -- set once, right after a challenge paid out
}

-- Gap 14: the bench (server to client only). Looks come from Claude Design; this is only the facts.
export type BenchPartView = { kind: string, tier: number, count: number, canMerge: boolean }
export type BenchNeedView = { kind: string, tier: number, count: number, have: number }
export type BenchBlueprintView = {
	id: string,
	name: string,
	slot: string, -- "head" | "body" | "feet"
	needs: { BenchNeedView },
	built: boolean,
	ready: boolean,
}
export type BenchState = {
	status: string, -- "ready" | "temporary" | "loading" | "failed" | ...
	parts: { BenchPartView },
	blueprints: { BenchBlueprintView },
	built: number,
	total: number,
	justGot: { { kind: string, tier: number } }?, -- parts that just dropped after a match
	event: string?, -- "merged" | "built" | "dropped" | "denied"
	reason: string?, -- why a request was denied
}

-- Piece 19. What the loadout screen needs: which ids are picked, which are open, and what the player has.
export type LoadoutState = {
	selection: { [string]: string }, -- slot -> item id
	unlocked: { [string]: { string } }, -- slot -> ids this player can wear
	level: number, -- rewards bought (0..6), from piece 18
	coins: number?, -- Scrap, from piece 18 (nil until saved data is loaded)
	saved: boolean, -- false = picks last this visit only
}

-- Piece 38: the weather the server picked for this match. level "clear" means no rain.
export type WeatherState = {
	matchId: MatchId,
	level: string, -- "clear" | one of Config.Weather.levels
	serverNow: number,
}

return {}
