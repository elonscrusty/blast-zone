--!strict
-- When the map vote is open and who may vote (piece 33). Pure: the system feeds it phases and votes.
--
-- Open:   Results, Resetting, Waiting, Countdown (the lobby between matches).
-- Locked: the moment the arena builder asks for the winner (end of Countdown), or Spawning, whichever is first.
-- A fresh window (votes cleared) starts when the phase becomes Results, or when the first Waiting begins.

local MatchPhase = require("../MatchPhase")
local VoteBook = require("./VoteBook")

local VoteFlow = {}
VoteFlow.__index = VoteFlow

export type Entry = { id: string, name: string, votes: number }
export type State = {
	open: boolean,
	maps: { Entry },
	yourVote: string?,
	nextMapId: string?, -- set once the vote is locked and someone won
}

export type Flow = {
	book: VoteBook.Book,
	locked: boolean,
	decided: boolean,
	nextMapId: string?,
	currentMapId: string?,
	pick: (n: number) -> number,
	setPool: (self: Flow, pool: { VoteBook.MapInfo }) -> (),
	setCurrentMap: (self: Flow, mapId: string?) -> (),
	onPhase: (self: Flow, phase: string) -> (),
	vote: (self: Flow, voterId: string, mapId: string) -> boolean,
	leave: (self: Flow, voterId: string) -> (),
	takeWinner: (self: Flow) -> string?,
	state: (self: Flow, voterId: string?) -> State,
}

local OPEN_PHASES: { [string]: boolean } = {
	[MatchPhase.Results] = true,
	[MatchPhase.Resetting] = true,
	[MatchPhase.Waiting] = true,
	[MatchPhase.Countdown] = true,
}

-- `pick(n)` returns a whole number 1..n; the server passes a real random one, tests pass a fixed one.
function VoteFlow.new(pool: { VoteBook.MapInfo }, pick: (n: number) -> number): Flow
	local self: any = setmetatable({}, VoteFlow)
	self.book = VoteBook.new(pool)
	self.locked = false
	self.decided = false
	self.nextMapId = nil
	self.currentMapId = nil
	self.pick = pick
	self.book:setOpen(true) -- the lobby before the first match
	return self
end

local function freshWindow(self: Flow)
	self.book = VoteBook.new(self.book.pool)
	self.locked = false
	self.decided = false
	self.nextMapId = nil
	self.book:setOpen(true)
end

-- The pool can change while a window is open (a map joins the rotation). Votes for maps still in it stay.
function VoteFlow.setPool(self: Flow, pool: { VoteBook.MapInfo })
	local old = self.book
	self.book = VoteBook.new(pool)
	for voterId, mapId in old.votes do
		if self.book:has(mapId) then
			self.book.votes[voterId] = mapId
		end
	end
	self.book:setOpen(old.open)
end

function VoteFlow.setCurrentMap(self: Flow, mapId: string?)
	self.currentMapId = mapId
end

function VoteFlow.onPhase(self: Flow, phase: string)
	if phase == MatchPhase.Results then
		freshWindow(self)
	elseif OPEN_PHASES[phase] then
		-- A match that ended without Results (abort) leaves the vote locked: start a clean window.
		-- Countdown falling back to Waiting (players left) is not locked, so that window stays as it is.
		if self.locked and phase ~= MatchPhase.Countdown then
			freshWindow(self)
		end
	else
		self:takeWinner() -- Spawning and later: the vote is over
	end
end

function VoteFlow.vote(self: Flow, voterId: string, mapId: string): boolean
	if self.locked then
		return false
	end
	return self.book:cast(voterId, mapId)
end

function VoteFlow.leave(self: Flow, voterId: string)
	if not self.locked then
		self.book:clear(voterId)
	end
end

-- Locks the vote (once) and returns the winner, or nil if nobody voted. Asking again gives the same answer.
function VoteFlow.takeWinner(self: Flow): string?
	if not self.decided then
		self.decided = true
		self.locked = true
		self.book:setOpen(false)
		self.nextMapId = self.book:winner(self.pick, self.currentMapId)
	end
	return self.nextMapId
end

function VoteFlow.state(self: Flow, voterId: string?): State
	local counts = self.book:counts()
	local maps: { Entry } = {}
	for _, m in self.book.pool do
		table.insert(maps, { id = m.id, name = m.name, votes = counts[m.id] or 0 })
	end
	return {
		open = self.book.open,
		maps = maps,
		yourVote = if voterId then self.book.votes[voterId] else nil,
		nextMapId = self.nextMapId,
	}
end

return VoteFlow
