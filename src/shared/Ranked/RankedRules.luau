--!strict
-- Pure rules for the ranked ladder (gap 23). No Roblox: Lune tests it. Saved in the profile as `data.ranked`.
--   * Points: last place loses lastPoints, first place gains winPoints, the rest sit on a straight line between.
--     Each elimination adds killPoints (capped). A draw for 1st counts as 2nd place.
--   * Stake: when a ranked fight begins the loss for last place is taken at once (`stake`) and handed back when
--     the match is scored. Leaving mid-fight therefore keeps the loss, and quitting can never dodge it.
--   * Tiers start at Config.Ranked.tiers[i].from. The warm-up (qualifyMatches counted matches) shows "Unranked".
--   * Losses stop at the start of your tier (Config.Ranked.dropTiers = false), so a tier you reached is yours for the
--     season. With dropTiers = true you can fall back down. Points never go below 0.
--   * A bots-only match (fewer than 2 real players) gains less and cannot lift you into soloCeilingTier or above.
--   * A new season keeps seasonKeep of the points and asks for the warm-up again. The peak tier is kept for good.

local Config = require("../Config")

local RankedRules = {}

export type Cfg = typeof(Config.Ranked)

export type State = {
	season: number,
	points: number,
	matches: number, -- counted matches this season
	peak: string, -- id of the best tier ever shown to this player
	enabled: boolean, -- the ranked switch
	stake: number, -- points taken when the fight began, not yet handed back
}

-- What one match was, from the server's own books.
export type Result = {
	place: number, -- 1 = first
	field: number, -- fighters in the match (bots too)
	kills: number,
	won: boolean, -- false at place 1 means a draw
	humans: number, -- real players in the match
}

export type Standing = {
	qualified: boolean,
	qualifyLeft: number,
	label: string,
	tierIndex: number,
	tierId: string,
	tierName: string,
	step: number, -- 1..divisions, 0 in the top tier
	intoStep: number,
	stepSize: number,
	nextTierName: string?,
	toNextTier: number?,
}

export type Change = {
	delta: number, -- real points moved (after floors and ceilings)
	fromLabel: string,
	toLabel: string,
	promoted: boolean,
	demoted: boolean,
	state: State,
}

local ROMAN = { "I", "II", "III", "IV", "V", "VI" }

local function whole(v: any, lo: number, hi: number): number
	if type(v) ~= "number" or v ~= v then
		return lo
	end
	return math.clamp(math.floor(v), lo, hi)
end

local function round(x: number): number
	return math.floor(x + 0.5)
end

-- ===== tiers =====

function RankedRules.tierIndex(points: number, cfg: Cfg?): number
	local tiers = (cfg or Config.Ranked).tiers
	local index = 1
	for i, tier in tiers do
		if points >= tier.from then
			index = i
		end
	end
	return index
end

local function tierById(id: any, cfg: Cfg): number?
	for i, tier in cfg.tiers do
		if tier.id == id then
			return i
		end
	end
	return nil
end

-- Points below which a player with `points` cannot sink.
function RankedRules.floorFor(points: number, cfg: Cfg?): number
	local c = cfg or Config.Ranked
	if c.dropTiers then
		return 0
	end
	return c.tiers[RankedRules.tierIndex(points, c)].from
end

-- ===== state =====

function RankedRules.empty(cfg: Cfg?): State
	local c = cfg or Config.Ranked
	return {
		season = c.season,
		points = 0,
		matches = 0,
		peak = c.tiers[1].id,
		enabled = false,
		stake = 0,
	}
end

-- Any saved value (a table, nil, junk) -> a clean State. Never errors. Moves an old season to the current one.
function RankedRules.read(raw: any, cfg: Cfg?): State
	local c = cfg or Config.Ranked
	local state = RankedRules.empty(c)
	if type(raw) ~= "table" then
		return state
	end
	state.points = whole(raw.points, 0, c.maxPoints)
	state.matches = whole(raw.matches, 0, 1e9)
	state.stake = whole(raw.stake, 0, c.maxPoints)
	state.enabled = raw.enabled == true
	if tierById(raw.peak, c) then
		state.peak = raw.peak
	end
	local season = whole(raw.season, 0, 1e6)
	if season < c.season then
		-- A new season: the stake of a fight that never finished is simply gone.
		state.points = math.floor(state.points * c.seasonKeep)
		state.matches = 0
		state.stake = 0
	end
	return state
end

function RankedRules.toSaved(state: State): { [string]: any }
	return {
		season = state.season,
		points = state.points,
		matches = state.matches,
		peak = state.peak,
		enabled = state.enabled,
		stake = state.stake,
	}
end

-- ===== how it shows =====

function RankedRules.standing(state: State, cfg: Cfg?): Standing
	local c = cfg or Config.Ranked
	local points = state.points
	local index = RankedRules.tierIndex(points, c)
	local tier = c.tiers[index]
	local nextTier = c.tiers[index + 1]
	local qualified = state.matches >= c.qualifyMatches

	local step, intoStep, stepSize = 0, 0, 0
	local label = tier.name
	if nextTier then
		local span = nextTier.from - tier.from
		local function stepStart(k: number): number
			if k > c.divisions then
				return nextTier.from
			end
			return tier.from + math.floor(span * (k - 1) / c.divisions)
		end
		step = 1
		for k = 1, c.divisions do
			if points >= stepStart(k) then
				step = k
			end
		end
		intoStep = points - stepStart(step)
		stepSize = stepStart(step + 1) - stepStart(step)
		local roman = ROMAN[c.divisions - step + 1] or tostring(c.divisions - step + 1)
		label = `{tier.name} {roman}`
	end
	return {
		qualified = qualified,
		qualifyLeft = math.max(0, c.qualifyMatches - state.matches),
		label = if qualified then label else "Unranked",
		tierIndex = index,
		tierId = tier.id,
		tierName = tier.name,
		step = step,
		intoStep = intoStep,
		stepSize = stepSize,
		nextTierName = if nextTier then nextTier.name else nil,
		toNextTier = if nextTier then nextTier.from - points else nil,
	}
end

-- ===== scoring =====

-- Does a match with this many fighters count for the ladder?
function RankedRules.counts(field: any, cfg: Cfg?): boolean
	local c = cfg or Config.Ranked
	return type(field) == "number" and field == field and field >= c.minField
end

-- Points a result is worth before floors and solo limits. Can be negative.
function RankedRules.pointsFor(result: Result, cfg: Cfg?): number
	local c = cfg or Config.Ranked
	local field = whole(result.field, 2, 1000)
	local place = whole(result.place, 1, field)
	if place == 1 and not result.won then
		place = 2 -- a draw is not a win
	end
	local share = (field - place) / (field - 1)
	local byPlace = c.lastPoints + (c.winPoints - c.lastPoints) * share
	local byKills = math.min(whole(result.kills, 0, 99) * c.killPoints, c.maxKillPoints)
	return round(byPlace + byKills)
end

-- The fight begins: take the last-place loss now. Returns the new state; call only for a ranked fight.
function RankedRules.takeStake(state: State, cfg: Cfg?): State
	local c = cfg or Config.Ranked
	local out = table.clone(state)
	local loss = math.max(0, -c.lastPoints)
	local after = math.max(RankedRules.floorFor(state.points, c), state.points - loss)
	out.stake = state.points - after -- a stake left by a fight that never ended is forgotten, not handed back
	out.points = after
	return out
end

-- Score a finished match. The stake is handed back first, then the result is added.
function RankedRules.apply(state: State, result: Result, cfg: Cfg?): Change
	local c = cfg or Config.Ranked
	local before = math.min(state.points + state.stake, c.maxPoints)
	local was = table.clone(state)
	was.points = before
	was.stake = 0
	local wasStanding = RankedRules.standing(was, c)

	local delta = RankedRules.pointsFor(result, c)
	if delta > 0 and result.humans < 2 then
		delta = math.floor(delta * c.soloScale)
		local ceilingTier = c.tiers[c.soloCeilingTier]
		if ceilingTier then
			delta = math.clamp(delta, 0, math.max(0, ceilingTier.from - 1 - before))
		end
	end
	local after = math.clamp(before + delta, RankedRules.floorFor(before, c), c.maxPoints)

	local out = table.clone(was)
	out.points = after
	out.matches = state.matches + 1
	out.season = c.season
	local now = RankedRules.standing(out, c)
	if now.qualified and now.tierIndex > (tierById(out.peak, c) or 1) then
		out.peak = now.tierId
	end
	return {
		delta = after - before,
		fromLabel = wasStanding.label,
		toLabel = now.label,
		promoted = wasStanding.qualified and now.tierIndex > wasStanding.tierIndex,
		demoted = wasStanding.qualified and now.tierIndex < wasStanding.tierIndex,
		state = out,
	}
end

function RankedRules.peakName(state: State, cfg: Cfg?): string
	local c = cfg or Config.Ranked
	local index = tierById(state.peak, c) or 1
	return c.tiers[index].name
end

return RankedRules
