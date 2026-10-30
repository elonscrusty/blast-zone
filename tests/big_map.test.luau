--!strict
-- piece 47: the big map. World point -> panel spot (turned with the camera), circle size, when the
-- map may open and close, and that the map sits clear of the thumbs, buttons and the card band.
local Harness = require("./harness")
local BigMapMath = require("../src/client/Hud/BigMapMath")
local BigMapModel = require("../src/client/Hud/BigMapModel")
local Bindings = require("../src/client/Controls/Bindings")
local Config = require("../src/shared/Config")
local Layout = require("../src/client/Hud/Layout")

local ARENA: BigMapMath.Arena = { size = 220, centerX = 10, centerZ = -20 }

-- ===== maths =====

Harness.test(
	"big map: the arena centre is the middle of the panel, whatever the camera does",
	function()
		for _, yaw in { 0, 45, 90, 137, 270 } do
			local s = BigMapMath.point(10, -20, ARENA, yaw)
			Harness.near(s.x, 0.5, 1e-9)
			Harness.near(s.y, 0.5, 1e-9)
		end
	end
)

Harness.test("big map: with the camera at 0, east is right and south is down", function()
	local east = BigMapMath.point(10 + 55, -20, ARENA, 0)
	Harness.truthy(east.x > 0.5, "east is right of the middle")
	Harness.near(east.y, 0.5, 1e-9)
	local south = BigMapMath.point(10, -20 + 55, ARENA, 0)
	Harness.truthy(south.y > 0.5, "south is below the middle")
	Harness.near(south.x, 0.5, 1e-9)
end)

Harness.test("big map: turning the camera 90 degrees puts east at the top", function()
	local east = BigMapMath.point(10 + 55, -20, ARENA, 90)
	Harness.near(east.x, 0.5, 1e-9)
	Harness.truthy(east.y < 0.5, "east is up when the camera looks east")
end)

Harness.test("big map: the dot agrees with the turned arena square for any camera", function()
	-- The arena square is drawn turned by arenaRotation and its corners must stay on the panel.
	for yaw = 0, 350, 10 do
		for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
			local s = BigMapMath.point(
				ARENA.centerX + corner[1] * ARENA.size / 2,
				ARENA.centerZ + corner[2] * ARENA.size / 2,
				ARENA,
				yaw
			)
			local dx, dy = (s.x - 0.5) * 2, (s.y - 0.5) * 2
			Harness.truthy(dx * dx + dy * dy <= 1 + 1e-9, `corner leaves the panel at yaw {yaw}`)
		end
	end
	Harness.eq(BigMapMath.arenaRotation(30), -30)
end)

Harness.test("big map: a point past the edge is held on the panel", function()
	local s = BigMapMath.point(9999, -9999, ARENA, 0)
	Harness.truthy(s.x >= 0 and s.x <= 1 and s.y >= 0 and s.y <= 1)
end)

Harness.test("big map: a ring is placed and sized inside the arena square", function()
	local whole = BigMapMath.ring(10, -20, 110, ARENA)
	Harness.near(whole.x, 0.5, 1e-9)
	Harness.near(whole.y, 0.5, 1e-9)
	Harness.near(whole.size, 1, 1e-9, "radius = half the arena fills the square")
	local small = BigMapMath.ring(10 + 55, -20, 20, ARENA)
	Harness.near(small.x, 0.75, 1e-9)
	Harness.near(small.size, 20 / 110, 1e-9)
	Harness.eq(BigMapMath.ring(10, -20, 1e6, ARENA).size, BigMapMath.MAX_RING)
end)

Harness.test("big map: the first zone covers the arena, a late one is a small ring", function()
	local first = BigMapMath.ring(0, 0, Config.Zone.initialRadius, ARENA)
	Harness.truthy(first.size >= 1)
	local last = BigMapMath.ring(0, 0, Config.Zone.suddenDeath.targetRadius, ARENA)
	Harness.truthy(last.size < 0.5)
end)

-- ===== when it opens and closes =====

Harness.test("big map: a tap opens it, another tap closes it", function()
	local m = BigMapModel.new()
	BigMapModel.toggle(m, 5, true)
	Harness.eq(BigMapModel.step(m, 5.1, true, 0), true)
	BigMapModel.toggle(m, 6, true)
	Harness.eq(BigMapModel.step(m, 6.1, true, 0), false)
end)

Harness.test("big map: it cannot open when the HUD is hidden (lobby, countdown, dead)", function()
	local m = BigMapModel.new()
	BigMapModel.toggle(m, 5, false)
	Harness.eq(BigMapModel.step(m, 5.1, false, 0), false)
end)

Harness.test("big map: it closes the moment the HUD goes away", function()
	local m = BigMapModel.new()
	BigMapModel.toggle(m, 5, true)
	Harness.eq(BigMapModel.step(m, 6, true, 0), true)
	Harness.eq(BigMapModel.step(m, 7, false, 0), false, "eliminated or match over")
	Harness.eq(BigMapModel.step(m, 8, true, 0), false, "and it stays shut when the HUD returns")
end)

Harness.test("big map: with an auto-close time it is only a peek; 0 means it stays", function()
	local peek = BigMapModel.new()
	BigMapModel.toggle(peek, 10, true)
	Harness.eq(BigMapModel.step(peek, 13.9, true, 4), true)
	Harness.eq(BigMapModel.step(peek, 14, true, 4), false)
	local stays = BigMapModel.new()
	BigMapModel.toggle(stays, 10, true)
	Harness.eq(BigMapModel.step(stays, 5000, true, 0), true)
end)

-- ===== controls and layout =====

Harness.test("big map: M and pad Y open it, and it has a touch button (the minimap)", function()
	Harness.eq(Bindings.actionFor("M"), "map")
	Harness.eq(Bindings.actionFor("ButtonY"), "map")
	Harness.eq(Bindings.actions.map.touch, "minimap")
end)

Harness.test("big map: config is sane", function()
	Harness.eq(Config.BigMap.enabled, true)
	Harness.truthy(Config.BigMap.autoCloseSeconds >= 0)
end)

local PHONES = { 16 / 9, 2, 19.5 / 9, 20 / 9, 21 / 9 }

Harness.test(
	"big map: it fits on screen and leaves the thumbs, buttons and card band free",
	function()
		local map = Layout.bigMap
		Harness.truthy(Layout.inside(map), "big map is off screen")
		Harness.eq(map.w, map.h, "the map is a square")
		Harness.eq(Layout.overlaps(map, Layout.CardsBand), false, "covers the upgrade cards")
		for _, name in Layout.touchTargets do
			for _, left in { false, true } do
				local r = if left then Layout.mirror(Layout.regions[name]) else Layout.regions[name]
				Harness.eq(Layout.overlaps(map, r), false, `big map covers {name}`)
			end
		end
		for _, name in { "moveZone", "fireZone" } do
			local z = Layout.zones[name]
			Harness.eq(Layout.overlaps(map, z), false, `big map covers {name}`)
		end
		for _, name in { "settings", "heal", "sprint" } do
			Harness.eq(Layout.overlaps(map, Layout.regions[name]), false, `big map covers {name}`)
		end
	end
)

Harness.test("big map: it stays clear of the thumbs on every phone shape", function()
	for _, aspect in PHONES do
		local map = Layout.onScreen(Layout.bigMap, aspect)
		for _, name in Layout.touchTargets do
			if string.sub(name, 1, 4) == "chip" then
				continue
			end
			Harness.eq(
				Layout.overlaps(map, Layout.onScreen(Layout.regions[name], aspect)),
				false,
				`big map covers {name} at {aspect}`
			)
		end
	end
end)
