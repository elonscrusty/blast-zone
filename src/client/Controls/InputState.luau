--!strict
-- What the player is holding right now, from every device, as one state machine.
-- Pure (strings and numbers only) so Lune can test the rules that matter:
--   * input never stays stuck (focus loss, elimination, device change, menu open all clear it)
--   * keys held while the controls are off do not "wake up" when they come back on
--   * diagonal movement is not faster

local Bindings = require("./Bindings")
local InputMath = require("./InputMath")

export type Device = "keyboard" | "touch" | "gamepad"

export type InputState = {
	enabled: boolean,
	modal: boolean, -- a menu has the player's attention: input is ignored and held input is cleared
	device: Device,
	keys: { [string]: boolean },
	touchMove: { x: number, y: number },
	touchAim: { x: number, y: number, active: boolean },
	padMove: { x: number, y: number },
	padAim: { x: number, y: number },
	padTrigger: number,
	padLookHold: boolean, -- L2 held: the right stick turns the camera instead of aiming
	padLookX: number, -- right stick sideways, deadzoned (before aim speed), -1..1
	lookPixels: number, -- drag since the camera last asked (right = positive): mouse button 2, touch drag
	mouseAim: { x: number, y: number, valid: boolean },
	mouseDown: boolean,
	firingStick: boolean,
	aimSensitivity: number,
}

local InputStateModule = {}

-- Input only counts when controls are on and no menu is open.
local function live(s: InputState): boolean
	return s.enabled and not s.modal
end

function InputStateModule.new(): InputState
	return {
		enabled = true,
		modal = false,
		device = "keyboard",
		keys = {},
		touchMove = { x = 0, y = 0 },
		touchAim = { x = 0, y = 0, active = false },
		padMove = { x = 0, y = 0 },
		padAim = { x = 0, y = 0 },
		padTrigger = 0,
		padLookHold = false,
		padLookX = 0,
		lookPixels = 0,
		mouseAim = { x = 0, y = 0, valid = false },
		mouseDown = false,
		firingStick = false,
		aimSensitivity = 1,
	}
end

-- Forget everything held. Call on focus loss, elimination, a menu opening, or leaving combat.
function InputStateModule.reset(s: InputState)
	s.keys = {}
	s.touchMove = { x = 0, y = 0 }
	s.touchAim = { x = 0, y = 0, active = false }
	s.padMove = { x = 0, y = 0 }
	s.padAim = { x = 0, y = 0 }
	s.padTrigger = 0
	s.padLookHold = false
	s.padLookX = 0
	s.lookPixels = 0
	s.mouseDown = false
	s.firingStick = false
end

-- Turning controls off also clears them, so nothing is held when they turn back on.
function InputStateModule.setEnabled(s: InputState, enabled: boolean)
	if s.enabled == enabled then
		return
	end
	s.enabled = enabled
	InputStateModule.reset(s)
end

-- Switching device (say a gamepad plugged in while a key is held) drops what the old one held.
-- Returns true if the device changed.
function InputStateModule.noteDevice(s: InputState, device: Device): boolean
	if s.device == device then
		return false
	end
	InputStateModule.reset(s)
	s.device = device
	return true
end

-- A menu opened or closed. Either way nothing held carries over. Returns true if it changed.
function InputStateModule.setModal(s: InputState, modal: boolean): boolean
	if s.modal == modal then
		return false
	end
	s.modal = modal
	InputStateModule.reset(s)
	return true
end

-- The gamepad was unplugged. Whatever it held is dropped, and if it was the device in use the
-- player is handed back to the touch screen or the keyboard (touch wins on a phone).
-- Returns the device now in use.
function InputStateModule.padDisconnected(s: InputState, hasTouch: boolean): Device
	InputStateModule.reset(s)
	if s.device == "gamepad" then
		s.device = if hasTouch then "touch" else "keyboard"
	end
	return s.device
end

-- Key or button went down. Returns the one-shot action it triggers, if any.
function InputStateModule.keyDown(s: InputState, code: string): string?
	if not live(s) then
		return nil
	end
	local already = s.keys[code] == true
	s.keys[code] = true
	if already then
		return nil -- key repeat does not trigger twice
	end
	return Bindings.actionFor(code)
end

function InputStateModule.keyUp(s: InputState, code: string)
	s.keys[code] = nil
end

local function anyDown(s: InputState, codes: { string }): boolean
	for _, c in codes do
		if s.keys[c] then
			return true
		end
	end
	return false
end

function InputStateModule.setTouchMove(s: InputState, x: number, y: number)
	if live(s) then
		s.touchMove = { x = x, y = y }
	end
end

function InputStateModule.setTouchAim(s: InputState, x: number, y: number, active: boolean)
	if not live(s) then
		return
	end
	local ax, ay = InputMath.applySensitivity(x, y, s.aimSensitivity)
	s.touchAim = { x = ax, y = ay, active = active and (ax ~= 0 or ay ~= 0) }
end

function InputStateModule.setPadMove(s: InputState, x: number, y: number)
	if live(s) then
		local dx, dy = InputMath.deadzone(x, y)
		s.padMove = { x = dx, y = dy }
	end
end

function InputStateModule.setPadAim(s: InputState, x: number, y: number)
	if live(s) then
		local dx, dy = InputMath.deadzone(x, y)
		local ax, ay = InputMath.applySensitivity(dx, dy, s.aimSensitivity)
		s.padAim = { x = ax, y = ay }
		s.padLookX = dx
	end
end

-- L2 on the gamepad: while held, the right stick turns the camera and stops aiming.
function InputStateModule.setPadLookHold(s: InputState, held: boolean)
	if live(s) then
		s.padLookHold = held
	end
end

-- The view was dragged by `pixels` (right = positive): a mouse with button 2 down, or a thumb on
-- the free side of the touch screen. Collected until the camera takes it.
function InputStateModule.addLook(s: InputState, pixels: number)
	if live(s) and pixels == pixels and pixels ~= math.huge and pixels ~= -math.huge then
		s.lookPixels += pixels
	end
end

-- What the player asked of the camera since the last call: (drag pixels, stick -1..1).
-- The drag is handed over once and starts again from zero.
function InputStateModule.takeLook(s: InputState): (number, number)
	if not live(s) then
		s.lookPixels = 0
		return 0, 0
	end
	local pixels = s.lookPixels
	s.lookPixels = 0
	local stick = if s.device == "gamepad" and s.padLookHold then s.padLookX else 0
	return pixels, stick
end

function InputStateModule.setPadTrigger(s: InputState, amount: number)
	if live(s) then
		s.padTrigger = if amount == amount then math.clamp(amount, 0, 1) else 0
	end
end

-- Pointer position in pixels and where the character is on screen.
function InputStateModule.setPointer(
	s: InputState,
	px: number,
	py: number,
	originX: number,
	originY: number
)
	if not live(s) then
		return
	end
	local x, y, valid = InputMath.aimFromPointer(px, py, originX, originY)
	s.mouseAim = { x = x, y = y, valid = valid }
end

function InputStateModule.setMouseDown(s: InputState, down: boolean)
	if live(s) then
		s.mouseDown = down
	end
end

-- Movement as x right, y forward (screen up), length at most 1. The touch stick wins while it is
-- touched, then a pushed gamepad stick, then the keyboard.
function InputStateModule.move(s: InputState): (number, number)
	if not live(s) then
		return 0, 0
	end
	if s.touchMove.x ~= 0 or s.touchMove.y ~= 0 then
		return s.touchMove.x, s.touchMove.y
	end
	if s.padMove.x ~= 0 or s.padMove.y ~= 0 then
		return s.padMove.x, s.padMove.y
	end
	local m = Bindings.held.moveKeys
	return InputMath.keyboardMove(
		anyDown(s, m.up),
		anyDown(s, m.down),
		anyDown(s, m.left),
		anyDown(s, m.right)
	)
end

-- Aim as a unit vector (x right, y up) plus whether anything is aiming. The device that was used
-- last wins when several could aim.
function InputStateModule.aim(s: InputState): (number, number, boolean)
	if not live(s) then
		return 0, 0, false
	end
	if s.device == "touch" then
		if s.touchAim.active then
			local m = InputMath.magnitude(s.touchAim.x, s.touchAim.y)
			return s.touchAim.x / m, s.touchAim.y / m, true
		end
		return 0, 0, false
	elseif s.device == "gamepad" then
		if s.padLookHold then
			return 0, 0, false -- the stick is turning the camera
		end
		local m = InputMath.magnitude(s.padAim.x, s.padAim.y)
		if m > 0 then
			return s.padAim.x / m, s.padAim.y / m, true
		end
		return 0, 0, false
	end
	return s.mouseAim.x, s.mouseAim.y, s.mouseAim.valid
end

-- Call once per frame: fire state needs the "on" / "off" gap between frames.
function InputStateModule.firing(s: InputState): boolean
	if not live(s) then
		s.firingStick = false
		return false
	end
	local fire = false
	if s.device == "touch" then
		fire = InputMath.firing(InputMath.magnitude(s.touchAim.x, s.touchAim.y), s.firingStick)
			and s.touchAim.active
		s.firingStick = fire
	elseif s.device == "gamepad" then
		fire = InputMath.firing(s.padTrigger, s.firingStick)
		s.firingStick = fire
	else
		fire = s.mouseDown
		s.firingStick = fire
	end
	return fire
end

return InputStateModule
