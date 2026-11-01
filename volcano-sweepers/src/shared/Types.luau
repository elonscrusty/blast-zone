--!strict
-- Shared data shapes. This is the contract between server and client. Change a shape here ONLY
-- by also fixing every user (grep the field name). Times are server time (workspace:GetServerTimeNow()).

local Types = {}

-- What gets saved (see Profile/ProfileSchema + SaveVersion in Config). All numbers finite.
export type Stats = {
	ashSwept: number, -- units removed by this player, lifetime
	unitsSold: number,
	sellCount: number,
	findsTotal: number,
	burpHits: number,
	burpDodged: number, -- events survived without a hit
	cleared: number, -- cells swept to bare ground, lifetime
	playSeconds: number,
}

export type Settings = {
	music: boolean,
	sfx: boolean,
	autoSweep: boolean,
	shake: boolean, -- camera nudges
	vibrate: boolean, -- phone haptics where available
}

export type Profile = {
	version: number,
	coins: number, -- current wallet
	runCoins: number, -- coins earned since the last Cool Down (drives Spark math)
	lifetimeCoins: number,
	sparks: number,
	coolDowns: number,
	tool: string, -- equipped tool id
	toolsOwned: { [string]: boolean },
	upgrades: { [string]: number }, -- upgrade id -> level (absent = 0)
	zones: { [string]: boolean }, -- zone id as string ("1".."5") -> unlocked
	helpers: number, -- bots owned (0..6)
	helperLevel: number, -- one shared level for all of your bots
	sparkPerks: { [string]: number }, -- perk id -> level
	finds: { [string]: number }, -- find id -> times found
	setsClaimed: { [string]: boolean }, -- find-set id -> reward taken
	goalsClaimed: { [string]: boolean },
	daily: { lastDay: number, streak: number }, -- lastDay = days since epoch (UTC), 0 = never
	stats: Stats,
	settings: Settings,
	tutorialDone: boolean,
}

-- Derived numbers the server computed from the profile (Stats.compute). Client only DISPLAYS these.
export type Derived = {
	reach: number,
	arcDeg: number,
	power: number, -- units removed per cell per swing
	interval: number, -- seconds between swings
	capacity: number, -- backpack units
	walkSpeed: number,
	sellMult: number, -- total coin multiplier from everything (upgrades, sparks, sets, buffs)
	luck: number,
	armor: number, -- 0..1 share of carried ash saved when hit
}

-- What the client holds. Server sends partial updates (State remote): any subset of these keys.
export type View = Profile & {
	carried: number, -- units in backpack right now
	carriedValue: number, -- coins the backpack is worth before multipliers
	derived: Derived,
	buffs: { [string]: number }, -- buff id -> endsAt (server time). ids: party, perfect, golden
	cleanTotal: number, -- 0..1 island clean fraction
}

-- ===== Remote payloads (server -> client) =====
export type SoldInfo = { units: number, coins: number, bonusCoins: number, luckyDouble: boolean }
export type ToastInfo = { text: string, kind: "info" | "good" | "warn" | "gold" }
export type BurpPhase = "calm" | "rumble" | "event" | "recover"
export type BurpKind = "pops" | "ashStorm" | "golden" | "geysers"
export type BurpInfo = { phase: BurpPhase, kind: BurpKind?, startsAt: number, endsAt: number }
export type Bomb = { id: number, x: number, z: number, radius: number, landsAt: number }
export type BombsInfo = { bombs: { Bomb } }
export type BurpHitInfo = { userId: number, dropped: number }
export type ProgressInfo = { zones: { [string]: number }, total: number } -- fractions 0..1
export type PartyInfo = { milestone: number, zone: number } -- zone 0 = whole island
export type FindInfo = { id: string, rarity: string, isNew: boolean, coins: number }
export type SweepFxInfo = {
	userId: number,
	x: number,
	z: number,
	dx: number,
	dz: number,
	tool: string,
}
export type CoolDownInfo = { sparksGained: number }

return Types
