--!strict
-- Pure model kit. NO Roblox types in here (Lune can run it): a model is a list of part specs made of
-- plain numbers and strings. Models/Build.luau turns a spec list into real Parts, the preview and
-- the tests read the very same numbers.
--
-- Model space: origin on the ground in the middle of the footprint, +Y up, the FRONT of the thing
-- faces -Z (like a Roblox part's front). Rotations are Euler XYZ in radians = CFrame.Angles(rx, ry, rz).
--
-- kinds:  block / wedge = size (sx, sy, sz); the wedge is tall at +Z and slopes down to -Z
--         ball = diameter sx;  cyl = an UPRIGHT cylinder, diameter sx, height sy

local Kit = {}

export type V3 = { x: number, y: number, z: number }

export type Spec = {
	name: string,
	kind: string, -- "block" | "wedge" | "ball" | "cyl"
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	rx: number,
	ry: number,
	rz: number,
	color: string,
	mat: string, -- Enum.Material name
	neon: boolean,
	collide: boolean,
	shadow: boolean,
	alpha: number,
	text: string?, -- painted on the Front face
	textColor: string?,
}

export type Opts = {
	mat: string?,
	neon: boolean?,
	collide: boolean?,
	shadow: boolean?,
	alpha: number?,
	rot: V3?,
	text: string?,
	textColor: string?,
}

-- What a model's spec() takes. Everything is optional.
export type Params = {
	style: string?, -- "toy" | "tiki" | "basalt" (see Styles)
	v: number?, -- 1..1000 variant number: picks little differences, same number = same model
	accent: string?, -- hex glow colour (gates take the zone colour)
	ground: string?, -- hex main colour (gates take the zone ground colour)
	text: string?, -- sign text
}

export type Model = {
	name: string,
	style: string,
	parts: { Spec },
	anchors: { [string]: V3 }, -- named spots the wiring code can hang prompts / signs / emitters on
	-- footprint half sizes on the ground (x, z), used for placement
	halfX: number,
	halfZ: number,
}

function Kit.v3(x: number, y: number, z: number): V3
	return { x = x, y = y, z = z }
end

function Kit.new(name: string, style: string, halfX: number, halfZ: number): Model
	return { name = name, style = style, parts = {}, anchors = {}, halfX = halfX, halfZ = halfZ }
end

local function add(
	m: Model,
	kind: string,
	name: string,
	p: V3,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	o: Opts?
): Spec
	local opts: Opts = o or {}
	local rot = opts.rot
	local s: Spec = {
		name = name,
		kind = kind,
		x = p.x,
		y = p.y,
		z = p.z,
		sx = sx,
		sy = sy,
		sz = sz,
		rx = if rot then rot.x else 0,
		ry = if rot then rot.y else 0,
		rz = if rot then rot.z else 0,
		color = color,
		mat = opts.mat or "SmoothPlastic",
		neon = opts.neon == true,
		collide = opts.collide == true,
		shadow = opts.shadow == true,
		alpha = opts.alpha or 0,
		text = opts.text,
		textColor = opts.textColor,
	}
	if s.neon then
		s.mat = "Neon"
	end
	table.insert(m.parts, s)
	return s
end

function Kit.block(
	m: Model,
	name: string,
	p: V3,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	o: Opts?
)
	return add(m, "block", name, p, sx, sy, sz, color, o)
end

function Kit.wedge(
	m: Model,
	name: string,
	p: V3,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	o: Opts?
)
	return add(m, "wedge", name, p, sx, sy, sz, color, o)
end

function Kit.ball(m: Model, name: string, p: V3, d: number, color: string, o: Opts?)
	return add(m, "ball", name, p, d, d, d, color, o)
end

-- Upright cylinder centred on p.
function Kit.cyl(m: Model, name: string, p: V3, d: number, h: number, color: string, o: Opts?)
	return add(m, "cyl", name, p, d, h, d, color, o)
end

-- Cylinder resting on the ground (or on `baseY`): p is the centre of its bottom face.
function Kit.post(
	m: Model,
	name: string,
	x: number,
	baseY: number,
	z: number,
	d: number,
	h: number,
	color: string,
	o: Opts?
)
	return add(m, "cyl", name, Kit.v3(x, baseY + h / 2, z), d, h, d, color, o)
end

-- ===== rotation helpers (3x3 matrices stored as 9 numbers, row major) =====

type Mat = { number }

local function mul(a: Mat, b: Mat): Mat
	local out: Mat = {}
	for r = 0, 2 do
		for c = 0, 2 do
			local sum = 0
			for k = 0, 2 do
				sum += a[r * 3 + k + 1] * b[k * 3 + c + 1]
			end
			out[r * 3 + c + 1] = sum
		end
	end
	return out
end

local function rotZ(a: number): Mat
	local c, s = math.cos(a), math.sin(a)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end

-- Matrix -> Euler XYZ (matrix = Rx * Ry * Rz), the order CFrame.Angles uses.
local function toEuler(r: Mat): V3
	local sb = math.clamp(r[3], -1, 1)
	local b = math.asin(sb)
	if math.abs(sb) > 0.99999 then
		return Kit.v3(math.atan2(r[8], r[5]), b, 0)
	end
	return Kit.v3(math.atan2(-r[6], r[9]), b, math.atan2(-r[2], r[1]))
end

-- Euler that turns local -Z towards `dir` (like CFrame.lookAt), with world up as the up hint.
function Kit.lookEuler(dir: V3, rollZ: number?): V3
	local len = math.sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z)
	local zx, zy, zz = -dir.x / len, -dir.y / len, -dir.z / len -- local +Z axis in world
	-- x axis = up cross z, with up = (0, 1, 0)
	local xx, xy, xz = zz, 0, -zx
	local xl = math.sqrt(xx * xx + xz * xz)
	if xl < 1e-6 then
		xx, xy, xz = 1, 0, 0
	else
		xx, xz = xx / xl, xz / xl
	end
	-- y axis = z cross x
	local yx, yy, yz = zy * xz - zz * xy, zz * xx - zx * xz, zx * xy - zy * xx
	local m: Mat = { xx, yx, zx, xy, yy, zy, xz, yz, zz }
	if rollZ and rollZ ~= 0 then
		m = mul(m, rotZ(rollZ))
	end
	return toEuler(m)
end

-- Euler that turns the local +Y axis (a cylinder's long side) towards `dir`.
function Kit.upEuler(dir: V3): V3
	local len = math.sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z)
	local dx, dy, dz = dir.x / len, dir.y / len, dir.z / len
	local tilt = math.acos(math.clamp(dy, -1, 1))
	local sin = math.sqrt(dx * dx + dz * dz)
	if sin < 1e-6 then
		return Kit.v3(0, 0, if dy < 0 then math.pi else 0)
	end
	-- Ry(a) * Rz(tilt): local Y -> (-sin*cos a, cos t, sin*sin a)
	return Kit.v3(0, math.atan2(dz, -dx), tilt)
end

-- Euler XYZ -> matrix (Rx * Ry * Rz, like CFrame.Angles).
local function fromEuler(e: V3): Mat
	local ca, sa = math.cos(e.x), math.sin(e.x)
	local cb, sb = math.cos(e.y), math.sin(e.y)
	local cc, sc = math.cos(e.z), math.sin(e.z)
	return {
		cb * cc,
		-cb * sc,
		sb,
		ca * sc + sa * sb * cc,
		ca * cc - sa * sb * sc,
		-sa * cb,
		sa * sc - ca * sb * cc,
		sa * cc + ca * sb * sc,
		ca * cb,
	}
end

-- Turn the vector p by the Euler rotation e (like CFrame.Angles(e.x, e.y, e.z) * p).
function Kit.turn(e: V3, p: V3): V3
	local r = fromEuler(e)
	return Kit.v3(
		r[1] * p.x + r[2] * p.y + r[3] * p.z,
		r[4] * p.x + r[5] * p.y + r[6] * p.z,
		r[7] * p.x + r[8] * p.y + r[9] * p.z
	)
end

-- The Euler rotation of "first turn by `inner`, then by `outer`" (CFrame.Angles(outer) *
-- CFrame.Angles(inner)): puts a part that is rotated inside another part's frame into model space.
function Kit.compose(outer: V3, inner: V3): V3
	return toEuler(mul(fromEuler(outer), fromEuler(inner)))
end

local function withRot(o: Opts?, rot: V3): Opts
	local out: Opts = {}
	if o then
		out.mat, out.neon, out.collide, out.shadow = o.mat, o.neon, o.collide, o.shadow
		out.alpha, out.text, out.textColor = o.alpha, o.text, o.textColor
	end
	out.rot = rot
	return out
end

-- Round stick from a to b (a cylinder, a little longer than the gap so joints overlap).
function Kit.pole(m: Model, name: string, a: V3, b: V3, thickness: number, color: string, o: Opts?)
	local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	local opts = withRot(o, Kit.upEuler(Kit.v3(dx, dy, dz)))
	return add(
		m,
		"cyl",
		name,
		Kit.v3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2),
		thickness,
		len + 0.15,
		thickness,
		color,
		opts
	)
end

-- A flat leaf: a wedge starting at `base`, pointing along `dir`, `len` long, `wide` wide, thin `thick`.
-- Wide at the base, pointed at the tip, lying flat (like the fern fronds).
function Kit.leaf(
	m: Model,
	name: string,
	base: V3,
	dir: V3,
	len: number,
	wide: number,
	thick: number,
	color: string,
	o: Opts?
)
	local dl = math.sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z)
	local ux, uy, uz = dir.x / dl, dir.y / dl, dir.z / dl
	local opts = withRot(o, Kit.lookEuler(dir, math.pi / 2))
	return add(
		m,
		"wedge",
		name,
		Kit.v3(base.x + ux * len / 2, base.y + uy * len / 2, base.z + uz * len / 2),
		thick,
		wide,
		len,
		color,
		opts
	)
end

-- Two wedges that make a gable roof: width w (x), depth d (z), height h, resting on baseY.
function Kit.gable(
	m: Model,
	name: string,
	cx: number,
	baseY: number,
	cz: number,
	w: number,
	d: number,
	h: number,
	color: string,
	o: Opts?
)
	Kit.wedge(
		m,
		name,
		Kit.v3(cx - w / 4, baseY + h / 2, cz),
		d,
		h,
		w / 2 + 0.02,
		color,
		withRot(o, Kit.v3(0, math.pi / 2, 0))
	)
	Kit.wedge(
		m,
		name,
		Kit.v3(cx + w / 4, baseY + h / 2, cz),
		d,
		h,
		w / 2 + 0.02,
		color,
		withRot(o, Kit.v3(0, -math.pi / 2, 0))
	)
end

function Kit.anchor(m: Model, name: string, p: V3)
	m.anchors[name] = p
end

-- ===== measuring (tests + placement) =====

export type Bounds = {
	minX: number,
	maxX: number,
	minY: number,
	maxY: number,
	minZ: number,
	maxZ: number,
}

-- Axis-aligned box around the part after its rotation (corner box, so slightly generous).
function Kit.partBounds(s: Spec): Bounds
	local hx, hy, hz = s.sx / 2, s.sy / 2, s.sz / 2
	if s.kind == "ball" then
		hx, hy, hz = s.sx / 2, s.sx / 2, s.sx / 2
	elseif s.kind == "cyl" then
		hx, hy, hz = s.sx / 2, s.sy / 2, s.sx / 2
	end
	local a, b, c = s.rx, s.ry, s.rz
	local ca, sa, cb, sb, cc, sc =
		math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
	-- rows of Rx*Ry*Rz
	local r = {
		{ cb * cc, -cb * sc, sb },
		{ ca * sc + sa * sb * cc, ca * cc - sa * sb * sc, -sa * cb },
		{ sa * sc - ca * sb * cc, sa * cc + ca * sb * sc, ca * cb },
	}
	local ex = math.abs(r[1][1]) * hx + math.abs(r[1][2]) * hy + math.abs(r[1][3]) * hz
	local ey = math.abs(r[2][1]) * hx + math.abs(r[2][2]) * hy + math.abs(r[2][3]) * hz
	local ez = math.abs(r[3][1]) * hx + math.abs(r[3][2]) * hy + math.abs(r[3][3]) * hz
	return {
		minX = s.x - ex,
		maxX = s.x + ex,
		minY = s.y - ey,
		maxY = s.y + ey,
		minZ = s.z - ez,
		maxZ = s.z + ez,
	}
end

function Kit.bounds(m: Model): Bounds
	local out: Bounds = {
		minX = math.huge,
		maxX = -math.huge,
		minY = math.huge,
		maxY = -math.huge,
		minZ = math.huge,
		maxZ = -math.huge,
	}
	for _, s in m.parts do
		local b = Kit.partBounds(s)
		out.minX = math.min(out.minX, b.minX)
		out.maxX = math.max(out.maxX, b.maxX)
		out.minY = math.min(out.minY, b.minY)
		out.maxY = math.max(out.maxY, b.maxY)
		out.minZ = math.min(out.minZ, b.minZ)
		out.maxZ = math.max(out.maxZ, b.maxZ)
	end
	return out
end

-- The variant number every spec uses: a whole number 1..1000. Anything else (nil, 12.5, 0, -3,
-- 5000, NaN) is turned into one, so a list pick can never land between two entries and return nil.
function Kit.variant(v: number?): number
	if v == nil or v ~= v then
		return 1
	end
	return math.clamp(math.floor(v), 1, 1000)
end

-- Tiny deterministic pick from a 1..1000 variant number (no Random object needed).
function Kit.pick<T>(list: { T }, v: number, salt: number?): T
	local i = math.floor(Kit.variant(v) + math.floor(salt or 0))
	return list[(i % #list) + 1]
end

-- 0..1 from a variant number and a salt (same inputs, same output, on every server).
function Kit.unit(v: number, salt: number): number
	local x = math.sin(v * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end

return Kit
