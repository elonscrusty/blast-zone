--!strict
-- Pure part lists for the helper bots (no Roblox types: Lune tests them).
-- Bot space: origin = middle of the ground under the bot, +Y up, -Z is the way it faces.
-- Three different bots (carter picks one, the others become skins):
--   A "Bumble"  a round hover bot with a propeller and two brush arms
--   B "Roller"  a boxy bot on wheels with a spinning brush roller and a dustbin
--   C "Ember"   a mini volcano on stubby feet with a glowing crater
-- All bots share one level (0..15). The level only changes the trim colour (bronze, silver, gold,
-- volcano), so the part count never changes with level.
-- Parts whose name starts with "Spin" are meant to be turned by the animator (propeller, brush).
-- Parts whose name starts with "Bob" can bob up and down (crater bubbles, antenna bulb).

local ModelKit = require("./ModelKit")

export type PartSpec = ModelKit.PartSpec
export type BotParts = { look: string, level: number, parts: { PartSpec } }

local BotSpecs = {}

BotSpecs.MAX_PARTS = 34
BotSpecs.maxLevel = 15
BotSpecs.looks = { "A", "B", "C" } :: { string }
BotSpecs.names = { A = "Bumble Bot", B = "Roller Bot", C = "Ember Bot" } :: { [string]: string }

local box, cyl, ball = ModelKit.box, ModelKit.cyl, ModelKit.ball

-- Trim colour for a shared bot level.
local TIER_COLORS = { "#CD8A52", "#C9D2DE", "#FFD23F", "#FF6A3D" }
local TIER_NAMES = { "Bronze", "Silver", "Gold", "Volcano" }

function BotSpecs.tier(level: number): number
	local lv = math.clamp(math.floor(level), 0, BotSpecs.maxLevel)
	return math.min(4, lv // 4 + 1)
end

function BotSpecs.tierColor(level: number): string
	return TIER_COLORS[BotSpecs.tier(level)]
end

function BotSpecs.tierName(level: number): string
	return TIER_NAMES[BotSpecs.tier(level)]
end

local function add(list: { PartSpec }, ...: PartSpec)
	for _, p in { ... } do
		table.insert(list, p)
	end
end

-- Body colours per look. The bots do not come from the tool catalog, so each look has its own.
local function palette(look: string): (string, string, string, string)
	-- returns body, belly, dark, glow
	if look == "B" then
		return "#7A859C", "#B4BCCB", "#222836", "#7DF0FF"
	elseif look == "C" then
		return "#FF9BCB", "#FFE0F0", "#8A4FB0", "#FF5FB4"
	end
	return "#4FB3E8", "#F4F0E6", "#2B2430", "#7DF0FF"
end

local function bodyMat(look: string): ModelKit.Mat
	return if look == "B" then "Metal" else "SmoothPlastic"
end

-- A little face on the front (-Z) of something at (0, y, z): dark visor, two glowing eyes.
local function face(list: { PartSpec }, y: number, z: number, w: number, dark: string, glow: string)
	add(
		list,
		box("Visor", { w, 0.62, 0.14 }, { 0, y, z }, dark, "SmoothPlastic"),
		box("EyeL", { 0.2, 0.3, 0.06 }, { -w * 0.25, y + 0.02, z - 0.08 }, glow, "Neon"),
		box("EyeR", { 0.2, 0.3, 0.06 }, { w * 0.25, y + 0.02, z - 0.08 }, glow, "Neon")
	)
end

local builders: { [string]: (look: string, trim: string, parts: { PartSpec }) -> () } = {}

-- ===== A: Bumble Bot (hovering) =====
builders.A = function(look, trim, parts)
	local body, belly, dark, glow = palette(look)
	add(
		parts,
		-- soft shadow on the ground
		cyl("Shadow", 1.8, 0.04, { 0, 0.03, 0 }, "#000000", "SmoothPlastic", nil, 0.65),
		-- hover pad and puff
		cyl("HoverPad", 1.2, 0.2, { 0, 0.95, 0 }, dark, "Metal"),
		cyl("HoverGlow", 0.9, 0.08, { 0, 0.8, 0 }, glow, "Neon", nil, 0.15),
		-- round body
		ball("Body", 2.0, { 0, 1.95, 0 }, body, bodyMat(look)),
		cyl("Belt", 2.02, 0.22, { 0, 1.55, 0 }, belly, bodyMat(look)),
		ball("Badge", 0.38, { 0, 1.55, -0.92 }, trim, "Neon"),
		-- propeller
		cyl("Mast", 0.14, 0.4, { 0, 3.1, 0 }, dark, "Metal"),
		cyl("SpinHub", 0.3, 0.16, { 0, 3.35, 0 }, trim, "Metal"),
		box("SpinBlade1", { 1.7, 0.05, 0.3 }, { 0, 3.4, 0 }, belly, "SmoothPlastic"),
		box("SpinBlade2", { 1.7, 0.05, 0.3 }, { 0, 3.4, 0 }, belly, "SmoothPlastic", { 0, 90, 0 }),
		-- antenna bulb
		cyl("Antenna", 0.07, 0.5, { 0.55, 3.0, 0.2 }, dark, "Metal", { 0, 0, -15 }),
		ball("BobBulb", 0.26, { 0.63, 3.3, 0.2 }, trim, "Neon"),
		-- sweeping arms with little brushes
		cyl("ArmL", 0.26, 0.9, { -1.12, 1.6, -0.35 }, belly, bodyMat(look), { -50, 0, 25 }),
		cyl("ArmR", 0.26, 0.9, { 1.12, 1.6, -0.35 }, belly, bodyMat(look), { -50, 0, -25 }),
		box("BrushL", { 0.7, 0.22, 0.34 }, { -1.3, 1.15, -0.75 }, dark, "Fabric"),
		box("BrushR", { 0.7, 0.22, 0.34 }, { 1.3, 1.15, -0.75 }, dark, "Fabric"),
		-- intake funnel on the belly
		cyl("Funnel", 0.8, 0.3, { 0, 1.0, -0.5 }, belly, bodyMat(look), { 90, 0, 0 }),
		cyl("FunnelHole", 0.5, 0.06, { 0, 1.0, -0.68 }, dark, "SmoothPlastic", { 90, 0, 0 }),
		-- cheeks
		ball("CheekL", 0.22, { -0.62, 1.75, -0.9 }, glow, "Neon", 0.35),
		ball("CheekR", 0.22, { 0.62, 1.75, -0.9 }, glow, "Neon", 0.35)
	)
	face(parts, 2.1, -0.93, 1.2, dark, glow)
end

-- ===== B: Roller Bot (wheels + brush roller) =====
builders.B = function(look, trim, parts)
	local body, belly, dark, glow = palette(look)
	add(
		parts,
		cyl("Shadow", 2.6, 0.04, { 0, 0.03, 0 }, "#000000", "SmoothPlastic", nil, 0.65),
		-- wheels
		cyl("WheelL", 1.3, 0.45, { -1.0, 0.65, 0.3 }, dark, "Fabric", { 0, 0, 90 }),
		cyl("WheelR", 1.3, 0.45, { 1.0, 0.65, 0.3 }, dark, "Fabric", { 0, 0, 90 }),
		cyl("HubL", 0.6, 0.5, { -1.0, 0.65, 0.3 }, trim, "Metal", { 0, 0, 90 }),
		cyl("HubR", 0.6, 0.5, { 1.0, 0.65, 0.3 }, trim, "Metal", { 0, 0, 90 }),
		-- body
		box("Body", { 1.7, 1.2, 1.9 }, { 0, 1.55, 0.2 }, body, bodyMat(look)),
		box("Belly", { 1.74, 0.3, 1.94 }, { 0, 1.1, 0.2 }, belly, bodyMat(look)),
		box("Badge", { 0.4, 0.4, 0.08 }, { 0, 1.5, -0.79 }, trim, "Neon"),
		-- head
		cyl("Neck", 0.3, 0.3, { 0, 2.3, 0.1 }, dark, "Metal"),
		box("Head", { 1.5, 0.95, 1.1 }, { 0, 2.85, 0.0 }, belly, bodyMat(look)),
		cyl("Antenna", 0.07, 0.6, { -0.5, 3.6, 0.1 }, dark, "Metal"),
		ball("BobBulb", 0.26, { -0.5, 3.95, 0.1 }, trim, "Neon"),
		-- brush roller out front
		cyl("RollerBar", 0.7, 1.8, { 0, 0.5, -1.35 }, dark, "Fabric", { 0, 0, 90 }),
		box("SpinSpoke1", { 1.8, 0.1, 0.9 }, { 0, 0.5, -1.35 }, trim, "Fabric"),
		box("SpinSpoke2", { 1.8, 0.1, 0.9 }, { 0, 0.5, -1.35 }, trim, "Fabric", { 60, 0, 0 }),
		box("SpinSpoke3", { 1.8, 0.1, 0.9 }, { 0, 0.5, -1.35 }, trim, "Fabric", { 120, 0, 0 }),
		box("RollerArmL", { 0.12, 0.12, 1.2 }, { -0.95, 0.75, -0.85 }, dark, "Metal"),
		box("RollerArmR", { 0.12, 0.12, 1.2 }, { 0.95, 0.75, -0.85 }, dark, "Metal"),
		-- dustbin on the back
		box("BinBack", { 1.5, 0.9, 0.12 }, { 0, 1.4, 1.35 }, body, bodyMat(look)),
		box("BinFloor", { 1.5, 0.12, 0.8 }, { 0, 0.95, 1.5 }, dark, "SmoothPlastic"),
		box("BinWindow", { 1.1, 0.6, 0.06 }, { 0, 1.45, 1.43 }, "#B8D8E8", "Glass", nil, 0.4),
		ball("BinAsh", 0.7, { 0, 1.2, 1.45 }, "#8A8480", "SmoothPlastic")
	)
	face(parts, 2.9, -0.58, 1.2, dark, glow)
end

-- ===== C: Ember Bot (mini volcano) =====
builders.C = function(look, trim, parts)
	local body, _belly, dark, glow = palette(look)
	local rock = if look == "A" then "#6B4A3E" elseif look == "B" then "#4A5160" else "#C9A8DA"
	add(
		parts,
		cyl("Shadow", 2.4, 0.04, { 0, 0.03, 0 }, "#000000", "SmoothPlastic", nil, 0.65),
		-- feet
		box("FootL", { 0.7, 0.4, 0.9 }, { -0.55, 0.25, -0.1 }, dark, "SmoothPlastic"),
		box("FootR", { 0.7, 0.4, 0.9 }, { 0.55, 0.25, -0.1 }, dark, "SmoothPlastic"),
		-- the volcano body: three tiers
		cyl("TierLow", 2.3, 0.8, { 0, 0.9, 0 }, rock, "Metal"),
		cyl("TierMid", 1.8, 0.7, { 0, 1.65, 0 }, ModelKit.lighten(rock, 0.1), "Metal"),
		cyl("TierTop", 1.3, 0.6, { 0, 2.3, 0 }, ModelKit.lighten(rock, 0.2), "Metal"),
		cyl("Rim", 1.45, 0.14, { 0, 2.65, 0 }, trim, "Metal"),
		cyl("Crater", 1.05, 0.1, { 0, 2.68, 0 }, "#FF6A1F", "Neon"),
		ball("BobBubble1", 0.34, { 0.2, 2.85, 0.1 }, "#FFD23F", "Neon"),
		ball("BobBubble2", 0.24, { -0.28, 2.82, -0.15 }, "#FFB020", "Neon"),
		ball("BobPuff1", 0.5, { 0.1, 3.4, 0 }, "#B8AEB0", "SmoothPlastic", 0.5),
		ball("BobPuff2", 0.36, { -0.2, 3.85, 0.1 }, "#D2CACC", "SmoothPlastic", 0.6),
		-- lava drips down the sides
		box("Drip1", { 0.22, 0.9, 0.14 }, { 0.62, 2.05, 0.55 }, "#FF8A2F", "Neon", { 0, -50, 0 }),
		box("Drip2", { 0.2, 0.7, 0.14 }, { -0.75, 1.5, 0.5 }, "#FFB020", "Neon", { 0, 50, 0 }),
		-- belly band with the level badge
		cyl("Band", 2.34, 0.2, { 0, 1.3, 0 }, body, bodyMat(look)),
		ball("Badge", 0.38, { 0, 1.3, -1.12 }, trim, "Neon"),
		-- arms with brushes
		cyl("ArmL", 0.26, 0.8, { -1.25, 1.5, -0.2 }, rock, "Metal", { -40, 0, 25 }),
		cyl("ArmR", 0.26, 0.8, { 1.25, 1.5, -0.2 }, rock, "Metal", { -40, 0, -25 }),
		box("BrushL", { 0.7, 0.22, 0.34 }, { -1.45, 1.05, -0.5 }, dark, "Fabric"),
		box("BrushR", { 0.7, 0.22, 0.34 }, { 1.45, 1.05, -0.5 }, dark, "Fabric"),
		-- cheeks
		ball("CheekL", 0.22, { -0.6, 1.72, -0.66 }, glow, "Neon", 0.35),
		ball("CheekR", 0.22, { 0.6, 1.72, -0.66 }, glow, "Neon", 0.35)
	)
	face(parts, 1.95, -0.6, 0.95, dark, glow)
end

-- ===== public =====

-- Parts of one helper bot. `look` = "A" | "B" | "C" (else "A"), `level` = shared level 0..15.
function BotSpecs.build(look: string?, level: number?): BotParts
	local key = if look == "B" or look == "C" then look else "A"
	local lv = math.clamp(math.floor(level or 0), 0, BotSpecs.maxLevel)
	local parts: { PartSpec } = {}
	builders[key](key, BotSpecs.tierColor(lv), parts)
	return { look = key, level = lv, parts = parts }
end

return BotSpecs
