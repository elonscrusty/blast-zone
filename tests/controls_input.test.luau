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

-- ===== menus, unplugging, focus (piece 15) =====

Harness.test(
	"a menu on top ignores movement, fire and action keys, and drops what was held",
	function()
		local s = InputState.new()
		InputState.keyDown(s, "D")
		InputState.setMouseDown(s, true)
		Harness.eq(InputState.setModal(s, true), true)
		Harness.eq(InputState.setModal(s, true), false)
		local x = InputState.move(s)
		Harness.eq(x, 0)
		Harness.eq(InputState.firing(s), false)
		Harness.eq(InputState.keyDown(s, "Space"), nil) -- A / Space must not slide while a menu is open
		InputState.setTouchMove(s, 1, 0)
		InputState.setPadTrigger(s, 1)
		InputState.setModal(s, false) -- D is still physically down, it must not wake up
		local mx = InputState.move(s)
		Harness.eq(mx, 0)
		Harness.eq(InputState.keyDown(s, "Space"), "slide")
	end
)

Harness.test(
	"unplugging the gamepad drops its input and hands back to touch or keyboard",
	function()
		local s = InputState.new()
		InputState.noteDevice(s, "gamepad")
		InputState.setPadMove(s, 0, 1)
		InputState.setPadTrigger(s, 1)
		Harness.eq(InputState.padDisconnected(s, true), "touch")
		local _, y = InputState.move(s)
		Harness.eq(y, 0)
		Harness.eq(InputState.firing(s), false)
		local k = InputState.new()
		InputState.noteDevice(k, "gamepad")
		Harness.eq(InputState.padDisconnected(k, false), "keyboard")
		-- a pad unplugged while the player was on the keyboard changes nothing but the pad input
		local other = InputState.new()
		Harness.eq(InputState.padDisconnected(other, true), "keyboard")
	end
)

Harness.test("menu buttons never clash with combat actions", function()
	for name, code in Bindings.menu do
		local sharedShoulder = string.sub(name, 1, 8) == "spectate"
			or string.sub(name, 1, 6) == "slider"
		if not sharedShoulder then
			Harness.eq(Bindings.actionFor(code), nil, `{name} ({code}) is also a combat action`)
		end
	end
	-- the shoulders do double duty only while controls are off or a menu is open
	Harness.eq(Bindings.actionFor(Bindings.menu.spectatePrev), "swap")
	Harness.eq(Bindings.actionFor(Bindings.menu.sliderMore), "swap")
	Harness.eq(Bindings.actionFor("DPadLeft"), "upgrade1") -- the D-pad stays with the cards
end)

local FocusMap = require("../src/client/Controls/FocusMap")

local function item(id: string, x: number, y: number, priority: number?): FocusMap.Item
	return { id = id, x = x, y = y, w = 100, h = 40, priority = priority }
end

Harness.test(
	"focus starts on the top-priority button, else top-left, the same every time",
	function()
		local items = { item("settings", 300, 400), item("play", 300, 300), item("bots", 100, 100) }
		Harness.eq(FocusMap.first(items), "bots")
		items[2] = item("play", 300, 300, 10)
		Harness.eq(FocusMap.first(items), "play")
		Harness.eq(FocusMap.first({}), nil)
		local row = { item("b", 200, 100), item("a", 50, 104) } -- one row, a little off
		Harness.eq(FocusMap.first(row), "a")
	end
)

Harness.test("a direction moves only toward a button that lies that way", function()
	local cards = { item("c1", 100, 300), item("c2", 250, 300), item("c3", 400, 300) }
	Harness.eq(FocusMap.neighbor(cards, "c1", "right"), "c2")
	Harness.eq(FocusMap.neighbor(cards, "c2", "right"), "c3")
	Harness.eq(FocusMap.neighbor(cards, "c3", "left"), "c2")
	Harness.eq(FocusMap.neighbor(cards, "c3", "right"), nil) -- edge: nothing to wrap to
	Harness.eq(FocusMap.neighbor(cards, "c2", "up"), nil)
	Harness.eq(FocusMap.neighbor(cards, "zzz", "up"), nil)
end)

Harness.test("a button straight across beats one that is far to the side", function()
	local items = { item("from", 300, 300), item("near", 300, 200), item("farSide", 700, 190) }
	Harness.eq(FocusMap.neighbor(items, "from", "up"), "near")
end)

Harness.test("links keep the cursor on the button when nothing lies that way", function()
	local links = FocusMap.links({ item("a", 0, 0), item("b", 200, 0) })
	Harness.eq(links.a.right, "b")
	Harness.eq(links.a.left, "a")
	Harness.eq(links.a.up, "a")
	Harness.eq(links.b.left, "a")
end)

Harness.test("a menu on top owns focus; otherwise every button is on offer", function()
	local scopes: { FocusMap.Scope } = {
		{ name = "MatchFlow", modal = false, items = { item("play", 0, 0) } },
		{ name = "BotBanner", modal = false, items = { item("bots", 0, 100) } },
	}
	Harness.eq(#FocusMap.active(scopes), 2)
	Harness.eq(FocusMap.hasModal(scopes), false)
	table.insert(scopes, { name = "Settings", modal = true, items = { item("done", 0, 0) } })
	Harness.eq(#FocusMap.active(scopes), 1)
	Harness.eq(FocusMap.active(scopes)[1].id, "done")
	Harness.eq(FocusMap.hasModal(scopes), true)
	scopes[3].items = {} -- a closed menu with no visible buttons does not block the rest
	Harness.eq(FocusMap.hasModal(scopes), false)
	Harness.eq(#FocusMap.active(scopes), 2)
end)

Harness.test("focus stays put while its button exists and restarts when it vanishes", function()
	local items = { item("play", 0, 0, 10), item("settings", 0, 100) }
	Harness.eq(FocusMap.settle(items, "settings"), "settings")
	Harness.eq(FocusMap.settle(items, "gone"), "play")
	Harness.eq(FocusMap.settle(items, nil), "play")
	Harness.eq(FocusMap.settle({}, "play"), nil)
	local zero = { { id = "z", x = 0, y = 0, w = 0, h = 0 } :: FocusMap.Item }
	Harness.eq(FocusMap.first(zero), nil) -- hidden or empty buttons cannot take focus
end)

local ChipModel = require("../src/client/Controls/ChipModel")

Harness.test("chips follow the offer: one per option up to three, none once closed", function()
	local c = ChipModel.new()
	Harness.eq(ChipModel.applyOffer(c, { offerId = "o1", options = { {}, {}, {} } }), 3)
	Harness.eq(ChipModel.visible(c, 3), true)
	Harness.eq(ChipModel.visible(c, 4), false)
	Harness.eq(ChipModel.applyOffer(c, { offerId = "o2", options = { {}, {} } }), 2)
	Harness.eq(ChipModel.visible(c, 3), false)
	Harness.eq(ChipModel.applyOffer(c, { offerId = "o3", options = { {}, {}, {}, {}, {} } }), 3)
	ChipModel.clear(c)
	Harness.eq(ChipModel.visible(c, 1), false)
end)

Harness.test("a bad or empty offer shows no chips", function()
	local c = ChipModel.new()
	Harness.eq(ChipModel.applyOffer(c, nil), 0)
	Harness.eq(ChipModel.applyOffer(c, "x"), 0)
	Harness.eq(ChipModel.applyOffer(c, { options = { {} } }), 0) -- no offer id
	Harness.eq(ChipModel.applyOffer(c, { offerId = "o", options = 5 }), 0)
	Harness.eq(ChipModel.applyOffer(c, { offerId = "o", options = {} }), 0)
	Harness.eq(ChipModel.fighting("Active"), true)
	Harness.eq(ChipModel.fighting("FinalPressure"), true)
	Harness.eq(ChipModel.fighting("Results"), false)
	Harness.eq(ChipModel.fighting(nil), false)
end)

-- ===== turning the camera =====

Harness.test("a drag is collected and handed over once", function()
	local s = InputState.new()
	InputState.addLook(s, 12)
	InputState.addLook(s, -5)
	local pixels = InputState.takeLook(s)
	Harness.eq(pixels, 7)
	Harness.eq((InputState.takeLook(s)), 0) -- taken: it does not turn again
end)

Harness.test("a drag does nothing while controls are off or a menu is open", function()
	local s = InputState.new()
	InputState.setEnabled(s, false)
	InputState.addLook(s, 50)
	InputState.setEnabled(s, true)
	Harness.eq((InputState.takeLook(s)), 0)
	InputState.setModal(s, true)
	InputState.addLook(s, 50)
	Harness.eq((InputState.takeLook(s)), 0)
	InputState.setModal(s, false)
	InputState.addLook(s, 0 / 0) -- a bad number is ignored
	InputState.addLook(s, math.huge)
	Harness.eq((InputState.takeLook(s)), 0)
end)

Harness.test("a drag held when controls turn off does not turn the view later", function()
	local s = InputState.new()
	InputState.addLook(s, 80)
	InputState.setEnabled(s, false)
	InputState.setEnabled(s, true)
	Harness.eq((InputState.takeLook(s)), 0)
end)

Harness.test("gamepad: L2 plus the right stick turns the camera instead of aiming", function()
	local s = InputState.new()
	InputState.noteDevice(s, "gamepad")
	InputState.setPadAim(s, 1, 0)
	local _, stick = InputState.takeLook(s)
	Harness.eq(stick, 0) -- no L2: the stick only aims
	local _, _, aiming = InputState.aim(s)
	Harness.eq(aiming, true)

	InputState.setPadLookHold(s, true)
	_, stick = InputState.takeLook(s)
	Harness.truthy(stick > 0.9, "stick should turn right, got " .. stick)
	_, _, aiming = InputState.aim(s)
	Harness.eq(aiming, false) -- and it stops aiming while it turns

	InputState.setPadAim(s, -1, 0)
	_, stick = InputState.takeLook(s)
	Harness.truthy(stick < -0.9, "stick should turn left, got " .. stick)

	InputState.setPadLookHold(s, false)
	_, _, aiming = InputState.aim(s)
	Harness.eq(aiming, true) -- let go of L2: aim is back
end)

Harness.test("gamepad turning ignores a tiny stick wobble and does not use aim speed", function()
	local s = InputState.new()
	InputState.noteDevice(s, "gamepad")
	InputState.setPadLookHold(s, true)
	InputState.setPadAim(s, 0.05, 0)
	Harness.eq(select(2, InputState.takeLook(s)), 0)
	s.aimSensitivity = 3
	InputState.setPadAim(s, 0.5, 0)
	local half = select(2, InputState.takeLook(s))
	s.aimSensitivity = 1
	InputState.setPadAim(s, 0.5, 0)
	Harness.near(half, select(2, InputState.takeLook(s)), 1e-9)
end)

Harness.test("L2 and the stick are forgotten when the controls clear", function()
	local s = InputState.new()
	InputState.noteDevice(s, "gamepad")
	InputState.setPadLookHold(s, true)
	InputState.setPadAim(s, 1, 0)
	InputState.reset(s)
	Harness.eq(select(2, InputState.takeLook(s)), 0)
	InputState.setPadAim(s, 1, 0)
	local _, _, aiming = InputState.aim(s)
	Harness.eq(aiming, true) -- L2 did not stay stuck down
end)

Harness.test("a phone drag works, and the stick does not turn the camera on a phone", function()
	local s = InputState.new()
	InputState.noteDevice(s, "touch")
	InputState.addLook(s, 30)
	local pixels, stick = InputState.takeLook(s)
	Harness.eq(pixels, 30)
	Harness.eq(stick, 0)
end)

-- ===== walking in the lobby =====
Harness.test("lobby: you can walk with the stick, keys and pad while fighting is off", function()
	local s = InputState.new()
	InputState.setEnabled(s, false)
	InputState.setWalking(s, true)
	InputState.setTouchMove(s, 0.5, 1)
	local x, y = InputState.move(s)
	Harness.eq(x, 0.5)
	Harness.eq(y, 1)
	InputState.reset(s)
	InputState.keyDown(s, "W")
	local _, fy = InputState.move(s)
	Harness.eq(fy, 1)
	InputState.reset(s)
	InputState.setPadMove(s, 1, 0)
	local px = InputState.move(s)
	Harness.truthy(px > 0, "pad did not walk")
end)

Harness.test("lobby: walking never aims, fires, slides, reloads or turns the camera", function()
	local s = InputState.new()
	InputState.setEnabled(s, false)
	InputState.setWalking(s, true)
	InputState.noteDevice(s, "touch")
	InputState.setTouchAim(s, 1, 0, true)
	local _, _, aiming = InputState.aim(s)
	Harness.eq(aiming, false)
	Harness.eq(InputState.firing(s), false)
	InputState.setMouseDown(s, true)
	Harness.eq(InputState.firing(s), false)
	InputState.addLook(s, 40)
	local pixels = InputState.takeLook(s)
	Harness.eq(pixels, 0)
	-- an action key (slide, reload...) is held but does nothing in the lobby
	Harness.eq(InputState.keyDown(s, "Space"), nil)
	Harness.eq(InputState.keyDown(s, "R"), nil)
end)

Harness.test("lobby: a menu stops walking, and walking off stops everything", function()
	local s = InputState.new()
	InputState.setEnabled(s, false)
	InputState.setWalking(s, true)
	InputState.setTouchMove(s, 1, 0)
	InputState.setModal(s, true)
	local mx, my = InputState.move(s)
	Harness.eq(mx, 0)
	Harness.eq(my, 0)
	InputState.setModal(s, false)
	InputState.setTouchMove(s, 1, 0)
	InputState.setWalking(s, false) -- the match starts: held input is dropped
	local fx, fy = InputState.move(s)
	Harness.eq(fx, 0)
	Harness.eq(fy, 0)
	InputState.setTouchMove(s, 1, 0) -- and a thumb cannot walk outside the lobby when fighting is off too
	local ox = InputState.move(s)
	Harness.eq(ox, 0)
end)

Harness.test("combat is unchanged: actions still fire while fighting", function()
	local s = InputState.new()
	InputState.setEnabled(s, true)
	Harness.eq(InputState.keyDown(s, "R"), "reload")
end)
