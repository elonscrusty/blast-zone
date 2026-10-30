--!strict
-- Every control on every device, as plain names (KeyCode / UserInputType names, touch widget names).
-- These are PROPOSED bindings from the brief, not copied from the reference game.
-- Rule from CLAUDE.md: every action has a touch button.

export type Binding = {
	keyboard: { string },
	gamepad: { string },
	touch: string, -- name of the on-screen widget
	label: string,
}

local Bindings = {}

-- One-shot actions (fire on press). Moving, aiming and firing are held states, listed below.
Bindings.actions = {
	slide = { keyboard = { "Space" }, gamepad = { "ButtonA" }, touch = "slide", label = "Slide" },
	reload = { keyboard = { "R" }, gamepad = { "ButtonX" }, touch = "reload", label = "Reload" },
	swap = {
		keyboard = { "Q" },
		gamepad = { "ButtonL1", "ButtonR1" },
		touch = "weapon",
		label = "Swap weapon",
	},
	-- Heal pack (piece 42). Q is already Swap here, so F; the pad uses D-pad Down (Left/Up/Right are the cards).
	heal = { keyboard = { "F" }, gamepad = { "DPadDown" }, touch = "heal", label = "Use heal pack" },
	-- Sprint (piece 45): press to start running, press again (or run out of breath) to stop. A toggle,
	-- so a thumb on the move stick never has to hold anything else. Pad: click the left stick.
	sprint = {
		keyboard = { "LeftShift" },
		gamepad = { "ButtonL3" },
		touch = "sprint",
		label = "Sprint",
	},
	-- Big map (piece 47): open or close the whole-arena map. Y is the emote button in the lobby only.
	map = { keyboard = { "M" }, gamepad = { "ButtonY" }, touch = "minimap", label = "Big map" },
	-- Upgrade picks. The card interface (piece 08) listens for these and also has tap targets.
	upgrade1 = {
		keyboard = { "One" },
		gamepad = { "DPadLeft" },
		touch = "card1",
		label = "Upgrade 1",
	},
	upgrade2 = {
		keyboard = { "Two" },
		gamepad = { "DPadUp" },
		touch = "card2",
		label = "Upgrade 2",
	},
	upgrade3 = {
		keyboard = { "Three" },
		gamepad = { "DPadRight" },
		touch = "card3",
		label = "Upgrade 3",
	},
} :: { [string]: Binding }

-- Stable order for UI lists and tests.
Bindings.actionOrder =
	{ "slide", "reload", "swap", "heal", "sprint", "map", "upgrade1", "upgrade2", "upgrade3" }

Bindings.held = {
	moveKeys = {
		up = { "W", "Up" },
		down = { "S", "Down" },
		left = { "A", "Left" },
		right = { "D", "Right" },
	},
	moveStick = "Thumbstick1",
	aimStick = "Thumbstick2",
	fireMouse = "MouseButton1",
	fireTriggers = { "ButtonR2" },
	-- Touch: left stick moves, right stick aims and fires while pushed.
	touchMove = "moveStick",
	touchAim = "fireStick",
}

-- Gamepad buttons for the menus (they are not combat actions, so they never clash with them).
-- Shoulders also flip spectate targets and nudge settings sliders. Both only happen while controls
-- are off or a menu is open, when weapon swap is not in use. (The D-pad is left to the upgrade
-- cards, which read it themselves.)
Bindings.menu = {
	settings = "ButtonSelect", -- open or close settings from anywhere
	back = "ButtonB", -- close the menu on top
	spectatePrev = "ButtonL1",
	spectateNext = "ButtonR1",
	sliderLess = "ButtonL1",
	sliderMore = "ButtonR1",
}

-- Which action a key / button triggers, built once.
local lookup: { [string]: string } = {}
for _, name in Bindings.actionOrder do
	local b = Bindings.actions[name]
	for _, code in b.keyboard do
		lookup[code] = name
	end
	for _, code in b.gamepad do
		lookup[code] = name
	end
end

function Bindings.actionFor(code: string): string?
	return lookup[code]
end

return Bindings
