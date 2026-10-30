--!strict
-- Pure rules for daily challenges (piece 25): which three are on today, counting progress, and what is ready to
-- pay. No Roblox, so Lune tests it. The saved table is data.daily in the profile: { day, progress, paid }.
-- A new day wipes progress and paid marks. Every pick depends only on the day number, so all servers agree.

local DailyDefs = require("./DailyDefs")

local DailyRules = {}

export type State = {
	day: number,
	progress: { [string]: number },
	paid: { [string]: boolean },
}

export type View = {
	id: string,
	tier: string,
	kind: string,
	goal: number,
	progress: number,
	reward: number,
	paid: boolean,
}

local DAY = 86400

-- Days since 1970 (UTC), where each day starts at `resetHour`:00 UTC.
function DailyRules.dayOf(unixSeconds: number, resetHour: number): number
	return math.floor((unixSeconds - resetHour * 3600) / DAY)
end

function DailyRules.secondsLeft(unixSeconds: number, resetHour: number): number
	local day = DailyRules.dayOf(unixSeconds, resetHour)
	return math.max(0, (day + 1) * DAY + resetHour * 3600 - unixSeconds)
end

-- Small number mixer that stays exact in doubles (all products are well below 2^53).
local function mix(a: number, b: number): number
	local h = (a * 31 + b * 17) % 1000003
	h = (h * 48271) % 2147483647
	h = (h * 48271) % 2147483647
	return h
end

-- Today's three challenges: one per tier, never two of the same kind. Same answer on every server.
function DailyRules.pick(day: number): { DailyDefs.Def }
	local out: { DailyDefs.Def } = {}
	local usedKinds: { [string]: boolean } = {}
	for t, tier in DailyDefs.tiers do
		local defs = DailyDefs.ofTier(tier)
		local start = mix(day, t) % #defs
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

function DailyRules.new(day: number): State
	return { day = day, progress = {}, paid = {} }
end

local function isCount(n: any): boolean
	return type(n) == "number" and n == n and n >= 0 and n < 1e9 and n == math.floor(n)
end

-- Repairs a saved table in place (missing or wrong-typed fields) and returns it.
function DailyRules.fill(raw: any): State
	local s = raw :: any
	if type(s.day) ~= "number" or s.day ~= s.day then
		s.day = -1
	end
	if type(s.progress) ~= "table" then
		s.progress = {}
	end
	if type(s.paid) ~= "table" then
		s.paid = {}
	end
	for id, n in s.progress do
		if type(id) ~= "string" or not isCount(n) then
			s.progress[id] = nil
		end
	end
	return s
end

-- Starts a new day if the saved one is old. Returns true if it changed anything.
function DailyRules.roll(s: State, day: number): boolean
	if s.day == day then
		return false
	end
	s.day = day
	s.progress = {}
	s.paid = {}
	return true
end

-- Counts `amount` toward every challenge of `kind` that is on today and not paid yet. Caps at the goal.
-- Returns the ids that reached their goal because of this call.
function DailyRules.add(s: State, day: number, kind: string, amount: number): { string }
	DailyRules.roll(s, day)
	local done: { string } = {}
	if not isCount(amount) or amount == 0 then
		return done
	end
	for _, def in DailyRules.pick(day) do
		if def.kind == kind and not s.paid[def.id] then
			local before = s.progress[def.id] or 0
			local after = math.min(def.goal, before + amount)
			if after ~= before then
				s.progress[def.id] = after
				if after >= def.goal then
					table.insert(done, def.id)
				end
			end
		end
	end
	return done
end

-- Challenges that are finished but not paid yet (a payment that failed is tried again later).
function DailyRules.readyToPay(s: State, day: number): { DailyDefs.Def }
	local out: { DailyDefs.Def } = {}
	if s.day ~= day then
		return out
	end
	for _, def in DailyRules.pick(day) do
		if not s.paid[def.id] and (s.progress[def.id] or 0) >= def.goal then
			table.insert(out, def)
		end
	end
	return out
end

-- Marks one of today's challenges paid. False if it is not on today or not finished.
function DailyRules.markPaid(s: State, day: number, id: string): boolean
	if s.day ~= day then
		return false
	end
	for _, def in DailyRules.pick(day) do
		if def.id == id then
			if (s.progress[id] or 0) < def.goal then
				return false
			end
			s.paid[id] = true
			return true
		end
	end
	return false
end

function DailyRules.rewardFor(def: DailyDefs.Def, rewards: { [string]: number }): number
	return rewards[def.tier] or 0
end

-- Once-only receipt key for one challenge on one day (fits Profile/Receipts: letters, digits, _ : . -).
function DailyRules.receiptKey(day: number, id: string): string
	return "d:" .. tostring(day) .. ":" .. id
end

-- What the player sees. `s` may be nil (not loaded): everything shows as 0.
function DailyRules.view(s: State?, day: number, rewards: { [string]: number }): { View }
	local out: { View } = {}
	local current = s ~= nil and s.day == day
	for _, def in DailyRules.pick(day) do
		local progress = if current and s then s.progress[def.id] or 0 else 0
		local paid = if current and s then s.paid[def.id] == true else false
		table.insert(out, {
			id = def.id,
			tier = def.tier,
			kind = def.kind,
			goal = def.goal,
			progress = progress,
			reward = DailyRules.rewardFor(def, rewards),
			paid = paid,
		})
	end
	return out
end

return DailyRules
