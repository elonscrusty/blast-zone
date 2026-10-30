--!strict
-- Shared tools for the city art planner (piece 14). Everything here is plain data and maths, no
-- Roblox types, so Lune can test the whole plan. A Spec is "one part to make"; ArtBuilder turns
-- the list into real parts. Axes: x east, z south, y up. Colors are "#RRGGBB".

local ArtKit = {}

export type Neon = {
	on: string, -- color when glowing
	off: string, -- color when dark (also the day color of soft neon)
	litAt: number, -- window style: switches on once the glow passes this (0 to 1)
	soft: boolean, -- true: fades between off and on as the glow rises instead of switching
}
export type Light = { color: string, range: number, brightness: number }
export type Sign = { text: string, color: string, face: string, font: string?, background: string? }

export type Spec = {
	name: string,
	group: string, -- Facades | Roofs | Street | Park | Interior | Props | Skyline
	shape: string, -- Block | Cylinder | Ball | Wedge
	x: number,
	y: number,
	z: number,
	sx: number, -- Part.Size
	sy: number,
	sz: number,
	rx: number, -- degrees
	ry: number,
	rz: number,
	color: string,
	material: string, -- an Enum.Material name
	transparency: number,
	reflectance: number,
	shadow: boolean,
	fadeWith: string?, -- the occluder part whose see-through fade this part copies
	owner: string?, -- the solid this part dresses; when that solid breaks (piece 43) its parts go
	neon: Neon?,
	light: Light?,
	sign: Sign?,
}

export type Opts = {
	name: string?,
	shape: string?,
	material: string?,
	transparency: number?,
	reflectance: number?,
	shadow: boolean?,
	fadeWith: string?,
	neon: Neon?,
	light: Light?,
	sign: Sign?,
	rx: number?,
	ry: number?,
	rz: number?,
}

export type Plan = {
	parts: { Spec },
	seed: number,
	state: number,
	lights: number,
	signs: number,
	counter: number,
	fade: string?, -- while set, new parts copy this occluder's fade (kiosk, bandstand)
	owner: string?, -- while set, new parts belong to this solid (a car that can break)
}

-- Day colors. The night comes from the lighting, so these are the "lit by the sun" values.
ArtKit.P = {
	wall = { "#4F77AB", "#4470A4", "#5B88BD" },
	wallDark = "#2E4A70",
	plinth = "#1B2A44",
	trim = "#C9D6E6",
	trimDark = "#26395A",
	roof = "#2E4A70",
	roofPatch = "#35547C",
	glassDark = "#1B2B44",
	steel = "#7B8794",
	steelDark = "#59616D",
	concrete = "#9AA3AF",
	asphalt = "#2E3D56",
	paint = "#F4F7FB",
	cyan = "#36D9E8",
	cyanDim = "#2A6F86",
	coral = "#F15B64",
	coralDim = "#8A3F55",
	mint = "#7FE5C3",
	white = "#EAF1F8",
	warm = "#FFD98A", -- lit window light, only used well above head height
	coolLamp = "#DDEBFF",
	tree = { "#3F8A58", "#55A56D", "#2F7A4C" },
	trunk = "#5E4632",
	hedge = "#3B7F4D",
	grass = "#62A266",
	grassAlt = "#72B076",
	path = "#C9D3E0",
	water = "#2A7BA6",
	container = { "#3B8F9A", "#C9503F", "#4D6A93" },
	car = { "#4D6A93", "#F15B64", "#9FB2C8", "#3B8F9A", "#E8F1FA" },
}

-- ----------------------------------------------------------------- random

-- Small deterministic generator (Lehmer). Same seed, same city.
function ArtKit.newPlan(seed: number): Plan
	return {
		parts = {},
		seed = seed,
		state = (seed % 2147483646) + 1,
		lights = 0,
		signs = 0,
		counter = 0,
		fade = nil,
		owner = nil,
	}
end

function ArtKit.rand(plan: Plan): number
	plan.state = (plan.state * 16807) % 2147483647
	return plan.state / 2147483647
end

function ArtKit.range(plan: Plan, a: number, b: number): number
	return a + (b - a) * ArtKit.rand(plan)
end

function ArtKit.chance(plan: Plan, p: number): boolean
	return ArtKit.rand(plan) < p
end

function ArtKit.pick<T>(plan: Plan, list: { T }): T
	return list[math.min(#list, 1 + math.floor(ArtKit.rand(plan) * #list))]
end

-- ----------------------------------------------------------------- colors

function ArtKit.rgb(hex: string): (number, number, number)
	local h = string.gsub(hex, "#", "")
	local r = tonumber(string.sub(h, 1, 2), 16) or 0
	local g = tonumber(string.sub(h, 3, 4), 16) or 0
	local b = tonumber(string.sub(h, 5, 6), 16) or 0
	return r / 255, g / 255, b / 255
end

function ArtKit.hex(r: number, g: number, b: number): string
	local function c(v: number): number
		return math.clamp(math.floor(v * 255 + 0.5), 0, 255)
	end
	return string.format("#%02X%02X%02X", c(r), c(g), c(b))
end

-- hue in degrees (0-360), saturation and value (0-1)
function ArtKit.hsv(hex: string): (number, number, number)
	local r, g, b = ArtKit.rgb(hex)
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h *= 60
	end
	local s = if mx == 0 then 0 else d / mx
	return h, s, mx
end

-- Pickups use gold orbs and violet crates. Anything low and close to those colors is banned, so
-- nothing in the scenery can be mistaken for a pickup.
function ArtKit.reservedColor(hex: string): string?
	local h, s, v = ArtKit.hsv(hex)
	if h >= 36 and h <= 54 and s >= 0.45 and v >= 0.6 then
		return "gold"
	end
	if h >= 255 and h <= 292 and s >= 0.3 and v >= 0.35 then
		return "violet"
	end
	return nil
end

function ArtKit.mix(a: string, b: string, k: number): string
	local ar, ag, ab = ArtKit.rgb(a)
	local br, bg, bb = ArtKit.rgb(b)
	return ArtKit.hex(ar + (br - ar) * k, ag + (bg - ag) * k, ab + (bb - ab) * k)
end

-- ----------------------------------------------------------------- parts

local function add(
	plan: Plan,
	group: string,
	shape: string,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	o: Opts?
): Spec
	local opts: Opts = o or {}
	plan.counter += 1
	local spec: Spec = {
		name = opts.name or `{group}{plan.counter}`,
		group = group,
		shape = opts.shape or shape,
		x = cx,
		y = cy,
		z = cz,
		sx = sx,
		sy = sy,
		sz = sz,
		rx = opts.rx or 0,
		ry = opts.ry or 0,
		rz = opts.rz or 0,
		color = color,
		material = opts.material or "SmoothPlastic",
		transparency = opts.transparency or 0,
		reflectance = opts.reflectance or 0,
		shadow = opts.shadow == true,
		fadeWith = opts.fadeWith or plan.fade,
		owner = plan.owner,
		neon = opts.neon,
		light = opts.light,
		sign = opts.sign,
	}
	if opts.light then
		plan.lights += 1
	end
	if opts.sign then
		plan.signs += 1
	end
	table.insert(plan.parts, spec)
	return spec
end

-- Centered box.
function ArtKit.box(
	plan: Plan,
	group: string,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	o: Opts?
): Spec
	return add(plan, group, "Block", cx, cy, cz, sx, sy, sz, color, o)
end

-- Box from two corners.
function ArtKit.span(
	plan: Plan,
	group: string,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	color: string,
	o: Opts?
): Spec
	return add(
		plan,
		group,
		"Block",
		(x0 + x1) / 2,
		(y0 + y1) / 2,
		(z0 + z1) / 2,
		x1 - x0,
		y1 - y0,
		z1 - z0,
		color,
		o
	)
end

-- Upright cylinder standing on y0.
function ArtKit.vcyl(
	plan: Plan,
	group: string,
	cx: number,
	y0: number,
	cz: number,
	radius: number,
	height: number,
	color: string,
	o: Opts?
): Spec
	local opts: Opts = o or {}
	opts.rz = 90
	return add(
		plan,
		group,
		"Cylinder",
		cx,
		y0 + height / 2,
		cz,
		height,
		radius * 2,
		radius * 2,
		color,
		opts
	)
end

-- Lying cylinder along x or z.
function ArtKit.hcyl(
	plan: Plan,
	group: string,
	cx: number,
	cy: number,
	cz: number,
	radius: number,
	length: number,
	axis: string,
	color: string,
	o: Opts?
): Spec
	local opts: Opts = o or {}
	if axis == "z" then
		opts.ry = 90
	end
	return add(plan, group, "Cylinder", cx, cy, cz, length, radius * 2, radius * 2, color, opts)
end

function ArtKit.ball(
	plan: Plan,
	group: string,
	cx: number,
	cy: number,
	cz: number,
	radius: number,
	color: string,
	o: Opts?
): Spec
	return add(plan, group, "Ball", cx, cy, cz, radius * 2, radius * 2, radius * 2, color, o)
end

-- A thin slab lying on the ground, bottom at y. Walkers never notice it (it is only paint).
ArtKit.FLAT = 0.06
function ArtKit.flat(
	plan: Plan,
	group: string,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	y: number,
	color: string,
	o: Opts?
): Spec
	return add(
		plan,
		group,
		"Block",
		(x0 + x1) / 2,
		y + ArtKit.FLAT / 2,
		(z0 + z1) / 2,
		x1 - x0,
		ArtKit.FLAT,
		z1 - z0,
		color,
		o
	)
end

function ArtKit.disc(
	plan: Plan,
	group: string,
	cx: number,
	cz: number,
	radius: number,
	y: number,
	color: string,
	o: Opts?
): Spec
	local opts: Opts = o or {}
	opts.rz = 90
	return add(
		plan,
		group,
		"Cylinder",
		cx,
		y + ArtKit.FLAT / 2,
		cz,
		ArtKit.FLAT,
		radius * 2,
		radius * 2,
		color,
		opts
	)
end

-- A window or strip of neon. The off color shows by day.
function ArtKit.glow(on: string, off: string, litAt: number, soft: boolean): Neon
	return { on = on, off = off, litAt = litAt, soft = soft }
end

-- ----------------------------------------------------------------- faces

-- A Face is a flat run along a wall: side is the way it looks ("N" looks toward -z, "S" toward
-- +z, "E" toward +x, "W" toward -x), u0..u1 runs along it, `at` is where the wall plane is, and
-- h is its height. Everything on a face is placed as (u along, y up, d out from the wall).
export type Face = {
	side: string,
	u0: number,
	u1: number,
	at: number,
	h: number,
	group: string,
	fadeWith: string?,
}

function ArtKit.faceWorld(f: Face, u: number, y: number, d: number): (number, number, number)
	if f.side == "S" then
		return u, y, f.at + d
	elseif f.side == "N" then
		return u, y, f.at - d
	elseif f.side == "E" then
		return f.at + d, y, u
	end
	return f.at - d, y, u
end

-- Face dimensions (along, up, out) to Part.Size.
function ArtKit.faceSize(
	f: Face,
	along: number,
	vert: number,
	depth: number
): (number, number, number)
	if f.side == "S" or f.side == "N" then
		return along, vert, depth
	end
	return depth, vert, along
end

-- The SurfaceGui face that points the way the Face looks (Front is -z in Roblox).
function ArtKit.guiFace(side: string): string
	if side == "N" then
		return "Front"
	elseif side == "S" then
		return "Back"
	elseif side == "E" then
		return "Right"
	end
	return "Left"
end

function ArtKit.fbox(
	plan: Plan,
	f: Face,
	u: number,
	y: number,
	d: number,
	along: number,
	vert: number,
	depth: number,
	color: string,
	o: Opts?
): Spec
	local opts: Opts = o or {}
	if opts.fadeWith == nil then
		opts.fadeWith = f.fadeWith
	end
	local x, yy, z = ArtKit.faceWorld(f, u, y, d)
	local sx, sy, sz = ArtKit.faceSize(f, along, vert, depth)
	return add(plan, f.group, "Block", x, yy, z, sx, sy, sz, color, opts)
end

-- Cylinder standing on the ground against a face.
function ArtKit.fvcyl(
	plan: Plan,
	f: Face,
	u: number,
	y0: number,
	d: number,
	radius: number,
	height: number,
	color: string,
	o: Opts?
): Spec
	local opts: Opts = o or {}
	if opts.fadeWith == nil then
		opts.fadeWith = f.fadeWith
	end
	local x, _, z = ArtKit.faceWorld(f, u, 0, d)
	return ArtKit.vcyl(plan, f.group, x, y0, z, radius, height, color, opts)
end

function ArtKit.fball(
	plan: Plan,
	f: Face,
	u: number,
	y: number,
	d: number,
	radius: number,
	color: string,
	o: Opts?
): Spec
	local opts: Opts = o or {}
	if opts.fadeWith == nil then
		opts.fadeWith = f.fadeWith
	end
	local x, yy, z = ArtKit.faceWorld(f, u, y, d)
	return ArtKit.ball(plan, f.group, x, yy, z, radius, color, opts)
end

-- The inside or outside face of a wall segment (a box x0..x1, z0..z1) of a building whose
-- middle is bcx, bcz. "Inside" looks into the room.
function ArtKit.wallFace(
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	bcx: number,
	bcz: number,
	inside: boolean,
	h: number,
	group: string,
	fadeWith: string?
): Face
	local horiz = (x1 - x0) >= (z1 - z0)
	local north = (z0 + z1) / 2 < bcz
	local west = (x0 + x1) / 2 < bcx
	if horiz then
		-- a north wall: its outside looks N and sits on z0; its inside looks S and sits on z1
		if north == inside then
			return {
				side = "S",
				u0 = x0,
				u1 = x1,
				at = z1,
				h = h,
				group = group,
				fadeWith = fadeWith,
			}
		end
		return { side = "N", u0 = x0, u1 = x1, at = z0, h = h, group = group, fadeWith = fadeWith }
	end
	if west == inside then
		return { side = "E", u0 = z0, u1 = z1, at = x1, h = h, group = group, fadeWith = fadeWith }
	end
	return { side = "W", u0 = z0, u1 = z1, at = x0, h = h, group = group, fadeWith = fadeWith }
end

return ArtKit
