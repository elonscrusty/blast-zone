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
}

export type ExplosiveStats = {
	damage: number,
	radius: number,
	fireInterval: number,
	magazine: number,
	reloadSeconds: number,
	range: number,
	projectileSpeed: number,
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
	draw: boolean,
	you: { placement: number, eliminations: number, survivedSeconds: number, reward: number }?,
}

return {}
