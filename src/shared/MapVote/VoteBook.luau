--!strict
-- Pure map-vote rules (piece 33). One book per voting window. No Roblox types, so Lune tests it.
-- The server owns the book: clients only ask to vote, the server checks the map and the voter.

local VoteBook = {}
VoteBook.__index = VoteBook

export type MapInfo = { id: string, name: string }

export type Book = {
	open: boolean,
	pool: { MapInfo },
	votes: { [string]: string }, -- voterId -> mapId
	setOpen: (self: Book, open: boolean) -> (),
	has: (self: Book, mapId: string) -> boolean,
	cast: (self: Book, voterId: string, mapId: string) -> boolean,
	clear: (self: Book, voterId: string) -> (),
	counts: (self: Book) -> { [string]: number },
	winner: (self: Book, pick: (n: number) -> number, lastMapId: string?) -> string?,
}

function VoteBook.new(pool: { MapInfo }): Book
	local copy: { MapInfo } = {}
	for _, m in pool do
		table.insert(copy, { id = m.id, name = m.name })
	end
	return setmetatable({ open = false, pool = copy, votes = {} }, VoteBook) :: any
end

function VoteBook.setOpen(self: Book, open: boolean)
	self.open = open
end

function VoteBook.has(self: Book, mapId: string): boolean
	for _, m in self.pool do
		if m.id == mapId then
			return true
		end
	end
	return false
end

-- A vote counts only while the window is open and the map is in the pool. A new vote replaces the old one.
function VoteBook.cast(self: Book, voterId: string, mapId: string): boolean
	if not self.open or not self:has(mapId) then
		return false
	end
	self.votes[voterId] = mapId
	return true
end

function VoteBook.clear(self: Book, voterId: string)
	self.votes[voterId] = nil
end

function VoteBook.counts(self: Book): { [string]: number }
	local out: { [string]: number } = {}
	for _, m in self.pool do
		out[m.id] = 0
	end
	for _, mapId in self.votes do
		out[mapId] = (out[mapId] or 0) + 1
	end
	return out
end

-- Most votes wins. A tie is broken by `pick(n)` (a random whole number 1..n), but a tie that includes
-- anything other than `lastMapId` never picks `lastMapId`, so the same map does not repeat when there is a choice.
-- Nobody voted: nil (the caller keeps its normal rotation).
function VoteBook.winner(self: Book, pick: (n: number) -> number, lastMapId: string?): string?
	local counts = self:counts()
	local best = 0
	for _, n in counts do
		best = math.max(best, n)
	end
	if best == 0 then
		return nil
	end
	local tied: { string } = {}
	for _, m in self.pool do -- pool order keeps the tie list the same every time
		if counts[m.id] == best then
			table.insert(tied, m.id)
		end
	end
	if #tied > 1 and lastMapId ~= nil then
		local fresh: { string } = {}
		for _, id in tied do
			if id ~= lastMapId then
				table.insert(fresh, id)
			end
		end
		if #fresh > 0 then
			tied = fresh
		end
	end
	local i = math.clamp(math.floor(pick(#tied)), 1, #tied)
	return tied[i]
end

return VoteBook
