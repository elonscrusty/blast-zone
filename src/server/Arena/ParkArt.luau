--!strict
-- The park for the Neon Night city (piece 14): mown stripes, paved paths from every gate, flower
-- beds, trees, rounded hedges, benches, a pond with a stone rim and lily pads, the bandstand,
-- and fence lamps. Everything tall sits inside the box of the solid it dresses. Pure planning.
local ArtKit = require("./ArtKit")
local ArtMap = require("./ArtMap")
local Layout = require("./Layout")

local ParkArt = {}

local P = ArtKit.P
local G = "Park"

local FLOWERS = { "#F15B64", "#FFB3A7", "#EAF1F8", "#8FE3EC", "#FF8FB8" } -- never gold, never violet

local function stripes(plan: ArtKit.Plan, map: ArtMap.Map)
	for _, park in map:ground("park") do
		local x = park.x0
		local i = 0
		while x < park.x1 do
			local x1 = math.min(x + 10, park.x1)
			if i % 2 == 0 then
				ArtKit.flat(plan, G, x, park.z0, x1, park.z1, 0.05, P.grassAlt)
			end
			x = x1
			i += 1
		end
	end
end

-- A path from each gate straight inward until it would hit something.
local function paths(plan: ArtKit.Plan, map: ArtMap.Map)
	local halfW = 3
	for _, gate in map.layout.gates do
		local dx, dz = 0, 0
		if gate.side == "N" then
			dz = 1
		elseif gate.side == "S" then
			dz = -1
		elseif gate.side == "W" then
			dx = 1
		else
			dx = -1
		end
		local length = 0
		for step = 1, 26 do
			local x0, x1, z0, z1 = 0, 0, 0, 0
			local px, pz = gate.x + dx * step, gate.z + dz * step
			if dx ~= 0 then
				x0, x1, z0, z1 = px - 0.5, px + 0.5, pz - halfW, pz + halfW
			else
				x0, x1, z0, z1 = px - halfW, px + halfW, pz - 0.5, pz + 0.5
			end
			if map:rectHitsSolid(x0, z0, x1, z1, 0.5) or map:groundKind(px, pz) ~= "park" then
				break
			end
			length = step
		end
		if length >= 4 then
			local x0, x1, z0, z1 = 0, 0, 0, 0
			if dx ~= 0 then
				x0 = math.min(gate.x, gate.x + dx * length)
				x1 = math.max(gate.x, gate.x + dx * length)
				z0, z1 = gate.z - halfW, gate.z + halfW
			else
				x0, x1 = gate.x - halfW, gate.x + halfW
				z0 = math.min(gate.z, gate.z + dz * length)
				z1 = math.max(gate.z, gate.z + dz * length)
			end
			ArtKit.flat(plan, G, x0 - 0.4, z0 - 0.4, x1 + 0.4, z1 + 0.4, 0.062, "#8892A0")
			ArtKit.flat(plan, G, x0, z0, x1, z1, 0.07, P.path)
			-- tile joints
			if dx ~= 0 then
				local x = x0 + 3
				while x < x1 - 0.5 do
					ArtKit.flat(plan, G, x, z0, x + 0.12, z1, 0.14, "#AEB9C9")
					x += 3
				end
			else
				local z = z0 + 3
				while z < z1 - 0.5 do
					ArtKit.flat(plan, G, x0, z, x1, z + 0.12, 0.14, "#AEB9C9")
					z += 3
				end
			end
		end
	end
end

local function flowerBeds(plan: ArtKit.Plan, map: ArtMap.Map)
	for _, park in map:ground("park") do
		local made, tries = 0, 0
		while made < 12 and tries < 120 do
			tries += 1
			local x = ArtKit.range(plan, park.x0 + 4, park.x1 - 4)
			local z = ArtKit.range(plan, park.z0 + 4, park.z1 - 4)
			if map:groundKind(x, z) == "park" and not map:blocked(x, z, 4) then
				made += 1
				ArtKit.disc(plan, G, x, z, 2.4, 0.12, "#3B2E27")
				for _ = 1, 6 do
					local a = ArtKit.range(plan, 0, math.pi * 2)
					local r = ArtKit.range(plan, 0.2, 1.9)
					ArtKit.disc(
						plan,
						G,
						x + math.cos(a) * r,
						z + math.sin(a) * r,
						0.34,
						0.17,
						ArtKit.pick(plan, FLOWERS)
					)
				end
			end
		end
	end
end

local function tree(plan: ArtKit.Plan, s: Layout.Solid)
	local cx, cz = (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
	local height = math.max(s.h, 8)
	ArtKit.vcyl(plan, G, cx, 0, cz, 0.75, 5.4, P.trunk, { material = "Wood", shadow = true })
	ArtKit.vcyl(plan, G, cx, 0, cz, 1.1, 0.6, P.trunk, { material = "Wood" })
	local c1, c2 = ArtKit.pick(plan, P.tree), ArtKit.pick(plan, P.tree)
	-- canopy starts above head height so it can never hide a player standing at the trunk
	ArtKit.ball(plan, G, cx, 7.6, cz, 2.6, c1, { shadow = true })
	ArtKit.ball(plan, G, cx + 0.5, height + 0.4, cz - 0.3, 2.0, c2, { shadow = true })
	ArtKit.ball(plan, G, cx - 0.7, 6.9, cz + 0.8, 1.7, c2)
end

local function hedge(plan: ArtKit.Plan, s: Layout.Solid)
	local w, d = s.x1 - s.x0, s.z1 - s.z0
	local cx, cz = (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
	ArtKit.box(
		plan,
		G,
		cx,
		s.h / 2 - 0.1,
		cz,
		w,
		s.h - 0.2,
		d,
		P.hedge,
		{ material = "Grass", shadow = true }
	)
	local horiz = w >= d
	local len = math.max(w, d)
	local n = math.max(2, math.floor(len / 2.5))
	for i = 1, n do
		local u = -len / 2 + (i - 0.5) * len / n
		local px = if horiz then cx + u else cx
		local pz = if horiz then cz else cz + u
		ArtKit.ball(
			plan,
			G,
			px,
			s.h - 0.1,
			pz,
			math.min(1.3, math.min(w, d) / 2 + 0.3),
			ArtKit.mix(P.hedge, "#FFFFFF", 0.08)
		)
	end
end

local function bench(plan: ArtKit.Plan, s: Layout.Solid)
	local w, d = s.x1 - s.x0, s.z1 - s.z0
	local cx, cz = (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
	local horiz = w >= d
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
	local len = math.max(w, d)
	local thick = math.min(w, d)
	B(
		0,
		1.45,
		len,
		0.2,
		math.max(math.min(thick, 0.6) - 0.08, 0.3),
		"#B9885A",
		{ material = "Wood" }
	)
	B(0, 1.15, len, 0.18, 0.22, "#B9885A", { material = "Wood" })
	B(0, 2.4, len, 1.1, 0.2, "#A9784A", { material = "Wood" })
	for _, u in { -len / 2 + 0.5, len / 2 - 0.5 } do
		B(u, 0.8, 0.3, 1.6, math.min(thick, 1.2), P.steelDark, { material = "Metal" })
	end
end

local function pond(plan: ArtKit.Plan, s: Layout.Solid)
	local cx, cz = (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
	local w, d = s.x1 - s.x0, s.z1 - s.z0
	-- stone rim stays inside the pond box so nothing sticks out into the walkway
	ArtKit.span(
		plan,
		G,
		s.x0,
		0.05,
		s.z0,
		s.x1,
		0.32,
		s.z0 + 0.9,
		"#8892A0",
		{ material = "Slate" }
	)
	ArtKit.span(
		plan,
		G,
		s.x0,
		0.05,
		s.z1 - 0.9,
		s.x1,
		0.32,
		s.z1,
		"#8892A0",
		{ material = "Slate" }
	)
	ArtKit.span(
		plan,
		G,
		s.x0,
		0.05,
		s.z0 + 0.9,
		s.x0 + 0.9,
		0.32,
		s.z1 - 0.9,
		"#8892A0",
		{ material = "Slate" }
	)
	ArtKit.span(
		plan,
		G,
		s.x1 - 0.9,
		0.05,
		s.z0 + 0.9,
		s.x1,
		0.32,
		s.z1 - 0.9,
		"#8892A0",
		{ material = "Slate" }
	)
	ArtKit.span(plan, G, s.x0 + 0.9, 0.1, s.z0 + 0.9, s.x1 - 0.9, 0.2, s.z1 - 0.9, P.water, {
		material = "Glass",
		transparency = 0.12,
		reflectance = 0.3,
	})
	for i = 1, 7 do
		local a = i * 2.4
		local r = ArtKit.range(plan, 1, math.min(w, d) / 2 - 2.2)
		ArtKit.disc(
			plan,
			G,
			cx + math.cos(a) * r * 1.3,
			cz + math.sin(a) * r * 0.9,
			ArtKit.range(plan, 0.5, 0.9),
			0.22,
			"#3FA05C"
		)
	end
	-- a little jet in the middle that lights up at dusk
	ArtKit.vcyl(
		plan,
		G,
		cx,
		0.2,
		cz,
		0.35,
		2.2,
		"#C9D6E6",
		{ material = "SmoothPlastic", transparency = 0.35 }
	)
	ArtKit.ball(plan, G, cx, 2.5, cz, 0.55, "#8FE3EC", {
		material = "Neon",
		neon = ArtKit.glow("#8FE3EC", "#5A7390", 0.3, true),
		light = if plan.lights < 26
			then { color = "#8FE3EC", range = 20, brightness = 1.6 }
			else nil,
	})
end

local function bandstand(plan: ArtKit.Plan, s: Layout.Solid)
	local cx, cz = (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
	local w, d = s.x1 - s.x0, s.z1 - s.z0
	ArtKit.box(plan, G, cx, 0.7, cz, w, 1.4, d, "#8892A0", { material = "Concrete", shadow = true })
	ArtKit.box(plan, G, cx, 1.5, cz, w - 1, 0.3, d - 1, "#B08A62", { material = "WoodPlanks" })
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			ArtKit.vcyl(
				plan,
				G,
				cx + sx * (w / 2 - 0.9),
				1.6,
				cz + sz * (d / 2 - 0.9),
				0.4,
				s.h - 2.6,
				P.trim,
				{ material = "Metal" }
			)
		end
	end
	-- stepped roof
	ArtKit.box(plan, G, cx, s.h - 0.9, cz, w, 0.6, d, "#2E4A70", { shadow = true })
	ArtKit.box(plan, G, cx, s.h - 0.3, cz, w - 2.2, 0.7, d - 2.2, "#35547C", { shadow = true })
	ArtKit.box(plan, G, cx, s.h + 0.4, cz, w - 5, 0.8, d - 5, "#3E6296")
	ArtKit.vcyl(plan, G, cx, s.h + 0.8, cz, 0.15, 2, P.steel)
	ArtKit.ball(plan, G, cx, s.h + 3, cz, 0.45, P.coral, {
		material = "Neon",
		neon = ArtKit.glow(P.coral, P.coralDim, 0.2, false),
		light = if plan.lights < 26 then { color = P.coral, range = 24, brightness = 1.8 } else nil,
	})
	-- neon rim under the roof edge
	local n = ArtKit.glow(P.cyan, P.cyanDim, 0, true)
	ArtKit.box(
		plan,
		G,
		cx,
		s.h - 1.3,
		cz - d / 2 + 0.1,
		w - 0.4,
		0.2,
		0.2,
		P.cyan,
		{ material = "Neon", neon = n }
	)
	ArtKit.box(
		plan,
		G,
		cx,
		s.h - 1.3,
		cz + d / 2 - 0.1,
		w - 0.4,
		0.2,
		0.2,
		P.cyan,
		{ material = "Neon", neon = n }
	)
	ArtKit.box(
		plan,
		G,
		cx - w / 2 + 0.1,
		s.h - 1.3,
		cz,
		0.2,
		0.2,
		d - 0.4,
		P.cyan,
		{ material = "Neon", neon = n }
	)
	ArtKit.box(
		plan,
		G,
		cx + w / 2 - 0.1,
		s.h - 1.3,
		cz,
		0.2,
		0.2,
		d - 0.4,
		P.cyan,
		{ material = "Neon", neon = n }
	)
end

-- Lamps stand on the fence line (the fence already blocks walking there).
local function fenceLamps(plan: ArtKit.Plan, map: ArtMap.Map)
	local lampsMade = 0
	for _, s in map.solids do
		if s.kind ~= "fence" then
			continue
		end
		local w, d = s.x1 - s.x0, s.z1 - s.z0
		local horiz = w >= d
		local len = math.max(w, d)
		local cx, cz = (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
		-- posts and rails
		local posts = math.max(2, math.floor(len / 3))
		for i = 0, posts do
			local u = -len / 2 + i * len / posts
			local px = if horiz then cx + u else cx
			local pz = if horiz then cz else cz + u
			ArtKit.vcyl(plan, G, px, 0, pz, 0.2, 4, "#59616D", { material = "Metal" })
		end
		if horiz then
			ArtKit.box(plan, G, cx, 3.5, cz, len, 0.18, 0.3, "#59616D", { material = "Metal" })
			ArtKit.box(plan, G, cx, 1.2, cz, len, 0.18, 0.3, "#59616D", { material = "Metal" })
		else
			ArtKit.box(plan, G, cx, 3.5, cz, 0.3, 0.18, len, "#59616D", { material = "Metal" })
			ArtKit.box(plan, G, cx, 1.2, cz, 0.3, 0.18, len, "#59616D", { material = "Metal" })
		end
		-- a lamp near each end of a long fence run
		if len >= 24 then
			for _, u in { -len / 2 + 6, len / 2 - 6 } do
				local px = if horiz then cx + u else cx
				local pz = if horiz then cz else cz + u
				ArtKit.vcyl(
					plan,
					G,
					px,
					0,
					pz,
					0.28,
					7.2,
					"#3B4658",
					{ material = "Metal", shadow = true }
				)
				local lamp: ArtKit.Opts =
					{ material = "Neon", neon = ArtKit.glow(P.coolLamp, "#6C7C93", 0.2, true) }
				lampsMade += 1
				if plan.lights < 24 and lampsMade % 2 == 0 then
					lamp.light = { color = P.coolLamp, range = 26, brightness = 1.6 }
				end
				ArtKit.ball(plan, G, px, 7.6, pz, 0.7, P.coolLamp, lamp)
			end
		end
	end
end

function ParkArt.build(plan: ArtKit.Plan, map: ArtMap.Map)
	stripes(plan, map)
	paths(plan, map)
	flowerBeds(plan, map)
	for _, s in map.solids do
		local k = string.sub(s.id, 1, 4)
		if k == "tree" then
			tree(plan, s)
		elseif k == "hedg" then
			hedge(plan, s)
		elseif k == "benc" then
			plan.owner = s.id -- a bench can burst (piece 47)
			bench(plan, s)
			plan.owner = nil
		elseif k == "pond" or k == "pool" then
			pond(plan, s)
		elseif k == "band" or k == "gaze" then
			bandstand(plan, s)
		end
	end
	fenceLamps(plan, map)
end

return ParkArt
