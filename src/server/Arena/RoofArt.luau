--!strict
-- Rooftops for the Neon Night city (piece 14): parapets with a neon rim, tar patches, air
-- conditioners, vents, water tanks, antennas with blinking lights, solar panels, skylights and
-- big signs. Roofs fade away when you stand inside, so every part copies that fade (fadeWith).
-- Pure planning, no Roblox types.
local ArtKit = require("./ArtKit")

local RoofArt = {}

local P = ArtKit.P

export type Roof = {
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	y: number, -- top surface height
	fadeWith: string,
	rich: boolean, -- true for roofs that get the big extras (tank, solar, billboard)
	sign: string?, -- optional big rooftop sign text
}

local function rim(plan: ArtKit.Plan, r: Roof, color: string, dim: string)
	local g = "Roofs"
	local t, h = 0.7, 1.1
	local o = { fadeWith = r.fadeWith, material = "Concrete" } :: ArtKit.Opts
	ArtKit.span(plan, g, r.x0, r.y, r.z0, r.x1, r.y + h, r.z0 + t, P.trim, o)
	ArtKit.span(
		plan,
		g,
		r.x0,
		r.y,
		r.z1 - t,
		r.x1,
		r.y + h,
		r.z1,
		P.trim,
		{ fadeWith = r.fadeWith, material = "Concrete" }
	)
	ArtKit.span(
		plan,
		g,
		r.x0,
		r.y,
		r.z0 + t,
		r.x0 + t,
		r.y + h,
		r.z1 - t,
		P.trim,
		{ fadeWith = r.fadeWith, material = "Concrete" }
	)
	ArtKit.span(
		plan,
		g,
		r.x1 - t,
		r.y,
		r.z0 + t,
		r.x1,
		r.y + h,
		r.z1 - t,
		P.trim,
		{ fadeWith = r.fadeWith, material = "Concrete" }
	)
	-- neon line on top of the parapet
	local n = ArtKit.glow(color, dim, 0, true)
	local top = r.y + h + 0.08
	ArtKit.span(
		plan,
		g,
		r.x0 + 0.1,
		top,
		r.z0 + 0.25,
		r.x1 - 0.1,
		top + 0.14,
		r.z0 + 0.45,
		color,
		{ fadeWith = r.fadeWith, material = "Neon", neon = n }
	)
	ArtKit.span(
		plan,
		g,
		r.x0 + 0.1,
		top,
		r.z1 - 0.45,
		r.x1 - 0.1,
		top + 0.14,
		r.z1 - 0.25,
		color,
		{ fadeWith = r.fadeWith, material = "Neon", neon = n }
	)
	ArtKit.span(
		plan,
		g,
		r.x0 + 0.25,
		top,
		r.z0 + 0.45,
		r.x0 + 0.45,
		top + 0.14,
		r.z1 - 0.45,
		color,
		{ fadeWith = r.fadeWith, material = "Neon", neon = n }
	)
	ArtKit.span(
		plan,
		g,
		r.x1 - 0.45,
		top,
		r.z0 + 0.45,
		r.x1 - 0.25,
		top + 0.14,
		r.z1 - 0.45,
		color,
		{ fadeWith = r.fadeWith, material = "Neon", neon = n }
	)
end

local function acUnit(plan: ArtKit.Plan, r: Roof, x: number, z: number)
	local w, d = ArtKit.range(plan, 3, 4.6), ArtKit.range(plan, 2.2, 3.4)
	ArtKit.box(
		plan,
		"Roofs",
		x,
		r.y + 1.1,
		z,
		w,
		2.2,
		d,
		P.steel,
		{ fadeWith = r.fadeWith, material = "Metal", shadow = true }
	)
	ArtKit.vcyl(
		plan,
		"Roofs",
		x - w * 0.18,
		r.y + 2.2,
		z,
		math.min(w, d) * 0.3,
		0.25,
		P.steelDark,
		{ fadeWith = r.fadeWith }
	)
	ArtKit.box(
		plan,
		"Roofs",
		x + w * 0.3,
		r.y + 1.1,
		z - d / 2 - 0.05,
		0.12,
		1.6,
		0.1,
		P.steelDark,
		{ fadeWith = r.fadeWith }
	)
end

local function vent(plan: ArtKit.Plan, r: Roof, x: number, z: number)
	ArtKit.vcyl(
		plan,
		"Roofs",
		x,
		r.y,
		z,
		0.6,
		1.6,
		P.steelDark,
		{ fadeWith = r.fadeWith, material = "Metal" }
	)
	ArtKit.vcyl(
		plan,
		"Roofs",
		x,
		r.y + 1.6,
		z,
		0.95,
		0.25,
		P.steel,
		{ fadeWith = r.fadeWith, material = "Metal" }
	)
end

local function tank(plan: ArtKit.Plan, r: Roof, x: number, z: number)
	for _, d in { { -1.4, -1.4 }, { 1.4, -1.4 }, { -1.4, 1.4 }, { 1.4, 1.4 } } do
		ArtKit.vcyl(
			plan,
			"Roofs",
			x + (d[1] :: number),
			r.y,
			z + (d[2] :: number),
			0.18,
			2.6,
			P.steelDark,
			{ fadeWith = r.fadeWith }
		)
	end
	ArtKit.vcyl(
		plan,
		"Roofs",
		x,
		r.y + 2.6,
		z,
		2.3,
		4,
		"#8A6A52",
		{ fadeWith = r.fadeWith, material = "Wood", shadow = true }
	)
	ArtKit.vcyl(plan, "Roofs", x, r.y + 6.6, z, 2.4, 0.35, P.steelDark, { fadeWith = r.fadeWith })
	for i = 0, 2 do
		ArtKit.vcyl(
			plan,
			"Roofs",
			x,
			r.y + 3.2 + i * 1.3,
			z,
			2.38,
			0.14,
			P.steelDark,
			{ fadeWith = r.fadeWith }
		)
	end
end

local function antenna(plan: ArtKit.Plan, r: Roof, x: number, z: number, h: number)
	ArtKit.vcyl(
		plan,
		"Roofs",
		x,
		r.y,
		z,
		0.14,
		h,
		P.steel,
		{ fadeWith = r.fadeWith, material = "Metal" }
	)
	ArtKit.box(
		plan,
		"Roofs",
		x,
		r.y + h * 0.7,
		z,
		2.4,
		0.12,
		0.12,
		P.steel,
		{ fadeWith = r.fadeWith }
	)
	ArtKit.box(
		plan,
		"Roofs",
		x,
		r.y + h * 0.85,
		z,
		1.4,
		0.12,
		0.12,
		P.steel,
		{ fadeWith = r.fadeWith }
	)
	ArtKit.ball(plan, "Roofs", x, r.y + h + 0.2, z, 0.35, P.coral, {
		fadeWith = r.fadeWith,
		material = "Neon",
		neon = ArtKit.glow(P.coral, P.coralDim, 0.35, false),
	})
end

local function solar(plan: ArtKit.Plan, r: Roof, x: number, z: number)
	for i = 0, 2 do
		ArtKit.box(plan, "Roofs", x + i * 6.4, r.y + 1.3, z, 6, 0.25, 3.6, "#3E6C9A", {
			fadeWith = r.fadeWith,
			rx = -18,
			material = "Glass",
			reflectance = 0.25,
			shadow = true,
		})
		ArtKit.box(
			plan,
			"Roofs",
			x + i * 6.4,
			r.y + 0.6,
			z + 1.1,
			5.6,
			1.2,
			0.2,
			P.steelDark,
			{ fadeWith = r.fadeWith }
		)
	end
end

local function skylight(plan: ArtKit.Plan, r: Roof, x: number, z: number, w: number, d: number)
	ArtKit.box(
		plan,
		"Roofs",
		x,
		r.y + 0.35,
		z,
		w + 0.8,
		0.7,
		d + 0.8,
		P.trimDark,
		{ fadeWith = r.fadeWith }
	)
	ArtKit.box(plan, "Roofs", x, r.y + 0.75, z, w, 0.2, d, P.cyan, {
		fadeWith = r.fadeWith,
		material = "Neon",
		neon = ArtKit.glow(P.cyan, "#35547C", 0.4, false),
		transparency = 0.15,
	})
end

function RoofArt.build(plan: ArtKit.Plan, r: Roof)
	local w, d = r.x1 - r.x0, r.z1 - r.z0
	if w < 6 or d < 6 then
		return
	end
	rim(plan, r, P.cyan, P.cyanDim)

	-- tar patches
	for _ = 1, 2 + math.floor(w * d / 1400) do
		local pw, pd =
			ArtKit.range(plan, 4, math.min(18, w - 4)), ArtKit.range(plan, 4, math.min(14, d - 4))
		local px = ArtKit.range(plan, r.x0 + 2, r.x1 - 2 - pw)
		local pz = ArtKit.range(plan, r.z0 + 2, r.z1 - 2 - pd)
		ArtKit.flat(
			plan,
			"Roofs",
			px,
			pz,
			px + pw,
			pz + pd,
			r.y,
			P.roofPatch,
			{ fadeWith = r.fadeWith }
		)
	end

	local keepOut = 2.5
	local function spot(): (number, number)
		return ArtKit.range(plan, r.x0 + keepOut + 2, r.x1 - keepOut - 2),
			ArtKit.range(plan, r.z0 + keepOut + 2, r.z1 - keepOut - 2)
	end

	for _ = 1, math.max(3, math.floor(w * d / 300)) do
		local x, z = spot()
		acUnit(plan, r, x, z)
	end
	for _ = 1, math.max(2, math.floor(w * d / 700)) do
		local x, z = spot()
		vent(plan, r, x, z)
	end
	for _ = 1, 2 do
		local x, z = spot()
		antenna(plan, r, x, z, ArtKit.range(plan, 7, 13))
	end
	if r.rich then
		local x, z = spot()
		tank(plan, r, x, z)
		local sx, sz = spot()
		solar(plan, r, math.clamp(sx, r.x0 + 6, r.x1 - 14), sz)
		for _ = 1, 2 do
			local kx, kz = spot()
			skylight(plan, r, kx, kz, 5, 3.4)
		end
	end
	if r.sign ~= nil and plan.signs < 26 then
		-- A big sign on legs, facing south, near the front edge
		local sw, sh = math.min(w - 8, 30), 6.4
		local cx = (r.x0 + r.x1) / 2
		local cz = r.z1 - 5
		for _, dx in { -sw / 2 + 2, sw / 2 - 2 } do
			ArtKit.box(
				plan,
				"Roofs",
				cx + dx,
				r.y + 2.6,
				cz,
				0.5,
				5.2,
				0.5,
				P.steelDark,
				{ fadeWith = r.fadeWith }
			)
		end
		ArtKit.box(plan, "Roofs", cx, r.y + 5.2 + sh / 2, cz, sw, sh, 0.5, "#10203A", {
			fadeWith = r.fadeWith,
			sign = { text = r.sign, color = P.cyan, face = "Back", background = "#10203A" },
			shadow = true,
		})
		local n = ArtKit.glow(P.coral, P.coralDim, 0, true)
		ArtKit.box(
			plan,
			"Roofs",
			cx,
			r.y + 5.2 + sh + 0.15,
			cz,
			sw + 0.6,
			0.3,
			0.6,
			P.coral,
			{ fadeWith = r.fadeWith, material = "Neon", neon = n }
		)
		ArtKit.box(plan, "Roofs", cx, r.y + 5.05, cz, sw + 0.6, 0.3, 0.6, P.coral, {
			fadeWith = r.fadeWith,
			material = "Neon",
			neon = n,
			light = if plan.lights < 28
				then { color = P.cyan, range = 36, brightness = 2 }
				else nil,
		})
	end
end

return RoofArt
