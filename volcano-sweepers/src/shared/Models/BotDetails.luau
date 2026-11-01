--!strict
-- Extra detail for the helper bots (pure, no Roblox types). BotSpecs.build adds these after the basic
-- shape unless the caller asks for the "lite" version (bots far away). Bot space: origin = ground
-- under the bot, -Z forward. `trim` is the level colour (bronze / silver / gold / volcano).

local ModelKit = require("./ModelKit")

export type PartSpec = ModelKit.PartSpec

local BotDetails = {}

local box, cyl, ball = ModelKit.box, ModelKit.cyl, ModelKit.ball

local function add(list: { PartSpec }, ...: PartSpec)
	for _, p in { ... } do
		table.insert(list, p)
	end
end

local details: { [string]: (look: string, trim: string, parts: { PartSpec }) -> () } = {}

-- Colours per look: body, belly, dark, glow (same as BotSpecs).
-- A: Bumble
details.A = function(look, trim, parts)
	local body, belly, dark, glow = ModelKit.botPalette(look)
	add(
		parts,
		box("SpinBlade3", { 1.7, 0.05, 0.3 }, { 0, 3.42, 0 }, belly, "SmoothPlastic", { 0, 45, 0 }),
		box("SpinBlade4", { 1.7, 0.05, 0.3 }, { 0, 3.42, 0 }, belly, "SmoothPlastic", { 0, 135, 0 }),
		cyl("EarPodL", 0.55, 0.22, { -1.0, 2.2, 0 }, belly, ModelKit.botBodyMat(look), { 0, 0, 90 }),
		cyl("EarPodR", 0.55, 0.22, { 1.0, 2.2, 0 }, belly, ModelKit.botBodyMat(look), { 0, 0, 90 }),
		ball("EarGlowL", 0.26, { -1.12, 2.2, 0 }, glow, "Neon"),
		ball("EarGlowR", 0.26, { 1.12, 2.2, 0 }, glow, "Neon"),
		box("Smile", { 0.5, 0.06, 0.04 }, { 0, 1.8, -0.98 }, glow, "Neon"),
		box(
			"BrowL",
			{ 0.28, 0.05, 0.05 },
			{ -0.3, 2.52, -0.86 },
			dark,
			"SmoothPlastic",
			{ 0, 0, 10 }
		),
		box(
			"BrowR",
			{ 0.28, 0.05, 0.05 },
			{ 0.3, 2.52, -0.86 },
			dark,
			"SmoothPlastic",
			{ 0, 0, -10 }
		),
		ball("ShoulderL", 0.4, { -1.0, 1.65, -0.3 }, trim, "Metal"),
		ball("ShoulderR", 0.4, { 1.0, 1.65, -0.3 }, trim, "Metal"),
		box("BristleL1", { 0.18, 0.2, 0.3 }, { -1.55, 1.05, -0.75 }, dark, "Fabric"),
		box("BristleL2", { 0.18, 0.2, 0.3 }, { -1.05, 1.05, -0.75 }, dark, "Fabric"),
		box("BristleR1", { 0.18, 0.2, 0.3 }, { 1.55, 1.05, -0.75 }, dark, "Fabric"),
		box("BristleR2", { 0.18, 0.2, 0.3 }, { 1.05, 1.05, -0.75 }, dark, "Fabric"),
		box("BinBack", { 0.9, 0.8, 0.4 }, { 0, 1.9, 1.15 }, body, ModelKit.botBodyMat(look)),
		box("BinWindow", { 0.6, 0.45, 0.06 }, { 0, 1.95, 1.37 }, "#B8D8E8", "Glass", nil, 0.4),
		ball("BinAsh", 0.4, { 0, 1.75, 1.28 }, "#8A8480", "SmoothPlastic"),
		ball("Dust1", 0.18, { -0.5, 0.15, 0.3 }, "#BDB5AE", "SmoothPlastic", 0.55),
		ball("Dust2", 0.14, { 0.55, 0.12, -0.2 }, "#BDB5AE", "SmoothPlastic", 0.6),
		ball("Dust3", 0.12, { 0.1, 0.1, 0.6 }, "#BDB5AE", "SmoothPlastic", 0.65)
	)
end

-- B: Roller
details.B = function(look, trim, parts)
	local body, belly, dark, glow = ModelKit.botPalette(look)
	add(
		parts,
		box("FenderL", { 0.6, 0.12, 1.5 }, { -1.0, 1.4, 0.3 }, body, ModelKit.botBodyMat(look)),
		box("FenderR", { 0.6, 0.12, 1.5 }, { 1.0, 1.4, 0.3 }, body, ModelKit.botBodyMat(look)),
		ball("HeadlightL", 0.24, { -0.5, 1.3, -0.8 }, "#FFF6C8", "Neon"),
		ball("HeadlightR", 0.24, { 0.5, 1.3, -0.8 }, "#FFF6C8", "Neon"),
		box("Vent1", { 1.0, 0.05, 0.05 }, { 0, 1.95, -0.79 }, dark, "Metal"),
		box("Vent2", { 1.0, 0.05, 0.05 }, { 0, 2.05, -0.79 }, dark, "Metal"),
		box("Vent3", { 1.0, 0.05, 0.05 }, { 0, 2.15, -0.79 }, dark, "Metal"),
		box("ArmL", { 0.2, 0.2, 0.9 }, { -1.0, 1.75, -0.25 }, belly, ModelKit.botBodyMat(look)),
		box("ArmR", { 0.2, 0.2, 0.9 }, { 1.0, 1.75, -0.25 }, belly, ModelKit.botBodyMat(look)),
		ball("HandL", 0.3, { -1.0, 1.75, -0.8 }, trim, "Metal"),
		ball("HandR", 0.3, { 1.0, 1.75, -0.8 }, trim, "Metal"),
		cyl("DishArm", 0.07, 0.5, { 0.5, 3.45, 0.1 }, dark, "Metal"),
		cyl("Dish", 0.5, 0.08, { 0.5, 3.75, 0.1 }, belly, "Metal", { 25, 0, 20 }),
		cyl("EarL", 0.36, 0.15, { -0.8, 2.85, 0 }, dark, "Metal", { 0, 0, 90 }),
		cyl("EarR", 0.36, 0.15, { 0.8, 2.85, 0 }, dark, "Metal", { 0, 0, 90 }),
		box("Mouth", { 0.6, 0.05, 0.04 }, { 0, 2.55, -0.57 }, glow, "Neon"),
		cyl("Exhaust", 0.2, 0.6, { 0.5, 2.3, 1.0 }, dark, "Metal"),
		ball("ExhaustPuff", 0.3, { 0.5, 2.8, 1.0 }, "#C4BCBE", "SmoothPlastic", 0.55),
		cyl("RollerCapL", 0.9, 0.08, { -0.95, 0.5, -1.35 }, trim, "Metal", { 0, 0, 90 }),
		cyl("RollerCapR", 0.9, 0.08, { 0.95, 0.5, -1.35 }, trim, "Metal", { 0, 0, 90 }),
		box("TopStripe", { 0.3, 0.04, 1.6 }, { 0, 2.17, 0.2 }, trim, "Neon"),
		ball("SensorEye", 0.22, { 0, 3.4, -0.2 }, glow, "Neon")
	)
end

-- C: Ember
details.C = function(look, trim, parts)
	local _body, _belly, dark, _glow = ModelKit.botPalette(look)
	local rock = if look == "A" then "#6B4A3E" elseif look == "B" then "#4A5160" else "#C9A8DA"
	add(
		parts,
		ball("Boulder1", 0.36, { 1.0, 0.75, 0.5 }, rock, "Metal"),
		ball("Boulder2", 0.32, { -1.0, 0.7, 0.5 }, rock, "Metal"),
		ball("Boulder3", 0.3, { 0.5, 0.65, 1.0 }, rock, "Metal"),
		ball("Boulder4", 0.34, { -0.45, 0.7, 1.0 }, rock, "Metal"),
		ball("Boulder5", 0.28, { 0.0, 1.1, 0.95 }, rock, "Metal"),
		box("Crack1", { 0.07, 0.6, 0.05 }, { 0.7, 0.9, -0.95 }, "#FF8A2F", "Neon", { 0, -35, 15 }),
		box("Crack2", { 0.07, 0.5, 0.05 }, { -0.7, 0.9, -0.95 }, "#FFB020", "Neon", { 0, 35, -15 }),
		box("Crack3", { 0.07, 0.5, 0.05 }, { 1.0, 1.9, 0.1 }, "#FF8A2F", "Neon", { 0, -90, 10 }),
		box("Crack4", { 0.07, 0.5, 0.05 }, { -1.0, 1.9, 0.1 }, "#FFB020", "Neon", { 0, 90, -10 }),
		box(
			"BrowL",
			{ 0.25, 0.05, 0.05 },
			{ -0.25, 2.3, -0.62 },
			dark,
			"SmoothPlastic",
			{ 0, 0, 10 }
		),
		box(
			"BrowR",
			{ 0.25, 0.05, 0.05 },
			{ 0.25, 2.3, -0.62 },
			dark,
			"SmoothPlastic",
			{ 0, 0, -10 }
		),
		ball("HandL", 0.32, { -1.62, 1.0, -0.62 }, trim, "Metal"),
		ball("HandR", 0.32, { 1.62, 1.0, -0.62 }, trim, "Metal"),
		ball("EmberTail", 0.5, { 0, 0.9, 1.25 }, rock, "Metal"),
		ball("EmberTailGlow", 0.26, { 0, 0.95, 1.5 }, "#FF8A2F", "Neon"),
		ball("BobBubble3", 0.2, { 0.35, 2.82, -0.1 }, "#FFD23F", "Neon"),
		ball("BobBubble4", 0.16, { -0.05, 2.8, 0.3 }, "#FFB020", "Neon"),
		box("ToeL1", { 0.22, 0.15, 0.25 }, { -0.7, 0.2, -0.65 }, dark, "SmoothPlastic"),
		box("ToeL2", { 0.22, 0.15, 0.25 }, { -0.4, 0.2, -0.65 }, dark, "SmoothPlastic"),
		box("ToeR1", { 0.22, 0.15, 0.25 }, { 0.4, 0.2, -0.65 }, dark, "SmoothPlastic"),
		box("ToeR2", { 0.22, 0.15, 0.25 }, { 0.7, 0.2, -0.65 }, dark, "SmoothPlastic"),
		ball("Stud1", 0.13, { 0.7, 2.7, 0 }, trim, "Metal"),
		ball("Stud2", 0.13, { -0.7, 2.7, 0 }, trim, "Metal"),
		ball("Stud3", 0.13, { 0, 2.7, 0.7 }, trim, "Metal"),
		ball("Stud4", 0.13, { 0, 2.7, -0.7 }, trim, "Metal")
	)
end

function BotDetails.add(look: string, trim: string, parts: { PartSpec })
	local fn = details[look]
	if fn ~= nil then
		fn(look, trim, parts)
	end
end

return BotDetails
