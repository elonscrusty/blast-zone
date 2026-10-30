--!strict
-- Who is in the current match. Server only (one instance: Core/Participants).
-- A Participant belongs to ONE match: its matchId is stamped on enroll, so stale events can be spotted.

local Ids = require("./Ids")
local Signal = require("./Signal")

export type Participant = {
	id: string,
	kind: string,
	matchId: number,
	displayName: string,
	userId: number?,
	player: any?,
	alive: boolean,
	eliminatedAt: number?,
}

local Registry = {}
Registry.__index = Registry

function Registry.new(clock: () -> number): any
	return setmetatable({
		_clock = clock,
		_byId = {} :: { [string]: Participant },
		_order = {} :: { string },
		Enrolled = Signal.new(), -- (Participant)
		Eliminated = Signal.new(), -- (Participant)
		Removed = Signal.new(), -- (Participant)
	}, Registry)
end

-- Enroll a player (userId + player) or a bot (botIndex). Returns nil if the id is already enrolled.
function Registry.enrollPlayer(
	self: any,
	matchId: number,
	player: any,
	userId: number,
	displayName: string
): Participant?
	return self:_add(matchId, Ids.player(userId), "player", displayName, userId, player)
end

function Registry.enrollBot(
	self: any,
	matchId: number,
	botIndex: number,
	displayName: string
): Participant?
	return self:_add(matchId, Ids.bot(botIndex), "bot", displayName, nil, nil)
end

function Registry._add(
	self: any,
	matchId: number,
	id: string,
	kind: string,
	displayName: string,
	userId: number?,
	player: any?
): Participant?
	if self._byId[id] ~= nil then
		return nil
	end
	local p: Participant = {
		id = id,
		kind = kind,
		matchId = matchId,
		displayName = displayName,
		userId = userId,
		player = player,
		alive = true,
		eliminatedAt = nil,
	}
	self._byId[id] = p
	table.insert(self._order, id)
	self.Enrolled:fire(p)
	return p
end

function Registry.get(self: any, id: string): Participant?
	return self._byId[id]
end

function Registry.ofPlayer(self: any, player: any): Participant?
	for _, p in self._byId do
		if p.player == player then
			return p
		end
	end
	return nil
end

function Registry.isAlive(self: any, id: string): boolean
	local p: Participant? = self._byId[id]
	return p ~= nil and p.alive
end

-- Enrollment order, so results and spectate cycling are stable.
function Registry.list(self: any): { Participant }
	local out = {}
	for _, id in self._order do
		table.insert(out, self._byId[id])
	end
	return out
end

function Registry.aliveList(self: any): { Participant }
	local out = {}
	for _, id in self._order do
		local p: Participant = self._byId[id]
		if p.alive then
			table.insert(out, p)
		end
	end
	return out
end

function Registry.aliveCount(self: any): number
	return #self:aliveList()
end

-- Once only: returns false when already eliminated or unknown (no double elimination).
function Registry.markEliminated(self: any, id: string): boolean
	local p: Participant? = self._byId[id]
	if p == nil or not p.alive then
		return false
	end
	p.alive = false
	p.eliminatedAt = self._clock()
	self.Eliminated:fire(p)
	return true
end

-- Disconnect or abort: the entry goes away entirely.
function Registry.remove(self: any, id: string): Participant?
	local p: Participant? = self._byId[id]
	if p == nil then
		return nil
	end
	self._byId[id] = nil
	local i = table.find(self._order, id)
	if i then
		table.remove(self._order, i)
	end
	self.Removed:fire(p)
	return p
end

-- Match reset: forget everyone.
function Registry.clear(self: any)
	self._byId = {}
	self._order = {}
end

return Registry
