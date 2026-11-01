--!strict
-- Pure model "kit" (no Roblox types, so Lune can test it): part specs, 3 looks (styles), colour maths.
-- The spec modules (ToolSpecs, BotSpecs, CartSpecs) describe a model as a list of PartSpec; the thin
-- ModelBuilder turns a list into real Parts. Colours are hex strings, sizes/offsets are studs,
-- rotations are degrees (CFrame.Angles order).
--
-- Kinds:  Block {x, y, z}   Cyl {diameter, length, diameter} (axis = Y, roll it with rot)   Ball {d, d, d}
-- Looks:  A "Toy" (bright plastic) | B "Steel" (dark metal + neon trim) | C "Candy" (pastel + glow).
-- carter picks one look; the other two become skins.

local ModelKit = {}

export type Kind = "Block" | "Cyl" | "Ball"
export type Mat = "Wood" | "SmoothPlastic" | "Neon" | "Metal" | "Fabric" | "Glass"

export type PartSpec = {
	name: string,
	kind: Kind,
	size: { number },
	pos: { number },
	rot: { number },
	color: string,
	mat: Mat,
	alpha: number,
}

export type Style = {
	id: string,
	label: string,
	rodMat: Mat, -- poles and handles
	bodyMat: Mat, -- shells and housings
	soft: Mat, -- bristles, straps, rope
	dark: string,
	trim: string,
	straw: { string },
	main: (c: string) -> string, -- turns a tool's catalog colour into this look's body colour
	accent: (c: string) -> string, -- lively bit (rings, vents, badges)
	accentMat: Mat,
}

-- ===== colour maths =====

local function parseHex(hex: string): (number, number, number)
	local r = tonumber(string.sub(hex, 2, 3), 16) or 0
	local g = tonumber(string.sub(hex, 4, 5), 16) or 0
	local b = tonumber(string.sub(hex, 6, 7), 16) or 0
	return r, g, b
end

local function toHex(r: number, g: number, b: number): string
	local function c(v: number): number
		return math.clamp(math.floor(v + 0.5), 0, 255)
	end
	return string.format("#%02X%02X%02X", c(r), c(g), c(b))
end

-- t = 0 gives a, t = 1 gives b.
function ModelKit.mix(a: string, b: string, t: number): string
	local ar, ag, ab = parseHex(a)
	local br, bg, bb = parseHex(b)
	return toHex(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end

function ModelKit.darken(c: string, t: number): string
	return ModelKit.mix(c, "#000000", t)
end

function ModelKit.lighten(c: string, t: number): string
	return ModelKit.mix(c, "#FFFFFF", t)
end

-- ===== the three looks =====

ModelKit.styles = {
	A = {
		id = "A",
		label = "Toy",
		rodMat = "Wood",
		bodyMat = "SmoothPlastic",
		soft = "Fabric",
		dark = "#2B2430",
		trim = "#F4F0E6",
		straw = { "#E0BE78", "#C9A25A" },
		main = function(c: string): string
			return c
		end,
		accent = function(_: string): string
			return "#FFD23F"
		end,
		accentMat = "SmoothPlastic",
	},
	B = {
		id = "B",
		label = "Steel",
		rodMat = "Metal",
		bodyMat = "Metal",
		soft = "Fabric",
		dark = "#222836",
		trim = "#C7CEDB",
		straw = { "#8C93A3", "#6D7485" },
		main = function(c: string): string
			return ModelKit.mix(c, "#5A6378", 0.6)
		end,
		accent = function(c: string): string
			return ModelKit.lighten(c, 0.2)
		end,
		accentMat = "Neon",
	},
	C = {
		id = "C",
		label = "Candy",
		rodMat = "SmoothPlastic",
		bodyMat = "SmoothPlastic",
		soft = "Fabric",
		dark = "#8A4FB0",
		trim = "#FFE0F0",
		straw = { "#FF9BCB", "#FFD27A" },
		main = function(c: string): string
			return ModelKit.mix(c, "#FFFFFF", 0.28)
		end,
		accent = function(_: string): string
			return "#FF5FB4"
		end,
		accentMat = "Neon",
	},
} :: { [string]: Style }

ModelKit.styleOrder = { "A", "B", "C" } :: { string }

-- Unknown look -> the Toy look.
function ModelKit.style(id: string?): Style
	return ModelKit.styles[id or "A"] or ModelKit.styles.A
end

-- Helper bot colours per look: body, belly, dark, glow. (Bot look = bot shape: A Bumble, B Roller, C Ember.)
function ModelKit.botPalette(look: string): (string, string, string, string)
	if look == "B" then
		return "#7A859C", "#B4BCCB", "#222836", "#7DF0FF"
	elseif look == "C" then
		return "#FF9BCB", "#FFE0F0", "#8A4FB0", "#FF5FB4"
	end
	return "#4FB3E8", "#F4F0E6", "#2B2430", "#7DF0FF"
end

-- Body material of a bot look.
function ModelKit.botBodyMat(look: string): Mat
	return if look == "B" then "Metal" else "SmoothPlastic"
end

-- ===== part makers =====

local function vec(v: { number }?, fallback: number): { number }
	if v == nil then
		return { fallback, fallback, fallback }
	end
	return { v[1], v[2], v[3] }
end

function ModelKit.part(
	name: string,
	kind: Kind,
	size: { number },
	pos: { number },
	color: string,
	mat: Mat,
	rot: { number }?,
	alpha: number?
): PartSpec
	return {
		name = name,
		kind = kind,
		size = vec(size, 1),
		pos = vec(pos, 0),
		rot = vec(rot, 0),
		color = color,
		mat = mat,
		alpha = alpha or 0,
	}
end

function ModelKit.box(
	name: string,
	size: { number },
	pos: { number },
	color: string,
	mat: Mat,
	rot: { number }?,
	alpha: number?
): PartSpec
	return ModelKit.part(name, "Block", size, pos, color, mat, rot, alpha)
end

-- Round disc/rod: axis along Y unless rolled with rot.
function ModelKit.cyl(
	name: string,
	dia: number,
	len: number,
	pos: { number },
	color: string,
	mat: Mat,
	rot: { number }?,
	alpha: number?
): PartSpec
	return ModelKit.part(name, "Cyl", { dia, len, dia }, pos, color, mat, rot, alpha)
end

function ModelKit.ball(
	name: string,
	dia: number,
	pos: { number },
	color: string,
	mat: Mat,
	alpha: number?
): PartSpec
	return ModelKit.part(name, "Ball", { dia, dia, dia }, pos, color, mat, nil, alpha)
end

-- Vertical rod from yTop down to yBot at (x, z).
function ModelKit.rod(
	name: string,
	dia: number,
	yTop: number,
	yBot: number,
	color: string,
	mat: Mat,
	x: number?,
	z: number?
): PartSpec
	return ModelKit.cyl(name, dia, yTop - yBot, { x or 0, (yTop + yBot) / 2, z or 0 }, color, mat)
end

-- ===== checks and numbers =====

export type Bounds = {
	minX: number,
	maxX: number,
	minY: number,
	maxY: number,
	minZ: number,
	maxZ: number,
}

-- Half sizes of the axis-aligned box that holds one part after it is turned (CFrame.Angles order:
-- the matrix is Rx * Ry * Rz, so |R| rows give the reach on each world axis).
function ModelKit.halfExtent(p: PartSpec): (number, number, number)
	local rx, ry, rz = math.rad(p.rot[1]), math.rad(p.rot[2]), math.rad(p.rot[3])
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	-- R = Rx * Ry * Rz
	local m11 = cy * cz
	local m12 = -cy * sz
	local m13 = sy
	local m21 = sx * sy * cz + cx * sz
	local m22 = -sx * sy * sz + cx * cz
	local m23 = -sx * cy
	local m31 = -cx * sy * cz + sx * sz
	local m32 = cx * sy * sz + sx * cz
	local m33 = cx * cy
	local hx, hy, hz = p.size[1] / 2, p.size[2] / 2, p.size[3] / 2
	return math.abs(m11) * hx + math.abs(m12) * hy + math.abs(m13) * hz,
		math.abs(m21) * hx + math.abs(m22) * hy + math.abs(m23) * hz,
		math.abs(m31) * hx + math.abs(m32) * hy + math.abs(m33) * hz
end

-- Box that holds every part (a Cyl's real axis is Y here; the builder rolls it into Roblox's X axis).
function ModelKit.bounds(parts: { PartSpec }): Bounds
	local b: Bounds = {
		minX = math.huge,
		maxX = -math.huge,
		minY = math.huge,
		maxY = -math.huge,
		minZ = math.huge,
		maxZ = -math.huge,
	}
	for _, p in parts do
		local hx, hy, hz = ModelKit.halfExtent(p)
		b.minX = math.min(b.minX, p.pos[1] - hx)
		b.maxX = math.max(b.maxX, p.pos[1] + hx)
		b.minY = math.min(b.minY, p.pos[2] - hy)
		b.maxY = math.max(b.maxY, p.pos[2] + hy)
		b.minZ = math.min(b.minZ, p.pos[3] - hz)
		b.maxZ = math.max(b.maxZ, p.pos[3] + hz)
	end
	return b
end

-- Every colour/material a list uses, as one sorted string (to compare looks).
function ModelKit.signature(parts: { PartSpec }): string
	local seen: { [string]: boolean } = {}
	local list: { string } = {}
	for _, p in parts do
		local key = p.color .. ":" .. p.mat
		if not seen[key] then
			seen[key] = true
			table.insert(list, key)
		end
	end
	table.sort(list)
	return table.concat(list, ",")
end

return ModelKit
