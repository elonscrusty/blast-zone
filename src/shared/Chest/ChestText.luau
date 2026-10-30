--!strict
-- Words for the chest screen (gap 19). Short on purpose. Pure so Lune can test them.

local ChestDefs = require("./ChestDefs")
local TrackDefs = require("../Progression/TrackDefs")

local ChestText = {}

local RARITY_WORDS: { [string]: string } = { common = "Common", rare = "Rare", epic = "Epic" }

function ChestText.rarity(rarity: string): string
	return RARITY_WORDS[rarity] or "Common"
end

local function totalWeight(chest: ChestDefs.Chest): number
	local total = 0
	for _, row in chest.rows do
		total += row.weight
	end
	return total
end

-- The chance of one row, in whole percent (weights add up to 100, so this is the weight).
function ChestText.percent(chest: ChestDefs.Chest, row: ChestDefs.Row): number
	return math.floor(row.weight / totalWeight(chest) * 100 + 0.5)
end

function ChestText.rowName(row: ChestDefs.Row): string
	if row.kind == "look" and row.itemId ~= nil then
		local def = TrackDefs.get(row.itemId)
		return if def ~= nil then def.name else row.id
	end
	return `{row.amount or 0} Scrap`
end

-- One line per row, rarest first, e.g. "Epic  Blaze Dash  4%". Shown BEFORE the player opens anything.
function ChestText.oddsLines(kind: string, currencyName: string): { string }
	local chest = ChestDefs.get(kind)
	if chest == nil then
		return {}
	end
	local rows = table.clone(chest.rows)
	table.sort(rows, function(a, b)
		local ra, rb = ChestDefs.rank(a.rarity), ChestDefs.rank(b.rarity)
		if ra ~= rb then
			return ra > rb
		end
		if a.weight ~= b.weight then
			return a.weight < b.weight
		end
		return a.id < b.id
	end)
	local out: { string } = {}
	for _, row in rows do
		local name = if row.kind == "scrap"
			then `{row.amount or 0} {currencyName}`
			else ChestText.rowName(row)
		table.insert(
			out,
			`{ChestText.rarity(row.rarity)}  {name}  {ChestText.percent(chest, row)}%`
		)
	end
	return out
end

function ChestText.contents(kind: string): string
	local chest = ChestDefs.get(kind)
	if chest == nil then
		return ""
	end
	return if chest.items == 1 then "1 prize" else `{chest.items} prizes`
end

-- What one prize says on the reveal.
function ChestText.prize(
	prize: { kind: string, name: string, amount: number?, dupe: boolean },
	currencyName: string
): string
	if prize.kind == "scrap" then
		if prize.dupe then
			return `Had it! +{prize.amount or 0} {currencyName}`
		end
		return `+{prize.amount or 0} {currencyName}`
	end
	return prize.name
end

-- How far the free-chest meter is. `left` is matches still to play.
function ChestText.meter(meter: number, goal: number): string
	local left = math.max(0, goal - meter)
	if left == 0 then
		return "Free chest ready!"
	end
	return if left == 1 then "1 more match = free chest" else `{left} more matches = free chest`
end

function ChestText.deny(reason: string?): string
	local words: { [string]: string } = {
		none = "No chest to open",
		badKind = "No chest to open",
		full = "Too much Scrap",
		busy = "One moment...",
		loading = "Loading...",
		failed = "Progress not loaded",
		lost = "Progress not loaded",
	}
	return words[reason or ""] or "Try again"
end

return ChestText
