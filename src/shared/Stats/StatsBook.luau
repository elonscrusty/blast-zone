--!strict
-- Keeps each player's stats for this server session (piece 24). Pure: the saving is passed in.
-- Stats earned before the profile has loaded wait in `pending` and are written once it loads,
-- so a slow load never loses a match. If the profile never loads, they stay for this session only.
--
--   local book = StatsBook.new({ save = ..., changed = ..., savedWins = ... })
--   book:join(userId)                 -- player arrived (zeros, nothing saved yet)
--   book:loaded(userId)               -- their profile is ready: write what is pending
--   book:earn(userId, delta)          -- add a match or an elimination
--   book:get(userId) -> Shown?        -- what to show: saved + pending
--   book:leave(userId)
--
-- Ports:
--   save(userId, delta) -> Stats?     add delta to the saved stats; return the new saved totals,
--                                     or nil when the profile cannot be written (not loaded, failed).
--   changed(userId, shown)            what the player sees changed.
--   savedWins(userId, wins)           the SAVED win count went up (the top-wins board listens).

local StatsRules = require("./StatsRules")

type Stats = StatsRules.Stats

export type Shown = Stats & { saved: boolean }

export type Ports = {
	save: (userId: number, delta: Stats) -> Stats?,
	changed: (userId: number, shown: Shown) -> (),
	savedWins: (userId: number, wins: number) -> (),
}

type Entry = {
	saved: Stats?, -- last known saved totals; nil until the profile is written once
	pending: Stats, -- earned but not saved yet
}

export type Book = {
	join: (self: Book, userId: number) -> (),
	loaded: (self: Book, userId: number) -> (),
	earn: (self: Book, userId: number, delta: Stats) -> (),
	get: (self: Book, userId: number) -> Shown?,
	leave: (self: Book, userId: number) -> (),
}

local StatsBook = {}

function StatsBook.new(ports: Ports): Book
	local entries: { [number]: Entry } = {}
	local book = {} :: Book

	local function shownOf(e: Entry): Shown
		local total = StatsRules.add(e.saved or StatsRules.empty(), e.pending)
		return {
			wins = total.wins,
			eliminations = total.eliminations,
			matches = total.matches,
			saved = e.saved ~= nil and StatsRules.isEmpty(e.pending),
		}
	end

	-- Tries to write the pending stats. An empty delta still reads the saved totals.
	local function flush(userId: number, e: Entry)
		local before = if e.saved then e.saved.wins else nil
		local result = ports.save(userId, e.pending)
		if result == nil then
			return
		end
		if entries[userId] ~= e then
			return -- left while saving
		end
		e.saved = StatsRules.read(result)
		e.pending = StatsRules.empty()
		local wins = (e.saved :: Stats).wins
		if wins > 0 and wins ~= before then
			ports.savedWins(userId, wins)
		end
	end

	function book.join(_self: Book, userId: number)
		if entries[userId] == nil then
			entries[userId] = { saved = nil, pending = StatsRules.empty() }
		end
	end

	function book.loaded(self: Book, userId: number)
		self:join(userId)
		local e = entries[userId]
		flush(userId, e)
		ports.changed(userId, shownOf(e))
	end

	function book.earn(_self: Book, userId: number, delta: Stats)
		local e = entries[userId]
		if e == nil then
			return -- not in this server (left, or a stale event)
		end
		e.pending = StatsRules.add(e.pending, StatsRules.read(delta))
		if e.saved ~= nil then
			flush(userId, e) -- only write once the profile has been read
		end
		ports.changed(userId, shownOf(e))
	end

	function book.get(_self: Book, userId: number): Shown?
		local e = entries[userId]
		return if e then shownOf(e) else nil
	end

	function book.leave(_self: Book, userId: number)
		entries[userId] = nil
	end

	return book
end

return StatsBook
