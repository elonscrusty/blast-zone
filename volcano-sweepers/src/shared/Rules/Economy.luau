--!strict
-- Selling, Sparks and Cool Down (prestige). Pure: rng and profiles are passed in.

local Config = require("../Config")
local Rng = require("../Rng")
local Types = require("../Types")
local SparkPerks = require("../Catalog/SparkPerks")
local StatsCalc = require("./StatsCalc")

local Economy = {}

-- A brand new profile (what a first-time player starts with). R3's ProfileSchema owns the saved
-- default; this one is for the rules, the balance sim and tests.
function Economy.blankProfile(): Types.Profile
	return {
		version = Config.Game.SaveVersion,
		coins = 0,
		runCoins = 0,
		lifetimeCoins = 0,
		sparks = 0,
		coolDowns = 0,
		tool = "twig_broom",
		toolsOwned = { twig_broom = true },
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
		settings = { music = true, sfx = true, autoSweep = true, shake = true, vibrate = true },
		tutorialDone = false,
	}
end

local function finite(n: number): number
	if n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return n
end

-- What the Trade Hut pays for a backpack worth `carriedValue` coins before multipliers.
-- Returns (coins, bonusCoins, luckyDouble):
--   coins       = total paid, a whole number >= 0 (includes the lucky bonus)
--   bonusCoins  = the extra part that came from Lucky Coins (0 unless luckyDouble)
--   luckyDouble = true when Lucky Coins doubled this sale
-- `derived` needs sellMult and luckyChance (StatsCalc.compute gives both). Uses exactly one rng
-- roll, and only when luckyChance > 0.
function Economy.sellValue(
	carriedValue: number,
	derived: StatsCalc.Full,
	rng: Rng.Rng
): (number, number, boolean)
	local base =
		math.floor(math.max(0, finite(carriedValue)) * math.max(0, finite(derived.sellMult)) + 0.5)
	if base <= 0 then
		return 0, 0, false
	end
	local chance = derived.luckyChance
	if chance > 0 and rng:chance(chance) then
		return base * 2, base, true
	end
	return base, 0, false
end

-- Sparks a Cool Down gives for `runCoins` earned this run. Sublinear (square root) so very long
-- runs help but never explode: floor(sparkScale x sqrt(runCoins / coolDownMinRunCoins)).
function Economy.sparksFor(runCoins: number): number
	local rc = math.max(0, finite(runCoins))
	local e = Config.Economy
	return math.floor(e.sparkScale * math.sqrt(rc / e.coolDownMinRunCoins))
end

-- Cool Down is offered once this run earned enough to be worth at least 1 Spark and the minimum.
function Economy.canCoolDown(profile: Types.Profile): boolean
	return profile.runCoins >= Config.Economy.coolDownMinRunCoins
		and Economy.sparksFor(profile.runCoins) >= 1
end

-- Coins a fresh run starts with (Head Start Spark perk).
function Economy.startingCoins(profile: Types.Profile): number
	return math.floor(SparkPerks.value("head_start", profile.sparkPerks["head_start"] or 0))
end

-- What buying a Spark perk hands over RIGHT NOW (the same things a Cool Down hands over at reset):
-- coins (Head Start: the extra coins that level adds) and a tool id (Free Push Broom).
-- The server adds the coins and marks the tool owned, so a perk bought after a Cool Down helps at
-- once. Returns (coins, toolId or nil). `newLevel` is the level just bought.
function Economy.perkGrant(id: string, newLevel: number): (number, string?)
	if id == "head_start" then
		local gain = SparkPerks.value(id, newLevel) - SparkPerks.value(id, newLevel - 1)
		return math.max(0, math.floor(gain)), nil
	elseif id == "free_push" and newLevel >= 1 then
		return 0, "push_broom"
	end
	return 0, nil
end

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

-- The profile after a Cool Down, and the Sparks gained. Does NOT check canCoolDown (the server
-- does). Always returns a NEW table; the input is not changed.
-- Keeps: version, lifetimeCoins, sparks (+gained), coolDowns (+1), sparkPerks, finds, setsClaimed,
--   goalsClaimed, daily, stats, settings, tutorialDone (and any unknown field).
-- Resets: coins (to the Head Start amount), runCoins 0, tools (Twig Broom, + Push Broom with the
--   Free Push Broom perk), upgrades, zones (only "1"), helpers 0, helperLevel 0.
function Economy.coolDownReset(profile: Types.Profile): (Types.Profile, number)
	local gained = Economy.sparksFor(profile.runCoins)
	local out: Types.Profile = deepCopy(profile) -- also keeps any field this version doesn't know

	local freePush = (profile.sparkPerks["free_push"] or 0) >= 1
	out.sparks = profile.sparks + gained
	out.coolDowns = profile.coolDowns + 1
	out.coins = Economy.startingCoins(profile)
	out.runCoins = 0
	out.tool = if freePush then "push_broom" else "twig_broom"
	out.toolsOwned = if freePush
		then { twig_broom = true, push_broom = true }
		else { twig_broom = true }
	out.upgrades = {}
	out.zones = { ["1"] = true }
	out.helpers = 0
	out.helperLevel = 0
	return out, gained
end

return Economy
