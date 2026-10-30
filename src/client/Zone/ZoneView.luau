--!strict
-- What the client knows about the zone, and the only place that turns a ZoneState message into a
-- circle. The HUD and minimap (piece 10) read `ZoneView.get(now)`; nothing here is trusted by the
-- server (damage is decided there).
--   local zone = ZoneView.get(workspace:GetServerTimeNow())  -- nil when there is no live zone
--   zone.centerX, zone.centerZ, zone.radius, zone.targetRadius  -- draw the safe circle and the next one

local ZoneView = {}

export type State = {
	matchId: number,
	centerX: number,
	centerZ: number,
	fromRadius: number,
	toRadius: number,
	startedAt: number,
	endsAt: number,
	warningEndsAt: number?,
	damagePerSecond: number,
	stage: number,
}

export type Phase = "Holding" | "Warning" | "Closing"

export type View = {
	matchId: number,
	phase: Phase,
	stage: number,
	suddenDeath: boolean,
	centerX: number,
	centerZ: number,
	radius: number, -- the safe circle right now
	targetRadius: number, -- where it is going (equals radius when holding)
	secondsToClose: number?, -- during a warning: time until it starts to move
	secondsToSettle: number?, -- while closing: time until it stops
	damagePerSecond: number, -- outside damage right now
}

local SUDDEN_DEATH_STAGE = 99

local current: State? = nil
local live = false -- only true while the match is in a combat phase
local liveMatchId = -1

function ZoneView.radiusAt(state: State, now: number): number
	local warningEndsAt = state.warningEndsAt
	if warningEndsAt ~= nil and now < warningEndsAt then
		return state.fromRadius
	end
	if now >= state.endsAt then
		return state.toRadius
	end
	if now <= state.startedAt then
		return state.fromRadius
	end
	local k = (now - state.startedAt) / (state.endsAt - state.startedAt)
	return state.fromRadius + (state.toRadius - state.fromRadius) * k
end

function ZoneView.viewOf(state: State, now: number): View
	local warningEndsAt = state.warningEndsAt
	local phase: Phase = "Holding"
	local toClose: number? = nil
	local toSettle: number? = nil
	if warningEndsAt ~= nil and now < warningEndsAt then
		phase = "Warning"
		toClose = warningEndsAt - now
	elseif now < state.endsAt and state.endsAt > state.startedAt then
		phase = "Closing"
		toSettle = state.endsAt - now
	end
	return {
		matchId = state.matchId,
		phase = phase,
		stage = state.stage,
		suddenDeath = state.stage == SUDDEN_DEATH_STAGE,
		centerX = state.centerX,
		centerZ = state.centerZ,
		radius = ZoneView.radiusAt(state, now),
		targetRadius = state.toRadius,
		secondsToClose = toClose,
		secondsToSettle = toSettle,
		damagePerSecond = state.damagePerSecond,
	}
end

function ZoneView.isInside(view: View, x: number, z: number): boolean
	local dx = x - view.centerX
	local dz = z - view.centerZ
	return dx * dx + dz * dz <= view.radius * view.radius
end

-- A ZoneState from an older match never replaces a newer one.
function ZoneView.setState(state: State)
	if current ~= nil and state.matchId < current.matchId then
		return
	end
	current = state
end

-- Called with the match id and whether that match is in a combat phase (from MatchState).
function ZoneView.setLive(isLive: boolean, matchId: number)
	live = isLive
	liveMatchId = matchId
	if current ~= nil and current.matchId < matchId then
		current = nil
	end
end

function ZoneView.clear()
	current = nil
	live = false
	liveMatchId = -1
end

function ZoneView.get(now: number): View?
	if not live or current == nil or current.matchId ~= liveMatchId then
		return nil
	end
	return ZoneView.viewOf(current, now)
end

return ZoneView
