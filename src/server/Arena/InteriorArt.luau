--!strict
-- Inside the arcade for the Neon Night city (piece 14): striped floor, arcade cabinet fronts
-- along the walls, glowing rails, partition caps, round pillars with neon rings and a few colored
-- lights. Everything standing is flush with a wall or inside a pillar's box, so rooms stay as
-- tight as they were tuned. Pure planning, no Roblox types.
local ArtKit = require("./ArtKit")
local ArtMap = require("./ArtMap")
local Layout = require("./Layout")

local InteriorArt = {}

local P = ArtKit.P
local G = "Interior"

local SCREENS = { P.cyan, P.coral, P.mint, "#EAF1F8" }
local SCREEN_DIM = { P.cyanDim, P.coralDim, "#3B7F6C", "#6C7C93" }

local function floorArt(plan: ArtKit.Plan, b: Layout.BuildingSpec, wall: number)
	local x0, z0, x1, z1 = b.x0 + wall, b.z0 + wall, b.x1 - wall, b.z1 - wall
	-- carpet stripes
	local x = x0
	local i = 0
	while x < x1 - 0.1 do
		local nx = math.min(x + 4, x1)
		if i % 2 == 0 then
			ArtKit.flat(plan, G, x, z0, nx, z1, 0.12, "#3A4D6C")
		else
			ArtKit.flat(plan, G, x, z0, nx, z1, 0.12, "#45597A")
		end
		x = nx
		i += 1
	end
	-- long guide lines, plain paint (not glowing, so nothing reads as a shot)
	local cx = (x0 + x1) / 2
	ArtKit.flat(plan, G, cx - 0.25, z0, cx + 0.25, z1, 0.19, P.coral)
	for _, inset in { 1.2, 2.0 } do
		ArtKit.flat(plan, G, x0 + inset - 0.1, z0 + 1, x0 + inset + 0.1, z1 - 1, 0.19, "#2A8CA0")
		ArtKit.flat(plan, G, x1 - inset - 0.1, z0 + 1, x1 - inset + 0.1, z1 - 1, 0.19, "#2A8CA0")
	end
	local z = z0 + 8
	while z < z1 - 4 do
		ArtKit.flat(plan, G, x0 + 2.5, z - 0.1, x1 - 2.5, z + 0.1, 0.19, "#5E7396")
		z += 12
	end
end

local function cabinets(plan: ArtKit.Plan, f: ArtKit.Face)
	local len = f.u1 - f.u0
	if len < 8 then
		return
	end
	local pitch = 3.8
	local n = math.floor((len - 2) / pitch)
	local start = f.u0 + (len - (n - 1) * pitch) / 2
	for i = 0, n - 1 do
		local u = start + i * pitch
		local k = (i % #SCREENS) + 1
		ArtKit.fbox(plan, f, u, 2.6, 0.28, 3.2, 5.2, 0.56, "#2C3E5C", { material = "Metal" })
		ArtKit.fbox(plan, f, u, 3.5, 0.53, 2.4, 1.8, 0.1, SCREENS[k] :: string, {
			material = "Neon",
			neon = ArtKit.glow(SCREENS[k] :: string, "#1B2B44", 0.05 + (i % 5) * 0.06, false),
		})
		ArtKit.fbox(plan, f, u, 1.95, 0.45, 2.6, 0.5, 0.3, "#1B2A44")
		ArtKit.fbox(
			plan,
			f,
			u - 0.5,
			1.95,
			0.6,
			0.35,
			0.18,
			0.12,
			P.coral,
			{ material = "Neon", neon = ArtKit.glow(P.coral, P.coralDim, 0.2, true) }
		)
		ArtKit.fbox(
			plan,
			f,
			u + 0.5,
			1.95,
			0.6,
			0.35,
			0.18,
			0.12,
			P.cyan,
			{ material = "Neon", neon = ArtKit.glow(P.cyan, P.cyanDim, 0.2, true) }
		)
		ArtKit.fbox(plan, f, u, 5.05, 0.5, 3.2, 0.4, 0.2, SCREENS[k] :: string, {
			material = "Neon",
			neon = ArtKit.glow(SCREENS[k] :: string, SCREEN_DIM[k] :: string, 0, true),
		})
	end
end

local function wallDressing(plan: ArtKit.Plan, f: ArtKit.Face)
	local len = f.u1 - f.u0
	if len < 3 then
		return
	end
	local mid = (f.u0 + f.u1) / 2
	ArtKit.fbox(plan, f, mid, 1.1, 0.12, len, 2.2, 0.24, "#1B2A44")
	ArtKit.fbox(plan, f, mid, 6.2, 0.1, len, 0.18, 0.2, P.cyan, {
		material = "Neon",
		neon = ArtKit.glow(P.cyan, P.cyanDim, 0, true),
	})
	cabinets(plan, f)
end

local function partition(plan: ArtKit.Plan, s: Layout.Solid, b: Layout.BuildingSpec, wall: number)
	local horiz = (s.x1 - s.x0) >= (s.z1 - s.z0)
	local len = if horiz then s.x1 - s.x0 else s.z1 - s.z0
	if len < 2 then
		return
	end
	local cx, cz = (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
	local function B(
		u: number,
		y: number,
		su: number,
		sy: number,
		sv: number,
		c: string,
		o: ArtKit.Opts?
	)
		if horiz then
			ArtKit.box(plan, G, cx + u, y, cz, su, sy, sv, c, o)
		else
			ArtKit.box(plan, G, cx, y, cz + u, sv, sy, su, c, o)
		end
	end
	local thick = if horiz then s.z1 - s.z0 else s.x1 - s.x0
	B(0, 1.1, len, 2.2, thick + 0.3, "#1B2A44")
	B(
		0,
		2.45,
		len,
		0.18,
		thick + 0.36,
		P.coral,
		{ material = "Neon", neon = ArtKit.glow(P.coral, P.coralDim, 0, true) }
	)
	B(0, s.h + 0.15, len + 0.2, 0.3, thick + 0.2, P.white, {
		material = "Neon",
		neon = ArtKit.glow(P.white, "#6C7C93", 0, true),
	})
	-- white glowing end strips (cyan streaks read as shots) where a partition stops at a doorway
	for _, sign in { -1, 1 } do
		local u = sign * (len / 2)
		local endAt = if horiz then cx + u else cz + u
		local lo = if horiz then b.x0 + wall else b.z0 + wall
		local hi = if horiz then b.x1 - wall else b.z1 - wall
		if math.abs(endAt - lo) > 2.5 and math.abs(endAt - hi) > 2.5 then
			B(u + sign * 0.12, s.h / 2, 0.24, s.h, thick + 0.1, P.white, {
				material = "Neon",
				neon = ArtKit.glow(P.white, "#6C7C93", 0.1, true),
			})
		end
	end
end

local function pillar(plan: ArtKit.Plan, s: Layout.Solid, index: number)
	local cx, cz = (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
	local r = math.min(s.x1 - s.x0, s.z1 - s.z0) / 2
	local h = s.h
	ArtKit.vcyl(plan, G, cx, 0, cz, r, 1.2, P.steelDark, { material = "Metal" })
	ArtKit.vcyl(
		plan,
		G,
		cx,
		1.2,
		cz,
		r - 0.15,
		h - 2.4,
		"#4D6A93",
		{ material = "Concrete", shadow = true }
	)
	ArtKit.vcyl(plan, G, cx, h - 1.2, cz, r, 1.2, P.steelDark, { material = "Metal" })
	local c1, c2 = P.cyan, P.coral
	local d1, d2 = P.cyanDim, P.coralDim
	for k, y in { 3.4, 8.8 } do
		local on = if (k + index) % 2 == 0 then c1 else c2
		local off = if (k + index) % 2 == 0 then d1 else d2
		local o: ArtKit.Opts = { material = "Neon", neon = ArtKit.glow(on, off, 0, true) }
		if k == 2 and plan.lights < 26 then
			o.light = { color = on, range = 28, brightness = 1.5 }
		end
		ArtKit.vcyl(plan, G, cx, y, cz, r - 0.05, 0.3, on, o)
	end
end

function InteriorArt.build(plan: ArtKit.Plan, map: ArtMap.Map, wall: number)
	local pillarIndex = 0
	for _, b in map.layout.buildings do
		floorArt(plan, b, wall)
		local bcx, bcz = (b.x0 + b.x1) / 2, (b.z0 + b.z1) / 2
		for _, s in map.solids do
			if s.building == b.id and s.kind == "wall" then
				wallDressing(
					plan,
					ArtKit.wallFace(s.x0, s.z0, s.x1, s.z1, bcx, bcz, true, s.h, G, s.id)
				)
			elseif s.building == b.id and s.kind == "partition" then
				partition(plan, s, b, wall)
			end
		end
		for _, s in map.solids do
			if
				string.sub(s.id, 1, 6) == "pillar"
				and s.x0 > b.x0
				and s.x1 < b.x1
				and s.z0 > b.z0
				and s.z1 < b.z1
			then
				pillarIndex += 1
				pillar(plan, s, pillarIndex)
			end
		end
	end
end

return InteriorArt
