--!strict
-- The global top-wins board (piece 24). Pure: no DataStore here, so Lune can test it.
--   * One OrderedDataStore entry per player: key = tostring(userId), value = saved wins.
--   * A write never lowers a value (two servers, or an old queued write, cannot undo a win).
--   * Writes wait in a queue and go out in small batches, never per match event.

export type Row = {
	rank: number,
	userId: number,
	name: string,
	wins: number,
}

local BoardRules = {}

BoardRules.FALLBACK_NAME = "Player"

function BoardRules.keyFor(userId: number): string
	return tostring(math.floor(userId))
end

function BoardRules.userIdOf(key: any): number?
	if type(key) ~= "string" or string.match(key, "^%d+$") == nil then
		return nil
	end
	return tonumber(key)
end

-- The value UpdateAsync should store: the larger of what is saved and what we want to write.
function BoardRules.merge(old: any, new: number): number
	local have = if type(old) == "number" and old == old then math.floor(old) else 0
	return math.max(have, math.max(0, math.floor(new)))
end

-- GetSortedAsync page entries ({ key, value }) -> clean rows, best first, at most `limit`.
-- `nameOf(userId)` may return nil; the row then shows FALLBACK_NAME.
function BoardRules.rows(entries: { any }, nameOf: (number) -> string?, limit: number): { Row }
	local rows: { Row } = {}
	for _, entry in entries do
		if #rows >= limit then
			break
		end
		local userId = if type(entry) == "table" then BoardRules.userIdOf(entry.key) else nil
		local wins = if type(entry) == "table" then entry.value else nil
		if userId and type(wins) == "number" and wins == wins and wins > 0 then
			local name = nameOf(userId)
			table.insert(rows, {
				rank = 0,
				userId = userId,
				name = if type(name) == "string" and name ~= ""
					then name
					else BoardRules.FALLBACK_NAME,
				wins = math.floor(wins),
			})
		end
	end
	table.sort(rows, function(a, b)
		if a.wins ~= b.wins then
			return a.wins > b.wins
		end
		return a.userId < b.userId
	end)
	for i, row in rows do
		row.rank = i
	end
	return rows
end

-- Short number for a small board cell: 999, 1.2K, 34K, 1.5M.
function BoardRules.short(n: number): string
	n = math.max(0, math.floor(n))
	if n < 1000 then
		return tostring(n)
	elseif n < 10000 then
		local s = string.format("%.1fK", math.floor(n / 100) / 10)
		return (string.gsub(s, "%.0K", "K"))
	elseif n < 1e6 then
		return `{math.floor(n / 1000)}K`
	end
	local s = string.format("%.1fM", math.floor(n / 1e5) / 10)
	return (string.gsub(s, "%.0M", "M"))
end

-- A queue of wins waiting to be written. Keeps only the newest (largest) value per player.
export type Queue = {
	put: (self: Queue, userId: number, wins: number) -> (),
	take: (self: Queue, max: number) -> { { userId: number, wins: number } },
	size: (self: Queue) -> number,
}

function BoardRules.newQueue(): Queue
	local waiting: { [number]: number } = {}
	local order: { number } = {}
	local q = {} :: Queue

	function q.put(_self: Queue, userId: number, wins: number)
		if wins <= 0 then
			return
		end
		if waiting[userId] == nil then
			table.insert(order, userId)
		end
		waiting[userId] = math.max(waiting[userId] or 0, wins)
	end

	function q.take(_self: Queue, max: number)
		local out = {}
		while #out < max and #order > 0 do
			local userId = table.remove(order, 1) :: number
			table.insert(out, { userId = userId, wins = waiting[userId] })
			waiting[userId] = nil
		end
		return out
	end

	function q.size(_self: Queue): number
		return #order
	end

	return q
end

return BoardRules
