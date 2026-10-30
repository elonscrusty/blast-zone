--!strict
-- Every remote in the game, in one list. The server makes them (piece 1 `Net`), the client waits
-- for them. Nobody adds a remote anywhere else: ask the coordinator to change this list.
-- `kind`: "event" = RemoteEvent, "fast" = UnreliableRemoteEvent (ok to drop), "func" = RemoteFunction.
-- `dir`: "c2s" the client asks (the server MUST check it), "s2c" the server tells.
-- `perSecond`: the most calls per second the server lets one player make (c2s only).

export type RemoteSpec = {
	kind: "event" | "fast" | "func",
	dir: "c2s" | "s2c",
	perSecond: number?,
	about: string,
}

local RemoteNames: { [string]: RemoteSpec } = {
	-- Client -> server
	Intent = {
		kind = "fast",
		dir = "c2s",
		perSecond = 30,
		about = "{aim: Vector2, fire: boolean}. Where I point, am I shooting.",
	},
	Action = {
		kind = "event",
		dir = "c2s",
		perSecond = 10,
		about = '"heavy" | "dodge" | "heal"',
	},
	PickPerk = {
		kind = "event",
		dir = "c2s",
		perSecond = 5,
		about = "number 1..3, answers a PerkOffer",
	},
	GhostPoke = {
		kind = "event",
		dir = "c2s",
		perSecond = 2,
		about = "Vector3 on the map, only for knocked-out players",
	},
	QueueJoin = { kind = "event", dir = "c2s", perSecond = 2, about = "FIGHT button" },
	QueueLeave = { kind = "event", dir = "c2s", perSecond = 2, about = "cancel button" },
	Menu = {
		kind = "func",
		dir = "c2s",
		perSecond = 5,
		about = "(cmd: string, args: any) -> {ok: boolean, reason: string?, ...}",
	},

	-- Server -> client
	MatchState = { kind = "event", dir = "s2c", about = "{phase, endsAt, alive, total}" },
	QueueState = {
		kind = "event",
		dir = "s2c",
		about = "{queued: boolean, humans: number, botsToFill: number, startsAt: number?}",
	},
	ProfileUpdate = {
		kind = "event",
		dir = "s2c",
		about = "the player's own saved numbers (cogs, gems, trophies, heroes, weapon levels, chests, dailies)",
	},
	Shot = {
		kind = "fast",
		dir = "s2c",
		about = "{fighterId, kind, origin, dir, speed, range} look only",
	},
	Hit = { kind = "fast", dir = "s2c", about = "{pos, amount, crit, targetId} for damage numbers" },
	Explosion = { kind = "event", dir = "s2c", about = "{pos, radius}" },
	Banner = { kind = "event", dir = "s2c", about = "{kind: string} MULTI KILL, LEVEL UP, ..." },
	KillFeed = {
		kind = "event",
		dir = "s2c",
		about = "{killer: string?, victim: string, weapon: string}",
	},
	PerkOffer = { kind = "event", dir = "s2c", about = "{options: {string}, expiresAt: number}" },
	LevelUp = { kind = "event", dir = "s2c", about = "{fighterId, level}" },
	BlastWarn = { kind = "event", dir = "s2c", about = "{waveId, cells: {Vector2}, boomAt}" },
	BlastBoom = { kind = "event", dir = "s2c", about = "{waveId, cells: {Vector2}}" },
	GhostWarn = { kind = "event", dir = "s2c", about = "{pos, radius, boomAt}" },
	Results = {
		kind = "event",
		dir = "s2c",
		about = "{placement, kills, cogs, trophies, heroXp, chest}",
	},
}

return RemoteNames
