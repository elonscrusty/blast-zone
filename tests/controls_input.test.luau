--!strict
local Harness = require("./harness")
local InputMath = require("../src/client/Controls/InputMath")
local InputState = require("../src/client/Controls/InputState")
local Bindings = require("../src/client/Controls/Bindings")

-- ===== maths =====

Harness.test("diagonal keyboard movement is not faster", function()
	local x, y = InputMath.keyboardMove(true, false, false, true)
	Harness.near(math.sqrt(x * x + y * y), 1, 1e-9)
	local sx, sy = InputMath.keyboardMove(true, false, false, false)
	Harness.eq(sx, 0)
	Harness.eq(sy, 1)
	local ox, oy = InputMath.keyboardMove(true, true, true, true) -- opposite keys cancel
	Harness.eq(ox, 0)
	Harness.eq(oy, 0)
end)

Harness.test(
	"stick: a small wobble is ignored, full push is length 1, past the rim is clamped",
	function()
		local x, y = InputMath.stickFromOffset(3, 3, 60)
		Harness.eq(x, 0)
		Harness.eq(y, 0)
		local fx, fy = InputMath.stickFromOffset(0, -60, 60)
		Harness.near(fx, 0, 1e-9)
		Harness.near(fy, 1, 1e-9) -- finger above the centre (screen y down) pushes UP
		local cx, cy = InputMath.stickFromOffset(500, 0, 60)
		Harness.near(math.sqrt(cx * cx + cy * cy), 1, 1e-9)
		Harness.near(cx, 1, 1e-9)
	end
)

Harness.test("stick starts gently after the deadzone instead of jumping", function()
	local _, y = InputMath.stickFromOffset(0, -60 * 0.2, 60) -- just past the 0.15 deadzone
	Harness.truthy(y > 0 and y < 0.1, "got " .. y)
end)

Harness.test("bad numbers give no input", function()
	local x, y = InputMath.deadzone(0 / 0, 1)
	Harness.eq(x, 0)
	Harness.eq(y, 0)
	local _, _, valid = InputMath.aimFromPointer(math.huge, 0, 0, 0)
	Harness.eq(valid, false)
	local sx, sy = InputMath.stickFromOffset(10, 10, 0)
	Harness.eq(sx, 0)
	Harness.eq(sy, 0)
end)

Harness.test("mouse aim points from the character to the pointer, y up", function()
	local x, y, valid = InputMath.aimFromPointer(500, 100, 400, 300)
	Harness.eq(valid, true)
	Harness.near(math.sqrt(x * x + y * y), 1, 1e-9)
	Harness.truthy(x > 0 and y > 0, "pointer is right and above")
	local _, _, onTop = InputMath.aimFromPointer(402, 301, 400, 300)
	Harness.eq(onTop, false) -- pointer on the character gives no direction
end)

Harness.test("aim speed changes how soon the stick is fully pushed, never the direction", function()
	local x, y = InputMath.applySensitivity(0.3, 0.4, 2)
	Harness.near(x / y, 0.3 / 0.4, 1e-9)
	Harness.near(math.sqrt(x * x + y * y), 1, 1e-9)
	local slowX, slowY = InputMath.applySensitivity(0.6, 0, 0.5)
	Harness.near(slowX, 0.3)
	Harness.eq(slowY, 0)
end)

Harness.test("firing has a gap between on and off so it does not flicker", function()
	Harness.eq(InputMath.firing(0.5, false), false)
	Harness.eq(InputMath.firing(0.6, false), true)
	Harness.eq(InputMath.firing(0.5, true), true)
	Harness.eq(InputMath.firing(0.3, true), false)
end)

-- ===== state machine =====

Harness.test("held keys give movement, releasing stops it", function()
	local s = InputState.new()
	InputState.keyDown(s, "W")
	local _, y = InputState.move(s)
	Harness.eq(y, 1)
	InputState.keyUp(s, "W")
	local x2, y2 = InputState.move(s)
	Harness.eq(x2, 0)
	Harness.eq(y2, 0)
end)

Harness.test("a key repeating does not trigger its action twice", function()
	local s = InputState.new()
	Harness.eq(InputState.keyDown(s, "Space"), "slide")
	Harness.eq(InputState.keyDown(s, "Space"), nil)
	InputState.keyUp(s, "Space")
	Harness.eq(InputState.keyDown(s, "Space"), "slide")
end)

Harness.test("nothing stays stuck after focus loss, elimination or a menu (reset)", function()
	local s = InputState.new()
	InputState.keyDown(s, "W")
	InputState.setMouseDown(s, true)
	InputState.setTouchMove(s, 0.5, 0.5)
	InputState.setPadTrigger(s, 1)
	InputState.reset(s)
	local x, y = InputState.move(s)
	Harness.eq(x, 0)
	Harness.eq(y, 0)
	Harness.eq(InputState.firing(s), false)
end)

Harness.test(
	"controls turned off ignore input, and held keys do not wake up when turned back on",
	function()
		local s = InputState.new()
		InputState.keyDown(s, "W")
		InputState.setEnabled(s, false)
		Harness.eq(InputState.keyDown(s, "R"), nil)
		local _, offY = InputState.move(s)
		Harness.eq(offY, 0)
		InputState.setEnabled(s, true) -- W was still physically down; it must NOT count
		local _, backY = InputState.move(s)
		Harness.eq(backY, 0)
		Harness.eq(InputState.keyDown(s, "R"), "reload")
	end
)

Harness.test("changing device clears what the old device held", function()
	local s = InputState.new()
	InputState.keyDown(s, "D")
	Harness.eq(InputState.noteDevice(s, "gamepad"), true)
	Harness.eq(InputState.noteDevice(s, "gamepad"), false)
	local x = InputState.move(s)
	Harness.eq(x, 0)
end)

Harness.test("the touch stick wins over keys, a pushed gamepad stick over keys", function()
	local s = InputState.new()
	InputState.keyDown(s, "D")
	InputState.setTouchMove(s, -1, 0)
	local x = InputState.move(s)
	Harness.eq(x, -1)
	InputState.setTouchMove(s, 0, 0)
	InputState.setPadMove(s, 0, 1)
	local _, y = InputState.move(s)
	Harness.near(y, 1)
end)

Harness.test("touch: pushing the right stick aims and fires, letting go stops", function()
	local s = InputState.new()
	InputState.noteDevice(s, "touch")
	InputState.setTouchAim(s, 0, 0.9, true)
	local ax, ay, has = InputState.aim(s)
	Harness.eq(has, true)
	Harness.near(ax, 0, 1e-9)
	Harness.near(ay, 1, 1e-9)
	Harness.eq(InputState.firing(s), true)
	InputState.setTouchAim(s, 0, 0, false)
	Harness.eq(InputState.firing(s), false)
	local _, _, has2 = InputState.aim(s)
	Harness.eq(has2, false)
end)

Harness.test("gamepad: trigger fires, right stick aims", function()
	local s = InputState.new()
	InputState.noteDevice(s, "gamepad")
	InputState.setPadAim(s, 1, 0)
	local ax, _, has = InputState.aim(s)
	Harness.eq(has, true)
	Harness.near(ax, 1, 1e-9)
	InputState.setPadTrigger(s, 0.2)
	Harness.eq(InputState.firing(s), false)
	InputState.setPadTrigger(s, 0.9)
	Harness.eq(InputState.firing(s), true)
end)

Harness.test("desktop: mouse button fires and the pointer aims", function()
	local s = InputState.new()
	InputState.setPointer(s, 600, 300, 400, 300)
	InputState.setMouseDown(s, true)
	Harness.eq(InputState.firing(s), true)
	local x, y, has = InputState.aim(s)
	Harness.eq(has, true)
	Harness.near(x, 1, 1e-9)
	Harness.near(y, 0, 1e-9)
	InputState.setMouseDown(s, false)
	Harness.eq(InputState.firing(s), false)
end)

-- ===== bindings =====

Harness.test("every action has keyboard, gamepad and touch controls (phone first)", function()
	for _, name in Bindings.actionOrder do
		local b = Bindings.actions[name]
		Harness.truthy(#b.keyboard > 0, name .. " has no keyboard key")
		Harness.truthy(#b.gamepad > 0, name .. " has no gamepad button")
		Harness.truthy(b.touch ~= "", name .. " has no touch control")
	end
end)

Harness.test("no key or button is bound to two actions", function()
	local seen: { [string]: string } = {}
	for _, name in Bindings.actionOrder do
		local b = Bindings.actions[name]
		for _, code in b.keyboard do
			Harness.eq(seen[code], nil, `{code} is used by {seen[code]} and {name}`)
			seen[code] = name
		end
		for _, code in b.gamepad do
			Harness.eq(seen[code], nil, `{code} is used by {seen[code]} and {name}`)
			seen[code] = name
		end
	end
	for _, codes in Bindings.held.moveKeys :: any do
		for _, code in codes do
			Harness.eq(seen[code], nil, code .. " is both a move key and an action")
		end
	end
end)

Harness.test("the brief's keys are bound: space slides, R reloads, 1-3 pick upgrades", function()
	Harness.eq(Bindings.actionFor("Space"), "slide")
	Harness.eq(Bindings.actionFor("R"), "reload")
	Harness.eq(Bindings.actionFor("One"), "upgrade1")
	Harness.eq(Bindings.actionFor("Three"), "upgrade3")
	Harness.eq(Bindings.actionFor("ButtonA"), "slide")
	Harness.eq(Bindings.actionFor("ButtonL1"), "swap")
	Harness.eq(Bindings.actionFor("Banana"), nil)
end)
