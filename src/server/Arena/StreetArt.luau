--!strict
-- Streets, alleys, yards and street furniture for the Neon Night city (piece 14): lane paint,
-- crosswalks, curbs, manholes, drains, puddles, circuit lines in the pavement, detailed cars,
-- concrete barriers, containers, cargo bins, dumpsters and planters.
-- Rules the tests check: ground paint is flat; anything taller stays inside the box of the solid
-- it dresses (plus `flushStuds`); nothing here is gold or violet. Pure planning.
local ArtKit = require("./ArtKit")
local ArtMap = require("./ArtMap")
local Layout = require("./Layout")

local StreetArt = {}

local P = ArtKit.P
local G = "Street"
local PR = "Props"

-- Which kind of dressing a solid gets, by its id. nil = the planner dresses it generically.
function StreetArt.classify(id: string): string?
	local function starts(p: string): boolean
		return string.sub(id, 1, #p) == p
	end
	if starts("car-") or starts("lot-car") then
		return "car"
	elseif starts("median") or starts("bar-") or starts("lot-bar") then
		return "barrier"
	elseif starts("dumpster") then
		return "dumpster"
	elseif starts("crate") then
		return "crate"
	elseif starts("box-") then
		return "container"
	elseif starts("planter") or starts("block-") then
		return "planter"
	elseif starts("pillar") then
		return "pillar"
	elseif starts("tree") then
		return "tree"
	elseif starts("hedge") then
		return "hedge"
	elseif starts("bench") then
		return "bench"
	elseif starts("pond") or starts("pool") then
		return "pond"
	elseif starts("bandstand") or starts("gazebo") then
		return "bandstand"
	elseif starts("kiosk") then
		return "kiosk"
	end
	return nil
end

local function overlaps(
	a: Layout.GroundSpec,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	pad: number
): boolean
	return x1 >= a.x0 - pad and x0 <= a.x1 + pad and z1 >= a.z0 - pad and z0 <= a.z1 + pad
end

-- Does this rectangle cut across a road other than `except`?
local function crossesOtherRoad(
	roads: { Layout.GroundSpec },
	except: Layout.GroundSpec,
	x0: number,
	z0: number,
	x1: number,
	z1: number
): boolean
	for _, r in roads do
		if r ~= except and overlaps(r, x0, z0, x1, z1, 0.5) then
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------ ground paint

local function pavement(plan: ArtKit.Plan, map: ArtMap.Map)
	local half = map.layout.half
	-- paving seams (only where bare sidewalk shows)
	local seam = "#7E8CA3"
	for k = -half, half, 10 do
		for a = -half, half - 20, 20 do
			local cx, cz = a + 10, k
			if
				map:groundKind(cx, cz) == "sidewalk"
				and map:groundKind(a, k) == "sidewalk"
				and map:groundKind(a + 20, k) == "sidewalk"
				and not map:blocked(cx, cz, 0)
			then
				ArtKit.flat(plan, G, a, k - 0.1, a + 20, k + 0.1, 0.01, seam)
			end
			local sx, sz = k, a + 10
			if
				map:groundKind(sx, sz) == "sidewalk"
				and map:groundKind(k, a) == "sidewalk"
				and map:groundKind(k, a + 20) == "sidewalk"
				and not map:blocked(sx, sz, 0)
			then
				ArtKit.flat(plan, G, k - 0.1, a, k + 0.1, a + 20, 0.011, seam)
			end
		end
	end
end

-- Thin circuit-board lines in the pavement. Plain paint, not glowing, so nothing reads as a shot.
local function circuitLines(plan: ArtKit.Plan, map: ArtMap.Map)
	local half = map.layout.half
	local color = "#4B93A6"
	local function clear(x: number, z: number): boolean
		return math.abs(x) < half - 2
			and math.abs(z) < half - 2
			and map:groundKind(x, z) == "sidewalk"
			and not map:blocked(x, z, 1.5)
	end
	local made = 0
	local tries = 0
	while made < 110 and tries < 900 do
		tries += 1
		local x = math.floor(ArtKit.range(plan, -half, half) / 5) * 5
		local z = math.floor(ArtKit.range(plan, -half, half) / 5) * 5
		local horizontal = ArtKit.chance(plan, 0.5)
		for _ = 1, 3 do
			local len = 5 * math.floor(ArtKit.range(plan, 1, 5))
			if ArtKit.chance(plan, 0.5) then
				len = -len
			end
			local nx, nz = x, z
			if horizontal then
				nx = x + len
			else
				nz = z + len
			end
			if not (clear(x, z) and clear(nx, nz) and clear((x + nx) / 2, (z + nz) / 2)) then
				break
			end
			if horizontal then
				ArtKit.flat(
					plan,
					G,
					math.min(x, nx),
					z - 0.18,
					math.max(x, nx),
					z + 0.18,
					0.02,
					color
				)
			else
				ArtKit.flat(
					plan,
					G,
					x - 0.18,
					math.min(z, nz),
					x + 0.18,
					math.max(z, nz),
					0.021,
					color
				)
			end
			made += 1
			x, z = nx, nz
			horizontal = not horizontal
		end
		if clear(x, z) then
			ArtKit.disc(plan, G, x, z, 0.7, 0.025, color)
			ArtKit.disc(plan, G, x, z, 0.3, 0.09, "#10203A")
		end
	end
end

local function roads(plan: ArtKit.Plan, map: ArtMap.Map)
	local rs = map:ground("road")
	local paint = P.paint
	for _, r in rs do
		local horiz = r.x1 - r.x0 > r.z1 - r.z0
		local a0, a1 = if horiz then r.x0 else r.z0, if horiz then r.x1 else r.z1
		local c0, c1 = if horiz then r.z0 else r.x0, if horiz then r.z1 else r.x1
		local mid = (c0 + c1) / 2
		local function seg(a: number, b: number, c: number, wdt: number, y: number, color: string)
			local x0, x1, z0, z1
			if horiz then
				x0, x1, z0, z1 = a, b, c - wdt / 2, c + wdt / 2
			else
				x0, x1, z0, z1 = c - wdt / 2, c + wdt / 2, a, b
			end
			if crossesOtherRoad(rs, r, x0, z0, x1, z1) then
				return
			end
			ArtKit.flat(plan, G, x0, z0, x1, z1, y, color)
		end
		-- center dashes
		local a = a0 + 3
		while a + 6 <= a1 - 2 do
			seg(a, a + 6, mid, 0.5, 0.11, paint)
			a += 12
		end
		-- solid edge lines and curbs
		a = a0
		while a + 12 <= a1 + 0.01 do
			seg(a, a + 12, c0 + 1.4, 0.3, 0.11, paint)
			seg(a, a + 12, c1 - 1.4, 0.3, 0.11, paint)
			seg(a, a + 12, c0 - 0.4, 0.8, 0.02, P.trim)
			seg(a, a + 12, c1 + 0.4, 0.8, 0.021, P.trim)
			a += 12
		end
	end
	-- crosswalks and stop lines on every arm of every junction
	for _, i in map.layout.intersections do
		local w, d = i.x1 - i.x0, i.z1 - i.z0
		local arms = {
			{ "N", (i.x0 + i.x1) / 2, i.z0 - 3 },
			{ "S", (i.x0 + i.x1) / 2, i.z1 + 3 },
			{ "W", i.x0 - 3, (i.z0 + i.z1) / 2 },
			{ "E", i.x1 + 3, (i.z0 + i.z1) / 2 },
		}
		for _, arm in arms do
			local side, ax, az = arm[1] :: string, arm[2] :: number, arm[3] :: number
			if map:groundKind(ax, az) ~= "road" then
				continue
			end
			if side == "N" or side == "S" then
				local n = math.floor(w / 2.6)
				for k = 0, n - 1 do
					local x = i.x0 + 1.3 + k * 2.6
					ArtKit.flat(plan, G, x, az - 2, x + 1.3, az + 2, 0.11, paint)
				end
				local sz = if side == "N" then az - 3.4 else az + 3.4
				ArtKit.flat(plan, G, i.x0 + 1, sz - 0.3, i.x1 - 1, sz + 0.3, 0.11, paint)
			else
				local n = math.floor(d / 2.6)
				for k = 0, n - 1 do
					local z = i.z0 + 1.3 + k * 2.6
					ArtKit.flat(plan, G, ax - 2, z, ax + 2, z + 1.3, 0.11, paint)
				end
				local sx = if side == "W" then ax - 3.4 else ax + 3.4
				ArtKit.flat(plan, G, sx - 0.3, i.z0 + 1, sx + 0.3, i.z1 - 1, 0.11, paint)
			end
		end
	end
end

local function manholesAndPuddles(plan: ArtKit.Plan, map: ArtMap.Map)
	local function spot(kind: string): (number?, number?)
		for _ = 1, 40 do
			local x = ArtKit.range(plan, -100, 100)
			local z = ArtKit.range(plan, -100, 100)
			if map:groundKind(x, z) == kind and not map:blocked(x, z, 3) then
				return x, z
			end
		end
		return nil, nil
	end
	for _ = 1, 7 do
		local x, z = spot("road")
		if x ~= nil and z ~= nil then
			ArtKit.disc(plan, G, x, z, 1.7, 0.11, P.steelDark)
			ArtKit.disc(plan, G, x, z, 1.35, 0.17, "#20262F")
			ArtKit.flat(plan, G, x - 1.2, z - 0.1, x + 1.2, z + 0.1, 0.23, P.steelDark)
			ArtKit.flat(plan, G, x - 0.1, z - 1.2, x + 0.1, z + 1.2, 0.231, P.steelDark)
		end
	end
	for _ = 1, 9 do
		local x, z = spot("road")
		if x ~= nil and z ~= nil then
			ArtKit.flat(plan, G, x - 1, z - 0.4, x + 1, z + 0.4, 0.11, "#14202F")
			for k = -2, 2 do
				ArtKit.flat(
					plan,
					G,
					x + k * 0.38 - 0.06,
					z - 0.4,
					x + k * 0.38 + 0.06,
					z + 0.4,
					0.18,
					P.steelDark
				)
			end
		end
	end
	local kinds = { "road", "road", "road", "sidewalk", "sidewalk", "alley", "alley" }
	for i = 1, 14 do
		local x, z = spot(kinds[(i % #kinds) + 1] :: string)
		if x ~= nil and z ~= nil then
			local r = ArtKit.range(plan, 1.6, 3.4)
			ArtKit.disc(
				plan,
				G,
				x,
				z,
				r,
				0.115,
				"#142238",
				{ reflectance = 0.55, transparency = 0.08, material = "Glass" }
			)
			ArtKit.disc(
				plan,
				G,
				x + r * 0.6,
				z + r * 0.2,
				r * 0.6,
				0.12,
				"#142238",
				{ reflectance = 0.55, transparency = 0.08, material = "Glass" }
			)
		end
	end
end

local function lots(plan: ArtKit.Plan, map: ArtMap.Map)
	for _, g in map:ground("lot") do
		local z = g.z0 + 8
		while z < g.z1 - 4 do
			local x0, x1 = g.x0 + 3, g.x1 - 3
			if not map:rectHitsSolid(x0, z - 0.2, x1, z + 0.2, 0.2) then
				ArtKit.flat(plan, G, x0, z - 0.15, x1, z + 0.15, 0.06, P.paint)
			end
			z += 12
		end
		for _ = 1, 6 do
			local x = ArtKit.range(plan, g.x0 + 4, g.x1 - 4)
			local zz = ArtKit.range(plan, g.z0 + 4, g.z1 - 4)
			if not map:blocked(x, zz, 3) then
				ArtKit.disc(plan, G, x, zz, ArtKit.range(plan, 0.8, 1.6), 0.07, "#4B5568")
			end
		end
	end
	for _, g in map:ground("alley") do
		local horiz = g.x1 - g.x0 > g.z1 - g.z0
		local mx, mz = (g.x0 + g.x1) / 2, (g.z0 + g.z1) / 2
		if horiz then
			ArtKit.flat(plan, G, g.x0 + 1, mz - 0.3, g.x1 - 1, mz + 0.3, 0.09, "#1B2638")
		else
			ArtKit.flat(plan, G, mx - 0.3, g.z0 + 1, mx + 0.3, g.z1 - 1, 0.09, "#1B2638")
		end
	end
end

-- ------------------------------------------------------------ props

type Box = { x0: number, z0: number, x1: number, z1: number, h: number, id: string }

local function boxOf(s: Layout.Solid): Box
	return { x0 = s.x0, z0 = s.z0, x1 = s.x1, z1 = s.z1, h = s.h, id = s.id }
end

local function car(plan: ArtKit.Plan, b: Box)
	local cx, cz = (b.x0 + b.x1) / 2, (b.z0 + b.z1) / 2
	local alongX = (b.x1 - b.x0) >= (b.z1 - b.z0)
	local len = math.max(b.x1 - b.x0, b.z1 - b.z0) - 0.4
	local wid = math.min(b.x1 - b.x0, b.z1 - b.z0) - 0.4
	local dir = if ArtKit.chance(plan, 0.5) then 1 else -1
	local color = ArtKit.pick(plan, P.car)
	local function B(
		du: number,
		y: number,
		dv: number,
		su: number,
		sy: number,
		sv: number,
		c: string,
		o: ArtKit.Opts?
	)
		if alongX then
			ArtKit.box(plan, PR, cx + du, y, cz + dv, su, sy, sv, c, o)
		else
			ArtKit.box(plan, PR, cx + dv, y, cz + du, sv, sy, su, c, o)
		end
	end
	B(0, 1.15, 0, len, 1.3, wid, color, { material = "Metal", shadow = true, reflectance = 0.1 }) -- body
	B(
		-dir * len * 0.08,
		2.35,
		0,
		len * 0.5,
		1.1,
		wid - 0.5,
		color,
		{ material = "Metal", shadow = true }
	) -- cabin
	B(
		-dir * len * 0.08,
		2.4,
		0,
		len * 0.5 + 0.06,
		0.8,
		wid - 0.4,
		"#10203A",
		{ material = "Glass", reflectance = 0.25 }
	) -- windows
	B(dir * len * 0.3, 1.9, 0, len * 0.3, 0.2, wid - 0.3, ArtKit.mix(color, "#000000", 0.2)) -- hood line
	B(0, 0.55, 0, len - 0.6, 0.5, wid - 0.5, "#1B1F27") -- skirt
	-- wheels
	for _, du in { -len * 0.32, len * 0.32 } do
		for _, dv in { -wid / 2 + 0.1, wid / 2 - 0.1 } do
			local wx, wz = cx, cz
			if alongX then
				wx, wz = cx + du, cz + dv
			else
				wx, wz = cx + dv, cz + du
			end
			ArtKit.hcyl(
				plan,
				PR,
				wx,
				0.85,
				wz,
				0.85,
				0.5,
				if alongX then "z" else "x",
				"#15181D",
				{ material = "Rubber" }
			)
			ArtKit.hcyl(
				plan,
				PR,
				wx,
				0.85,
				wz,
				0.4,
				0.56,
				if alongX then "z" else "x",
				P.steel,
				{ material = "Metal" }
			)
		end
	end
	-- lights: white at the front, red at the back
	for _, dv in { -wid / 2 + 0.55, wid / 2 - 0.55 } do
		B(
			dir * (len / 2 - 0.05),
			1.45,
			dv,
			0.18,
			0.45,
			0.8,
			P.coolLamp,
			{ material = "Neon", neon = ArtKit.glow(P.coolLamp, "#6C7C93", 0.25, true) }
		)
		B(
			-dir * (len / 2 - 0.05),
			1.45,
			dv,
			0.18,
			0.45,
			0.8,
			P.coral,
			{ material = "Neon", neon = ArtKit.glow(P.coral, P.coralDim, 0.2, true) }
		)
	end
	B(-dir * (len / 2 - 0.02), 0.95, 0, 0.1, 0.4, 1.4, P.white) -- plate
end

local function barrier(plan: ArtKit.Plan, b: Box)
	local cx, cz = (b.x0 + b.x1) / 2, (b.z0 + b.z1) / 2
	local w, d = b.x1 - b.x0, b.z1 - b.z0
	local alongX = w >= d
	local len = math.max(w, d)
	local thick = math.min(w, d)
	local function B(
		u: number,
		y: number,
		su: number,
		sy: number,
		sv: number,
		c: string,
		o: ArtKit.Opts?
	)
		if alongX then
			ArtKit.box(plan, PR, cx + u, y, cz, su, sy, sv, c, o)
		else
			ArtKit.box(plan, PR, cx, y, cz + u, sv, sy, su, c, o)
		end
	end
	B(0, 0.6, len, 1.2, thick, "#8892A0", { material = "Concrete", shadow = true })
	B(
		0,
		2.0,
		len,
		1.6,
		math.max(thick - 0.9, 0.6),
		"#9AA3AF",
		{ material = "Concrete", shadow = true }
	)
	B(0, 3.0, len, 0.4, math.max(thick - 1.0, 0.5), P.trim, { material = "Concrete" })
	local n = math.max(2, math.floor(len / 1.8))
	for i = 0, n - 1, 2 do
		local u = -len / 2 + (i + 0.5) * len / n
		B(u, 2.0, len / n, 1.3, math.max(thick - 0.8, 0.7), P.coral, { material = "SmoothPlastic" })
	end
	for _, u in { -len / 2 + 0.2, len / 2 - 0.2 } do
		B(
			u,
			1.0,
			0.25,
			0.5,
			math.max(thick - 0.4, 0.8),
			P.coral,
			{ material = "Neon", neon = ArtKit.glow(P.coral, P.coralDim, 0.15, true) }
		)
	end
end

local function dumpster(plan: ArtKit.Plan, b: Box)
	local cx, cz = (b.x0 + b.x1) / 2, (b.z0 + b.z1) / 2
	local w, d = b.x1 - b.x0, b.z1 - b.z0
	ArtKit.box(
		plan,
		PR,
		cx,
		1.5,
		cz,
		w - 0.2,
		3,
		d - 0.2,
		"#3E6B52",
		{ material = "Metal", shadow = true }
	)
	ArtKit.box(plan, PR, cx, 3.2, cz, w, 0.35, d, "#2B3A46", { material = "Metal" })
	ArtKit.box(plan, PR, cx, 1.6, cz, w + 0.04, 0.3, d + 0.04, "#2B3A46")
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			ArtKit.vcyl(
				plan,
				PR,
				cx + sx * (w / 2 - 0.4),
				0,
				cz + sz * (d / 2 - 0.4),
				0.3,
				0.5,
				"#15181D"
			)
		end
	end
end

local function planter(plan: ArtKit.Plan, b: Box)
	local cx, cz = (b.x0 + b.x1) / 2, (b.z0 + b.z1) / 2
	local w, d = b.x1 - b.x0, b.z1 - b.z0
	local h = math.min(b.h, 4)
	ArtKit.box(
		plan,
		PR,
		cx,
		h * 0.4,
		cz,
		w,
		h * 0.8,
		d,
		"#8892A0",
		{ material = "Concrete", shadow = true }
	)
	ArtKit.box(
		plan,
		PR,
		cx,
		h * 0.8 + 0.15,
		cz,
		w + 0.3,
		0.3,
		d + 0.3,
		P.trim,
		{ material = "Concrete" }
	)
	ArtKit.box(
		plan,
		PR,
		cx,
		h * 0.8 + 0.4,
		cz,
		w - 0.4,
		0.3,
		d - 0.4,
		"#3B2E27",
		{ material = "Ground" }
	)
	local n = math.max(2, math.floor(math.max(w, d) / 1.6))
	for i = 1, n do
		local t = (i - 0.5) / n
		local px = if w >= d then b.x0 + 0.8 + t * (w - 1.6) else cx
		local pz = if w >= d then cz else b.z0 + 0.8 + t * (d - 1.6)
		ArtKit.ball(
			plan,
			PR,
			px,
			h * 0.8 + 1.1,
			pz,
			math.min(0.75, math.min(w, d) / 2 - 0.2),
			ArtKit.pick(plan, P.tree),
			{ shadow = false }
		)
	end
end

local function crate(plan: ArtKit.Plan, b: Box)
	-- grey cargo bin with hazard bands: it must never look like a purple supply crate
	local cx, cz = (b.x0 + b.x1) / 2, (b.z0 + b.z1) / 2
	local w, d = b.x1 - b.x0, b.z1 - b.z0
	local h = math.min(b.h, 4)
	ArtKit.box(
		plan,
		PR,
		cx,
		h / 2 - 0.1,
		cz,
		w,
		h - 0.2,
		d,
		"#7B8794",
		{ material = "Metal", shadow = true }
	)
	ArtKit.box(
		plan,
		PR,
		cx,
		h - 0.1,
		cz,
		w + 0.2,
		0.3,
		d + 0.2,
		P.steelDark,
		{ material = "Metal" }
	)
	for _, k in { -0.28, 0.28 } do
		ArtKit.box(plan, PR, cx + k * w, h / 2 - 0.1, cz, 0.45, h - 0.15, d + 0.1, "#2B3440")
		ArtKit.box(plan, PR, cx, h / 2 - 0.1, cz + k * d, w + 0.1, h - 0.15, 0.45, "#2B3440")
	end
	for i = 0, 3 do
		ArtKit.box(
			plan,
			PR,
			cx - w * 0.3 + i * w * 0.2,
			0.7,
			cz - d / 2 - 0.05,
			w * 0.1,
			1.0,
			0.08,
			if i % 2 == 0 then P.coral else P.white,
			{ rx = 0 }
		)
	end
	ArtKit.box(plan, PR, cx, h * 0.6, cz - d / 2 - 0.08, 1.2, 0.35, 0.1, P.steel)
end

local function container(plan: ArtKit.Plan, b: Box, index: number)
	local cx, cz = (b.x0 + b.x1) / 2, (b.z0 + b.z1) / 2
	local w, d = b.x1 - b.x0, b.z1 - b.z0
	local h = b.h
	local alongX = w >= d
	local color = P.container[(index % #P.container) + 1] :: string
	ArtKit.box(
		plan,
		PR,
		cx,
		h / 2,
		cz,
		w,
		h,
		d,
		color,
		{ material = "CorrodedMetal", shadow = true }
	)
	local len = if alongX then w else d
	local n = math.floor((len - 1) / 1.2)
	local dark = ArtKit.mix(color, "#000000", 0.28)
	for i = 0, n do
		local u = -len / 2 + 0.6 + i * 1.2
		for _, side in { -1, 1 } do
			if alongX then
				ArtKit.box(
					plan,
					PR,
					cx + u,
					h / 2,
					cz + side * (d / 2 + 0.06),
					0.3,
					h - 0.6,
					0.12,
					dark
				)
			else
				ArtKit.box(
					plan,
					PR,
					cx + side * (w / 2 + 0.06),
					h / 2,
					cz + u,
					0.12,
					h - 0.6,
					0.3,
					dark
				)
			end
		end
	end
	-- frame rails top and bottom, door end with lock bars
	if alongX then
		ArtKit.box(plan, PR, cx, h - 0.15, cz, w + 0.1, 0.3, d + 0.1, dark)
		ArtKit.box(plan, PR, cx, 0.15, cz, w + 0.1, 0.3, d + 0.1, dark)
		for _, k in { -0.25, 0.25 } do
			ArtKit.box(plan, PR, cx + w / 2 + 0.05, h / 2, cz + k * d, 0.12, h - 0.5, 0.2, P.steel)
		end
	else
		ArtKit.box(plan, PR, cx, h - 0.15, cz, w + 0.1, 0.3, d + 0.1, dark)
		ArtKit.box(plan, PR, cx, 0.15, cz, w + 0.1, 0.3, d + 0.1, dark)
		for _, k in { -0.25, 0.25 } do
			ArtKit.box(plan, PR, cx + k * w, h / 2, cz + d / 2 + 0.05, 0.2, h - 0.5, 0.12, P.steel)
		end
	end
end

-- Kiosk: a newsstand with a counter window, awning and a neon sign. Fits inside its box.
local function kiosk(plan: ArtKit.Plan, b: Box)
	local cx, cz = (b.x0 + b.x1) / 2, (b.z0 + b.z1) / 2
	local w, d = b.x1 - b.x0, b.z1 - b.z0
	ArtKit.box(
		plan,
		PR,
		cx,
		b.h / 2 - 0.4,
		cz,
		w - 0.2,
		b.h - 0.8,
		d - 0.2,
		"#33507A",
		{ material = "Metal", shadow = true }
	)
	ArtKit.box(plan, PR, cx, b.h - 0.2, cz, w, 0.6, d, P.coral, { material = "Fabric" })
	ArtKit.box(plan, PR, cx, b.h + 0.5, cz, w - 3, 1.0, d - 3, P.roof)
	for i, side in { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } } do
		local sx, sz = side[1] :: number, side[2] :: number
		local px, pz = cx + sx * (w / 2 + 0.02), cz + sz * (d / 2 + 0.02)
		local ww = if sx == 0 then w - 3 else 0.12
		local dd = if sx == 0 then 0.12 else d - 3
		ArtKit.box(plan, PR, px, 3.6, pz, ww, 2.2, dd, "#8FE3EC", {
			material = "Neon",
			neon = ArtKit.glow("#8FE3EC", "#27405F", 0.1 + i * 0.1, false),
		})
		ArtKit.box(
			plan,
			PR,
			cx + sx * (w / 2 - 0.1),
			2.0,
			cz + sz * (d / 2 - 0.1),
			if sx == 0 then w - 3 else 0.4,
			0.3,
			if sx == 0 then 0.4 else d - 3,
			P.trim
		)
	end
	if plan.signs < 26 then
		ArtKit.box(plan, PR, cx, b.h + 1.9, cz, w - 4, 1.4, 0.3, "#10203A", {
			sign = { text = "NEWS", color = P.coral, face = "Back", background = "#10203A" },
		})
	end
end

local function generic(plan: ArtKit.Plan, s: Layout.Solid)
	-- Unknown solids still get a trimmed shell so nothing stays bare gray.
	local cx, cz = (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
	local w, d = s.x1 - s.x0, s.z1 - s.z0
	if s.h <= 0.6 then
		return
	end
	ArtKit.box(
		plan,
		PR,
		cx,
		s.h / 2,
		cz,
		w,
		s.h,
		d,
		"#5A7390",
		{ material = "Concrete", shadow = true }
	)
	ArtKit.box(plan, PR, cx, s.h + 0.1, cz, w + 0.2, 0.2, d + 0.2, P.trim)
end

function StreetArt.build(plan: ArtKit.Plan, map: ArtMap.Map, handled: { [string]: boolean })
	pavement(plan, map)
	circuitLines(plan, map)
	roads(plan, map)
	manholesAndPuddles(plan, map)
	lots(plan, map)
	local boxIndex = 0
	for _, s in map.solids do
		local kind = StreetArt.classify(s.id)
		if kind == "car" then
			car(plan, boxOf(s))
		elseif kind == "barrier" then
			barrier(plan, boxOf(s))
		elseif kind == "dumpster" then
			dumpster(plan, boxOf(s))
		elseif kind == "planter" then
			planter(plan, boxOf(s))
		elseif kind == "crate" then
			crate(plan, boxOf(s))
		elseif kind == "container" then
			boxIndex += 1
			container(plan, boxOf(s), boxIndex)
		elseif kind == "kiosk" then
			kiosk(plan, boxOf(s))
		elseif
			kind == nil
			and not handled[s.id]
			and s.kind ~= "wall"
			and s.kind ~= "partition"
			and s.kind ~= "fence"
			and s.kind ~= "mass"
			and s.kind ~= "water"
		then
			generic(plan, s)
		end
	end
end

return StreetArt
