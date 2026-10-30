--!strict
-- Lifetime player stats (piece 24): wins, eliminations and matches played.
-- Pure Luau so Lune can test it. Saved inside the player's profile as `data.stats`.
--   * A match counts once per player, when the match pays its reward (MatchSystem.RewardGranted).
--   * A win is placement 1 (a draw puts both players 1st, so both get the win).
--   * An elimination counts for the killer only: a real player, not a bot, never yourself, never the zone.

local Ids = require("../Ids")

export type Stats = {
	wins: number,
	eliminations: number,
	matches: number,
}

local StatsRules = {}

StatsRules.FIELDS = { "wins", "eliminations", "matches" }
StatsRules.MAX = 1e9 -- far beyond any real count; stops a broken record from growing forever

local function whole(v: any): number
	if type(v) ~= "number" or v ~= v then
		return 0
	end
	return math.clamp(math.floor(v), 0, StatsRules.MAX)
end

function StatsRules.empty(): Stats
	return { wins = 0, eliminations = 0, matches = 0 }
end

-- Any value (a saved table, nil, junk) -> clean Stats. Never errors.
function StatsRules.read(raw: any): Stats
	if type(raw) ~= "table" then
		return StatsRules.empty()
	end
	return {
		wins = whole(raw.wins),
		eliminations = whole(raw.eliminations),
		matches = whole(raw.matches),
	}
end

function StatsRules.add(a: Stats, b: Stats): Stats
	return {
		wins = whole(a.wins + b.wins),
		eliminations = whole(a.eliminations + b.eliminations),
		matches = whole(a.matches + b.matches),
	}
end

function StatsRules.isEmpty(s: Stats): boolean
	return s.wins == 0 and s.eliminations == 0 and s.matches == 0
end

function StatsRules.equal(a: Stats, b: Stats): boolean
	return a.wins == b.wins and a.eliminations == b.eliminations and a.matches == b.matches
end

-- The delta for one finished match.
function StatsRules.matchDelta(place: any): Stats
	local won = type(place) == "number" and place == 1
	return { wins = if won then 1 else 0, eliminations = 0, matches = 1 }
end

-- The userId that earns an elimination, or nil when nobody should get one.
function StatsRules.eliminationCredit(event: any): number?
	if type(event) ~= "table" then
		return nil
	end
	local killer = event.killerId
	if type(killer) ~= "string" or killer == event.victimId or event.cause == "zone" then
		return nil
	end
	if not Ids.isPlayer(killer) then
		return nil
	end
	return Ids.userIdOf(killer)
end

-- Phases where players are in the arena: the lobby board hides itself (for that client only).
local FIGHT_PHASES = { Spawning = true, Active = true, FinalPressure = true, Finished = true }

function StatsRules.boardVisible(phase: string?): boolean
	return phase == nil or not FIGHT_PHASES[phase]
end

-- The lobby stats card shows only while players are in the lobby (same phases as the PLAY button).
function StatsRules.cardVisible(phase: string?): boolean
	return phase == "Waiting" or phase == "Countdown"
end

-- The YOU row on the board. `short` turns a number into short text (BoardRules.short).
function StatsRules.youLine(s: Stats, short: (number) -> string): string
	return `🏆 {short(s.wins)} wins   💥 {short(s.eliminations)} elims   🎮 {short(s.matches)} games`
end

return StatsRules
