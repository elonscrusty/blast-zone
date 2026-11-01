--!strict
-- Turns a saved Profile (+ live buffs) into the numbers the game uses. Pure; server and client
-- agree because both call this. The client only DISPLAYS the server's result.
--
-- SELL MULTIPLIER (exact formula):
--   sellMult = (1 + upgradeSellBonus + setBonuses + sparkBonus(sparks)) x party x perfect
--     upgradeSellBonus = Upgrades.effect("sell", level)               (+5% per level, max +100%)
--     setBonuses       = sum of Finds.sets[].reward for sets in profile.setsClaimed
--     sparkBonus(n)    = cap x (1 - exp(-0.05 x n / cap)), cap = Config.Economy.sparkBonusCap (9)
--                        so each Spark is +5% at first (additive) and the Spark part never passes
--                        +900% (x10 total with the base 1). n = Sparks earned so far = unspent
--                        Sparks + Sparks spent on perks, so buying perks never lowers your bonus.
--     party   = Config.Economy.partyMult (2.0)    only while buffs.party   > now
--     perfect = Config.Economy.perfectMult (1.25) only while buffs.perfect > now
--     golden  = NO multiplier: golden cells are worth 5x in the cell itself (ash value)
-- Other stats:
--   reach    = tool.reach x (1 + reach bonus)            arcDeg = tool.arcDeg
--   power    = tool.power x (1 + power bonus)            (fractions are rolled by the server)
--   interval = max(minInterval, tool.interval / (1 + speed bonus))
--   capacity = floor((baseCapacity + tool.capacityBonus + perk big_pockets) x (1 + backpack bonus))
--   walkSpeed= (baseWalkSpeed + perk quick_feet) x (1 + walk bonus)
--   luck     = 1 + luck bonus + perk lucky_charm         (multiplier on treasure chance)
--   armor    = min(maxArmor, armor bonus)                (share of carried ash kept when hit)
--   melt     = tool.melt (0 for most tools): cells left with this many units or fewer melt away
-- Extras beyond Types.Derived (extra fields are fine for the client): sweetChance, luckyChance,
-- helperMult, buffTime, melt.

local Config = require("../Config")
local Types = require("../Types")
local Finds = require("../Catalog/Finds")
local SparkPerks = require("../Catalog/SparkPerks")
local Tools = require("../Catalog/Tools")
local Upgrades = require("../Catalog/Upgrades")

export type Full = {
	reach: number,
	arcDeg: number,
	power: number,
	interval: number,
	capacity: number,
	walkSpeed: number,
	sellMult: number,
	luck: number,
	armor: number,
	sweetChance: number, -- 0..1 chance a swing clears double
	luckyChance: number, -- 0..1 chance a sale pays double
	helperMult: number, -- multiplier on helper bot output
	buffTime: number, -- multiplier on how long Party / Perfect buffs last
	melt: number, -- tool trait: a cell left with <= this many units after a swing melts (0 = none)
}

local StatsCalc = {}

-- The Spark part of the sell multiplier for `sparks` Sparks (0 at 0 Sparks).
function StatsCalc.sparkBonus(sparks: number): number
	if sparks ~= sparks or sparks <= 0 then
		return 0
	end
	local cap = Config.Economy.sparkBonusCap
	return cap * (1 - math.exp(-Config.Economy.sparkBonusEach * sparks / cap))
end

-- Sum of the permanent sell bonuses of every claimed find set.
function StatsCalc.setBonus(setsClaimed: { [string]: boolean }): number
	local total = 0
	for _, set in Finds.sets do
		if setsClaimed[set.id] == true then
			total += set.reward
		end
	end
	return total
end

local function level(map: { [string]: number }, id: string): number
	local v = map[id]
	if type(v) ~= "number" or v ~= v then
		return 0
	end
	return math.clamp(math.floor(v), 0, Config.Economy.maxLevelCap)
end

local function active(buffs: { [string]: number }, id: string, now: number): boolean
	local endsAt = buffs[id]
	return type(endsAt) == "number" and endsAt > now
end

-- Sparks earned over all Cool Downs: the unspent balance plus what the perks cost.
function StatsCalc.totalSparks(profile: Types.Profile): number
	return math.max(0, profile.sparks) + SparkPerks.spent(profile.sparkPerks)
end

function StatsCalc.compute(profile: Types.Profile, buffs: { [string]: number }, now: number): Full
	local tool = Tools.byId[profile.tool] or Tools.list[1]
	local up = function(id: string): number
		return Upgrades.effect(id, level(profile.upgrades, id))
	end
	local perk = function(id: string): number
		return SparkPerks.value(id, level(profile.sparkPerks, id))
	end

	local sellMult = 1 + up("sell") + StatsCalc.setBonus(profile.setsClaimed)
	sellMult += StatsCalc.sparkBonus(StatsCalc.totalSparks(profile))
	if active(buffs, "party", now) then
		sellMult *= Config.Economy.partyMult
	end
	if active(buffs, "perfect", now) then
		sellMult *= Config.Economy.perfectMult
	end

	local capacity = (Config.Player.baseCapacity + tool.capacityBonus + perk("big_pockets"))
		* (1 + up("backpack"))

	return {
		reach = tool.reach * (1 + up("reach")),
		arcDeg = tool.arcDeg,
		power = tool.power * (1 + up("power")),
		interval = math.max(Config.Player.minInterval, tool.interval / (1 + up("speed"))),
		capacity = math.floor(capacity),
		walkSpeed = (Config.Player.baseWalkSpeed + perk("quick_feet")) * (1 + up("walk")),
		sellMult = sellMult,
		luck = 1 + up("luck") + perk("lucky_charm"),
		armor = math.clamp(up("armor"), 0, Config.Player.maxArmor),
		sweetChance = math.clamp(up("sweetspot"), 0, 1),
		luckyChance = math.clamp(up("lucky_coins"), 0, 1),
		helperMult = 1 + perk("bot_boost"),
		buffTime = 1 + perk("long_buffs"),
		melt = tool.melt or 0,
	}
end

return StatsCalc
