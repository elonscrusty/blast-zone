--!strict
local Harness = require("./harness")
local Layout = require("../src/server/Arena/Layout")
local Analysis = require("./arena_analysis")

local ENGAGE_RANGE = 50 -- guess until the firearm piece fixes its range
local CLEAR = 2.5 -- space a container needs around it
local MAX_EXPOSURE = 0.75 -- a spot with cover nearby may not see more than this share of the area around it

local specs = {
	A = require("../src/server/Arena/LayoutA"),
	B = require("../src/server/Arena/LayoutB"),
	C = require("../src/server/Arena/LayoutC"),
}

local function inside(x: number, z: number, s: Layout.Solid, pad: number): boolean
	return x >= s.x0 - pad and x <= s.x1 + pad and z >= s.z0 - pad and z <= s.z1 + pad
end

for key, spec in specs do
	local layout = Layout.compile(spec)
	local function t(name: string, fn: () -> ())
		Harness.test(`arena {key}: {name}`, fn)
	end
	local walk = Analysis.walkGrid(layout)

	t("has the required pieces", function()
		Harness.truthy(#layout.spawns >= 8, "8+ spawns")
		Harness.truthy(#layout.containers >= 10, "10+ container points")
		Harness.truthy(#layout.gates >= 2, "park has 2+ entrances")
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
		Harness.truthy(kinds["open-road"] and kinds["chokepoint"] and kinds["interior"], "3 encounter kinds")
	end)

	t("everything stays inside the arena", function()
		for _, s in layout.solids do
			if s.kind ~= "boundary" then
				Harness.truthy(
					s.x0 >= -layout.half and s.x1 <= layout.half and s.z0 >= -layout.half and s.z1 <= layout.half,
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
			Harness.truthy(Analysis.reaches(walk, first.x, first.z, a.x, a.z), a.id .. " is cut off")
			local d0 = math.sqrt((a.x - layout.finalZone.x) ^ 2 + (a.z - layout.finalZone.z) ^ 2)
			Harness.truthy(d0 < layout.zoneStages[1], a.id .. " starts outside the first zone")
			for j = i + 1, #layout.spawns do
				local b = layout.spawns[j]
				local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
				Harness.truthy(d >= 40, `{a.id} and {b.id} only {math.floor(d)} apart`)
				if d < ENGAGE_RANGE + 40 then
					Harness.truthy(
						Layout.shotBlocked(layout, a.x, a.z, b.x, b.z) or d > ENGAGE_RANGE,
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
			Harness.truthy(Analysis.reaches(walk, first.x, first.z, c.x, c.z), c.id .. " is cut off")
		end
	end)

	t("final zone can be walked and shrinking never strands a pocket", function()
		local z = layout.finalZone
		Harness.truthy(Analysis.walkable(walk, z.x, z.z), "final zone centre is blocked")
		for _, r in layout.zoneStages do
			local pieces = Analysis.pieces(walk, z.x, z.z, r)
			Harness.truthy(#pieces >= 1, `zone stage {r} has nowhere to stand`)
			for i = 2, #pieces do
				Harness.truthy(pieces[i] <= 6, `zone stage {r} has a pocket of {pieces[i]} cells cut off`)
			end
		end
		Harness.eq(layout.zoneStages[#layout.zoneStages], z.radius, "last stage is the final zone")
	end)

	t("losing any one door or gate leaves another way", function()
		local first = layout.spawns[1]
		local function ok(extra: { { number } }, what: string)
			local g = Analysis.walkGrid(layout, extra)
			for _, c in layout.containers do
				if Analysis.walkable(walk, c.x, c.z) then
					Harness.truthy(Analysis.reaches(g, first.x, first.z, c.x, c.z), `{what} shut: {c.id} cut off`)
				end
			end
		end
		for _, gate in layout.gates do
			local horizontal = gate.side == "N" or gate.side == "S"
			local w = if horizontal then { gate.from, gate.z - 0.5, gate.to, gate.z + 0.5 }
				else { gate.x - 0.5, gate.from, gate.x + 0.5, gate.to }
			ok({ w }, gate.id)
		end
		for _, b in layout.buildings do
			for i, d in b.doors do
				local w = if d.side == "N" then { d.from, b.z0, d.to, b.z0 + 2 }
					elseif d.side == "S" then { d.from, b.z1 - 2, d.to, b.z1 }
					elseif d.side == "W" then { b.x0, d.from, b.x0 + 2, d.to }
					else { b.x1 - 2, d.from, b.x1, d.to }
				ok({ w }, `{b.id} door {i}`)
			end
		end
	end)

	t("no covered spot sees too much (no map-wide camping seat)", function()
		local worst, wx, wz = 0, 0, 0
		for x = -100, 100, 5 do
			for z = -100, 100, 5 do
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
