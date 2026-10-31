--!strict
-- Counts for the results card (video 3 gap 29): things broken, crates opened, powers picked.
-- Pure, so Lune tests it. TallySystem owns one book per server and clears it when a match starts.
-- Only the server counts. The client is only ever sent the final numbers for its own player.

local MatchTally = {}

export type Kind = "broken" | "crates" | "powers"
export type Counts = { broken: number, crates: number, powers: number }
export type Book = { [string]: Counts }

-- One match cannot make more of anything than this, so a bug can never send a silly number to a screen.
MatchTally.MAX = 999

local KINDS: { [string]: boolean } = { broken = true, crates = true, powers = true }

function MatchTally.new(): Book
	return {}
end

function MatchTally.isKind(kind: any): boolean
	return type(kind) == "string" and KINDS[kind] == true
end

local function empty(): Counts
	return { broken = 0, crates = 0, powers = 0 }
end

-- Adds one (or n) to a fighter's count. Unknown kinds, empty ids and silly amounts do nothing. True when counted.
function MatchTally.add(book: Book, id: string?, kind: string, n: number?): boolean
	if type(id) ~= "string" or id == "" or not MatchTally.isKind(kind) then
		return false
	end
	local amount = n or 1
	if type(amount) ~= "number" or amount ~= amount or amount < 1 or amount > MatchTally.MAX then
		return false
	end
	local counts = book[id]
	if counts == nil then
		counts = empty()
		book[id] = counts
	end
	local c = counts :: any
	c[kind] = math.min(MatchTally.MAX, c[kind] + math.floor(amount))
	return true
end

-- A copy, so nobody edits the book by accident. Someone who did nothing gets zeros.
function MatchTally.get(book: Book, id: string): Counts
	local counts = book[id]
	if counts == nil then
		return empty()
	end
	return { broken = counts.broken, crates = counts.crates, powers = counts.powers }
end

function MatchTally.reset(book: Book)
	table.clear(book)
end

-- The card lists only what happened, in a fixed order. Each line is { label, value }.
-- Words are plain and ours. Zero lines are left out so a quiet match shows a short card.
function MatchTally.lines(counts: Counts): { { label: string, value: number } }
	local out = {}
	if counts.broken > 0 then
		table.insert(out, { label = "Things broken", value = counts.broken })
	end
	if counts.crates > 0 then
		table.insert(out, { label = "Crates opened", value = counts.crates })
	end
	if counts.powers > 0 then
		table.insert(out, { label = "Powers picked", value = counts.powers })
	end
	return out
end

-- The one line under the pills: "12 things broken · 3 crates opened". nil when nothing happened.
-- `raw` is whatever the server sent; it is cleaned first.
function MatchTally.extrasLine(raw: any): string?
	local parts = {}
	for _, line in MatchTally.lines(MatchTally.read(raw)) do
		table.insert(parts, `{line.value} {string.lower(line.label)}`)
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, " · ")
end

-- Reads whatever the server sent (never trusts its shape) and returns clean counts.
function MatchTally.read(raw: any): Counts
	local counts = empty()
	if type(raw) ~= "table" then
		return counts
	end
	for kind in KINDS do
		local v = raw[kind]
		if type(v) == "number" and v == v and v >= 0 then
			(counts :: any)[kind] = math.min(MatchTally.MAX, math.floor(v))
		end
	end
	return counts
end

return MatchTally
