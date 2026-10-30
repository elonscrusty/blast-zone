--!strict
-- Plain words for the bench (placeholder wording; Claude Design may reword). Pure Luau.

local BenchDefs = require("./BenchDefs")

local BenchText = {}

function BenchText.partName(kind: string, tier: number): string
	local k = BenchDefs.kind(kind)
	return `{BenchDefs.tierName(tier)} {if k then k.name else "?"}`
end

-- "Rough Bolt x3"
function BenchText.pile(kind: string, tier: number, count: number): string
	return `{BenchText.partName(kind, tier)} x{count}`
end

-- "Rough Bolt 1/2"
function BenchText.need(kind: string, tier: number, have: number, count: number): string
	return `{BenchText.partName(kind, tier)} {math.min(have, count)}/{count}`
end

-- Shown wherever parts can drop: the chance of each kind (all the same).
function BenchText.odds(): string
	local each = math.floor(100 / #BenchDefs.kinds + 0.5)
	local words: { string } = {}
	for _, k in BenchDefs.kinds do
		table.insert(words, `{k.name} {each}%`)
	end
	return "Each part: " .. table.concat(words, " / ")
end

local REASONS: { [string]: string } = {
	notEnough = "Not enough parts",
	maxTier = "Already the best",
	alreadyBuilt = "You built this",
	badPart = "Unknown part",
	badBlueprint = "Unknown plan",
	notLoaded = "Progress not loaded",
	busy = "Try again",
}

function BenchText.reason(reason: string?): string
	return REASONS[reason or ""] or "Cannot do that"
end

return BenchText
