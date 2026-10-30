--!strict
-- Pure rules for weekly missions, achievements and login days (piece 48). No Roblox, so Lune tests it.
-- The saved table is data.missions in the profile. A new week wipes weekly progress and claims; achievements and
-- the login row are for good. Every weekly pick depends only on the week number, so all servers agree.
-- Nothing pays here: the service asks for a claim, pays through a once-only key, then marks it claimed.

local DailyRules = require("../Daily/DailyRules")
local MissionDefs = require("./MissionDefs")
local Types = require("../Types")

local MissionRules = {}

export type State = {
	week: number,
	progress: { [string]: number }, -- weekly mission id -> count this week
	claimed: { [string]: boolean }, -- weekly mission ids claimed this week
	bonus: boolean, -- this week's bonus claimed
	life: { [string]: number }, -- kind -> count over all time (feeds the achievements)
	awards: { [string]: boolean }, -- achievement ids claimed
	loginDay: number, -- the day of the last login claim, -1 = never
	loginCount: number, -- login days claimed in all
}

export type Config = {
	weeklyRewards: { [string]: number },
	weeklyBonus: number,
	loginRewards: { number },
}

local DAY = 86400
local MAX = 1e9

-- ===== weeks =====

-- Weeks run Monday to Sunday, starting at `resetHour` UTC. Day 0 (1 Jan 1970) was a Thursday.
function MissionRules.weekOf(unixSeconds: number, resetHour: number): number
	return math.floor((DailyRules.dayOf(unixSeconds, resetHour) + 3) / 7)
end

function MissionRules.weekSecondsLeft(unixSeconds: number, resetHour: number): number
	local week = MissionRules.weekOf(unixSeconds, resetHour)
	local nextStartDay = (week + 1) * 7 - 3
	return math.max(0, nextStartDay * DAY + resetHour * 3600 - unixSeconds)
end

local function mix(a: number, b: number): number
	local h = (a * 29 + b * 13) % 1000003
	h = (h * 48271) % 2147483647
	h = (h * 48271) % 2147483647
	return h
end

-- This week's three missions: one per tier, never two of the same kind. Same answer on every server.
function MissionRules.pick(week: number): { MissionDefs.Weekly }
	local out: { MissionDefs.Weekly } = {}
	local usedKinds: { [string]: boolean } = {}
	for t, tier in MissionDefs.tiers do
		local defs = MissionDefs.weeklyOfTier(tier)
		local start = mix(week, t) % #defs
		for step = 0, #defs - 1 do
			local def = defs[(start + step) % #defs + 1]
			if not usedKinds[def.kind] then
				usedKinds[def.kind] = true
				table.insert(out, def)
				break
			end
		end
	end
	return out
end

-- ===== the saved table =====

function MissionRules.new(week: number): State
	return {
		week = week,
		progress = {},
		claimed = {},
		bonus = false,
		life = {},
		awards = {},
		loginDay = -1,
		loginCount = 0,
	}
end

local function isCount(n: any): boolean
	return type(n) == "number" and n == n and n >= 0 and n < MAX and n == math.floor(n)
end

local function cleanCounts(t: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(t) == "table" then
		for id, n in t do
			if type(id) == "string" and isCount(n) then
				out[id] = n
			end
		end
	end
	return out
end

local function cleanFlags(t: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(t) == "table" then
		for id, v in t do
			if type(id) == "string" and v == true then
				out[id] = true
			end
		end
	end
	return out
end

-- Repairs a saved table (missing or wrong-typed fields) and returns the clean State. `raw` may be anything.
function MissionRules.fill(raw: any): State
	local s = if type(raw) == "table" then raw else {}
	local week = if type(s.week) == "number" and s.week == s.week then s.week else -1
	return {
		week = week,
		progress = cleanCounts(s.progress),
		claimed = cleanFlags(s.claimed),
		bonus = s.bonus == true,
		life = cleanCounts(s.life),
		awards = cleanFlags(s.awards),
		loginDay = if type(s.loginDay) == "number" and s.loginDay == s.loginDay
			then s.loginDay
			else -1,
		loginCount = if isCount(s.loginCount) then s.loginCount else 0,
	}
end

-- Starts a new week if the saved one is old. Returns true if it changed anything.
function MissionRules.roll(s: State, week: number): boolean
	if s.week == week then
		return false
	end
	s.week = week
	s.progress = {}
	s.claimed = {}
	s.bonus = false
	return true
end

-- ===== counting =====

-- Counts `amount` of `kind` toward this week's missions (capped at the goal) and toward the lifetime total.
-- Returns the ids that just became claimable ("w_..." weekly missions and "a_..." achievements).
function MissionRules.add(s: State, week: number, kind: string, amount: number): { string }
	MissionRules.roll(s, week)
	local ready: { string } = {}
	if not isCount(amount) or amount == 0 then
		return ready
	end
	for _, def in MissionRules.pick(week) do
		if def.kind == kind and not s.claimed[def.id] then
			local before = s.progress[def.id] or 0
			local after = math.min(def.goal, before + amount)
			s.progress[def.id] = after
			if before < def.goal and after >= def.goal then
				table.insert(ready, def.id)
			end
		end
	end
	local lifeBefore = s.life[kind] or 0
	local lifeAfter = math.min(MAX - 1, lifeBefore + amount)
	s.life[kind] = lifeAfter
	for _, def in MissionDefs.awards do
		if
			def.kind == kind
			and not s.awards[def.id]
			and lifeBefore < def.goal
			and lifeAfter >= def.goal
		then
			table.insert(ready, def.id)
		end
	end
	return ready
end

-- ===== claiming =====

local function weeklyOnToday(week: number, id: string): MissionDefs.Weekly?
	for _, def in MissionRules.pick(week) do
		if def.id == id then
			return def
		end
	end
	return nil
end

local function claimedWeeklyCount(s: State, week: number): number
	local n = 0
	for _, def in MissionRules.pick(week) do
		if s.claimed[def.id] then
			n += 1
		end
	end
	return n
end

local function bonusReady(s: State, week: number): boolean
	return not s.bonus and claimedWeeklyCount(s, week) == #MissionRules.pick(week)
end

function MissionRules.canLogin(s: State, day: number): boolean
	return s.loginDay < day
end

-- Which day of the login row the next claim is (1 up to #rewards). The row never resets for a missed day.
function MissionRules.loginStep(s: State, cfg: Config): number
	return s.loginCount % math.max(1, #cfg.loginRewards) + 1
end

-- Once-only receipt keys (fit Profile/Receipts: letters, digits, _ : . -).
function MissionRules.receiptKey(what: string, week: number, day: number, id: string?): string
	if what == "week" then
		return "w:" .. tostring(week) .. ":" .. tostring(id)
	elseif what == "bonus" then
		return "w:" .. tostring(week) .. ":bonus"
	elseif what == "award" then
		return "a:" .. tostring(id)
	end
	return "l:" .. tostring(day)
end

-- What a claim would pay: amount and receipt key, or nil and the reason. `what` is "week" | "award" | "bonus" |
-- "login". `s` must already be rolled to `week`.
function MissionRules.claimInfo(
	s: State,
	week: number,
	day: number,
	what: string,
	id: string?,
	cfg: Config
): (number?, string?)
	if s.week ~= week then
		return nil, "oldWeek"
	end
	if what == "week" then
		local def = if id ~= nil then weeklyOnToday(week, id) else nil
		if def == nil then
			return nil, "unknown"
		end
		if s.claimed[def.id] then
			return nil, "claimed"
		end
		if (s.progress[def.id] or 0) < def.goal then
			return nil, "notDone"
		end
		return cfg.weeklyRewards[def.tier] or 0, MissionRules.receiptKey(what, week, day, def.id)
	elseif what == "bonus" then
		if s.bonus then
			return nil, "claimed"
		end
		if not bonusReady(s, week) then
			return nil, "notDone"
		end
		return cfg.weeklyBonus, MissionRules.receiptKey(what, week, day, nil)
	elseif what == "award" then
		local def = if id ~= nil then MissionDefs.getAward(id) else nil
		if def == nil then
			return nil, "unknown"
		end
		if s.awards[def.id] then
			return nil, "claimed"
		end
		if (s.life[def.kind] or 0) < def.goal then
			return nil, "notDone"
		end
		return def.reward, MissionRules.receiptKey(what, week, day, def.id)
	elseif what == "login" then
		if not MissionRules.canLogin(s, day) then
			return nil, "claimed"
		end
		return cfg.loginRewards[MissionRules.loginStep(s, cfg)] or 0,
			MissionRules.receiptKey(what, week, day, nil)
	end
	return nil, "unknown"
end

-- Marks a claim done after it paid (or was found already paid). Checks again, so a stale call changes nothing.
function MissionRules.markClaimed(
	s: State,
	week: number,
	day: number,
	what: string,
	id: string?,
	cfg: Config
): boolean
	local amount = MissionRules.claimInfo(s, week, day, what, id, cfg)
	if amount == nil then
		return false
	end
	if what == "week" and id ~= nil then
		s.claimed[id] = true
	elseif what == "bonus" then
		s.bonus = true
	elseif what == "award" and id ~= nil then
		s.awards[id] = true
	else
		s.loginDay = day
		s.loginCount += 1
	end
	return true
end

-- ===== what the player sees =====

-- `s` may be nil (not loaded): everything shows as 0 and nothing can be claimed.
function MissionRules.view(
	s: State?,
	week: number,
	day: number,
	cfg: Config
): (
	{ Types.MissionRow },
	Types.MissionBonus,
	{ Types.MissionRow },
	Types.LoginView
)
	local current = if s ~= nil and s.week == week then s else nil
	local weekly: { Types.MissionRow } = {}
	for _, def in MissionRules.pick(week) do
		local progress = if current then current.progress[def.id] or 0 else 0
		local claimed = if current then current.claimed[def.id] == true else false
		table.insert(weekly, {
			id = def.id,
			tier = def.tier,
			kind = def.kind,
			goal = def.goal,
			progress = progress,
			reward = cfg.weeklyRewards[def.tier] or 0,
			claimed = claimed,
			ready = not claimed and progress >= def.goal,
		})
	end
	local bonus: Types.MissionBonus = {
		have = if current then claimedWeeklyCount(current, week) else 0,
		need = #weekly,
		reward = cfg.weeklyBonus,
		claimed = current ~= nil and current.bonus,
		ready = current ~= nil and bonusReady(current, week),
	}
	local awards: { Types.MissionRow } = {}
	for _, def in MissionDefs.awards do
		local progress = if s then math.min(def.goal, s.life[def.kind] or 0) else 0
		local claimed = s ~= nil and s.awards[def.id] == true
		table.insert(awards, {
			id = def.id,
			kind = def.kind,
			goal = def.goal,
			progress = progress,
			reward = def.reward,
			claimed = claimed,
			ready = not claimed and progress >= def.goal,
		})
	end
	local login: Types.LoginView = {
		next = if s then MissionRules.loginStep(s, cfg) else 1,
		rewards = table.clone(cfg.loginRewards),
		canClaim = s ~= nil and MissionRules.canLogin(s, day),
		count = if s then s.loginCount else 0,
		secondsLeft = 0, -- the service fills this in
	}
	return weekly, bonus, awards, login
end

-- How many things are ready to claim right now (for the little dot on the lobby button).
function MissionRules.readyCount(state: Types.MissionsState): number
	local n = 0
	for _, row in state.weekly do
		if row.ready then
			n += 1
		end
	end
	for _, row in state.awards do
		if row.ready then
			n += 1
		end
	end
	if state.bonus.ready then
		n += 1
	end
	if state.login.canClaim then
		n += 1
	end
	return n
end

return MissionRules
