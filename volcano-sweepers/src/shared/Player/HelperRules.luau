--!strict
-- Helper bot rules, all pure: how much ash a bot sweeps, what that pays, where bots stand around
-- their owner, how many bots get a visible body. The HelperService only moves Models and calls this.
--
-- Pay: a bot's coins = ash value x PAY_SHARE x derived.helperMult x derived.sellMult, paid straight
-- to the owner (never the backpack). PAY_SHARE is 1 because Catalog/Helpers already bakes the
-- "bots earn about 35% of a hand sweeper" rate into unitsPerSecond (the balance sim uses it as is).
-- Only zones the owner has opened are swept.

local Config = require("../Config")
local AshGrid = require("../Ash/AshGrid")
local Helpers = require("../Catalog/Helpers")
local Rng = require("../Rng")
local Zones = require("../Catalog/Zones")

local HelperRules = {}

HelperRules.PAY_SHARE = 1
HelperRules.SWEEP_RADIUS = 14 -- studs around the bot where it picks cells
HelperRules.MAX_VISIBLE = 60 -- bot bodies per server
HelperRules.TELEPORT_DISTANCE = 80 -- owner farther than this: the bot jumps next to them
HelperRules.FLOAT_SECONDS = 2 -- at most one "+12" per bot this often
HelperRules.MAX_DT = 2 -- a lag spike never pays more than this many seconds

local function finite(n: number): number
	if n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return n
end

-- The zones an owner may be paid for: { [zoneId] = true } from profile.zones ("1".."5" keys).
function HelperRules.allowedZones(zones: { [string]: boolean }): { [number]: boolean }
	local out: { [number]: boolean } = {}
	for _, zone in Zones.list do
		if zones[tostring(zone.id)] == true then
			out[zone.id] = true
		end
	end
	return out
end

-- Whole ash units one bot has earned after `dt` more seconds. `carry` is the fraction left over
-- from before. Returns (wholeUnits, newCarry).
function HelperRules.accrue(carry: number, level: number, dt: number): (number, number)
	local step = math.clamp(finite(dt), 0, HelperRules.MAX_DT)
	local total = math.max(0, finite(carry)) + Helpers.unitsPerSecond(level) * step
	local whole = math.floor(total)
	return whole, total - whole
end

export type Tick = {
	units: number, -- ash units taken off the ground
	valueUnits: number, -- those units x zone value (before any multiplier)
	cleared: number, -- cells that reached bare ground
}

-- Takes up to `units` ash units from random non-empty cells within SWEEP_RADIUS of (x, z), only in
-- allowed zones, never from golden cells (those are for the players). One unit at a time, so a bot
-- spreads its work over its neighbourhood.
function HelperRules.sweepAround(
	grid: AshGrid.AshGrid,
	x: number,
	z: number,
	units: number,
	allowed: { [number]: boolean },
	rng: Rng.Rng
): Tick
	local result: Tick = { units = 0, valueUnits = 0, cleared = 0 }
	local want = math.floor(finite(units))
	if want <= 0 then
		return result
	end
	local zoneOf = grid.layout.zone
	local candidates: { number } = {}
	for _, i in grid.layout.cellsInRadius(x, z, HelperRules.SWEEP_RADIUS) do
		if grid:get(i) > 0 and allowed[zoneOf[i]] == true and not grid:isGolden(i) then
			table.insert(candidates, i)
		end
	end
	while want > 0 and #candidates > 0 do
		local k = rng:int(1, #candidates)
		local cell = candidates[k]
		local took = grid:remove(cell, 1)
		if took > 0 then
			want -= took
			result.units += took
			result.valueUnits += took * Zones.valueOf(zoneOf[cell])
		end
		if grid:get(cell) <= 0 then
			result.cleared += 1
			candidates[k] = candidates[#candidates]
			candidates[#candidates] = nil
		end
	end
	return result
end

-- Coins (fractional) for `valueUnits` of swept ash.
function HelperRules.coinsFor(valueUnits: number, helperMult: number, sellMult: number): number
	local v = math.max(0, finite(valueUnits))
	return v
		* HelperRules.PAY_SHARE
		* math.max(0, finite(helperMult))
		* math.max(0, finite(sellMult))
end

-- Splits pending fractional coins into (wholeCoinsToPay, remainderToKeep).
function HelperRules.settle(pending: number): (number, number)
	local p = math.max(0, finite(pending))
	local whole = math.floor(p)
	return whole, p - whole
end

-- Where bot number `index` of `count` stands, in the owner's own frame: x = right, z = behind.
-- A loose fan behind the owner. Returns (x, z) in studs.
function HelperRules.formationOffset(index: number, count: number): (number, number)
	local spread = 0.55 -- radians between neighbours
	local angle = (index - (count + 1) / 2) * spread
	local radius = 5 + (index % 2) * 1.5
	return radius * math.sin(angle), radius * math.cos(angle)
end

-- Little up-and-down float for a bot (studs). Different phase for every bot.
function HelperRules.bob(t: number, index: number): number
	return 0.35 * math.sin(t * 2.2 + index * 1.3)
end

-- Share (0..1) of the way a bot moves toward its spot this step. Frame-rate independent.
function HelperRules.followAlpha(dt: number): number
	return 1 - math.exp(-6 * math.clamp(finite(dt), 0, 1))
end

function HelperRules.shouldTeleport(distance: number): boolean
	return finite(distance) > HelperRules.TELEPORT_DISTANCE
end

function HelperRules.canShowFloat(lastAt: number, now: number): boolean
	return now - lastAt >= HelperRules.FLOAT_SECONDS
end

-- "+12", "+1.2K", "+3.4M"
function HelperRules.floatText(coins: number): string
	local n = math.max(0, math.floor(finite(coins)))
	if n < 1000 then
		return `+{n}`
	elseif n < 1000000 then
		return `+{math.floor(n / 100) / 10}K`
	end
	return `+{math.floor(n / 100000) / 10}M`
end

-- How many bot bodies each owner gets, so the server total never passes `cap`. Everybody gets one
-- before anybody gets two, and so on. counts[i] = bots owner i has; result[i] = visible bodies.
function HelperRules.allocateVisible(counts: { number }, cap: number): { number }
	local out: { number } = table.create(#counts, 0)
	local left = math.max(0, math.floor(finite(cap)))
	local moved = true
	while left > 0 and moved do
		moved = false
		for i, want in counts do
			if left > 0 and out[i] < want then
				out[i] += 1
				left -= 1
				moved = true
			end
		end
	end
	return out
end

-- Studs above the ground a bot hovers at (its body radius plus a gap).
HelperRules.hoverHeight = Config.World.groundY + 1.9

return HelperRules
