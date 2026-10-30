--!strict
local Harness = require("./harness")
local Layout = require("../src/server/Arena/Layout")
local Analysis = require("./arena_analysis")

local Config = require("../src/shared/Config")
local Visibility = require("../src/client/Arena/Visibility")

local ENGAGE_RANGE = Config.Weapons.Firearm.range
local CLEAR = Analysis.RADIUS -- space a container needs around it
local MAX_EXPOSURE = 0.8 -- a spot with cover nearby may not see more than this share of the area around it
-- A small nook beside a fence is fine; a big cut-off part of a zone ring is not. Stretching a map
-- moves thin hedges and fences apart a little differently, so a stretched map may keep a slightly
-- bigger nook (20 cells = 80 square studs, about 9 x 9) than the 220-stud originals (6 cells).
local MAX_POCKET = if Config.Arena.scale > 1 then 20 else 6
local ZONE = Config.Zone
local ZONE_RADII = { ZONE.initialRadius }
for _, s in ZONE.stages do
	table.insert(ZONE_RADII, s.targetRadius)
end
table.insert(ZONE_RADII, ZONE.suddenDeath.targetRadius)

local specs = {
	A = require("../src/server/Arena/LayoutA"),
	B = require("../src/server/Arena/LayoutB"),
	C = require("../src/server/Arena/LayoutC"),
	D = require("../src/server/Arena/LayoutD"),
	E = require("../src/server/Arena/LayoutE"),
	F = require("../src/server/Arena/LayoutF"),
}

local function inside(x: number, z: number, s: Layout.Solid, pad: number): boolean
	return x >= s.x0 - pad and x <= s.x1 + pad and z >= s.z0 - pad and z <= s.z1 + pad
end

-- The same options the game builds with (ArenaSystem): stretched, topped up to one spawn per fighter.
local CROWD = {
	scale = Config.Arena.scale,
	minSpawns = Config.Arena.minSpawns,
	minContainers = Config.Arena.containerSpots,
	spawnClear = Config.Arena.spawnClearRadius,
	zoneRadius = Config.Zone.initialRadius,
}

for key, spec in specs do
	local layout = Layout.compile(spec, CROWD)
	local function t(name: string, fn: () -> ())
		Harness.test(`arena {key}: {name}`, fn)
	end
	local walk = Analysis.walkGrid(layout)

	t("has the required pieces", function()
		Harness.truthy(#layout.spawns >= Config.Arena.minSpawns, "enough spawns")
		Harness.truthy(#layout.containers >= Config.Arena.containerSpots, "enough container points")
		Harness.truthy(#layout.gates >= Config.Arena.parkEntrancesMin, "park has 2+ entrances")
		Harness.truthy(#layout.intersections >= 1, "road intersection")
		Harness.truthy(#layout.alleys >= 1, "service alley")
		Harness.truthy(#layout.roofs >= 1, "enterable building")
		local cover = 0
		for _, s in layout.solids do
			if s.kind == "cover" then
				cover += 1
			end
		end
		Harness.truthy(cover >= 6, "6+ cover objects")
		local kinds = {}
		for _, e in layout.encounters do
			kinds[e.kind] = true
		end
		Harness.truthy(
			kinds["open-road"] and kinds["chokepoint"] and kinds["interior"],
			"3 encounter kinds"
		)
	end)

	t("everything stays inside the arena", function()
		for _, s in layout.solids do
			if s.kind ~= "boundary" then
				Harness.truthy(
					s.x0 >= -layout.half
						and s.x1 <= layout.half
						and s.z0 >= -layout.half
						and s.z1 <= layout.half,
					s.id .. " is outside"
				)
			end
		end
	end)

	t("gates and doors are wide enough to walk through", function()
		for _, g in layout.gates do
			Harness.truthy(g.to - g.from >= 8, g.id .. " too narrow")
		end
		for _, b in layout.buildings do
			for _, d in b.doors do
				Harness.truthy(d.to - d.from >= 8, b.id .. " door too narrow")
			end
			Harness.truthy(#b.doors >= 2, b.id .. " needs 2+ doors")
			for _, line in b.inner or {} do
				for _, gap in line.gaps or {} do
					Harness.truthy(gap[2] - gap[1] >= 8, b.id .. " inner gap too narrow")
				end
			end
		end
	end)

	t("spawns are free, apart, safe, and can reach everything", function()
		local first = layout.spawns[1]
		local reach = Analysis.flood(walk, first.x, first.z)
		Harness.truthy(next(reach) ~= nil, "first spawn is trapped")
		for i, a in layout.spawns do
			Harness.truthy(Analysis.walkable(walk, a.x, a.z), a.id .. " is inside a solid")
			Harness.truthy(
				Analysis.reaches(walk, first.x, first.z, a.x, a.z),
				a.id .. " is cut off"
			)
			local d0 = math.sqrt((a.x - ZONE.centerX) ^ 2 + (a.z - ZONE.centerZ) ^ 2)
			Harness.truthy(d0 < ZONE.initialRadius, a.id .. " starts outside the first zone")
			Harness.truthy(
				not Analysis.insideAny(layout, a.x, a.z, Config.Arena.spawnClearRadius),
				a.id .. " is too close to a solid"
			)
			for j = i + 1, #layout.spawns do
				local b = layout.spawns[j]
				local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
				Harness.truthy(
					d >= Config.Arena.spawnMinSeparation,
					`{a.id} and {b.id} only {math.floor(d)} apart`
				)
				-- Only the layout's own spawns hide from each other. The crowd spawns added for 25
				-- fighters cannot (they would need walls everywhere); the spawn shield and the bots'
				-- calm start cover those.
				if d <= ENGAGE_RANGE and i <= #spec.spawns and j <= #spec.spawns then
					Harness.truthy(
						Layout.shotBlocked(layout, a.x, a.z, b.x, b.z),
						`{a.id} can shoot {b.id} at once`
					)
				end
			end
		end
	end)

	t("container points are clear and reachable", function()
		local first = layout.spawns[1]
		for _, c in layout.containers do
			for _, s in layout.solids do
				Harness.truthy(not inside(c.x, c.z, s, CLEAR), `{c.id} touches {s.id}`)
			end
			Harness.truthy(
				Analysis.reaches(walk, first.x, first.z, c.x, c.z),
				c.id .. " is cut off"
			)
		end
	end)

	t("every zone ring can be walked and never strands a pocket", function()
		local stand = false
		for dx = -8, 8, 2 do
			for dz = -8, 8, 2 do
				stand = stand or Analysis.walkable(walk, ZONE.centerX + dx, ZONE.centerZ + dz)
			end
		end
		Harness.truthy(stand, "nowhere to stand within 8 studs of the zone centre")
		for _, r in ZONE_RADII do
			local pieces = Analysis.pieces(walk, ZONE.centerX, ZONE.centerZ, r)
			Harness.truthy(#pieces >= 1, `zone ring {r} has nowhere to stand`)
			for i = 2, #pieces do
				Harness.truthy(
					pieces[i] <= MAX_POCKET,
					`zone ring {r} has a pocket of {pieces[i]} cells cut off`
				)
			end
		end
	end)

	t("losing any one door or gate leaves another way", function()
		local first = layout.spawns[1]
		local function ok(extra: { { number } }, what: string)
			local g = Analysis.walkGrid(layout, extra)
			local reach = Analysis.flood(g, first.x, first.z) -- once, then ask for every crate
			for _, c in layout.containers do
				if Analysis.walkable(walk, c.x, c.z) then
					Harness.truthy(
						Analysis.inFlood(g, reach, c.x, c.z),
						`{what} shut: {c.id} cut off`
					)
				end
			end
		end
		for _, gate in layout.gates do
			local horizontal = gate.side == "N" or gate.side == "S"
			local w = if horizontal
				then { gate.from, gate.z - 0.5, gate.to, gate.z + 0.5 }
				else { gate.x - 0.5, gate.from, gate.x + 0.5, gate.to }
			ok({ w }, gate.id)
		end
		for _, b in layout.buildings do
			for i, d in b.doors do
				local w = if d.side == "N"
					then { d.from, b.z0, d.to, b.z0 + 2 }
					elseif d.side == "S" then { d.from, b.z1 - 2, d.to, b.z1 }
					elseif d.side == "W" then { b.x0, d.from, b.x0 + 2, d.to }
					else { b.x1 - 2, d.from, b.x1, d.to }
				ok({ w }, `{b.id} door {i}`)
			end
		end
	end)

	t("no covered spot sees too much (no map-wide camping seat)", function()
		local worst, wx, wz = 0, 0, 0
		local reach = math.floor(layout.half) - 10
		for x = -reach, reach, 5 do
			for z = -reach, reach, 5 do
				if Analysis.walkable(walk, x, z) and Analysis.nearBlocker(layout, x, z, 3.5) then
					local e = Analysis.exposure(layout, x, z, ENGAGE_RANGE)
					if e > worst then
						worst, wx, wz = e, x, z
					end
				end
			end
		end
		Harness.truthy(worst <= MAX_EXPOSURE, `({wx},{wz}) sees {math.floor(worst * 100)}%`)
	end)
end

-- Local roof and wall fading. Uses layout A's depot (a walk-in building) and a tall block.
local function visibilityWorld()
	local layout = Layout.compile(require("../src/server/Arena/LayoutA"))
	local boxes: { Visibility.Box } = {}
	local buildings: { Visibility.Footprint } = {}
	for _, r in layout.roofs do
		table.insert(boxes, {
			id = r.id,
			kind = "roof",
			building = r.building,
			x0 = r.x0,
			y0 = r.h,
			z0 = r.z0,
			x1 = r.x1,
			y1 = r.h + 1,
			z1 = r.z1,
		})
		table.insert(buildings, { id = r.building, x0 = r.x0, z0 = r.z0, x1 = r.x1, z1 = r.z1 })
	end
	for _, o in layout.solids do
		if o.occluder then
			table.insert(boxes, {
				id = o.id,
				kind = if o.kind == "mass" then "mass" else "wall",
				building = o.building,
				x0 = o.x0,
				y0 = 0,
				z0 = o.z0,
				x1 = o.x1,
				y1 = o.h,
				z1 = o.z1,
			})
		end
	end
	return boxes, buildings
end

-- Camera sits south of the player and above, looking north (Config.Camera, yaw 0).
local function fadeAt(
	boxes: { Visibility.Box },
	buildings: { Visibility.Footprint },
	x: number,
	z: number
)
	local pitch = math.rad(Config.Camera.pitchDegrees)
	local out: { [string]: number } = {}
	local inside = Visibility.compute(
		boxes,
		buildings,
		x,
		z,
		x,
		Config.Camera.distance * math.sin(pitch),
		z + Config.Camera.distance * math.cos(pitch),
		Config.Arena.fade,
		out
	)
	return inside, out
end

Harness.test("arena visibility: inside the depot the roof goes and the near wall fades", function()
	local boxes, buildings = visibilityWorld()
	local inside, out = fadeAt(boxes, buildings, 40, 72) -- 4 studs from the south wall
	Harness.eq(inside, "depot")
	Harness.eq(out["depot-roof"], Config.Arena.fade.insideRoof)
	local nearWall = false
	for id, v in out do
		if string.find(id, "depot-wall2", 1, true) then -- the south wall segments
			nearWall = true
			Harness.eq(v, Config.Arena.fade.insideWall)
		end
	end
	Harness.truthy(nearWall, "the wall between camera and player fades")
	Harness.eq(out["depot-wall1-1"], nil, "far north wall stays solid")
end)

Harness.test("arena visibility: mid-room only the roof fades", function()
	local boxes, buildings = visibilityWorld()
	local _, out = fadeAt(boxes, buildings, 40, 40)
	Harness.eq(out["depot-roof"], Config.Arena.fade.insideRoof)
	for id in out do
		Harness.truthy(id == "depot-roof", `{id} should stay solid`)
	end
end)

Harness.test("arena visibility: a block between camera and player fades, others do not", function()
	local boxes, buildings = visibilityWorld()
	local inside, behind = fadeAt(boxes, buildings, 35, -102) -- just north of the tall block
	Harness.eq(inside, nil)
	Harness.eq(behind["ne1"], Config.Arena.fade.outsideBlocker)
	local _, clear = fadeAt(boxes, buildings, 35, -14) -- south of it, in the open
	Harness.eq(clear["ne1"], nil)
	Harness.eq(next(clear), nil, "nothing fades in the open")
end)

Harness.test("arena visibility: people in a room you are not in are hidden", function()
	local _, buildings = visibilityWorld()
	Harness.truthy(Visibility.hidesOccupant(buildings, nil, 40, 40), "outside looking in")
	Harness.truthy(not Visibility.hidesOccupant(buildings, "depot", 40, 40), "same room")
	Harness.truthy(
		not Visibility.hidesOccupant(buildings, nil, 40, 18.5),
		"in the doorway counts as outside"
	)
	Harness.truthy(not Visibility.hidesOccupant(buildings, nil, 0, 0), "in the open")
end)

Harness.test("arena: the chosen layout exists", function()
	Harness.truthy(
		specs[Config.Arena.layout] ~= nil,
		"Config.Arena.layout must name a layout in src/server/Arena"
	)
end)
