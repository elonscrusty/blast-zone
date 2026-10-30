--!strict
-- Pure input maths (plain numbers, no Roblox types) so Lune can test it.
-- Screen vectors: x to the right, y UP (the same way as the movement stick pushes).

local InputMath = {}

InputMath.STICK_DEADZONE = 0.15
InputMath.FIRE_ON = 0.55 -- aim stick pushed this far starts firing
InputMath.FIRE_OFF = 0.4 -- and it must drop under this to stop (no flicker at the edge)
InputMath.POINTER_MIN_DISTANCE = 12 -- pixels; a mouse on top of the character gives no aim

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function length(x: number, y: number): number
	return math.sqrt(x * x + y * y)
end

-- Round deadzone, then stretch what is left back to 0..1 so the stick starts gently.
function InputMath.deadzone(x: number, y: number, inner: number?): (number, number)
	if not (finite(x) and finite(y)) then
		return 0, 0
	end
	local dz = inner or InputMath.STICK_DEADZONE
	local mag = length(x, y)
	if mag <= dz then
		return 0, 0
	end
	local scaled = math.min(1, (mag - dz) / (1 - dz))
	return x / mag * scaled, y / mag * scaled
end

-- Touch stick: finger offset from the stick centre in pixels (screen y points DOWN).
-- Returns a vector of length 0..1 with y pointing UP.
function InputMath.stickFromOffset(
	dx: number,
	dy: number,
	radius: number,
	inner: number?
): (number, number)
	if radius <= 0 then
		return 0, 0
	end
	local x, y = dx / radius, -dy / radius
	local mag = length(x, y)
	if mag > 1 then
		x, y = x / mag, y / mag
	end
	return InputMath.deadzone(x, y, inner)
end

-- WASD / arrow keys. Diagonals are normalised so they are not faster.
function InputMath.keyboardMove(
	up: boolean,
	down: boolean,
	left: boolean,
	right: boolean
): (number, number)
	local x = (if right then 1 else 0) - (if left then 1 else 0)
	local y = (if up then 1 else 0) - (if down then 1 else 0)
	if x ~= 0 and y ~= 0 then
		local inv = 1 / math.sqrt(2)
		return x * inv, y * inv
	end
	return x, y
end

-- Mouse aim: direction from the character's place on screen to the pointer.
-- Returns x, y (unit, y UP) and whether the pointer is far enough away to mean anything.
function InputMath.aimFromPointer(
	pointerX: number,
	pointerY: number,
	originX: number,
	originY: number
): (number, number, boolean)
	local dx, dy = pointerX - originX, originY - pointerY
	if not (finite(dx) and finite(dy)) then
		return 0, 0, false
	end
	local mag = length(dx, dy)
	if mag < InputMath.POINTER_MIN_DISTANCE then
		return 0, 0, false
	end
	return dx / mag, dy / mag, true
end

-- Aim stick sensitivity (1 = normal). Higher reaches full push sooner; the direction never changes.
function InputMath.applySensitivity(x: number, y: number, sensitivity: number): (number, number)
	local mag = length(x, y)
	if mag <= 0 or not finite(sensitivity) or sensitivity <= 0 then
		return 0, 0
	end
	local scaled = math.min(1, mag * sensitivity)
	return x / mag * scaled, y / mag * scaled
end

-- Firing from an aim stick or a trigger, with a gap between "on" and "off".
function InputMath.firing(magnitude: number, wasFiring: boolean): boolean
	if wasFiring then
		return magnitude >= InputMath.FIRE_OFF
	end
	return magnitude >= InputMath.FIRE_ON
end

function InputMath.magnitude(x: number, y: number): number
	return length(x, y)
end

return InputMath
