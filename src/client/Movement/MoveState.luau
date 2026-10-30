--!strict
-- What the local player's feet are doing (piece 45): sprint breath and slide charges. Written only
-- by MoveSystem from the server's SprintState and SlideState; read by the touch buttons (and any
-- HUD Claude Design draws). Never decides anything.

export type State = {
	wantsSprint: boolean, -- the player toggled running on
	running: boolean, -- the server says they are really running
	stamina: number, -- 0 .. 1
	locked: boolean, -- out of breath
	slideCharges: number,
	slideMax: number,
}

local MoveState = {}

local state: State = {
	wantsSprint = false,
	running = false,
	stamina = 1,
	locked = false,
	slideCharges = 1,
	slideMax = 1,
}

function MoveState.get(): State
	return state
end

-- The server's word on breath. If it says winded, the toggle goes back off.
function MoveState.setSprint(stamina: number, running: boolean, locked: boolean)
	state.stamina = math.clamp(stamina, 0, 1)
	state.running = running
	state.locked = locked
	if locked then
		state.wantsSprint = false
	end
end

function MoveState.setSlide(charges: number, max: number)
	state.slideMax = math.max(1, math.floor(max))
	state.slideCharges = math.clamp(math.floor(charges), 0, state.slideMax)
end

-- Tap: flip the toggle. Returns the new value (a winded runner cannot turn it on).
function MoveState.toggleSprint(): boolean
	state.wantsSprint = not state.wantsSprint and not state.locked and state.stamina > 0
	return state.wantsSprint
end

function MoveState.clearSprint()
	state.wantsSprint = false
	state.running = false
	state.stamina = 1
	state.locked = false
end

return MoveState
