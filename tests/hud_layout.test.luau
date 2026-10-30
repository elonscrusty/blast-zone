--!strict
local Harness = require("./harness")
local Layout = require("../src/client/Hud/Layout")
local MinimapMath = require("../src/client/Hud/MinimapMath")
local Warnings = require("../src/client/Hud/Warnings")
local Theme = require("../src/client/Hud/Theme")

local regions = Layout.regions

local function names(): { string }
	local out = {}
	for name in regions :: any do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

Harness.test("every HUD piece is on screen and none overlap each other", function()
	local list = names()
	for i, a in list do
		Harness.truthy(Layout.inside(regions[a]), a .. " is off screen")
		for j = i + 1, #list do
			local b = list[j]
			Harness.eq(Layout.overlaps(regions[a], regions[b]), false, `{a} overlaps {b}`)
		end
	end
end)

Harness.test("nothing covers the player at screen centre", function()
	for _, name in names() do
		Harness.eq(
			Layout.overlaps(regions[name], Layout.PlayerBox),
			false,
			name .. " covers the player"
		)
	end
end)

Harness.test("the upgrade-card band (piece 08) is free, also when left-handed", function()
	for _, name in names() do
		Harness.eq(
			Layout.overlaps(regions[name], Layout.CardsBand),
			false,
			name .. " is in the card band"
		)
		Harness.eq(
			Layout.overlaps(Layout.mirror(regions[name]), Layout.CardsBand),
			false,
			name .. " mirrored is in the card band"
		)
	end
end)

Harness.test("every thumb target is at least 48 points on a 780x360 phone", function()
	for _, name in Layout.touchTargets do
		local r = regions[name]
		Harness.truthy(r.w >= Layout.MIN_TOUCH and r.h >= Layout.MIN_TOUCH, `{name} is {r.w}x{r.h}`)
	end
end)

Harness.test(
	"touch zones are on screen, clear of the card band, the gear and the player",
	function()
		for name, zone in Layout.zones :: any do
			Harness.truthy(Layout.inside(zone), name .. " is off screen")
			Harness.eq(
				Layout.overlaps(zone, Layout.CardsBand),
				false,
				name .. " is in the card band"
			)
			Harness.eq(
				Layout.overlaps(Layout.mirror(zone), Layout.CardsBand),
				false,
				name .. " mirrored is in the card band"
			)
			Harness.eq(Layout.overlaps(zone, Layout.PlayerBox), false, name .. " covers the player")
			Harness.eq(Layout.overlaps(zone, regions.settings), false, name .. " covers the gear")
			Harness.eq(Layout.overlaps(zone, regions.vitals), false, name .. " covers the health")
		end
		-- a stick must fit inside its zone with room to float
		Harness.truthy(Layout.zones.moveZone.w > regions.moveStick.w + 40)
		Harness.truthy(Layout.zones.fireZone.w > regions.fireStick.w + 40)
		Harness.truthy(Layout.zones.moveZone.h > regions.moveStick.h + 40)
	end
)

Harness.test("the zones each hold their stick's resting place", function()
	for stick, zone in { moveStick = "moveZone", fireStick = "fireZone" } do
		local r, z = regions[stick], Layout.zones[zone]
		Harness.truthy(
			r.x >= z.x - 20 and r.x + r.w <= z.x + z.w + 20,
			stick .. " rests far outside its zone"
		)
	end
end)

Harness.test(
	"the pick chips sit in a row by the aim thumb, and the cards band stays free",
	function()
		local row = { regions.chip1, regions.chip2, regions.chip3 }
		for i, chip in row do
			Harness.eq(chip.y, row[1].y, "chips are not in one row")
			Harness.eq(
				Layout.overlaps(chip, Layout.CardsBand),
				false,
				"chip " .. i .. " in card band"
			)
			if i > 1 then
				Harness.truthy(chip.x > row[i - 1].x, "chips are out of order")
			end
		end
		-- left to right is 1, 2, 3 like the cards; mirrored play keeps the order readable too
		Harness.truthy(Layout.mirror(regions.chip1).x > Layout.mirror(regions.chip3).x)
	end
)

Harness.test("circles are round", function()
	for name in Layout.circles :: any do
		Harness.near(regions[name].w, regions[name].h, 1e-9, name)
	end
end)

Harness.test("pieces hug the nearest screen edge, mirrored for left-handed play", function()
	local fire = Layout.place(regions.fireStick)
	Harness.eq(fire.anchorX, 1)
	Harness.eq(fire.anchorY, 1)
	local lefty = Layout.place(regions.fireStick, true)
	Harness.eq(lefty.anchorX, 0)
	Harness.near(lefty.posX, 24 / Layout.WIDTH, 1e-9) -- the fire stick takes the move stick's old place
	Harness.eq(Layout.place(regions.status).anchorX, 0.5)
end)

Harness.test(
	"the look B palette matches the project palette and has no half-set colours",
	function()
		local look = Theme.get("B")
		Harness.eq(look.ink, "#14243A")
		Harness.eq(look.accent, "#FFC44D")
		Harness.eq(look.danger, "#F15B64")
		Harness.eq(Theme.get("nope").id, "B") -- unknown looks fall back, never nil
		for k, v in look :: any do
			if type(v) == "string" and k ~= "id" and k ~= "name" then
				Harness.truthy(
					string.match(v, "^#%x%x%x%x%x%x$") ~= nil,
					k .. " is not a hex colour"
				)
			end
		end
	end
)

-- ===== minimap and zone maths =====

Harness.test("minimap: east is right and north (-Z) is up at yaw 0", function()
	local u, v = MinimapMath.toMap(30, 0, 0, 0, 60, 0)
	Harness.near(u, 0.5)
	Harness.near(v, 0)
	local u2, v2 = MinimapMath.toMap(0, -30, 0, 0, 60, 0)
	Harness.near(u2, 0)
	Harness.near(v2, -0.5)
end)

Harness.test("minimap turns with the camera yaw", function()
	-- Camera turned 90 degrees: what was "north" is now to the left or right, never still up.
	local u, v = MinimapMath.toMap(0, -30, 0, 0, 60, 90)
	Harness.near(math.abs(u), 0.5, 1e-9)
	Harness.near(v, 0, 1e-9)
end)

local zone =
	{ centerX = 0, centerZ = 0, fromRadius = 100, toRadius = 50, startedAt = 10, endsAt = 20 }

Harness.test("zone radius closes in a straight line and holds at the ends", function()
	Harness.near(MinimapMath.currentRadius(zone, 0), 100)
	Harness.near(MinimapMath.currentRadius(zone, 10), 100)
	Harness.near(MinimapMath.currentRadius(zone, 15), 75)
	Harness.near(MinimapMath.currentRadius(zone, 20), 50)
	Harness.near(MinimapMath.currentRadius(zone, 99), 50)
end)

Harness.test("exactly on the edge is inside, like the server", function()
	Harness.eq(MinimapMath.isOutside(50, 0, 0, 0, 50, 0), false)
	Harness.eq(MinimapMath.isOutside(50.01, 0, 0, 0, 50, 0), true)
	Harness.eq(MinimapMath.isOutside(50.4, 0, 0, 0, 50, 0.5), false) -- Config.Zone.edgeTolerance
end)

Harness.test("the safe circle is placed relative to the player", function()
	local c = MinimapMath.safeCircle(30, 0, 0, 0, 60, 60, 0) -- zone centre is 30 west of the player
	Harness.near(c.u, -0.5)
	Harness.near(c.r, 1)
end)

Harness.test("far dots are pinned to the minimap rim", function()
	local u, v, pinned = MinimapMath.clampToRim(3, 4, 0.1)
	Harness.eq(pinned, true)
	Harness.near(math.sqrt(u * u + v * v), 0.9, 1e-9)
	local _, _, pinned2 = MinimapMath.clampToRim(0.2, 0.1)
	Harness.eq(pinned2, false)
end)

-- ===== warnings =====

local calm: Warnings.Inputs = {
	outsideZone = false,
	suddenDeath = false,
	lowHealth = false,
	weaponEmpty = false,
	reloading = false,
	zoneWarningSeconds = nil,
	zoneClosing = false,
	notice = nil,
}

local function with(change: { [string]: any }): Warnings.Inputs
	local copy = table.clone(calm) :: any
	for k, v in change do
		copy[k] = v
	end
	return copy
end

Harness.test("nothing to warn about shows nothing", function()
	Harness.eq(Warnings.pick(calm), nil)
end)

Harness.test("danger beats weapon news beats zone news (brief priority order)", function()
	local all = with({
		outsideZone = true,
		lowHealth = true,
		weaponEmpty = true,
		zoneWarningSeconds = 5,
		zoneClosing = true,
		notice = "hello",
	})
	Harness.eq((Warnings.pick(all) :: Warnings.Warning).key, "outside")
	Harness.eq(
		(
			Warnings.pick(
				with({ lowHealth = true, weaponEmpty = true, zoneClosing = true })
			) :: Warnings.Warning
		).key,
		"lowHealth"
	)
	Harness.eq(
		(Warnings.pick(with({ weaponEmpty = true, zoneWarningSeconds = 5 })) :: Warnings.Warning).key,
		"empty"
	)
	Harness.eq(
		(Warnings.pick(with({ zoneWarningSeconds = 5, notice = "x" })) :: Warnings.Warning).key,
		"zoneWarning"
	)
end)

Harness.test("the zone warning counts whole seconds up, never negative", function()
	Harness.eq(
		(Warnings.pick(with({ zoneWarningSeconds = 6.2 })) :: Warnings.Warning).text,
		"ZONE CLOSING IN 7"
	)
	Harness.eq(
		(Warnings.pick(with({ zoneWarningSeconds = -1 })) :: Warnings.Warning).text,
		"ZONE CLOSING IN 0"
	)
end)
