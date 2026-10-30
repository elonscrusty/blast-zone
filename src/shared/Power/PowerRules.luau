--!strict
-- Power rating (video 3 gap #16): ONE number that says how far a player has come. Pure rules, no Roblox, so Lune
-- tests it. It is a show-off number only. Nothing in combat, loot or matchmaking reads it, so it can never be
-- Robux power: it is built only from things earned by playing (account level, looks unlocked with coins, wins,
-- eliminations, matches). Every part has a cap, so no single habit can run away with the number.

local Config = require("../Config")
local LevelRules = require("../Level/LevelRules")
local TrackDefs = require("../Progression/TrackDefs")

local PowerRules = {}

export type Inputs = {
	level: number, -- account level (1 up)
	looks: number, -- looks owned beyond the free ones (store tiers and level gifts)
	wins: number,
	eliminations: number,
	matches: number,
}

export type Part = {
	id: string, -- "level" | "looks" | "wins" | "eliminations" | "matches"
	count: number, -- what the player has (already cleaned)
	points: number, -- what that is worth, after the cap
	capped: boolean,
}

export type Rating = {
	power: number,
	band: number, -- 1 up; see Config.Power.bands
	toNext: number?, -- points to the next band (nil at the top band)
	parts: { Part },
}

-- Order is the order a screen should list them in.
PowerRules.PART_IDS = { "level", "looks", "wins", "eliminations", "matches" }

-- Display words for a screen to start from. Claude Design may rename them freely; the ids above never change.
PowerRules.LABELS = {
	level = "Level",
	looks = "Looks",
	wins = "Wins",
	eliminations = "Eliminations",
	matches = "Matches",
} :: { [string]: string }

local function whole(v: any): number
	if type(v) ~= "number" or v ~= v then
		return 0
	end
	return math.clamp(math.floor(v), 0, 1e9)
end

-- Raw saved tables -> clean Inputs. `progression` is a ProgressRules.Progression (or junk or nil), `stats` the
-- saved stats table. Never errors, so a broken or missing save just gives a low number.
function PowerRules.inputsFrom(progression: any, stats: any): Inputs
	local level = 1
	local looks = 0
	if type(progression) == "table" then
		level = LevelRules.info(whole(progression.accountXp)).level
		local unlocked = progression.unlocked
		if type(unlocked) == "table" then
			for id, owned in unlocked do
				if owned == true and type(id) == "string" then
					local item = TrackDefs.get(id)
					-- Only real, non-free looks count: unknown ids (a newer game's) and the free ones do not.
					if item ~= nil and item.cost ~= 0 then
						looks += 1
					end
				end
			end
		end
	end
	local s: any = if type(stats) == "table" then stats else {}
	return {
		level = level,
		looks = looks,
		wins = whole(s.wins),
		eliminations = whole(s.eliminations),
		matches = whole(s.matches),
	}
end

local function bandOf(power: number): (number, number?)
	local bands = Config.Power.bands
	local band = 1
	for i, start in bands do
		if power >= start then
			band = i
		end
	end
	local nextStart = bands[band + 1]
	return band, if nextStart then nextStart - power else nil
end

function PowerRules.band(power: number): number
	local band = bandOf(power)
	return band
end

-- The most a player can ever have. Used by tests and by screens that draw a bar.
function PowerRules.maxPower(): number
	local cfg = Config.Power
	local total = (Config.Level.maxLevel - 1) * cfg.perLevel
	for _, id in { "looks", "wins", "eliminations", "matches" } do
		total += cfg.caps[id] * cfg.perUnit[id]
	end
	return total
end

function PowerRules.compute(raw: any): Rating
	local cfg = Config.Power
	local input: any = if type(raw) == "table" then raw else {}
	local counts: { [string]: number } = {
		level = math.clamp(whole(input.level), 1, Config.Level.maxLevel),
		looks = whole(input.looks),
		wins = whole(input.wins),
		eliminations = whole(input.eliminations),
		matches = whole(input.matches),
	}
	local parts: { Part } = {}
	local power = 0
	for _, id in PowerRules.PART_IDS do
		local count = counts[id]
		local points, capped
		if id == "level" then
			-- Level 1 is worth nothing, so a brand new player is at 0.
			points = (count - 1) * cfg.perLevel
			capped = false
		else
			local cap = cfg.caps[id]
			capped = count > cap
			points = math.min(count, cap) * cfg.perUnit[id]
		end
		power += points
		table.insert(parts, { id = id, count = count, points = points, capped = capped })
	end
	local band, toNext = bandOf(power)
	return { power = power, band = band, toNext = toNext, parts = parts }
end

function PowerRules.same(a: Rating?, b: Rating?): boolean
	if a == nil or b == nil then
		return a == b
	end
	if a.power ~= b.power or a.band ~= b.band then
		return false
	end
	for i, part in a.parts do
		local other = b.parts[i]
		if other == nil or other.count ~= part.count or other.points ~= part.points then
			return false
		end
	end
	return true
end

return PowerRules
