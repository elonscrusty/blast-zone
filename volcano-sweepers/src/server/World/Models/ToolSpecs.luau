--!strict
-- Pure part lists for the eight sweeper tools (no Roblox types: Lune tests them).
-- Tool space: the grip is the origin, the tool hangs along -Y (business end at the bottom), -Z is
-- the way the character faces. "hand" parts go in the hand, "back" parts are in torso space
-- (origin = torso centre, +Z is BEHIND the character: backpacks, wings, tanks).
-- Each tool comes in 3 looks (A Toy, B Steel, C Candy). Look A uses the tool's catalog colour.
-- Phone-light: at most MAX_HAND parts in the hand and MAX_BACK on the back.

local ModelKit = require("./ModelKit")
local ToolDetails = require("./ToolDetails")

export type PartSpec = ModelKit.PartSpec
export type ToolParts = { id: string, look: string, hand: { PartSpec }, back: { PartSpec } }

local ToolSpecs = {}

ToolSpecs.MAX_LITE_HAND = 26 -- the basic shape (far away players)
ToolSpecs.MAX_LITE_BACK = 10
ToolSpecs.MAX_HAND = 44 -- with all the detail
ToolSpecs.MAX_BACK = 22

local box, cyl, ball, rod = ModelKit.box, ModelKit.cyl, ModelKit.ball, ModelKit.rod

-- The catalog colour of each tool (copied from shared/Catalog/Tools so this file stays pure and
-- server-side; tests/models.test.luau checks the two lists agree).
ToolSpecs.colors = {
	twig_broom = "#A9805B",
	push_broom = "#E0B040",
	leaf_blower = "#4FB3E8",
	dust_vac = "#6BCB77",
	turbo_vac = "#FF7A59",
	lava_mop = "#FF5A36",
	dragon_vac = "#9B5DE5",
	volcano_vac = "#FFD23F",
} :: { [string]: string }

local function toolColor(id: string): string
	return ToolSpecs.colors[id] or "#A9805B"
end

local function add(list: { PartSpec }, ...: PartSpec)
	for _, p in { ... } do
		table.insert(list, p)
	end
end

local builders: { [string]: (S: ModelKit.Style, hand: { PartSpec }, back: { PartSpec }) -> () } = {}

-- ===== 1. Twig Broom: a stick and a fan of straw =====
builders.twig_broom = function(S, hand, _back)
	local c = toolColor("twig_broom")
	local wood = if S.id == "A" then c else S.main(c)
	add(
		hand,
		rod("Stick", 0.22, 0.75, -2.9, wood, S.rodMat),
		ball("Knob", 0.36, { 0, 0.8, 0 }, S.accent(c), S.accentMat),
		rod("Twine1", 0.44, -2.5, -2.68, S.trim, S.soft),
		rod("Twine2", 0.44, -2.78, -2.96, S.accent(c), S.accentMat)
	)
	-- a fan of seven straw twigs in front and four behind
	for k = 1, 7 do
		local t = (k - 4) / 3
		add(
			hand,
			box(
				"Twig" .. k,
				{ 0.2, 1.6, 0.14 },
				{ t * 0.55, -3.6 + math.abs(t) * 0.14, -0.06 },
				S.straw[(k % 2) + 1],
				"Wood",
				{ 0, 0, -t * 24 }
			)
		)
	end
	for k = 1, 4 do
		local t = (k - 2.5) / 1.5
		add(
			hand,
			box(
				"TwigBack" .. k,
				{ 0.2, 1.45, 0.14 },
				{ t * 0.36, -3.55 + math.abs(t) * 0.1, 0.1 },
				S.straw[(k % 2) + 1],
				"Wood",
				{ 0, 0, -t * 16 }
			)
		)
	end
end

-- ===== 2. Push Broom: T handle, braces, wide head =====
builders.push_broom = function(S, hand, _back)
	local c = toolColor("push_broom")
	local pole = S.main(c)
	add(
		hand,
		rod("Pole", 0.22, 0.6, -3.0, pole, S.rodMat),
		cyl("HandleBar", 0.26, 1.0, { 0, 0.7, 0 }, S.dark, S.soft, { 0, 0, 90 }),
		ball("GripL", 0.34, { -0.52, 0.7, 0 }, S.accent(c), S.accentMat),
		ball("GripR", 0.34, { 0.52, 0.7, 0 }, S.accent(c), S.accentMat),
		box("BraceL", { 0.12, 1.1, 0.12 }, { -0.5, -2.7, 0 }, S.trim, "Metal", { 0, 0, 38 }),
		box("BraceR", { 0.12, 1.1, 0.12 }, { 0.5, -2.7, 0 }, S.trim, "Metal", { 0, 0, -38 }),
		box("Head", { 2.8, 0.38, 0.62 }, { 0, -3.3, 0 }, S.main("#C98A4B"), "Wood"),
		box("Bumper", { 2.9, 0.12, 0.7 }, { 0, -3.52, 0 }, S.accent(c), S.accentMat),
		box("Bristles", { 2.7, 0.5, 0.5 }, { 0, -3.8, 0 }, S.dark, S.soft)
	)
	for k = 1, 7 do
		add(
			hand,
			box(
				"Tuft" .. k,
				{ 0.3, 0.3, 0.46 },
				{ (k - 4) * 0.4, -4.1, 0 },
				if k % 2 == 0 then S.dark else ModelKit.lighten(S.dark, 0.18),
				S.soft
			)
		)
	end
end

-- ===== 3. Leaf Blower: motor, fan, long tube, glowing nozzle =====
builders.leaf_blower = function(S, hand, _back)
	local c = toolColor("leaf_blower")
	local body = S.main(c)
	add(
		hand,
		box("Handle", { 0.22, 0.2, 0.7 }, { 0, 0.5, 0.05 }, S.dark, S.soft),
		box("HandlePostF", { 0.2, 0.55, 0.2 }, { 0, 0.22, -0.28 }, S.dark, S.soft),
		box("HandlePostB", { 0.2, 0.55, 0.2 }, { 0, 0.22, 0.38 }, S.dark, S.soft),
		cyl("Motor", 1.15, 1.0, { 0, -0.55, 0.1 }, body, S.bodyMat, { 90, 0, 0 }),
		cyl("Intake", 0.95, 0.1, { 0, -0.55, 0.64 }, S.dark, "Metal", { 90, 0, 0 }),
		box("FanBlade1", { 0.8, 0.05, 0.1 }, { 0, -0.55, 0.7 }, S.accent(c), S.accentMat),
		box(
			"FanBlade2",
			{ 0.8, 0.05, 0.1 },
			{ 0, -0.55, 0.7 },
			S.accent(c),
			S.accentMat,
			{ 0, 0, 60 }
		),
		box(
			"FanBlade3",
			{ 0.8, 0.05, 0.1 },
			{ 0, -0.55, 0.7 },
			S.accent(c),
			S.accentMat,
			{ 0, 0, 120 }
		),
		box("Trigger", { 0.12, 0.3, 0.14 }, { 0, -0.02, -0.12 }, S.accent(c), S.accentMat),
		rod("Tube", 0.46, -1.0, -3.2, S.trim, S.bodyMat, 0, -0.1),
		cyl("Rib1", 0.54, 0.1, { 0, -1.5, -0.1 }, S.dark, "Metal"),
		cyl("Rib2", 0.54, 0.1, { 0, -2.0, -0.1 }, S.dark, "Metal"),
		cyl("Rib3", 0.54, 0.1, { 0, -2.5, -0.1 }, S.dark, "Metal"),
		cyl("NozzleCone", 0.72, 0.4, { 0, -3.4, -0.1 }, S.accent(c), S.accentMat),
		cyl("NozzleRim", 0.84, 0.1, { 0, -3.62, -0.1 }, S.dark, "Metal"),
		cyl("Vent", 0.6, 0.06, { 0, -3.7, -0.1 }, "#BFF0FF", "Neon"),
		box(
			"WindL",
			{ 0.08, 0.5, 0.08 },
			{ -0.28, -4.0, -0.1 },
			"#DFF8FF",
			"Neon",
			{ 0, 0, -14 },
			0.3
		),
		box(
			"WindR",
			{ 0.08, 0.5, 0.08 },
			{ 0.28, -4.0, -0.1 },
			"#DFF8FF",
			"Neon",
			{ 0, 0, 14 },
			0.3
		)
	)
end

-- ===== 4. Dust Vac: wand, floor head, canister backpack with a window of ash =====
builders.dust_vac = function(S, hand, back)
	local c = toolColor("dust_vac")
	local green = S.main(c)
	local deepGreen = ModelKit.darken(green, 0.25)
	add(
		hand,
		rod("Wand", 0.28, 0.4, -2.85, green, S.bodyMat),
		box("Grip", { 0.28, 0.2, 0.75 }, { 0, 0.55, 0.12 }, S.dark, S.soft),
		box("GripPost", { 0.22, 0.5, 0.22 }, { 0, 0.3, 0.38 }, S.dark, S.soft),
		cyl("Joint", 0.42, 0.28, { 0, -2.92, 0 }, S.trim, "Metal"),
		box("FloorHead", { 1.5, 0.3, 0.8 }, { 0, -3.15, -0.08 }, deepGreen, S.bodyMat),
		box("Bumper", { 1.56, 0.12, 0.86 }, { 0, -3.3, -0.08 }, S.accent(c), S.accentMat),
		box("Slot", { 1.2, 0.05, 0.12 }, { 0, -3.36, -0.3 }, "#C8FFB0", "Neon"),
		cyl("WheelL", 0.3, 0.16, { -0.8, -3.22, 0.2 }, S.dark, S.soft, { 0, 0, 90 }),
		cyl("WheelR", 0.3, 0.16, { 0.8, -3.22, 0.2 }, S.dark, S.soft, { 0, 0, 90 }),
		ball("Light", 0.2, { 0, -3.05, -0.5 }, "#FFFFFF", "Neon"),
		cyl("HoseStub", 0.2, 0.5, { 0, 0.42, 0.62 }, S.dark, S.soft, { 70, 0, 0 })
	)
	add(
		back,
		cyl("Canister", 1.1, 1.8, { 0, 0.2, 1.1 }, green, S.bodyMat),
		cyl("CanisterBase", 1.22, 0.22, { 0, -0.78, 1.1 }, S.dark, "Metal"),
		ball("Lid", 1.1, { 0, 1.1, 1.1 }, S.trim, S.bodyMat),
		box("Window", { 0.6, 1.0, 0.1 }, { 0, 0.2, 1.62 }, "#B8D8E8", "Glass", nil, 0.4),
		ball("AshInside", 0.5, { 0, -0.05, 1.45 }, "#8A8480", "SmoothPlastic"),
		box("Strap", { 1.25, 0.2, 1.25 }, { 0, -0.15, 1.1 }, S.dark, S.soft)
	)
end

-- ===== 5. Turbo Vac: racing body, spinning turbo ring, rocket tanks =====
builders.turbo_vac = function(S, hand, back)
	local c = toolColor("turbo_vac")
	local orange = S.main(c)
	add(
		hand,
		cyl("Body", 1.0, 1.4, { 0, 0.0, 0 }, orange, S.bodyMat),
		cyl("Stripe1", 1.04, 0.14, { 0, 0.18, 0 }, S.trim, S.bodyMat),
		cyl("Stripe2", 1.04, 0.14, { 0, -0.16, 0 }, S.trim, S.bodyMat),
		box("Handle", { 0.22, 0.2, 0.7 }, { 0, 0.82, 0.05 }, S.dark, S.soft),
		box(
			"FinL",
			{ 0.12, 0.8, 0.7 },
			{ -0.58, -0.35, 0.3 },
			ModelKit.darken(orange, 0.2),
			S.bodyMat,
			{ -20, 0, 0 }
		),
		box(
			"FinR",
			{ 0.12, 0.8, 0.7 },
			{ 0.58, -0.35, 0.3 },
			ModelKit.darken(orange, 0.2),
			S.bodyMat,
			{ -20, 0, 0 }
		),
		rod("Tube", 0.36, -0.7, -3.3, "#D8D8E0", "Metal"),
		cyl("TubeBand1", 0.46, 0.12, { 0, -1.4, 0 }, S.accent(c), S.accentMat),
		cyl("TubeBand2", 0.46, 0.12, { 0, -2.3, 0 }, S.accent(c), S.accentMat),
		cyl("Head", 1.4, 0.4, { 0, -3.55, 0 }, orange, S.bodyMat),
		cyl("TurboRing", 1.55, 0.12, { 0, -3.8, 0 }, "#FFD23F", "Neon"),
		cyl("TurboHub", 0.4, 0.14, { 0, -3.83, 0 }, S.dark, "Metal"),
		box("Blade1", { 1.2, 0.06, 0.16 }, { 0, -3.84, 0 }, "#FFF0A0", "Neon"),
		box("Blade2", { 1.2, 0.06, 0.16 }, { 0, -3.84, 0 }, "#FFF0A0", "Neon", { 0, 60, 0 }),
		box("Blade3", { 1.2, 0.06, 0.16 }, { 0, -3.84, 0 }, "#FFF0A0", "Neon", { 0, 120, 0 }),
		box("Speed1", { 0.06, 0.06, 0.7 }, { -0.34, 0.4, 0.9 }, "#FFFFFF", "Neon", nil, 0.35),
		box("Speed2", { 0.06, 0.06, 0.7 }, { 0.34, 0.4, 0.9 }, "#FFFFFF", "Neon", nil, 0.35)
	)
	add(
		back,
		cyl("TankL", 0.55, 1.5, { -0.38, 0.75, 0.95 }, orange, S.bodyMat),
		cyl("TankR", 0.55, 1.5, { 0.38, 0.75, 0.95 }, orange, S.bodyMat),
		ball("NoseL", 0.55, { -0.38, 1.5, 0.95 }, S.trim, S.bodyMat),
		ball("NoseR", 0.55, { 0.38, 1.5, 0.95 }, S.trim, S.bodyMat),
		cyl("BandL", 0.6, 0.12, { -0.38, 0.9, 0.95 }, S.dark, "Metal"),
		cyl("BandR", 0.6, 0.12, { 0.38, 0.9, 0.95 }, S.dark, "Metal"),
		ball("FlameL", 0.5, { -0.38, -0.1, 0.95 }, "#FFB020", "Neon"),
		ball("FlameR", 0.5, { 0.38, -0.1, 0.95 }, "#FFB020", "Neon")
	)
end

-- ===== 6. Lava Mop: glowing strands =====
builders.lava_mop = function(S, hand, _back)
	local c = toolColor("lava_mop")
	local hot = if S.id == "A" then c else S.accent(c)
	local handle = if S.id == "A" then "#6E2A1E" else S.main("#6E2A1E")
	add(
		hand,
		rod("Handle", 0.24, 0.75, -2.8, handle, S.rodMat),
		ball("Knob", 0.38, { 0, 0.8, 0 }, "#FFB020", "Neon"),
		cyl("Collar", 0.56, 0.3, { 0, -2.85, 0 }, S.dark, "Metal"),
		cyl("Core", 0.6, 0.5, { 0, -3.25, 0 }, "#FFD23F", "Neon"),
		cyl("Cup", 1.05, 0.14, { 0, -3.05, 0 }, S.dark, "Metal")
	)
	-- eight outer strands and four inner ones
	for k = 0, 7 do
		local a = math.rad(k * 45)
		local x, z = math.cos(a) * 0.46, math.sin(a) * 0.46
		add(
			hand,
			box(
				"Strand" .. (k + 1),
				{ 0.17, 1.15, 0.17 },
				{ x, -3.75, z },
				if k % 2 == 0 then hot else "#FFB020",
				"Neon",
				{ z * 36, 0, -x * 36 }
			)
		)
	end
	for k = 0, 3 do
		local a = math.rad(k * 90 + 45)
		local x, z = math.cos(a) * 0.2, math.sin(a) * 0.2
		add(hand, box("Inner" .. (k + 1), { 0.15, 1.0, 0.15 }, { x, -3.65, z }, "#FFE08A", "Neon"))
	end
	add(
		hand,
		ball("Drip1", 0.2, { 0.5, -4.45, 0.1 }, "#FFB020", "Neon"),
		ball("Drip2", 0.16, { -0.3, -4.5, -0.4 }, hot, "Neon")
	)
end

-- ===== 7. Dragon Vac: a friendly dragon head, wings on the back =====
builders.dragon_vac = function(S, hand, back)
	local c = toolColor("dragon_vac")
	local purple = S.main(c)
	local light = ModelKit.lighten(purple, 0.25)
	local belly = S.accent(c)
	-- neck: a rod with five round bumps down it
	add(
		hand,
		rod("NeckRod", 0.3, 0.45, -1.6, ModelKit.darken(purple, 0.15), S.bodyMat, 0, 0),
		ball("Neck1", 0.5, { 0, 0.35, 0.02 }, purple, S.bodyMat),
		ball("Neck2", 0.5, { 0, -0.15, 0.0 }, purple, S.bodyMat),
		ball("Neck3", 0.54, { 0, -0.65, -0.02 }, purple, S.bodyMat),
		ball("Neck4", 0.56, { 0, -1.15, -0.05 }, purple, S.bodyMat),
		ball("Neck5", 0.6, { 0, -1.6, -0.1 }, purple, S.bodyMat),
		box("Spike1", { 0.16, 0.3, 0.3 }, { 0, 0.1, 0.3 }, belly, S.accentMat, { 45, 0, 0 }),
		box("Spike2", { 0.16, 0.3, 0.3 }, { 0, -0.75, 0.27 }, belly, S.accentMat, { 45, 0, 0 }),
		box("Head", { 1.0, 0.9, 1.0 }, { 0, -2.15, -0.2 }, purple, S.bodyMat),
		box("Snout", { 0.75, 0.38, 0.8 }, { 0, -2.55, -0.85 }, light, S.bodyMat),
		box("Jaw", { 0.7, 0.18, 0.7 }, { 0, -2.95, -0.8 }, light, S.bodyMat),
		box("Mouth", { 0.55, 0.12, 0.5 }, { 0, -2.82, -0.8 }, "#FF7AC8", "Neon"),
		box("Tooth1", { 0.1, 0.16, 0.1 }, { -0.22, -2.78, -1.15 }, "#FFFFFF", "SmoothPlastic"),
		box("Tooth2", { 0.1, 0.16, 0.1 }, { 0.22, -2.78, -1.15 }, "#FFFFFF", "SmoothPlastic"),
		ball("EyeL", 0.34, { -0.3, -1.95, -0.62 }, "#FFFFFF", "SmoothPlastic"),
		ball("EyeR", 0.34, { 0.3, -1.95, -0.62 }, "#FFFFFF", "SmoothPlastic"),
		ball("PupilL", 0.17, { -0.3, -1.95, -0.78 }, S.dark, "SmoothPlastic"),
		ball("PupilR", 0.17, { 0.3, -1.95, -0.78 }, S.dark, "SmoothPlastic"),
		ball("NostrilL", 0.1, { -0.18, -2.45, -1.26 }, S.dark, "SmoothPlastic"),
		ball("NostrilR", 0.1, { 0.18, -2.45, -1.26 }, S.dark, "SmoothPlastic"),
		cyl("HornL", 0.18, 0.6, { -0.32, -1.6, 0.0 }, "#FFE14D", S.accentMat, { -25, 0, 18 }),
		cyl("HornR", 0.18, 0.6, { 0.32, -1.6, 0.0 }, "#FFE14D", S.accentMat, { -25, 0, -18 })
	)
	add(
		back,
		box(
			"WingArmL",
			{ 0.14, 0.14, 1.3 },
			{ -0.75, 0.55, 0.85 },
			purple,
			S.bodyMat,
			{ 0, -25, -20 }
		),
		box("WingArmR", { 0.14, 0.14, 1.3 }, { 0.75, 0.55, 0.85 }, purple, S.bodyMat, { 0, 25, 20 }),
		box(
			"MembraneL",
			{ 0.06, 0.9, 1.2 },
			{ -1.15, 0.2, 0.95 },
			belly,
			S.accentMat,
			{ 0, -25, -20 },
			0.1
		),
		box(
			"MembraneR",
			{ 0.06, 0.9, 1.2 },
			{ 1.15, 0.2, 0.95 },
			belly,
			S.accentMat,
			{ 0, 25, 20 },
			0.1
		),
		box("WingTipL", { 0.2, 0.2, 0.3 }, { -1.45, 0.75, 1.35 }, "#FFE14D", S.accentMat),
		box("WingTipR", { 0.2, 0.2, 0.3 }, { 1.45, 0.75, 1.35 }, "#FFE14D", S.accentMat),
		ball("Tail", 0.5, { 0, -1.0, 0.95 }, purple, S.bodyMat),
		ball("TailTip", 0.3, { 0, -1.35, 1.1 }, belly, S.accentMat)
	)
end

-- ===== 8. Volcano Vacuum: a mini volcano on a golden pole, tank on the back =====
builders.volcano_vac = function(S, hand, back)
	local c = toolColor("volcano_vac")
	local gold = if S.id == "A" then c else S.main(c)
	local rock = if S.id == "C" then "#B79AC9" elseif S.id == "B" then "#3A404E" else "#7A5546"
	add(
		hand,
		rod("Pole", 0.26, 0.75, -2.6, gold, S.rodMat),
		ball("Knob", 0.4, { 0, 0.8, 0 }, "#FF7A2F", "Neon"),
		cyl("Ring1", 0.38, 0.12, { 0, 0.3, 0 }, S.accent(c), S.accentMat),
		cyl("Ring2", 0.38, 0.12, { 0, -0.7, 0 }, S.accent(c), S.accentMat),
		cyl("Ring3", 0.38, 0.12, { 0, -1.7, 0 }, S.accent(c), S.accentMat),
		cyl("VolcanoBase", 1.9, 0.5, { 0, -2.85, 0 }, rock, "Metal"),
		cyl("VolcanoMid", 1.45, 0.45, { 0, -3.3, 0 }, ModelKit.lighten(rock, 0.1), "Metal"),
		cyl("VolcanoTop", 1.0, 0.4, { 0, -3.7, 0 }, ModelKit.lighten(rock, 0.2), "Metal"),
		cyl("LavaRingLow", 1.62, 0.08, { 0, -3.1, 0 }, "#FF6A1F", "Neon"),
		cyl("LavaRingHigh", 1.18, 0.08, { 0, -3.52, 0 }, "#FF8A2F", "Neon"),
		cyl("CraterRim", 1.12, 0.12, { 0, -3.95, 0 }, gold, S.accentMat),
		cyl("Lava", 0.78, 0.1, { 0, -3.98, 0 }, "#FF6A1F", "Neon"),
		box("Flow1", { 0.22, 0.85, 0.1 }, { 0, -3.35, -0.76 }, "#FF6A1F", "Neon", { 12, 0, 0 }),
		box("Flow2", { 0.2, 0.75, 0.1 }, { 0.62, -3.25, 0.4 }, "#FF8A2F", "Neon", { 0, -60, 0 }),
		box("Flow3", { 0.2, 0.75, 0.1 }, { -0.62, -3.25, 0.4 }, "#FFB020", "Neon", { 0, 60, 0 }),
		ball("Bubble1", 0.26, { 0.16, -4.1, 0.05 }, "#FFD23F", "Neon"),
		ball("Bubble2", 0.18, { -0.22, -4.14, -0.15 }, "#FFB020", "Neon"),
		ball("Puff1", 0.5, { 0.45, -4.5, 0.2 }, "#9A8F90", "SmoothPlastic", 0.45),
		ball("Puff2", 0.38, { -0.4, -4.7, -0.2 }, "#B8AEB0", "SmoothPlastic", 0.55)
	)
	add(
		back,
		cyl("Tank", 1.4, 2.2, { 0, 0.4, 1.1 }, gold, S.bodyMat),
		cyl("TankCapTop", 1.5, 0.2, { 0, 1.55, 1.1 }, S.dark, "Metal"),
		cyl("TankCapBottom", 1.5, 0.2, { 0, -0.75, 1.1 }, S.dark, "Metal"),
		box("LavaWindow", { 0.6, 1.3, 0.1 }, { 0, 0.4, 1.82 }, "#FF6A1F", "Neon", nil, 0.1),
		cyl("PipeL", 0.2, 1.0, { -0.5, 1.9, 0.95 }, S.dark, "Metal"),
		cyl("PipeR", 0.2, 1.0, { 0.5, 1.9, 0.95 }, S.dark, "Metal"),
		ball("CrystalL", 0.3, { -0.5, 2.45, 0.95 }, "#FFD23F", "Neon"),
		ball("CrystalR", 0.3, { 0.5, 2.45, 0.95 }, "#FFD23F", "Neon")
	)
end

-- ===== public =====

function ToolSpecs.has(id: string): boolean
	return builders[id] ~= nil
end

-- Parts of tool `id` in look `look` ("A" | "B" | "C"; anything else is "A"). `lite` = only the basic
-- shape (for players far away); otherwise every detail is added too.
function ToolSpecs.build(id: string, look: string?, lite: boolean?): ToolParts
	local S = ModelKit.style(look)
	local known = builders[id] ~= nil
	local realId = if known then id else "twig_broom"
	local builder = builders[realId]
	local hand: { PartSpec } = {}
	local back: { PartSpec } = {}
	builder(S, hand, back)
	if lite ~= true then
		ToolDetails.add(realId, S, toolColor(realId), hand, back)
	end
	return { id = realId, look = S.id, hand = hand, back = back }
end

return ToolSpecs
