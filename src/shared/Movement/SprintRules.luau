--!strict
-- Sprint breath and who may run, as plain numbers (piece 45). One state per fighter, stepped by the
-- server every tick. The client only asks to start or stop; nothing here trusts it beyond `want`.

local SprintRules = {}

export type State = {
	stamina: number, -- 0 .. 1 (1 = full breath)
	locked: boolean, -- ran out: cannot start until `restartAt`
	wants: boolean, -- the player asked to run
	quietFor: number, -- seconds since last running (breath comes back after a short delay)
	firedAt: number, -- clock time of the last shot (a shot breaks the run for a moment)
	running: boolean, -- true when the last step ran at sprint speed
}

export type Settings = {
	staminaSeconds: number,
	regenSeconds: number,
	regenDelaySeconds: number,
	restartAt: number,
	afterFireSeconds: number,
}

function SprintRules.new(): State
	return {
		stamina = 1,
		locked = false,
		wants = false,
		quietFor = 0,
		firedAt = -math.huge,
		running = false,
	}
end

-- The player taps sprint. Returns whether `wants` ended up on (a winded fighter cannot start).
function SprintRules.request(s: State, cfg: Settings, on: boolean): boolean
	if on and (s.locked or s.stamina < cfg.restartAt) then
		s.wants = false
		return false
	end
	s.wants = on
	return s.wants
end

function SprintRules.noteFire(s: State, now: number)
	s.firedAt = now
end

-- One tick of `dt` seconds. `moving` = really walking (not just a nudge), `canRun` = alive and in a
-- fight. Returns true when the fighter should be at sprint speed this tick.
function SprintRules.step(
	s: State,
	cfg: Settings,
	dt: number,
	now: number,
	moving: boolean,
	canRun: boolean
): boolean
	if not canRun then
		s.wants = false
	end
	if s.locked and s.stamina >= cfg.restartAt then
		s.locked = false
	end
	local running = canRun
		and s.wants
		and not s.locked
		and moving
		and now - s.firedAt >= cfg.afterFireSeconds
	if running then
		s.quietFor = 0
		s.stamina -= dt / cfg.staminaSeconds
		if s.stamina <= 0 then
			s.stamina = 0
			s.locked = true
			s.wants = false
			running = false
		end
	else
		s.quietFor += dt
		if s.quietFor >= cfg.regenDelaySeconds then
			s.stamina = math.min(1, s.stamina + dt / cfg.regenSeconds)
		end
	end
	s.running = running
	return running
end

-- Walk speed for this tick: sprint speed (capped by the hard limit) or the normal speed.
function SprintRules.speed(
	normal: number,
	running: boolean,
	multiplier: number,
	cap: number
): number
	if not running then
		return normal
	end
	return math.min(normal * multiplier, cap)
end

return SprintRules
