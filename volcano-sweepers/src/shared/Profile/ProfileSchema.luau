--!strict
-- What a saved Volcano Sweepers profile looks like, how a stored one is cleaned, and how an old
-- one is brought up to date. Pure Luau (Lune tests it).
--
--   default()              a fresh Types.Profile for a new player. Always a new copy.
--   sanitize(raw)          ANY value in, a clean valid Types.Profile out. Never throws. Wrong types,
--                          NaN, inf, negatives and huge numbers are fixed or capped, unknown keys
--                          dropped, missing keys filled from default().
--   isValid(profile)       independent strict check of the shape sanitize promises: true, or false
--                          and the first problem found. sanitize(x) always passes it.
--   migrate(raw, from)     runs steps[from], steps[from+1], ... up to the current SaveVersion.
--   prepare(raw)           what a load uses: migrate + sanitize, refusing a NEWER save ("future").
--
-- Saved shape rules (DataStore safe): string keys only, no arrays, no NaN / inf, small numbers.
-- Unknown item ids (tools, upgrades, finds, ...) are KEPT when they look like an id, so an item
-- removed from the game later does not delete what a player owns; their values are still checked.

local Config = require("../Config")
local Types = require("../Types")

local Schema = {}

Schema.CURRENT = Config.Game.SaveVersion

-- Every top-level field of Types.Profile. Anything else is dropped by sanitize.
Schema.KEYS = {
	"version",
	"coins",
	"runCoins",
	"lifetimeCoins",
	"sparks",
	"coolDowns",
	"tool",
	"toolsOwned",
	"upgrades",
	"zones",
	"helpers",
	"helperLevel",
	"sparkPerks",
	"finds",
	"setsClaimed",
	"goalsClaimed",
	"daily",
	"stats",
	"settings",
	"tutorialDone",
} :: { string }

Schema.STAT_KEYS = {
	"ashSwept",
	"unitsSold",
	"sellCount",
	"findsTotal",
	"burpHits",
	"burpDodged",
	"cleared",
	"playSeconds",
} :: { string }

Schema.SETTING_KEYS = { "music", "sfx", "autoSweep", "shake", "vibrate" } :: { string }

Schema.START_TOOL = "twig_broom"
Schema.ZONE_COUNT = 5

-- Caps. Anything bigger is clamped; the numbers are far above anything play can reach.
Schema.MAX = {
	coins = 1e15, -- stays exact in a double (< 2^53)
	stat = 1e15,
	sparks = 1e9,
	coolDowns = 1e6,
	helpers = 6,
	helperLevel = 50,
	upgradeLevel = 50,
	perkLevel = 50,
	findCount = 1e9,
	day = 100000, -- days since 1970: year 2243
	streak = 9999,
	idLength = 40,
	entries = 100, -- per id map
}

export type Data = { [string]: any }
export type Steps = { [number]: (any) -> any }

local MAX = Schema.MAX

-- ===== small helpers =====

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A finite number inside lo..hi (clamped); anything else gives `fallback`.
local function number_(v: any, fallback: number, lo: number, hi: number): number
	if not isFinite(v) then
		return fallback
	end
	return math.clamp(v :: number, lo, hi) + 0 -- "+ 0" turns -0 into 0
end

local function integer(v: any, fallback: number, lo: number, hi: number): number
	if not isFinite(v) then
		return fallback
	end
	return math.clamp(math.floor(v :: number), lo, hi) + 0
end

local function bool(v: any, fallback: boolean): boolean
	if type(v) == "boolean" then
		return v
	end
	return fallback
end

function Schema.isId(id: any): boolean
	return type(id) == "string"
		and #id >= 1
		and #id <= MAX.idLength
		and string.match(id, "^[a-z][a-z0-9_]*$") ~= nil
end

function Schema.isZoneKey(key: any): boolean
	if type(key) ~= "string" then
		return false
	end
	for i = 1, Schema.ZONE_COUNT do
		if key == tostring(i) then
			return true
		end
	end
	return false
end

-- Id-shaped string keys of `raw`, sorted (so what survives the entries cap never depends on
-- table order).
local function idKeys(raw: any): { string }
	local keys: { string } = {}
	if type(raw) == "table" then
		for k in raw :: { [any]: any } do
			if Schema.isId(k) then
				table.insert(keys, k :: string)
			end
		end
	end
	table.sort(keys)
	return keys
end

local function cleanFlags(raw: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local count = 0
	for _, k in idKeys(raw) do
		if count >= MAX.entries then
			break
		end
		if (raw :: any)[k] == true then
			out[k] = true
			count += 1
		end
	end
	return out
end

local function cleanLevels(raw: any, hi: number): { [string]: number }
	local out: { [string]: number } = {}
	local count = 0
	for _, k in idKeys(raw) do
		if count >= MAX.entries then
			break
		end
		local level = integer((raw :: any)[k], 0, 0, hi)
		if level > 0 then
			out[k] = level
			count += 1
		end
	end
	return out
end

-- ===== default =====

function Schema.default(): Types.Profile
	return {
		version = Schema.CURRENT,
		coins = 0,
		runCoins = 0,
		lifetimeCoins = 0,
		sparks = 0,
		coolDowns = 0,
		tool = Schema.START_TOOL,
		toolsOwned = { [Schema.START_TOOL] = true },
		upgrades = {},
		zones = { ["1"] = true },
		helpers = 0,
		helperLevel = 0,
		sparkPerks = {},
		finds = {},
		setsClaimed = {},
		goalsClaimed = {},
		daily = { lastDay = 0, streak = 0 },
		stats = {
			ashSwept = 0,
			unitsSold = 0,
			sellCount = 0,
			findsTotal = 0,
			burpHits = 0,
			burpDodged = 0,
			cleared = 0,
			playSeconds = 0,
		},
		settings = {
			music = true,
			sfx = true,
			autoSweep = false,
			shake = true,
			vibrate = true,
		},
		tutorialDone = false,
	}
end

-- ===== sanitize =====

-- Accepts any value. Reads only the known keys, so junk (loops, functions, deep tables) elsewhere
-- is simply ignored.
function Schema.sanitize(raw: any): Types.Profile
	local src: any = raw
	if type(raw) == "table" then
		local v = (raw :: any).version
		local from = if isFinite(v) then math.max(0, math.floor(v :: number)) else 0
		if from < Schema.CURRENT then
			local moved = Schema.migrate(raw, from)
			if moved ~= nil then
				src = moved
			end
		end
	end
	if type(src) ~= "table" then
		return Schema.default()
	end
	local s = src :: { [string]: any }
	local def = Schema.default()

	local toolsOwned = cleanFlags(s.toolsOwned)
	toolsOwned[Schema.START_TOOL] = true

	local tool = Schema.START_TOOL
	if Schema.isId(s.tool) and toolsOwned[s.tool :: string] == true then
		tool = s.tool :: string
	end

	local zones: { [string]: boolean } = { ["1"] = true }
	if type(s.zones) == "table" then
		for i = 1, Schema.ZONE_COUNT do
			if (s.zones :: any)[tostring(i)] == true then
				zones[tostring(i)] = true
			end
		end
	end

	local rawDaily: any = if type(s.daily) == "table" then s.daily else {}
	local rawStats: any = if type(s.stats) == "table" then s.stats else {}
	local rawSettings: any = if type(s.settings) == "table" then s.settings else {}

	local stats: { [string]: number } = {}
	for _, key in Schema.STAT_KEYS do
		stats[key] = number_(rawStats[key], 0, 0, MAX.stat)
	end
	local settings: { [string]: boolean } = {}
	for _, key in Schema.SETTING_KEYS do
		settings[key] = bool(rawSettings[key], (def.settings :: any)[key])
	end

	local out = {
		version = Schema.CURRENT,
		coins = number_(s.coins, 0, 0, MAX.coins),
		runCoins = number_(s.runCoins, 0, 0, MAX.coins),
		lifetimeCoins = number_(s.lifetimeCoins, 0, 0, MAX.coins),
		sparks = integer(s.sparks, 0, 0, MAX.sparks),
		coolDowns = integer(s.coolDowns, 0, 0, MAX.coolDowns),
		tool = tool,
		toolsOwned = toolsOwned,
		upgrades = cleanLevels(s.upgrades, MAX.upgradeLevel),
		zones = zones,
		helpers = integer(s.helpers, 0, 0, MAX.helpers),
		helperLevel = integer(s.helperLevel, 0, 0, MAX.helperLevel),
		sparkPerks = cleanLevels(s.sparkPerks, MAX.perkLevel),
		finds = cleanLevels(s.finds, MAX.findCount),
		setsClaimed = cleanFlags(s.setsClaimed),
		goalsClaimed = cleanFlags(s.goalsClaimed),
		daily = {
			lastDay = integer(rawDaily.lastDay, 0, 0, MAX.day),
			streak = integer(rawDaily.streak, 0, 0, MAX.streak),
		},
		stats = stats,
		settings = settings,
		tutorialDone = bool(s.tutorialDone, false),
	}
	return out :: any
end

-- ===== isValid =====

local function exactKeys(t: { [any]: any }, allowed: { string }): string?
	local set: { [string]: boolean } = {}
	for _, k in allowed do
		set[k] = true
		if t[k] == nil then
			return "missing " .. k
		end
	end
	for k in t do
		if type(k) ~= "string" or not set[k] then
			return "unknown key " .. tostring(k)
		end
	end
	return nil
end

local function badNumber(v: any, lo: number, hi: number, whole: boolean): boolean
	if not isFinite(v) then
		return true
	end
	local n = v :: number
	if n < lo or n > hi then
		return true
	end
	return whole and n ~= math.floor(n)
end

local function checkIdMap(map: any, kind: string, hi: number?): string?
	if type(map) ~= "table" then
		return "not a table"
	end
	local count = 0
	for k, v in map :: { [any]: any } do
		count += 1
		if count > MAX.entries then
			return "too many entries"
		end
		if not Schema.isId(k) then
			return "bad id " .. tostring(k)
		end
		if kind == "flag" then
			if type(v) ~= "boolean" then
				return "value of " .. k .. " is not a boolean"
			end
		elseif badNumber(v, 0, hi :: number, true) then
			return "value of " .. k .. " is not a whole number in range"
		end
	end
	return nil
end

-- Returns true, or false and the first problem found ("coins: ...").
function Schema.isValid(p: any): (boolean, string?)
	if type(p) ~= "table" then
		return false, "not a table"
	end
	local t = p :: { [any]: any }
	local problem = exactKeys(t, Schema.KEYS)
	if problem then
		return false, problem
	end
	if t.version ~= Schema.CURRENT then
		return false, "version"
	end
	for _, k in { "coins", "runCoins", "lifetimeCoins" } do
		if badNumber(t[k], 0, MAX.coins, false) then
			return false, k
		end
	end
	if badNumber(t.sparks, 0, MAX.sparks, true) then
		return false, "sparks"
	end
	if badNumber(t.coolDowns, 0, MAX.coolDowns, true) then
		return false, "coolDowns"
	end
	if badNumber(t.helpers, 0, MAX.helpers, true) then
		return false, "helpers"
	end
	if badNumber(t.helperLevel, 0, MAX.helperLevel, true) then
		return false, "helperLevel"
	end
	if type(t.tutorialDone) ~= "boolean" then
		return false, "tutorialDone"
	end

	-- tools
	problem = checkIdMap(t.toolsOwned, "flag")
	if problem then
		return false, "toolsOwned: " .. problem
	end
	if t.toolsOwned[Schema.START_TOOL] ~= true then
		return false, "toolsOwned: the starter tool must be owned"
	end
	if not Schema.isId(t.tool) or t.toolsOwned[t.tool] ~= true then
		return false, "tool: not an owned tool"
	end

	-- id maps
	problem = checkIdMap(t.upgrades, "level", MAX.upgradeLevel)
	if problem then
		return false, "upgrades: " .. problem
	end
	problem = checkIdMap(t.sparkPerks, "level", MAX.perkLevel)
	if problem then
		return false, "sparkPerks: " .. problem
	end
	problem = checkIdMap(t.finds, "level", MAX.findCount)
	if problem then
		return false, "finds: " .. problem
	end
	problem = checkIdMap(t.setsClaimed, "flag")
	if problem then
		return false, "setsClaimed: " .. problem
	end
	problem = checkIdMap(t.goalsClaimed, "flag")
	if problem then
		return false, "goalsClaimed: " .. problem
	end

	-- zones: keys "1".."5" only, values booleans, zone 1 always open
	if type(t.zones) ~= "table" then
		return false, "zones"
	end
	for k, v in t.zones :: { [any]: any } do
		if not Schema.isZoneKey(k) or type(v) ~= "boolean" then
			return false, "zones: bad entry " .. tostring(k)
		end
	end
	if t.zones["1"] ~= true then
		return false, "zones: zone 1 must be open"
	end

	-- daily
	if type(t.daily) ~= "table" then
		return false, "daily"
	end
	problem = exactKeys(t.daily, { "lastDay", "streak" })
	if problem then
		return false, "daily: " .. problem
	end
	if badNumber(t.daily.lastDay, 0, MAX.day, true) then
		return false, "daily.lastDay"
	end
	if badNumber(t.daily.streak, 0, MAX.streak, true) then
		return false, "daily.streak"
	end

	-- stats
	if type(t.stats) ~= "table" then
		return false, "stats"
	end
	problem = exactKeys(t.stats, Schema.STAT_KEYS)
	if problem then
		return false, "stats: " .. problem
	end
	for _, k in Schema.STAT_KEYS do
		if badNumber(t.stats[k], 0, MAX.stat, false) then
			return false, "stats." .. k
		end
	end

	-- settings
	if type(t.settings) ~= "table" then
		return false, "settings"
	end
	problem = exactKeys(t.settings, Schema.SETTING_KEYS)
	if problem then
		return false, "settings: " .. problem
	end
	for _, k in Schema.SETTING_KEYS do
		if type(t.settings[k]) ~= "boolean" then
			return false, "settings." .. k
		end
	end
	return true, nil
end

-- ===== plain-data helpers (also used by the store) =====

-- Bounded deep copy of plain data. Functions and the like become nil; loops and huge tables are
-- cut off instead of throwing, so junk can be copied safely before a migration step edits it.
local function safeCopy(v: any, depth: number, budget: { number }): any
	local kind = type(v)
	if kind == "number" or kind == "string" or kind == "boolean" then
		return v
	end
	if kind ~= "table" or depth > 4 or budget[1] <= 0 then
		return nil
	end
	local out: { [any]: any } = {}
	for k, child in v :: { [any]: any } do
		budget[1] -= 1
		if budget[1] <= 0 then
			break
		end
		local kk = type(k)
		if kk == "string" or kk == "number" then
			out[k] = safeCopy(child, depth + 1, budget)
		end
	end
	return out
end

-- Deep equality of plain data (numbers by value, so NaN is never equal).
function Schema.equal(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in a :: { [any]: any } do
		if not Schema.equal(v, (b :: { [any]: any })[k]) then
			return false
		end
	end
	for k in b :: { [any]: any } do
		if (a :: { [any]: any })[k] == nil then
			return false
		end
	end
	return true
end

-- Empties `target` and fills it with a copy of `source`, keeping the table itself (other code may
-- hold it). Both are plain profile data.
function Schema.assign(target: { [any]: any }, source: { [any]: any })
	for k in table.clone(target) do
		target[k] = nil
	end
	local function copy(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out: { [any]: any } = {}
		for k, child in v :: { [any]: any } do
			out[k] = copy(child)
		end
		return out
	end
	for k, v in source do
		target[k] = copy(v)
	end
end

-- ===== migrate =====

-- steps[n] upgrades a profile from version n to n + 1. It receives a private copy, returns the
-- upgraded table. Version 0 is the first prototype's save (money / broom / tools list).
Schema.steps = {
	[0] = function(old: any): any
		if old.coins == nil and type(old.money) == "number" then
			old.coins = old.money
		end
		old.money = nil
		if old.tool == nil and type(old.broom) == "string" then
			old.tool = old.broom
		end
		old.broom = nil
		if old.toolsOwned == nil and type(old.tools) == "table" then
			local owned: { [string]: boolean } = {}
			for _, id in old.tools do
				if type(id) == "string" then
					owned[id] = true
				end
			end
			old.toolsOwned = owned
		end
		old.tools = nil
		return old
	end,
} :: Steps

-- Returns the upgraded copy, or nil and why: "corrupt" (not a table), "future" (saved by a newer
-- game), "noStep" (a version has no step), "error" (a step threw). `raw` is never changed.
function Schema.migrate(
	raw: any,
	fromVersion: number,
	target: number?,
	steps: Steps?
): (any?, string?)
	if type(raw) ~= "table" then
		return nil, "corrupt"
	end
	local goal = target or Schema.CURRENT
	local list = steps or Schema.steps
	local version = if isFinite(fromVersion) then math.max(0, math.floor(fromVersion)) else 0
	if version > goal then
		return nil, "future"
	end
	local data = safeCopy(raw, 0, { 20000 }) :: any
	while version < goal do
		local step = list[version]
		if step == nil then
			return nil, "noStep"
		end
		local ok, result = pcall(step, data)
		if not ok or type(result) ~= "table" then
			return nil, "error"
		end
		data = result
		version += 1
		data.version = version
	end
	return data, nil
end

-- What a load runs on the stored data: refuses a newer save, otherwise returns the clean profile
-- and whether it differs from what was stored (so the caller can save the repair).
-- Returns profile, nil, changed   or   nil, "future" | "corrupt", false
function Schema.prepare(raw: any): (Types.Profile?, string?, boolean)
	if type(raw) ~= "table" then
		return nil, "corrupt", false
	end
	local v = (raw :: any).version
	if isFinite(v) and (v :: number) > Schema.CURRENT then
		return nil, "future", false
	end
	local clean = Schema.sanitize(raw)
	return clean, nil, not Schema.equal(raw, clean)
end

return Schema
