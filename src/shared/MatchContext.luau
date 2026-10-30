--!strict
-- The server's one answer to "which match, which phase?". Piece 05 changes it; everyone else reads it.
-- matchId grows with every new match, so work that started in an old match can be recognised and dropped.

local MatchPhase = require("./MatchPhase")
local Signal = require("./Signal")

local MatchContext = {}
MatchContext.__index = MatchContext

function MatchContext.new(clock: () -> number): any
	return setmetatable({
		_clock = clock,
		_matchId = 0,
		_phase = "Waiting",
		_phaseStartedAt = clock(),
		_phaseEndsAt = nil :: number?,
		PhaseChanged = Signal.new(), -- (newPhase, oldPhase, matchId)
		MatchStarted = Signal.new(), -- (matchId)
	}, MatchContext)
end

function MatchContext.getMatchId(self: any): number
	return self._matchId
end

function MatchContext.getPhase(self: any): string
	return self._phase
end

-- Seconds on the server clock when the phase should end, if it has a timer.
function MatchContext.getPhaseEndsAt(self: any): number?
	return self._phaseEndsAt
end

function MatchContext.phaseElapsed(self: any): number
	return self._clock() - self._phaseStartedAt
end

function MatchContext.isCombat(self: any): boolean
	return MatchPhase.isCombat(self._phase)
end

-- True only for the current match. Check this before acting on anything delayed (projectiles, timers).
function MatchContext.isCurrent(self: any, matchId: number): boolean
	return matchId == self._matchId
end

-- Starts a new match number. Call once per match, when leaving Waiting for Countdown.
function MatchContext.beginMatch(self: any): number
	self._matchId += 1
	self.MatchStarted:fire(self._matchId)
	return self._matchId
end

-- Moves the phase if the move is legal. Returns false (and changes nothing) otherwise.
function MatchContext.setPhase(self: any, phase: string, durationSeconds: number?): boolean
	if not MatchPhase.canTransition(self._phase, phase) then
		return false
	end
	local old = self._phase
	self._phase = phase
	self._phaseStartedAt = self._clock()
	self._phaseEndsAt = if durationSeconds then self._phaseStartedAt + durationSeconds else nil
	self.PhaseChanged:fire(phase, old, self._matchId)
	return true
end

return MatchContext
