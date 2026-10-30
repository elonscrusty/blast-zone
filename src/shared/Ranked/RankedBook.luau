--!strict
-- Keeps each player's ranked standing for this server session (gap 23). Pure: saving is passed in.
-- A scored match that cannot be written yet (profile still loading, or a failed write) waits in `pending` and is
-- tried again on the next event, so a slow load never loses a match. Each one is written with its own once-only key.
--
--   local book = RankedBook.new({ read = ..., write = ..., changed = ... })
--   book:join(userId) / book:loaded(userId)       -- player arrived / their profile is ready
--   book:setEnabled(userId, on) -> boolean        -- the ranked switch (only once the profile is loaded)
--   book:isOn(userId) -> boolean                  -- is the switch on right now
--   book:stake(userId, key) -> boolean            -- a ranked fight begins: take the loss (once per key)
--   book:score(userId, key, matchId, result)      -- a ranked match finished
--   book:practice(userId, matchId, place, kills)  -- it did not count (too few fighters)
--   book:get(userId) -> Payload?                  -- what the client is shown
--   book:leave(userId)
--
-- Ports:
--   read(userId) -> State?                        the saved state, nil when the profile is not loaded
--   write(userId, key?, change: (State) -> State) -> (State?, string?)
--       runs `change` on the saved state and saves the answer (once per key when there is one).
--       Returns the new saved state. nil + "duplicate" = that key was already written; any other nil = not written.
--   changed(userId, payload)                      what the player sees changed

local RankedRules = require("./RankedRules")

type State = RankedRules.State

export type Pending = { key: string, matchId: number, result: RankedRules.Result }

export type Ports = {
	read: (userId: number) -> State?,
	write: (userId: number, key: string?, change: (State) -> State) -> (State?, string?),
	changed: (userId: number, payload: any) -> (),
}

type Entry = {
	saved: State?,
	pending: { Pending },
	last: any?, -- the RankedLast of the newest match
}

export type Book = {
	join: (self: Book, userId: number) -> (),
	loaded: (self: Book, userId: number) -> (),
	setEnabled: (self: Book, userId: number, on: boolean) -> boolean,
	isOn: (self: Book, userId: number) -> boolean,
	stake: (self: Book, userId: number, key: string) -> boolean,
	score: (
		self: Book,
		userId: number,
		key: string,
		matchId: number,
		result: RankedRules.Result
	) -> (),
	practice: (self: Book, userId: number, matchId: number, place: number, kills: number) -> (),
	get: (self: Book, userId: number) -> any?,
	leave: (self: Book, userId: number) -> (),
}

local RankedBook = {}

function RankedBook.new(ports: Ports): Book
	local entries: { [number]: Entry } = {}
	local book = {} :: Book

	local function payloadOf(e: Entry): any
		local state = e.saved or RankedRules.empty()
		local s = RankedRules.standing(state)
		return {
			enabled = state.enabled,
			points = state.points,
			matches = state.matches,
			qualified = s.qualified,
			qualifyLeft = s.qualifyLeft,
			label = s.label,
			tierId = s.tierId,
			tierName = s.tierName,
			step = s.step,
			intoStep = s.intoStep,
			stepSize = s.stepSize,
			nextTierName = s.nextTierName,
			toNextTier = s.toNextTier,
			peakTierName = RankedRules.peakName(state),
			season = state.season,
			saved = e.saved ~= nil and #e.pending == 0,
			last = e.last,
		}
	end

	local function tell(userId: number, e: Entry)
		ports.changed(userId, payloadOf(e))
	end

	-- Writes the waiting matches in order. Stops at the first that cannot be written.
	local function flush(userId: number, e: Entry)
		while #e.pending > 0 do
			local item = e.pending[1]
			local box: { change: RankedRules.Change? } = { change = nil } -- the writer fills it in
			local new, why = ports.write(userId, item.key, function(state: State): State
				local c = RankedRules.apply(state, item.result)
				box.change = c
				return c.state
			end)
			if entries[userId] ~= e then
				return -- left while saving
			end
			if new == nil and why ~= "duplicate" then
				return
			end
			table.remove(e.pending, 1)
			if new ~= nil then
				e.saved = new
			end
			local change = box.change
			if change ~= nil then
				e.last = {
					matchId = item.matchId,
					place = item.result.place,
					kills = item.result.kills,
					delta = change.delta,
					counted = true,
					promoted = change.promoted,
					demoted = change.demoted,
					fromLabel = change.fromLabel,
					toLabel = change.toLabel,
				}
			end
		end
	end

	function book.join(_self: Book, userId: number)
		if entries[userId] == nil then
			entries[userId] = { saved = nil, pending = {}, last = nil }
		end
	end

	function book.loaded(self: Book, userId: number)
		self:join(userId)
		local e = entries[userId]
		e.saved = ports.read(userId)
		if e.saved ~= nil then
			flush(userId, e)
		end
		tell(userId, e)
	end

	function book.setEnabled(_self: Book, userId: number, on: boolean): boolean
		local e = entries[userId]
		if e == nil or e.saved == nil then
			return false
		end
		local new = ports.write(userId, nil, function(state: State): State
			local out = table.clone(state)
			out.enabled = on
			return out
		end)
		if entries[userId] ~= e then
			return false
		end
		if new == nil then
			return false
		end
		e.saved = new
		tell(userId, e)
		return true
	end

	function book.isOn(_self: Book, userId: number): boolean
		local e = entries[userId]
		return e ~= nil and e.saved ~= nil and e.saved.enabled
	end

	function book.stake(_self: Book, userId: number, key: string): boolean
		local e = entries[userId]
		if e == nil or e.saved == nil then
			return false
		end
		local new = ports.write(userId, key, function(state: State): State
			return RankedRules.takeStake(state)
		end)
		if entries[userId] ~= e or new == nil then
			return false
		end
		e.saved = new
		tell(userId, e)
		return true
	end

	function book.score(
		_self: Book,
		userId: number,
		key: string,
		matchId: number,
		result: RankedRules.Result
	)
		local e = entries[userId]
		if e == nil then
			return -- not in this server (left, or a stale event)
		end
		table.insert(e.pending, { key = key, matchId = matchId, result = result })
		if e.saved ~= nil then
			flush(userId, e)
		end
		tell(userId, e)
	end

	function book.practice(
		_self: Book,
		userId: number,
		matchId: number,
		place: number,
		kills: number
	)
		local e = entries[userId]
		if e == nil then
			return
		end
		e.last = {
			matchId = matchId,
			place = place,
			kills = kills,
			delta = 0,
			counted = false,
			promoted = false,
			demoted = false,
			fromLabel = RankedRules.standing(e.saved or RankedRules.empty()).label,
			toLabel = RankedRules.standing(e.saved or RankedRules.empty()).label,
		}
		tell(userId, e)
	end

	function book.get(_self: Book, userId: number): any?
		local e = entries[userId]
		return if e then payloadOf(e) else nil
	end

	function book.leave(_self: Book, userId: number)
		entries[userId] = nil
	end

	return book
end

return RankedBook
