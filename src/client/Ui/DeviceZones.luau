--!strict
-- Parts of a real phone screen that our UI does not own, in dp (the points Roblox lays GUI out in).
-- The Studio emulator draws none of them, so a layout can look clean there and still pile up on a phone.
-- tests/phone_audit.test.luau lays every screen out on many real phone shapes and fails if a piece of
-- our UI lands on one of these or on another piece. Measured on a real iPhone (carter, 2026-10-31).
--
--   Roblox top bar: a pill at the top left (Roblox menu + chat) that is drawn over every ScreenGui.
--   Device cut-outs: the notch and rounded corners (left / right in landscape) and the home bar (bottom).
-- The game hides the Roblox player list, backpack, emote and health buttons (CoreGuiSetup), so the top right is ours.

local DeviceZones = {}

DeviceZones.TOP_BAR_HEIGHT = 58 -- Roblox's top bar, top of the screen
DeviceZones.MIN_TAP = 44 -- dp, the smallest thing a thumb can hit (Apple's rule, Roblox's too)
DeviceZones.NOTCH_MAX = 64 -- the widest side cut-out of a phone held sideways, in dp (iPhone 59)
DeviceZones.LEFT_CLUSTER_WIDTH = 112 -- menu + chat buttons, from the left edge of the safe area

export type Box = { x: number, y: number, w: number, h: number }

-- Where the Roblox buttons are, on a screen `width` wide whose left cut-out is `safeLeft` dp.
function DeviceZones.robloxTopLeft(safeLeft: number): Box
	return {
		x = safeLeft,
		y = 0,
		w = DeviceZones.LEFT_CLUSTER_WIDTH,
		h = DeviceZones.TOP_BAR_HEIGHT,
	}
end

return DeviceZones
