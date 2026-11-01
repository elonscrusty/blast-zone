--!strict
-- Helper bots: up to 6, all share one level (0..15). They follow you and sweep nearby ash on their
-- own. Their coins arrive at a reduced rate (shown as little numbers over the bot).
-- Balance target: 6 bots at level 5 earn about 35% of a skilled hand-sweeper with a mid-tier tool.

local Config = require("../Config")

local Helpers = {}

Helpers.max = Config.Economy.maxHelpers
Helpers.maxLevel = Config.Economy.maxHelperLevel

local BASE_UNITS = 0.108 -- ash units per second for ONE bot at level 0
local LEVEL_GROWTH = 1.25 -- each level multiplies the bot's speed
local FIRST_PRICE = 450
local PRICE_GROWTH = 2.6
local UP_BASE = 700
local UP_GROWTH = 1.42

-- Cost of the NEXT bot when you own `ownedCount`, or nil when you own all of them.
function Helpers.price(ownedCount: number): number?
	local owned = math.max(0, math.floor(ownedCount))
	if owned >= Helpers.max then
		return nil
	end
	return math.floor(FIRST_PRICE * PRICE_GROWTH ^ owned + 0.5)
end

-- Cost of the NEXT shared level when your bots are at `level`, or nil at the max level.
function Helpers.upgradeCost(level: number): number?
	local lv = math.max(0, math.floor(level))
	if lv >= Helpers.maxLevel then
		return nil
	end
	return math.floor(UP_BASE * UP_GROWTH ^ lv + 0.5)
end

-- Ash units per second ONE bot sweeps at `level`. With `zoneValue`, returns coins per second
-- (before the sell multiplier) in a zone worth that much per unit.
function Helpers.unitsPerSecond(level: number, zoneValue: number?): number
	local lv = math.clamp(math.floor(level), 0, Helpers.maxLevel)
	local units = BASE_UNITS * LEVEL_GROWTH ^ lv
	if zoneValue then
		return units * zoneValue
	end
	return units
end

-- Coins per second all your bots earn together in a zone worth `zoneValue` per unit.
-- sellMult = Derived.sellMult, helperMult = Derived.helperMult (Spark perk).
function Helpers.coinsPerSecond(
	count: number,
	level: number,
	zoneValue: number,
	sellMult: number,
	helperMult: number
): number
	local n = math.clamp(math.floor(count), 0, Helpers.max)
	return n * Helpers.unitsPerSecond(level, zoneValue) * sellMult * helperMult
end

return Helpers
