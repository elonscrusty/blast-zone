--!strict
-- Plans the whole Neon Night city for a compiled layout (piece 14): turns the graybox boxes into
-- a list of part specs. Pure and deterministic (same layout + seed = same plan), so Lune can test
-- it and every server builds the same city. ArtBuilder makes the real parts from the list.
--
-- What it never does: add collision, move a collision box, add a spawn or crate spot, or put a
-- gold or violet color near the ground. Those rules are checked in tests/art.test.luau.
local ArtKit = require("./ArtKit")
local ArtMap = require("./ArtMap")
local FacadeArt = require("./FacadeArt")
local InteriorArt = require("./InteriorArt")
local Layout = require("./Layout")
local ParkArt = require("./ParkArt")
local RoofArt = require("./RoofArt")
local SkylineArt = require("./SkylineArt")
local StreetArt = require("./StreetArt")

local ArtPlan = {}

export type Settings = {
	seed: number,
	towers: number,
	innerGap: number,
	outerReach: number,
}

export type Result = {
	parts: { ArtKit.Spec },
	lights: number,
	signs: number,
	groups: { [string]: number },
}

local WALL = Layout.WALL
local MASS_SIGNS = { "CORNER MARKET", "HOTEL ORBIT", "NEON LAUNDRY", "VOLT CAFE" }

local function massFaces(s: Layout.Solid): { ArtKit.Face }
	return {
		{
			side = "S",
			u0 = s.x0,
			u1 = s.x1,
			at = s.z1,
			h = s.h,
			group = "Facades",
			fadeWith = s.id,
		},
		{
			side = "N",
			u0 = s.x0,
			u1 = s.x1,
			at = s.z0,
			h = s.h,
			group = "Facades",
			fadeWith = s.id,
		},
		{
			side = "E",
			u0 = s.z0,
			u1 = s.z1,
			at = s.x1,
			h = s.h,
			group = "Facades",
			fadeWith = s.id,
		},
		{
			side = "W",
			u0 = s.z0,
			u1 = s.z1,
			at = s.x0,
			h = s.h,
			group = "Facades",
			fadeWith = s.id,
		},
	}
end

-- The point 3 studs out from the middle of a face.
local function outside(f: ArtKit.Face): (number, number)
	local mid = (f.u0 + f.u1) / 2
	if f.side == "S" then
		return mid, f.at + 3
	elseif f.side == "N" then
		return mid, f.at - 3
	elseif f.side == "E" then
		return f.at + 3, mid
	end
	return f.at - 3, mid
end

local function dressMasses(plan: ArtKit.Plan, map: ArtMap.Map)
	local masses: { Layout.Solid } = {}
	for _, s in map.solids do
		if s.kind == "mass" and StreetArt.classify(s.id) == nil then
			table.insert(masses, s)
		end
	end
	table.sort(masses, function(a, b)
		return (a.x1 - a.x0) * (a.z1 - a.z0) > (b.x1 - b.x0) * (b.z1 - b.z0)
	end)
	for index, s in masses do
		local big = s.h >= 10
		for _, f in massFaces(s) do
			local ox, oz = outside(f)
			local kind = map:groundKind(ox, oz)
			local detail = if kind == "sidewalk"
					and (math.abs(ox) > map.layout.half - 14 or math.abs(oz) > map.layout.half - 14)
				then 0.5
				else 1
			FacadeArt.run(plan, f, {
				groundHeight = if big then 5.4 else 4.6,
				detail = detail,
				bay = if big then 10 else 9,
				alley = kind == "alley",
				shops = kind ~= "alley" and detail >= 1,
				lamps = detail >= 1,
			})
			if f.side == "S" and big and MASS_SIGNS[index] ~= nil and f.u1 - f.u0 > 24 then
				FacadeArt.sign(
					plan,
					f,
					MASS_SIGNS[index] :: string,
					(f.u0 + f.u1) / 2,
					5.4 + 2.2,
					20,
					2.6,
					"#FFFFFF",
					"#1B2A44",
					ArtKit.P.coral
				)
			end
		end
		FacadeArt.corners(plan, s.x0, s.z0, s.x1, s.z1, s.h, s.id, 5.4)
		RoofArt.build(plan, {
			x0 = s.x0,
			z0 = s.z0,
			x1 = s.x1,
			z1 = s.z1,
			y = s.h,
			fadeWith = s.id,
			rich = (s.x1 - s.x0) * (s.z1 - s.z0) >= 1800,
			sign = nil,
		})
	end
end

-- Wall segments of one wall line, in order, so the gaps between them can get door headers.
local function wallLines(map: ArtMap.Map, b: Layout.BuildingSpec): { { Layout.Solid } }
	local lines: { [string]: { Layout.Solid } } = {}
	local order: { string } = {}
	for _, s in map.solids do
		if s.building == b.id and s.kind == "wall" then
			-- ids look like "<building>-wall<line>-<segment>"
			local key = string.match(s.id, "^(.*)%-%d+$") or s.id
			if lines[key] == nil then
				lines[key] = {}
				table.insert(order, key)
			end
			table.insert(lines[key], s)
		end
	end
	local out = {}
	for _, key in order do
		local segs = lines[key] :: { Layout.Solid }
		table.sort(segs, function(a, c)
			return (a.x0 + a.z0) < (c.x0 + c.z0)
		end)
		table.insert(out, segs)
	end
	return out
end

local function dressBuildings(plan: ArtKit.Plan, map: ArtMap.Map, layoutName: string)
	local first = true
	for _, b in map.layout.buildings do
		local bcx, bcz = (b.x0 + b.x1) / 2, (b.z0 + b.z1) / 2
		for _, segs in wallLines(map, b) do
			for _, s in segs do
				local f =
					ArtKit.wallFace(s.x0, s.z0, s.x1, s.z1, bcx, bcz, false, s.h, "Facades", s.id)
				FacadeArt.run(plan, f, { groundHeight = 5.4, bay = 9, detail = 1, lamps = true })
			end
			for i = 1, #segs - 1 do
				local a, c = segs[i] :: Layout.Solid, segs[i + 1] :: Layout.Solid
				local horiz = (a.x1 - a.x0) >= (a.z1 - a.z0)
				local g0 = if horiz then a.x1 else a.z1
				local g1 = if horiz then c.x0 else c.z0
				if g1 - g0 > 1 then
					local f = ArtKit.wallFace(
						a.x0,
						a.z0,
						a.x1,
						a.z1,
						bcx,
						bcz,
						false,
						a.h,
						"Facades",
						a.id
					)
					f.u0, f.u1 = g0, g1
					local label = nil
					if f.side == "S" and (g1 - g0) >= 10 and plan.signs < 24 then
						label = "ENTER"
					end
					FacadeArt.doorHeader(plan, f, g0, g1, a.id, label)
				end
			end
		end
		FacadeArt.corners(plan, b.x0, b.z0, b.x1, b.z1, b.h, nil, 5.4)
		-- the banner over the front of the first building carries the map name
		if first then
			first = false
			local southSeg: Layout.Solid? = nil
			for _, s in map.solids do
				if
					s.building == b.id
					and s.kind == "wall"
					and (s.x1 - s.x0) > (s.z1 - s.z0)
					and (s.z0 + s.z1) / 2 > bcz
				then
					if southSeg == nil or (s.x1 - s.x0) > (southSeg.x1 - southSeg.x0) then
						southSeg = s
					end
				end
			end
			if southSeg ~= nil then
				local f = ArtKit.wallFace(
					southSeg.x0,
					southSeg.z0,
					southSeg.x1,
					southSeg.z1,
					bcx,
					bcz,
					false,
					southSeg.h,
					"Facades",
					southSeg.id
				)
				FacadeArt.sign(
					plan,
					f,
					string.upper(layoutName),
					(southSeg.x0 + southSeg.x1) / 2,
					b.h - 3,
					math.min(southSeg.x1 - southSeg.x0 - 4, 30),
					3.6,
					ArtKit.P.cyan,
					"#10203A",
					ArtKit.P.coral
				)
			end
		end
	end
	for _, r in map.layout.roofs do
		RoofArt.build(plan, {
			x0 = r.x0,
			z0 = r.z0,
			x1 = r.x1,
			z1 = r.z1,
			y = r.h + 1,
			fadeWith = r.id,
			rich = true,
			sign = nil,
		})
	end
end

-- Solids whose graybox box the art redraws completely (cars, barriers, trees, kiosk, pillars...).
-- Once the art is built the server makes those boxes see-through to the eye; they keep every
-- collision, shot and fade job. Walls, partitions, fences and the big masses are never listed:
-- their art is a skin laid over the box, so the box stays as the body.
function ArtPlan.replaces(s: Layout.Solid): boolean
	if s.kind == "wall" or s.kind == "partition" or s.kind == "fence" or s.kind == "boundary" then
		return false
	end
	if s.kind == "mass" then
		local kind = StreetArt.classify(s.id)
		return kind == "kiosk" or kind == "bandstand"
	end
	return true
end

function ArtPlan.build(layout: Layout.Layout, settings: Settings): Result
	local plan = ArtKit.newPlan(settings.seed)
	local map = ArtMap.new(layout)

	dressMasses(plan, map)
	dressBuildings(plan, map, layout.name)
	InteriorArt.build(plan, map, WALL)

	-- kiosk and bandstand are masses that get their own dressing and copy their own fade
	local handled: { [string]: boolean } = {}
	for _, s in map.solids do
		if s.kind == "mass" and StreetArt.classify(s.id) ~= nil then
			handled[s.id] = true
		end
	end
	StreetArt.build(plan, map, handled)
	ParkArt.build(plan, map)
	SkylineArt.build(plan, layout.half, {
		towers = settings.towers,
		innerGap = settings.innerGap,
		outerReach = settings.outerReach,
	})

	local groups: { [string]: number } = {}
	for _, p in plan.parts do
		groups[p.group] = (groups[p.group] or 0) + 1
	end
	return { parts = plan.parts, lights = plan.lights, signs = plan.signs, groups = groups }
end

return ArtPlan
