--!strict
-- Pure rules for the season pass (video 3 gap 20). The saved table is data.season in the profile:
--   { season, xp, paid, claimed, keys }
-- A new season wipes all of it. Season XP comes only from the server (the run XP of a finished match, once per
-- match key). Claiming is checked here first and only then marked, so a refusal changes nothing.
-- No Roblox, so Lune tests it.

local Config = require("../Config")
local SeasonDefs = require("./SeasonDefs")

local SeasonRules = {}

export type State = {
	season: number, -- 1 up
	xp: number, -- season XP this season
	paid: boolean, -- the paid row is open
	claimed: { [string]: boolean }, -- "<tier>:free" / "<tier>:paid"
	keys: { string }, -- recent match keys that already counted, oldest first
}

export type Progress = {
	tier: number, -- tiers reached (0 to the last tier)
	intoTier: number, -- XP toward the next tier
	forNext: number?, -- XP the next tier needs (nil at the top)
}

export type AddResult = { ok: boolean, reason: string?, fromTier: number, toTier: number }

local DAY = 86400

local function isCount(n: any): boolean
	return type(n) == "number" and n == n and n >= 0 and n < 1e9 and n == math.floor(n)
end

-- ===== the season clock =====

-- Which season it is (1 up). Times before the first start count as season 1.
function SeasonRules.seasonAt(unixSeconds: number): number
	local length = Config.Season.lengthDays * DAY
	local n = math.floor((unixSeconds - Config.Season.startUnix) / length)
	return math.max(0, n) + 1
end

-- Seconds until the season turns (always at least 0).
function SeasonRules.secondsLeft(unixSeconds: number): number
	local season = SeasonRules.seasonAt(unixSeconds)
	local ends = Config.Season.startUnix + season * Config.Season.lengthDays * DAY
	return math.max(0, ends - unixSeconds)
end

-- ===== the saved table =====

function SeasonRules.new(season: number): State
	return { season = season, xp = 0, paid = false, claimed = {}, keys = {} }
end

-- Repairs a saved table in place (missing or wrong-typed fields) and returns it.
function SeasonRules.fill(raw: any): State
	local s = raw :: any
	if not isCount(s.season) or s.season < 1 then
		s.season = 0 -- never matches a real season, so the next roll starts fresh
	end
	if not isCount(s.xp) then
		s.xp = 0
	end
	if s.paid ~= true then
		s.paid = false
	end
	if type(s.claimed) ~= "table" then
		s.claimed = {}
	end
	for key, v in s.claimed do
		if type(key) ~= "string" or v ~= true then
			s.claimed[key] = nil
		end
	end
	if type(s.keys) ~= "table" then
		s.keys = {}
	end
	local keys: { string } = {}
	for _, k in s.keys do
		if type(k) == "string" then
			table.insert(keys, k)
		end
	end
	s.keys = keys
	return s
end

-- Starts a new season if the saved one is old. Returns true if it changed anything.
function SeasonRules.roll(s: State, season: number): boolean
	if s.season == season then
		return false
	end
	s.season = season
	s.xp = 0
	s.paid = false
	s.claimed = {}
	s.keys = {}
	return true
end

-- ===== tiers =====

function SeasonRules.maxXp(): number
	return SeasonDefs.count() * Config.Season.xpPerTier
end

function SeasonRules.progress(xp: number): Progress
	local per = Config.Season.xpPerTier
	local top = SeasonDefs.count()
	local tier = math.min(top, math.floor(xp / per))
	if tier >= top then
		return { tier = top, intoTier = 0, forNext = nil }
	end
	return { tier = tier, intoTier = xp - tier * per, forNext = per }
end

-- Adds a finished match's season XP. Counts once per `matchKey`; a repeat, a bad number or a number over `cap`
-- changes nothing. The total stops at the top of the pass.
function SeasonRules.addXp(s: State, amount: number, matchKey: string, cap: number): AddResult
	local before = SeasonRules.progress(s.xp).tier
	local function refuse(reason: string): AddResult
		return { ok = false, reason = reason, fromTier = before, toTier = before }
	end
	if type(matchKey) ~= "string" or #matchKey == 0 then
		return refuse("badKey")
	end
	if not isCount(amount) or amount == 0 then
		return refuse("badAmount")
	end
	if amount > cap then
		return refuse("tooMuch")
	end
	if table.find(s.keys, matchKey) ~= nil then
		return refuse("duplicate")
	end
	table.insert(s.keys, matchKey)
	while #s.keys > Config.Season.keepKeys do
		table.remove(s.keys, 1)
	end
	s.xp = math.min(SeasonRules.maxXp(), s.xp + amount)
	return { ok = true, reason = nil, fromTier = before, toTier = SeasonRules.progress(s.xp).tier }
end

-- ===== claiming =====

local function claimKey(tier: number, row: string): string
	return `{tier}:{row}`
end

function SeasonRules.isClaimed(s: State, tier: number, row: string): boolean
	return s.claimed[claimKey(tier, row)] == true
end

-- Can this reward be taken right now? ok, or false with why:
-- badTier / badRow / locked (tier not reached) / needPass (paid row closed) / claimed.
function SeasonRules.canClaim(s: State, tier: number, row: string): (boolean, string?)
	if not isCount(tier) or SeasonDefs.tiers[tier] == nil then
		return false, "badTier"
	end
	if row ~= "free" and row ~= "paid" then
		return false, "badRow"
	end
	if SeasonRules.progress(s.xp).tier < tier then
		return false, "locked"
	end
	if row == "paid" and not s.paid then
		return false, "needPass"
	end
	if SeasonRules.isClaimed(s, tier, row) then
		return false, "claimed"
	end
	return true, nil
end

-- Marks a reward as taken (after it was paid). False if it was not claimable.
function SeasonRules.markClaimed(s: State, tier: number, row: string): boolean
	if not SeasonRules.canClaim(s, tier, row) then
		return false
	end
	s.claimed[claimKey(tier, row)] = true
	return true
end

export type Ready = { tier: number, row: string }

-- Every reward that can be taken now, low tiers first (free before paid in a tier).
function SeasonRules.ready(s: State): { Ready }
	local out: { Ready } = {}
	for tier = 1, SeasonRules.progress(s.xp).tier do
		for _, row in SeasonDefs.rows do
			if SeasonRules.canClaim(s, tier, row) then
				table.insert(out, { tier = tier, row = row })
			end
		end
	end
	return out
end

-- Opens the paid row. True if it changed anything.
function SeasonRules.openPaid(s: State): boolean
	if s.paid then
		return false
	end
	s.paid = true
	return true
end

-- Once-only receipt key for one reward in one season (fits Profile/Receipts: letters, digits, _ : . -).
function SeasonRules.receiptKey(season: number, tier: number, row: string): string
	return `s:{season}:{tier}:{row}`
end

return SeasonRules
