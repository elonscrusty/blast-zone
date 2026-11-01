--!strict
-- Extra detail for the Sweeper Cart (pure, no Roblox types). CartSpecs.build adds these after the
-- basic shape unless the caller asks for the "lite" version (carts far away).
-- Cart space: origin = ground under the middle of the cart, -Z forward.

local ModelKit = require("./ModelKit")

export type PartSpec = ModelKit.PartSpec

local CartDetails = {}

local box, cyl, ball = ModelKit.box, ModelKit.cyl, ModelKit.ball

local function add(list: { PartSpec }, ...: PartSpec)
	for _, p in { ... } do
		table.insert(list, p)
	end
end

function CartDetails.add(S: ModelKit.Style, body: string, parts: { PartSpec })
	local deep = ModelKit.darken(body, 0.25)
	local gold = S.accent("#FFD23F")
	add(
		parts,
		-- mirrors
		box("MirrorArmL", { 0.4, 0.05, 0.05 }, { -1.35, 1.75, -0.7 }, S.dark, "Metal"),
		box("MirrorArmR", { 0.4, 0.05, 0.05 }, { 1.35, 1.75, -0.7 }, S.dark, "Metal"),
		box("MirrorL", { 0.05, 0.3, 0.22 }, { -1.58, 1.8, -0.72 }, S.trim, "Metal"),
		box("MirrorR", { 0.05, 0.3, 0.22 }, { 1.58, 1.8, -0.72 }, S.trim, "Metal"),
		-- headlight rims and side lamps
		cyl("LightRimL", 0.6, 0.06, { -0.85, 1.3, -2.31 }, S.dark, "Metal", { 90, 0, 0 }),
		cyl("LightRimR", 0.6, 0.06, { 0.85, 1.3, -2.31 }, S.dark, "Metal", { 90, 0, 0 }),
		ball("SideLampL", 0.15, { -1.4, 1.1, -2.1 }, "#FFB020", "Neon"),
		ball("SideLampR", 0.15, { 1.4, 1.1, -2.1 }, "#FFB020", "Neon"),
		-- fenders and mud flaps
		box("FenderFL", { 0.75, 0.1, 1.4 }, { -1.5, 1.2, -1.6 }, deep, S.bodyMat),
		box("FenderFR", { 0.75, 0.1, 1.4 }, { 1.5, 1.2, -1.6 }, deep, S.bodyMat),
		box("FenderBL", { 0.75, 0.1, 1.8 }, { -1.55, 1.6, 1.5 }, deep, S.bodyMat),
		box("FenderBR", { 0.75, 0.1, 1.8 }, { 1.55, 1.6, 1.5 }, deep, S.bodyMat),
		box("FlapL", { 0.5, 0.5, 0.05 }, { -1.55, 0.5, 2.35 }, S.dark, S.soft),
		box("FlapR", { 0.5, 0.5, 0.05 }, { 1.55, 0.5, 2.35 }, S.dark, S.soft),
		-- hood vents
		box("VentL1", { 0.5, 0.03, 0.06 }, { -0.8, 1.66, -1.2 }, S.dark, "Metal"),
		box("VentL2", { 0.5, 0.03, 0.06 }, { -0.8, 1.66, -1.0 }, S.dark, "Metal"),
		box("VentR1", { 0.5, 0.03, 0.06 }, { 0.8, 1.66, -1.2 }, S.dark, "Metal"),
		box("VentR2", { 0.5, 0.03, 0.06 }, { 0.8, 1.66, -1.0 }, S.dark, "Metal"),
		-- bumper and steps
		box("BumperBar", { 2.6, 0.18, 0.2 }, { 0, 0.85, -2.45 }, S.trim, "Metal"),
		ball("BumperBoltL", 0.15, { -1.1, 0.85, -2.57 }, S.dark, "Metal"),
		ball("BumperBoltR", 0.15, { 1.1, 0.85, -2.57 }, S.dark, "Metal"),
		box("StepL", { 0.3, 0.06, 1.2 }, { -1.55, 0.7, 0.1 }, S.dark, "Metal"),
		box("StepR", { 0.3, 0.06, 1.2 }, { 1.55, 0.7, 0.1 }, S.dark, "Metal"),
		-- dashboard lights
		ball("DashLed1", 0.14, { -0.25, 1.72, -0.75 }, "#9BFFB0", "Neon"),
		ball("DashLed2", 0.14, { 0, 1.72, -0.75 }, "#FFD23F", "Neon"),
		ball("DashLed3", 0.14, { 0.25, 1.72, -0.75 }, "#FF6A6A", "Neon"),
		-- bin: ribs, plate, tail lights, toolbox, shovel
		box("RibL1", { 0.05, 0.7, 0.08 }, { -0.9, 1.7, 2.84 }, S.dark, "Metal"),
		box("RibL2", { 0.05, 0.7, 0.08 }, { -0.45, 1.7, 2.84 }, S.dark, "Metal"),
		box("RibR1", { 0.05, 0.7, 0.08 }, { 0.45, 1.7, 2.84 }, S.dark, "Metal"),
		box("RibR2", { 0.05, 0.7, 0.08 }, { 0.9, 1.7, 2.84 }, S.dark, "Metal"),
		box("Plate", { 0.6, 0.25, 0.04 }, { 0, 1.6, 2.84 }, S.trim, "SmoothPlastic"),
		box("TailLightL", { 0.3, 0.2, 0.06 }, { -1.0, 1.95, 2.84 }, "#FF4D4D", "Neon"),
		box("TailLightR", { 0.3, 0.2, 0.06 }, { 1.0, 1.95, 2.84 }, "#FF4D4D", "Neon"),
		box("Toolbox", { 0.8, 0.4, 0.4 }, { -0.5, 0.95, 2.65 }, gold, S.accentMat),
		cyl("ShovelHandle", 0.08, 1.4, { -1.32, 1.95, 2.0 }, S.dark, "Wood", { 90, 0, 0 }),
		box("ShovelBlade", { 0.35, 0.04, 0.4 }, { -1.32, 1.95, 2.9 }, S.trim, "Metal"),
		-- flag on the roll bar
		cyl("FlagPole", 0.05, 1.2, { -0.95, 4.1, 0.95 }, S.trim, "Metal"),
		box("Flag", { 0.5, 0.3, 0.03 }, { -0.7, 4.5, 0.95 }, gold, S.accentMat),
		ball("FlagTip", 0.1, { -0.95, 4.75, 0.95 }, "#FFFFFF", "Neon")
	)
end

return CartDetails
