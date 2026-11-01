--!strict
-- Pure logic for the "+N" numbers that pop out of every swing (client/Vfx/WorldFeel draws them).
-- No Roblox types, so Lune can test it.
--
-- The server never echoes your own swing, so the number comes from the Store: every time `carried`
-- (units) / `carriedValue` (coins before multipliers) go UP, the gain is added to an accumulator.
-- The accumulator is flushed at most every `gap` seconds, so a fast tool shows one number per
-- swing-ish instead of a blizzard of tiny ones.
--
-- The number shown is what the gain is WORTH in coins (carriedValue x sellMult), because that is
-- what makes progress visible: the same 2 units read "+2" on the beach and "+120" in the Lava Heart.
-- Colour follows the richest zone of the swing; golden cells (worth 5x) pop bigger and in gold.
--
--   FloatLogic.new() -> Acc
--   FloatLogic.add(acc, dUnits, dValue, zoneValue)    ignores gains <= 0 and bad numbers
--   FloatLogic.ready(acc, now, gap) -> boolean         something to show and the gap has passed
--   FloatLogic.take(acc, now, sellMult) -> Pop?        empties the accumulator
--   FloatLogic.style(pop) -> { text, color, scale }    what to draw
--   FloatLogic.becameFull(oldCarried, newCarried, capacity) -> boolean

export type Acc = {
	units: number,
	value: number,
	zoneValue: number, -- richest zone value seen since the last flush
	golden: boolean,
	lastFlush: number,
}

export type Pop = {
	amount: number, -- coins worth, whole number >= 1
	units: number,
	zoneValue: number,
	golden: boolean,
}

export type Style = { text: string, color: string, scale: number }

local FloatLogic = {}

-- A gain whose coins-per-unit is this many times the zone value can only come from golden cells
-- (worth 5x). Neighbouring zones differ by at most ~3x, so a swing across a zone edge never trips it.
FloatLogic.GOLD_RATIO = 3.5
FloatLogic.GOLD_COLOR = "#FFD23F"

-- Colour per zone value tier (1 beach .. 60 lava heart). Bright and readable over sand, grass, water,
-- red rock and black glass (every float has a dark outline too).
local TIERS: { { minValue: number, color: string } } = {
	{ minValue = 60, color = "#FF7AE0" }, -- Lava Heart: hot pink
	{ minValue = 22, color = "#FFA05C" }, -- Crater Rim: orange
	{ minValue = 8, color = "#7FE8F5" }, -- Hot Springs: aqua
	{ minValue = 3, color = "#A8F07A" }, -- Fern Forest: leaf green
	{ minValue = 0, color = "#FFF6E6" }, -- Sunny Beach: warm white
}

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -1e15 and v < 1e15
end

function FloatLogic.new(): Acc
	return { units = 0, value = 0, zoneValue = 0, golden = false, lastFlush = -math.huge }
end

function FloatLogic.add(acc: Acc, dUnits: number, dValue: number, zoneValue: number)
	if not finite(dUnits) or dUnits <= 0 then
		return
	end
	local value = if finite(dValue) and dValue > 0 then dValue else 0
	local zv = if finite(zoneValue) and zoneValue > 0 then zoneValue else 0
	acc.units += dUnits
	acc.value += value
	if zv > acc.zoneValue then
		acc.zoneValue = zv
	end
	if zv > 0 and value >= dUnits * zv * FloatLogic.GOLD_RATIO then
		acc.golden = true
	end
end

function FloatLogic.ready(acc: Acc, now: number, gap: number): boolean
	return acc.units > 0 and now - acc.lastFlush >= gap
end

function FloatLogic.take(acc: Acc, now: number, sellMult: number?): Pop?
	if acc.units <= 0 then
		return nil
	end
	local mult = if finite(sellMult) and (sellMult :: number) > 0 then sellMult :: number else 1
	-- no value known (old server or zero-value zone): fall back to the units themselves
	local worth = if acc.value > 0 then acc.value * mult else acc.units
	local pop: Pop = {
		amount = math.max(1, math.floor(worth + 0.5)),
		units = acc.units,
		zoneValue = acc.zoneValue,
		golden = acc.golden,
	}
	acc.units = 0
	acc.value = 0
	acc.zoneValue = 0
	acc.golden = false
	acc.lastFlush = now
	return pop
end

function FloatLogic.tierColor(zoneValue: number): string
	for _, tier in TIERS do
		if zoneValue >= tier.minValue then
			return tier.color
		end
	end
	return TIERS[#TIERS].color
end

-- 1234 -> "1.2K" (same rules as StoreLogic.formatNumber, kept local so this file stands alone).
local SUFFIX = { "K", "M", "B", "T" }
local function short(n: number): string
	if n < 1000 then
		return tostring(math.floor(n + 0.5))
	end
	local tier = 0
	local v = n
	while v >= 1000 and tier < #SUFFIX do
		v /= 1000
		tier += 1
	end
	local text = string.format("%.1f", v)
	if string.sub(text, -2) == ".0" then
		text = string.sub(text, 1, -3)
	end
	return text .. SUFFIX[tier]
end

-- Bigger gains are drawn bigger: x0.85 for "+1", about x1.3 for "+1000", capped at x1.6.
-- Golden pops get an extra x1.25 and the gold colour.
function FloatLogic.style(pop: Pop): Style
	local scale = 0.85 + 0.15 * math.log10(math.max(pop.amount, 1))
	if pop.golden then
		scale *= 1.25
	end
	return {
		text = "+" .. short(pop.amount),
		color = if pop.golden then FloatLogic.GOLD_COLOR else FloatLogic.tierColor(pop.zoneValue),
		scale = math.clamp(scale, 0.85, 1.6),
	}
end

-- True only on the change that fills the backpack (so "FULL!" pops once per fill).
function FloatLogic.becameFull(oldCarried: any, newCarried: any, capacity: any): boolean
	if not (finite(oldCarried) and finite(newCarried) and finite(capacity)) then
		return false
	end
	if capacity <= 0 then
		return false
	end
	return oldCarried < capacity and newCarried >= capacity
end

return FloatLogic
