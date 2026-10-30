--!strict
-- The three fighter looks (Runner, Courier, Spark) as plain data, so Lune can check them and the server
-- can build them. Nothing here touches Roblox: sizes and offsets are plain numbers, colors are hex text.
--
-- Offsets are written in the preview's convention (the figure faces +Z, +X is its left) and measured from
-- the named R15 part's centre, except that Head and UpperTorso items are measured from the preview's neck
-- and waist, so ORIGIN_Y is taken off first. The builder flips to Roblox's -Z facing and applies UNIT.

local Looks = {}

export type Shape = "Block" | "Ball" | "Cylinder"

export type PartDef = {
	on: string, -- the R15 part it is welded to
	shape: Shape, -- Ball is a sphere mesh (may be squashed), Cylinder runs along X before `rot`
	role: string, -- a key of the look's palette; "glow" parts are Neon
	size: { number },
	pos: { number },
	rot: { number }?, -- degrees about X, Y, Z
	skipBot: boolean?, -- left off bots (their chest wears the target disc)
}

export type LookDef = {
	name: string,
	blurb: string,
	headScale: number, -- Humanoid HeadScale: the big, readable head
	hideHead: boolean?, -- the Head part itself is made invisible (a built head replaces it)
	palette: { [string]: string },
	parts: { PartDef },
}

-- Studs of preview units per R15 stud, by part. Head and torso were drawn bigger than R15's.
Looks.UNIT = { Head = 0.9, UpperTorso = 1.1, LowerTorso = 1.0 } :: { [string]: number }
Looks.ORIGIN_Y = { Head = 0.85, UpperTorso = 0.85 } :: { [string]: number }

-- Every R15 part a look may attach to.
Looks.R15_PARTS = {
	Head = true,
	UpperTorso = true,
	LowerTorso = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
} :: { [string]: boolean }

-- The body part colors every look sets (palette roles).
Looks.BODY_ROLES = {
	Head = "head",
	UpperTorso = "body",
	LowerTorso = "legs",
	RightUpperArm = "body",
	RightLowerArm = "body",
	LeftUpperArm = "body",
	LeftLowerArm = "body",
	RightHand = "glove",
	LeftHand = "glove",
	RightUpperLeg = "legs",
	RightLowerLeg = "legs",
	LeftUpperLeg = "legs",
	LeftLowerLeg = "legs",
	RightFoot = "foot",
	LeftFoot = "foot",
} :: { [string]: string }

-- ===== helpers =====

local function block(
	on: string,
	role: string,
	size: { number },
	pos: { number },
	rot: { number }?,
	skipBot: boolean?
): PartDef
	return {
		on = on,
		shape = "Block",
		role = role,
		size = size,
		pos = pos,
		rot = rot,
		skipBot = skipBot,
	}
end

local function ball(
	on: string,
	role: string,
	size: { number },
	pos: { number },
	skipBot: boolean?
): PartDef
	return { on = on, shape = "Ball", role = role, size = size, pos = pos, skipBot = skipBot }
end

-- A cylinder standing upright (Y axis) or lying along X.
local function cylUp(
	on: string,
	role: string,
	height: number,
	diameter: number,
	pos: { number }
): PartDef
	return {
		on = on,
		shape = "Cylinder",
		role = role,
		size = { height, diameter, diameter },
		pos = pos,
		rot = { 0, 0, 90 },
	}
end

local function cylX(
	on: string,
	role: string,
	length: number,
	diameter: number,
	pos: { number }
): PartDef
	return {
		on = on,
		shape = "Cylinder",
		role = role,
		size = { length, diameter, diameter },
		pos = pos,
	}
end

-- A stepped spike (three shrinking blocks) leaning `tiltDeg` about Z from base position (x, y, z).
local function spike(
	on: string,
	role: string,
	x: number,
	y: number,
	z: number,
	tiltDeg: number,
	width: number
): { PartDef }
	local out = {}
	local tilt = math.rad(tiltDeg)
	local steps = { { 0.17, 1.0 }, { 0.5, 0.62 }, { 0.84, 0.3 } }
	for _, step in steps do
		local along, scale = step[1], step[2]
		local h = 0.4
		table.insert(
			out,
			block(
				on,
				role,
				{ width * scale, h, width * scale },
				{ x - math.sin(tilt) * along * 1.15, y + math.cos(tilt) * along * 1.15, z },
				{ 0, 0, tiltDeg }
			)
		)
	end
	return out
end

local function append(list: { PartDef }, more: { PartDef })
	for _, p in more do
		table.insert(list, p)
	end
end

-- ===== A: Runner =====

local function runner(): LookDef
	local p: { PartDef } = {
		-- helmet
		ball("Head", "navy", { 1.96, 1.88, 2.04 }, { 0, 0.88, 0 }),
		block("Head", "ink", { 1.48, 0.52, 0.3 }, { 0, 0.92, 0.9 }),
		block("Head", "glow", { 1.28, 0.3, 0.3 }, { 0, 0.92, 1.0 }),
		block("Head", "white", { 0.78, 0.3, 0.3 }, { 0, 0.4, 0.8 }),
		block("Head", "ink", { 0.08, 0.2, 0.06 }, { -0.22, 0.4, 0.97 }),
		block("Head", "ink", { 0.08, 0.2, 0.06 }, { 0, 0.4, 0.97 }),
		block("Head", "ink", { 0.08, 0.2, 0.06 }, { 0.22, 0.4, 0.97 }),
		ball("Head", "coral", { 0.25, 1.12, 1.82 }, { 0, 1.78, -0.12 }),
		ball("Head", "white", { 0.27, 0.59, 1.05 }, { 0, 1.58, -0.05 }),
		cylX("Head", "navy2", 0.24, 0.8, { -0.98, 0.85, 0 }),
		cylX("Head", "navy2", 0.24, 0.8, { 0.98, 0.85, 0 }),
		cylX("Head", "white", 0.1, 0.44, { -1.1, 0.85, 0 }),
		cylX("Head", "white", 0.1, 0.44, { 1.1, 0.85, 0 }),
		block("Head", "white", { 0.16, 0.5, 0.6 }, { -0.84, 0.42, 0.4 }),
		block("Head", "white", { 0.16, 0.5, 0.6 }, { 0.84, 0.42, 0.4 }),
		-- big round white shoulders
		ball("UpperTorso", "white", { 1.32, 0.95, 1.32 }, { -1.28, 1.52, 0 }),
		ball("UpperTorso", "white", { 1.32, 0.95, 1.32 }, { 1.28, 1.52, 0 }),
		-- chest
		block("UpperTorso", "navy2", { 0.18, 1.5, 0.1 }, { -0.52, 0.85, 0.54 }, nil, true),
		block("UpperTorso", "navy2", { 0.18, 1.5, 0.1 }, { 0.52, 0.85, 0.54 }, nil, true),
		block("UpperTorso", "glow", { 1.3, 0.12, 0.08 }, { 0, 1.12, 0.55 }, nil, true),
		block("UpperTorso", "white", { 0.9, 0.55, 0.06 }, { 0, 0.45, 0.55 }, nil, true),
		block("UpperTorso", "coral", { 0.16, 0.16, 0.06 }, { -0.32, 0.68, 0.59 }, nil, true),
		block("UpperTorso", "coral", { 0.16, 0.16, 0.06 }, { 0.32, 0.68, 0.59 }, nil, true),
		-- back battery
		block("UpperTorso", "steel", { 1.0, 1.0, 0.42 }, { 0, 0.95, -0.74 }),
		block("UpperTorso", "glow", { 0.1, 0.7, 0.05 }, { -0.28, 0.95, -0.97 }),
		block("UpperTorso", "navy2", { 1.2, 0.14, 0.5 }, { 0, 1.5, -0.72 }),
		-- belt and pads
		block("LowerTorso", "coral", { 0.38, 0.28, 0.08 }, { 0, 0.05, 0.58 }, nil, true),
		block("LowerTorso", "navy2", { 0.4, 0.34, 0.3 }, { -0.78, 0, 0.28 }),
		block("LowerTorso", "navy2", { 0.4, 0.34, 0.3 }, { 0.78, 0, 0.28 }),
		cylUp("RightUpperArm", "coral", 0.16, 0.66, { 0, 0.15, 0 }),
		cylUp("LeftUpperArm", "coral", 0.16, 0.66, { 0, 0.15, 0 }),
		block("RightLowerArm", "navy2", { 0.5, 0.34, 0.5 }, { 0, 0.4, 0 }),
		block("LeftLowerArm", "navy2", { 0.5, 0.34, 0.5 }, { 0, 0.4, 0 }),
		block("RightLowerLeg", "white", { 0.5, 0.5, 0.12 }, { 0, 0.1, 0.3 }),
		block("LeftLowerLeg", "white", { 0.5, 0.5, 0.12 }, { 0, 0.1, 0.3 }),
		block("RightFoot", "ink", { 0.66, 0.1, 1.02 }, { 0, -0.1, 0.1 }),
		block("LeftFoot", "ink", { 0.66, 0.1, 1.02 }, { 0, -0.1, 0.1 }),
	}
	return {
		name = "Runner",
		blurb = "Visor helmet, top fin, round white shoulders.",
		headScale = 1.5,
		palette = {
			head = "#14243A",
			body = "#14243A",
			legs = "#14243A",
			glove = "#F3F1EA",
			foot = "#F3F1EA",
			navy = "#14243A",
			navy2 = "#24385A",
			white = "#F3F1EA",
			coral = "#F15B64",
			glow = "#36D9E8",
			ink = "#0B121C",
			steel = "#3A5A80",
		},
		parts = p,
	}
end

-- ===== B: Courier =====

local function courier(): LookDef
	local p: { PartDef } = {
		-- beanie, headphones, face
		ball("Head", "green", { 2.1, 1.25, 2.1 }, { 0, 1.32, -0.02 }),
		cylUp("Head", "green2", 0.24, 2.12, { 0, 1.15, -0.02 }),
		ball("Head", "green2", { 0.44, 0.44, 0.44 }, { 0, 2.02, 0 }),
		cylX("Head", "navy", 0.34, 0.92, { -1.02, 0.82, 0 }),
		cylX("Head", "navy", 0.34, 0.92, { 1.02, 0.82, 0 }),
		cylX("Head", "glow", 0.06, 0.7, { -1.24, 0.82, 0 }),
		cylX("Head", "glow", 0.06, 0.7, { 1.24, 0.82, 0 }),
		ball("Head", "white", { 0.3, 0.37, 0.21 }, { -0.32, 0.86, 0.9 }),
		ball("Head", "white", { 0.3, 0.37, 0.21 }, { 0.32, 0.86, 0.9 }),
		ball("Head", "ink", { 0.18, 0.23, 0.13 }, { -0.32, 0.86, 0.98 }),
		ball("Head", "ink", { 0.18, 0.23, 0.13 }, { 0.32, 0.86, 0.98 }),
		block("Head", "ink", { 0.34, 0.07, 0.07 }, { -0.32, 1.1, 0.93 }, { 0, 0, 9 }),
		block("Head", "ink", { 0.34, 0.07, 0.07 }, { 0.32, 1.1, 0.93 }, { 0, 0, -9 }),
		ball("Head", "skin2", { 0.26, 0.26, 0.26 }, { 0, 0.66, 0.97 }),
		block("Head", "lip", { 0.34, 0.06, 0.06 }, { 0, 0.42, 0.93 }),
		block("Head", "ink", { 0.05, 0.05, 0.95 }, { -0.72, 0.5, 0.6 }, { 0, 31, 0 }),
		-- hoodie
		block("UpperTorso", "hoodie2", { 1.35, 0.4, 1.15 }, { 0, 1.72, 0 }),
		ball("UpperTorso", "hoodie2", { 1.6, 1.12, 1.2 }, { 0, 1.68, -0.58 }),
		block("UpperTorso", "hoodie2", { 1.1, 0.5, 0.1 }, { 0, 0.28, 0.55 }, nil, true),
		block("UpperTorso", "navy", { 0.14, 1.5, 0.08 }, { -0.52, 0.95, 0.56 }, nil, true),
		block("UpperTorso", "navy", { 0.14, 1.5, 0.08 }, { 0.52, 0.95, 0.56 }, nil, true),
		block("UpperTorso", "coral", { 0.4, 0.26, 0.06 }, { 0.55, 1.1, 0.56 }, nil, true),
		-- tall backpack
		block("UpperTorso", "navy", { 1.45, 1.6, 0.62 }, { 0, 0.95, -0.82 }),
		block("UpperTorso", "navy2", { 1.5, 0.28, 0.72 }, { 0, 1.78, -0.82 }),
		block("UpperTorso", "navy2", { 0.3, 0.78, 0.5 }, { -0.84, 0.6, -0.82 }),
		block("UpperTorso", "navy2", { 0.3, 0.78, 0.5 }, { 0.84, 0.6, -0.82 }),
		block("UpperTorso", "glow", { 1.2, 0.2, 0.06 }, { 0, 1.45, -1.14 }),
		block("UpperTorso", "coral", { 0.3, 0.2, 0.08 }, { 0, 1.78, -1.2 }),
		ball("UpperTorso", "coral", { 0.24, 0.24, 0.24 }, { 0.5, 0.2, -1.2 }),
		-- belt, sleeve cuffs, cargo pockets, shoes
		block("LowerTorso", "navy", { 2.1, 0.2, 1.1 }, { 0, 0.05, 0 }),
		cylUp("RightLowerArm", "navy", 0.2, 0.58, { 0, -0.35, 0 }),
		cylUp("LeftLowerArm", "navy", 0.2, 0.58, { 0, -0.35, 0 }),
		block("RightUpperLeg", "navy2", { 0.14, 0.5, 0.42 }, { -0.34, -0.1, 0 }),
		block("LeftUpperLeg", "navy2", { 0.14, 0.5, 0.42 }, { 0.34, -0.1, 0 }),
		block("RightFoot", "ink", { 0.66, 0.1, 1.02 }, { 0, -0.1, 0.1 }),
		block("LeftFoot", "ink", { 0.66, 0.1, 1.02 }, { 0, -0.1, 0.1 }),
	}
	return {
		name = "Courier",
		blurb = "Headphones, green beanie, tall backpack.",
		headScale = 1.5,
		palette = {
			head = "#E0B08A",
			body = "#E8E4D8",
			legs = "#14243A",
			glove = "#E8E4D8",
			foot = "#36D9E8",
			navy = "#14243A",
			navy2 = "#24385A",
			white = "#F3F1EA",
			coral = "#F15B64",
			glow = "#36D9E8",
			ink = "#0B121C",
			green = "#718D57",
			green2 = "#5D7547",
			hoodie2 = "#D9D4C6",
			skin2 = "#C4906C",
			lip = "#8A3F3A",
		},
		parts = p,
	}
end

-- ===== C: Spark =====

local function spark(): LookDef
	local p: { PartDef } = {
		-- square head
		block("Head", "steel", { 1.7, 1.5, 1.5 }, { 0, 0.82, 0 }),
		block("Head", "steel2", { 1.5, 0.12, 0.22 }, { 0, 1.14, 0.8 }),
		block("Head", "glow", { 1.3, 0.24, 0.1 }, { 0, 0.92, 0.78 }),
		block("Head", "ink", { 1.0, 0.32, 0.08 }, { 0, 0.42, 0.78 }),
		block("Head", "steel2", { 0.8, 0.04, 0.05 }, { 0, 0.34, 0.83 }),
		block("Head", "steel2", { 0.8, 0.04, 0.05 }, { 0, 0.48, 0.83 }),
		block("Head", "coral", { 0.22, 1.0, 0.55 }, { -1.0, 1.55, -0.05 }, { 0, 0, 22 }),
		block("Head", "coral", { 0.22, 1.0, 0.55 }, { 1.0, 1.55, -0.05 }, { 0, 0, -22 }),
		block("Head", "coral2", { 0.14, 0.55, 0.4 }, { -0.72, 1.62, -0.05 }, { 0, 0, 11 }),
		block("Head", "coral2", { 0.14, 0.55, 0.4 }, { 0.72, 1.62, -0.05 }, { 0, 0, -11 }),
		cylX("Head", "navy", 0.18, 0.6, { -0.9, 0.85, 0 }),
		cylX("Head", "navy", 0.18, 0.6, { 0.9, 0.85, 0 }),
		cylUp("Head", "ink", 0.7, 0.1, { 0.5, 1.85, 0 }),
		ball("Head", "coral", { 0.16, 0.16, 0.16 }, { 0.5, 2.18, 0 }),
		-- pointy coral shoulders on round bases
		cylUp("UpperTorso", "steel2", 0.2, 0.8, { -1.3, 1.45, 0 }),
		cylUp("UpperTorso", "steel2", 0.2, 0.8, { 1.3, 1.45, 0 }),
		-- chest core
		block("UpperTorso", "navy", { 1.1, 0.9, 0.08 }, { 0, 0.95, 0.55 }, nil, true),
		block("UpperTorso", "ink", { 0.08, 0.5, 0.05 }, { -0.26, 0.95, 0.6 }, nil, true),
		block("UpperTorso", "ink", { 0.08, 0.5, 0.05 }, { 0, 0.95, 0.6 }, nil, true),
		block("UpperTorso", "ink", { 0.08, 0.5, 0.05 }, { 0.26, 0.95, 0.6 }, nil, true),
		ball("UpperTorso", "coral", { 0.18, 0.18, 0.11 }, { -0.42, 1.3, 0.6 }, true),
		ball("UpperTorso", "coral", { 0.18, 0.18, 0.11 }, { 0.42, 1.3, 0.6 }, true),
		block("UpperTorso", "steel2", { 1.7, 0.14, 0.08 }, { 0, 1.52, 0.54 }, nil, true),
		-- back exhausts
		cylUp("UpperTorso", "steel2", 0.7, 0.4, { -0.4, 1.0, -0.72 }),
		cylUp("UpperTorso", "steel2", 0.7, 0.4, { 0.4, 1.0, -0.72 }),
		cylUp("UpperTorso", "coral", 0.12, 0.32, { -0.4, 1.4, -0.72 }),
		cylUp("UpperTorso", "coral", 0.12, 0.32, { 0.4, 1.4, -0.72 }),
		block("UpperTorso", "steel2", { 1.0, 0.14, 0.4 }, { 0, 1.55, -0.62 }),
		-- belt glow, armor
		block("LowerTorso", "glow", { 2.1, 0.1, 1.05 }, { 0, 0.1, 0 }),
		block("RightLowerArm", "steel2", { 0.55, 0.6, 0.55 }, { 0, 0.1, 0 }),
		block("LeftLowerArm", "steel2", { 0.55, 0.6, 0.55 }, { 0, 0.1, 0 }),
		block("RightUpperLeg", "steel2", { 0.7, 0.55, 0.62 }, { 0, 0.05, 0 }),
		block("LeftUpperLeg", "steel2", { 0.7, 0.55, 0.62 }, { 0, 0.05, 0 }),
		block("RightLowerLeg", "coral", { 0.2, 0.2, 0.3 }, { 0, 0.4, 0.34 }),
		block("LeftLowerLeg", "coral", { 0.2, 0.2, 0.3 }, { 0, 0.4, 0.34 }),
		block("RightFoot", "coral", { 0.62, 0.2, 0.2 }, { 0, 0, 0.62 }),
		block("LeftFoot", "coral", { 0.62, 0.2, 0.2 }, { 0, 0, 0.62 }),
		block("RightFoot", "ink", { 0.66, 0.1, 1.02 }, { 0, -0.1, 0.1 }),
		block("LeftFoot", "ink", { 0.66, 0.1, 1.02 }, { 0, -0.1, 0.1 }),
	}
	append(p, spike("UpperTorso", "coral", -1.4, 1.65, 0, 54, 0.7))
	append(p, spike("UpperTorso", "coral", 1.4, 1.65, 0, -54, 0.7))
	return {
		name = "Spark",
		blurb = "Square head, coral fins, pointy shoulders.",
		headScale = 1.5,
		hideHead = true,
		palette = {
			head = "#3A5A80",
			body = "#3A5A80",
			legs = "#0B121C",
			glove = "#F15B64",
			foot = "#F3F1EA",
			navy = "#14243A",
			steel = "#3A5A80",
			steel2 = "#2B4260",
			coral = "#F15B64",
			coral2 = "#C4474F",
			glow = "#36D9E8",
			ink = "#0B121C",
		},
		parts = p,
	}
end

Looks.NAMES = { "Runner", "Courier", "Spark" }

local built: { [string]: LookDef } = {}

-- A look by name, or the first look when the name is unknown (so a bad value can never leave a body bare).
function Looks.get(name: string?): LookDef
	local key = if name ~= nil and (name == "Runner" or name == "Courier" or name == "Spark")
		then name
		else "Runner"
	local cached = built[key]
	if cached ~= nil then
		return cached
	end
	local def = if key == "Courier" then courier() elseif key == "Spark" then spark() else runner()
	built[key] = def
	return def
end

-- The parts a fighter wears: bots leave off what would cover their chest target.
function Looks.partsFor(def: LookDef, isBot: boolean): { PartDef }
	if not isBot then
		return def.parts
	end
	local out = {}
	for _, p in def.parts do
		if p.skipBot ~= true then
			table.insert(out, p)
		end
	end
	return out
end

-- The colors a fighter wears: bots take the Crash Dummy body and legs, everything else stays.
function Looks.paletteFor(def: LookDef, bot: { body: string, legs: string }?): { [string]: string }
	local out = {}
	for role, hex in def.palette do
		out[role] = hex
	end
	if bot ~= nil then
		out.body = bot.body
		out.head = bot.body
		out.legs = bot.legs
	end
	return out
end

return Looks
