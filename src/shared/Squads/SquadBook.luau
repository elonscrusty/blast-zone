--!strict
-- Squads (video 3 gap 11). Pure team rules, no Roblox, so Lune can test them. One book per server.
-- The server seats teams once, when a match starts; after that the teams never change until the reset.
--
-- Seating order (people before bots, friends before strangers):
--   1. Friends who joined each other (a party) share a team, in chunks of the squad size.
--   2. Loose players fill the seats that are still open, then open new teams.
--   3. Bots fill what is left, then make teams among themselves.
-- If that gives fewer than `minTeams` teams, nobody is seated and the match is solo.

local Signal = require("../Signal")

export type Member = { id: string, isBot: boolean }

local SquadBook = {}
SquadBook.__index = SquadBook

export type Book = {
	Assigned: any, -- Signal(): fired after every seating, solo or not
	wanted: number,
	parties: { { string } },
	setWanted: (self: Book, size: number) -> (),
	setParties: (self: Book, parties: { { string } }) -> (),
	assign: (self: Book, members: { Member }, minTeams: number) -> number,
	clear: (self: Book) -> (),
	size: (self: Book) -> number,
	active: (self: Book) -> boolean,
	teamCount: (self: Book) -> number,
	teamOf: (self: Book, id: string) -> number?,
	membersOf: (self: Book, team: number) -> { string },
	matesOf: (self: Book, id: string) -> { string },
	sameTeam: (self: Book, a: string, b: string) -> boolean,
	blocksDamage: (
		self: Book,
		sourceId: string?,
		targetId: string,
		friendlyFire: boolean
	) -> boolean,
	aliveTeamCount: (self: Book, isAlive: (string) -> boolean) -> number,
	teamAlive: (self: Book, team: number, isAlive: (string) -> boolean) -> boolean,
}

function SquadBook.new(): Book
	return setmetatable({
		Assigned = Signal.new(),
		wanted = 1,
		parties = {},
		_size = 1,
		_teams = {} :: { { string } },
		_teamOf = {} :: { [string]: number },
	}, SquadBook) :: any
end

-- The squad size to try at the next seating (1 = solo). Anything odd means solo.
function SquadBook.setWanted(self: any, size: number)
	if type(size) ~= "number" or size ~= size or size < 1 then
		self.wanted = 1
		return
	end
	self.wanted = math.floor(size)
end

-- Lists of participant ids who asked to play together. Read at the next seating.
function SquadBook.setParties(self: any, parties: { { string } })
	self.parties = parties
end

export type Mode = { id: string, name: string, size: number }

-- The vote pool for the lobby: one entry per mode, in config order.
function SquadBook.pool(modes: { Mode }): { { id: string, name: string } }
	local out = {}
	for _, m in modes do
		table.insert(out, { id = m.id, name = m.name })
	end
	return out
end

-- Squad size of a mode id; `fallbackId` when the id is missing or unknown; 1 if that is unknown too.
function SquadBook.sizeOf(modes: { Mode }, id: string?, fallbackId: string): number
	for _, wanted in { id, fallbackId } do
		for _, m in modes do
			if m.id == wanted then
				return m.size
			end
		end
	end
	return 1
end

-- Biggest squad that still leaves at least `minTeams` teams for `count` fighters.
function SquadBook.effectiveSize(wanted: number, count: number, minTeams: number): number
	local size = math.max(1, math.floor(wanted))
	local most = math.floor(count / math.max(1, minTeams))
	return math.max(1, math.min(size, most))
end

-- Seats `members` (enrollment order) and returns the squad size used (1 = solo, nobody seated).
function SquadBook.assign(self: any, members: { Member }, minTeams: number): number
	self._teams = {}
	self._teamOf = {}
	local size = SquadBook.effectiveSize(self.wanted, #members, minTeams)
	if size > 1 then
		local byId: { [string]: Member } = {}
		for _, m in members do
			byId[m.id] = m
		end
		local teams: { { string } } = {}
		local seated: { [string]: boolean } = {}
		local function seat(team: { string }, id: string)
			table.insert(team, id)
			seated[id] = true
		end

		-- 1. parties, in chunks of the squad size (people only; a party id that is not in the match is skipped)
		for _, party in self.parties do
			local team: { string } = {}
			for _, id in party do
				local m = byId[id]
				if m ~= nil and not m.isBot and not seated[id] then
					if #team == size then
						table.insert(teams, team)
						team = {}
					end
					seat(team, id)
				end
			end
			if #team > 0 then
				table.insert(teams, team)
			end
		end

		-- 2 and 3. loose people, then bots: fill open seats first, then open a new team
		for _, wantBots in { false, true } do
			for _, m in members do
				if not seated[m.id] and m.isBot == wantBots then
					local home: { string }? = nil
					for _, team in teams do
						if #team < size then
							home = team
							break
						end
					end
					if home == nil then
						home = {}
						table.insert(teams, home :: { string })
					end
					seat(home :: { string }, m.id)
				end
			end
		end

		if #teams >= minTeams then
			self._teams = teams
			self._size = size
			for t, team in teams do
				for _, id in team do
					self._teamOf[id] = t
				end
			end
			self.Assigned:fire()
			return size
		end
	end
	self._size = 1
	self.Assigned:fire()
	return 1
end

function SquadBook.clear(self: any)
	self._size = 1
	self._teams = {}
	self._teamOf = {}
end

function SquadBook.size(self: any): number
	return self._size
end

-- True while a seated squad match is running (size above 1).
function SquadBook.active(self: any): boolean
	return self._size > 1
end

function SquadBook.teamCount(self: any): number
	return #self._teams
end

function SquadBook.teamOf(self: any, id: string): number?
	return self._teamOf[id]
end

function SquadBook.membersOf(self: any, team: number): { string }
	local t = self._teams[team]
	return if t then table.clone(t) else {}
end

-- The others on this fighter's team (never the fighter).
function SquadBook.matesOf(self: any, id: string): { string }
	local team = self._teamOf[id]
	local out: { string } = {}
	if team == nil then
		return out
	end
	for _, other in self._teams[team] do
		if other ~= id then
			table.insert(out, other)
		end
	end
	return out
end

-- True for two different fighters on the same team. A fighter is not their own teammate.
function SquadBook.sameTeam(self: any, a: string, b: string): boolean
	if a == b then
		return false
	end
	local ta = self._teamOf[a]
	return ta ~= nil and ta == self._teamOf[b]
end

-- The damage door's question: does this hit stop at a teammate? Hurting yourself and the zone (no source) pass.
function SquadBook.blocksDamage(
	self: any,
	sourceId: string?,
	targetId: string,
	friendlyFire: boolean
): boolean
	return not friendlyFire and sourceId ~= nil and SquadBook.sameTeam(self, sourceId, targetId)
end

function SquadBook.teamAlive(self: any, team: number, isAlive: (string) -> boolean): boolean
	local t = self._teams[team]
	if t == nil then
		return false
	end
	for _, id in t do
		if isAlive(id) then
			return true
		end
	end
	return false
end

function SquadBook.aliveTeamCount(self: any, isAlive: (string) -> boolean): number
	local n = 0
	for team = 1, #self._teams do
		if SquadBook.teamAlive(self, team, isAlive) then
			n += 1
		end
	end
	return n
end

return SquadBook
