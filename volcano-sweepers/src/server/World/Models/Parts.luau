--!strict
-- Pure part lists for the big landmarks. NO Roblox types in here (Lune can run it and the preview
-- page draws the very same list). A model file fills a List with blocks, wedges, cylinders and balls;
-- ModelBuild turns the list into real Parts.
--
-- Frame: the model origin is the middle of its footprint ON the ground (y = 0 is the ground).
-- Numbers: pos = {x, y, z} centre of the part, size = {x, y, z}, rot = {pitch, yaw, roll} radians,
-- turned in Roblox as CFrame.fromEulerAnglesYXZ(pitch, yaw, roll) (yaw is the outermost turn).
-- Kinds: block, wedge (slope rises to the +Z side: the tall end), cyl (upright, size = {d, h, d}),
-- ball (size = {d, d, d}). Groups: "glow" (a part the world may pulse), "beam" (the lighthouse beam,
-- one group so the world can spin it around List.pivots.beam).

local Parts = {}

export type Vec = { number }

export type Part = {
	kind: string,
	name: string,
	pos: Vec,
	size: Vec,
	rot: Vec,
	color: string,
	material: string,
	transparency: number,
	collide: boolean,
	shadow: boolean,
	group: string?,
}

export type Fx = { kind: string, pos: Vec, radius: number }

export type List = {
	name: string,
	variant: string,
	parts: { Part },
	fx: { Fx },
	pivots: { [string]: Vec },
}

export type Opts = {
	rot: Vec?,
	material: string?,
	transparency: number?,
	collide: boolean?,
	shadow: boolean?,
	group: string?,
}

Parts.TAU = math.pi * 2

-- Only these materials are allowed (each one is an Enum.Material name).
Parts.MATERIALS = {
	SmoothPlastic = true,
	Neon = true,
	Basalt = true,
	Slate = true,
	Rock = true,
	Concrete = true,
	Wood = true,
	WoodPlanks = true,
	Glass = true,
	Sand = true,
	Marble = true,
	Metal = true,
} :: { [string]: boolean }

Parts.FX_KINDS =
	{ smoke = true, embers = true, steam = true, spray = true } :: { [string]: boolean }
Parts.KINDS = { block = true, wedge = true, cyl = true, ball = true } :: { [string]: boolean }

function Parts.new(name: string, variant: string): List
	return { name = name, variant = variant, parts = {}, fx = {}, pivots = {} }
end

local function add(
	list: List,
	kind: string,
	name: string,
	pos: Vec,
	size: Vec,
	color: string,
	o: Opts?
)
	local opts = o or {}
	table.insert(list.parts, {
		kind = kind,
		name = name,
		pos = pos,
		size = size,
		rot = opts.rot or { 0, 0, 0 },
		color = color,
		material = opts.material or "SmoothPlastic",
		transparency = opts.transparency or 0,
		collide = opts.collide == true,
		shadow = opts.shadow ~= false,
		group = opts.group,
	})
end

function Parts.block(list: List, name: string, pos: Vec, size: Vec, color: string, o: Opts?)
	add(list, "block", name, pos, size, color, o)
end

function Parts.wedge(list: List, name: string, pos: Vec, size: Vec, color: string, o: Opts?)
	add(list, "wedge", name, pos, size, color, o)
end

-- Upright cylinder: `pos` is the CENTRE, d = diameter, h = height.
function Parts.cyl(
	list: List,
	name: string,
	pos: Vec,
	d: number,
	h: number,
	color: string,
	o: Opts?
)
	add(list, "cyl", name, pos, { d, h, d }, color, o)
end

function Parts.ball(list: List, name: string, pos: Vec, d: number, color: string, o: Opts?)
	add(list, "ball", name, pos, { d, d, d }, color, o)
end

-- Flat disc lying on the ground-ish: `topY` is its TOP face.
function Parts.disc(
	list: List,
	name: string,
	x: number,
	topY: number,
	z: number,
	d: number,
	h: number,
	color: string,
	o: Opts?
)
	add(list, "cyl", name, { x, topY - h / 2, z }, { d, h, d }, color, o)
end

function Parts.fx(list: List, kind: string, pos: Vec, radius: number)
	table.insert(list.fx, { kind = kind, pos = pos, radius = radius })
end

-- A thin flat plate lying on a straight slope that runs from (r0, y0) down at the bottom to
-- (r1, y1) at the top, at ring angle `angle` (radians, 0 = +X, turning towards +Z). `width` runs
-- along the ring, `thick` is the plate thickness, `lift` pushes the plate out along its normal.
-- `grow` makes the plate a little longer so neighbours overlap.
function Parts.slab(
	list: List,
	name: string,
	r0: number,
	y0: number,
	r1: number,
	y1: number,
	angle: number,
	width: number,
	thick: number,
	color: string,
	lift: number,
	o: Opts?
)
	local dr = r0 - r1 -- horizontal run (positive when the top is nearer the middle)
	local dy = y1 - y0
	local len = math.sqrt(dr * dr + dy * dy) + 1
	local tilt = math.atan2(dy, dr) -- steepness of the slope
	local rm = (r0 + r1) / 2
	local ym = (y0 + y1) / 2
	-- normal of the plate: up and outwards
	local nr = math.sin(tilt)
	local ny = math.cos(tilt)
	local rr = rm + nr * lift
	local yy = ym + ny * lift
	local opts: Opts = {
		rot = { tilt, math.pi / 2 - angle, 0 },
		material = if o then o.material else nil,
		transparency = if o then o.transparency else nil,
		collide = if o then o.collide else nil,
		shadow = if o then o.shadow else nil,
		group = if o then o.group else nil,
	}
	add(
		list,
		"block",
		name,
		{ math.cos(angle) * rr, yy, math.sin(angle) * rr },
		{ width, thick, len },
		color,
		opts
	)
end

-- Same random number every time for the same (seed, i): 0 <= value < 1. Cheap integer hash, so a
-- model looks identical on every server and in the preview.
function Parts.rand(seed: number, i: number): number
	local h = bit32.band(seed * 374761393 + i * 668265263, 0xFFFFFFFF)
	h = bit32.band(bit32.bxor(h, bit32.rshift(h, 13)) * 1274126177, 0xFFFFFFFF)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return (h % 100000) / 100000
end

-- rand in [lo, hi)
function Parts.between(seed: number, i: number, lo: number, hi: number): number
	return lo + Parts.rand(seed, i) * (hi - lo)
end

local function hexToRgb(hex: string): (number, number, number)
	local r = tonumber(string.sub(hex, 2, 3), 16) or 0
	local g = tonumber(string.sub(hex, 4, 5), 16) or 0
	local b = tonumber(string.sub(hex, 6, 7), 16) or 0
	return r, g, b
end

function Parts.lerpHex(a: string, b: string, t: number): string
	local ar, ag, ab = hexToRgb(a)
	local br, bg, bb = hexToRgb(b)
	local function mix(p: number, q: number): number
		return math.clamp(math.floor(p + (q - p) * t + 0.5), 0, 255)
	end
	return string.format("#%02X%02X%02X", mix(ar, br), mix(ag, bg), mix(ab, bb))
end

-- Scale a finished list (every position and size; angles stay). Returns the same list.
function Parts.scale(list: List, k: number): List
	if k == 1 then
		return list
	end
	for _, p in list.parts do
		p.pos = { p.pos[1] * k, p.pos[2] * k, p.pos[3] * k }
		p.size = { p.size[1] * k, p.size[2] * k, p.size[3] * k }
	end
	for _, f in list.fx do
		f.pos = { f.pos[1] * k, f.pos[2] * k, f.pos[3] * k }
		f.radius *= k
	end
	for name, v in list.pivots do
		list.pivots[name] = { v[1] * k, v[2] * k, v[3] * k }
	end
	return list
end

-- Rough bounds: how far from the middle the model reaches and how tall it is.
function Parts.bounds(list: List): (number, number)
	local reach, top = 0, 0
	for _, p in list.parts do
		local half = math.max(p.size[1], p.size[2], p.size[3]) / 2
		reach = math.max(reach, math.sqrt(p.pos[1] ^ 2 + p.pos[3] ^ 2) + half)
		top = math.max(top, p.pos[2] + half)
	end
	return reach, top
end

return Parts
