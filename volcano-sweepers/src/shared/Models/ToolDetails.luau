--!strict
-- Extra detail for the eight sweeper tools (pure, no Roblox types). ToolSpecs.build calls these after
-- the basic shape is made, unless the caller asks for the "lite" version (far away players):
-- lite = the basic shape only, detail = lite + everything below.
-- Same space as ToolSpecs: grip at the origin, hangs along -Y, -Z forward; back parts +Z behind.

local ModelKit = require("./ModelKit")

export type PartSpec = ModelKit.PartSpec

local ToolDetails = {}

local box, cyl, ball = ModelKit.box, ModelKit.cyl, ModelKit.ball

local function add(list: { PartSpec }, ...: PartSpec)
	for _, p in { ... } do
		table.insert(list, p)
	end
end

local details: { [string]: (S: ModelKit.Style, c: string, hand: { PartSpec }, back: { PartSpec }) -> () } =
	{}

details.twig_broom = function(S, c, hand, _back)
	local bark = ModelKit.darken(S.main(c), 0.25)
	-- a hanging loop of little beads
	for k = 0, 5 do
		local a = math.rad(k * 60)
		add(
			hand,
			ball(
				"LoopBead" .. (k + 1),
				0.1,
				{ math.cos(a) * 0.22, 1.2 + math.sin(a) * 0.22, 0 },
				S.accent(c),
				S.accentMat
			)
		)
	end
	add(
		hand,
		cyl("Bark1", 0.27, 0.1, { 0, 0.25, 0 }, bark, S.rodMat),
		cyl("Bark2", 0.27, 0.1, { 0, -0.55, 0 }, bark, S.rodMat),
		cyl("Bark3", 0.27, 0.1, { 0, -1.4, 0 }, bark, S.rodMat),
		box("Leaf1", { 0.38, 0.05, 0.2 }, { 0.24, -2.1, 0.02 }, "#6BCB77", "Fabric", { 0, 30, 24 }),
		box(
			"Leaf2",
			{ 0.32, 0.05, 0.18 },
			{ -0.22, -1.8, -0.02 },
			"#4FA85E",
			"Fabric",
			{ 0, -30, -24 }
		),
		box(
			"OuterTwigL",
			{ 0.2, 1.5, 0.14 },
			{ -0.82, -3.55, 0 },
			S.straw[1],
			"Wood",
			{ 0, 0, -36 }
		),
		box("OuterTwigR", { 0.2, 1.5, 0.14 }, { 0.82, -3.55, 0 }, S.straw[2], "Wood", { 0, 0, 36 }),
		box(
			"BowL",
			{ 0.2, 0.12, 0.1 },
			{ -0.2, -2.6, -0.2 },
			S.accent(c),
			S.accentMat,
			{ 0, 0, 30 }
		),
		box(
			"BowR",
			{ 0.2, 0.12, 0.1 },
			{ 0.2, -2.6, -0.2 },
			S.accent(c),
			S.accentMat,
			{ 0, 0, -30 }
		)
	)
end

details.push_broom = function(S, c, hand, _back)
	add(
		hand,
		cyl("GripRubL", 0.32, 0.4, { -0.34, 0.7, 0 }, S.dark, S.soft, { 0, 0, 90 }),
		cyl("GripRubR", 0.32, 0.4, { 0.34, 0.7, 0 }, S.dark, S.soft, { 0, 0, 90 }),
		cyl("Ferrule", 0.32, 0.3, { 0, -2.75, 0 }, S.trim, "Metal"),
		box("Plate", { 0.55, 0.12, 0.45 }, { 0, -3.08, 0 }, S.trim, "Metal"),
		ball("Bolt1", 0.13, { -1.15, -3.12, -0.15 }, S.trim, "Metal"),
		ball("Bolt2", 0.13, { -1.15, -3.12, 0.15 }, S.trim, "Metal"),
		ball("Bolt3", 0.13, { 1.15, -3.12, -0.15 }, S.trim, "Metal"),
		ball("Bolt4", 0.13, { 1.15, -3.12, 0.15 }, S.trim, "Metal"),
		box("EndCapL", { 0.12, 0.5, 0.7 }, { -1.46, -3.4, 0 }, S.accent(c), S.accentMat),
		box("EndCapR", { 0.12, 0.5, 0.7 }, { 1.46, -3.4, 0 }, S.accent(c), S.accentMat),
		box("NamePlate", { 1.2, 0.16, 0.04 }, { 0, -3.3, -0.33 }, S.accent(c), S.accentMat)
	)
	for k = 1, 6 do
		add(
			hand,
			box(
				"TuftB" .. k,
				{ 0.3, 0.26, 0.4 },
				{ (k - 3.5) * 0.4 + 0.2, -4.3, 0 },
				if k % 2 == 0 then ModelKit.lighten(S.dark, 0.3) else S.dark,
				S.soft
			)
		)
	end
end

details.leaf_blower = function(S, c, hand, _back)
	local body = S.main(c)
	add(
		hand,
		cyl("FuelCap", 0.3, 0.1, { 0, 0.05, 0.2 }, S.dark, "Metal"),
		cyl("Logo", 0.5, 0.04, { -0.59, -0.55, 0.1 }, S.accent(c), S.accentMat, { 0, 0, 90 }),
		box("Lever", { 0.1, 0.1, 0.4 }, { 0, 0.28, -0.42 }, S.accent(c), S.accentMat),
		ball("Elbow", 0.62, { 0, -1.05, -0.1 }, body, S.bodyMat),
		box("Slat1", { 0.05, 0.5, 0.08 }, { 0.59, -0.55, -0.1 }, S.dark, "Metal"),
		box("Slat2", { 0.05, 0.5, 0.08 }, { 0.59, -0.55, 0.1 }, S.dark, "Metal"),
		box("Slat3", { 0.05, 0.5, 0.08 }, { 0.59, -0.55, 0.3 }, S.dark, "Metal"),
		box("Tooth1", { 0.1, 0.18, 0.1 }, { -0.4, -3.65, -0.1 }, S.dark, "Metal"),
		box("Tooth2", { 0.1, 0.18, 0.1 }, { 0.4, -3.65, -0.1 }, S.dark, "Metal"),
		box("Tooth3", { 0.1, 0.18, 0.1 }, { 0, -3.65, -0.5 }, S.dark, "Metal"),
		box("Tooth4", { 0.1, 0.18, 0.1 }, { 0, -3.65, 0.3 }, S.dark, "Metal"),
		box("Streak1", { 0.06, 0.6, 0.06 }, { -0.15, -4.3, -0.1 }, "#FFFFFF", "Neon", nil, 0.45),
		box("Streak2", { 0.06, 0.6, 0.06 }, { 0.15, -4.35, -0.1 }, "#FFFFFF", "Neon", nil, 0.45),
		box("Streak3", { 0.06, 0.6, 0.06 }, { 0, -4.4, -0.3 }, "#FFFFFF", "Neon", nil, 0.45),
		box("Streak4", { 0.06, 0.6, 0.06 }, { 0, -4.4, 0.1 }, "#FFFFFF", "Neon", nil, 0.45),
		ball("Spark1", 0.12, { -0.4, -4.1, -0.1 }, "#BFF0FF", "Neon", 0.3),
		ball("Spark2", 0.1, { 0.42, -4.2, 0.1 }, "#BFF0FF", "Neon", 0.3),
		ball("Spark3", 0.09, { 0.05, -4.7, -0.1 }, "#BFF0FF", "Neon", 0.3)
	)
end

details.dust_vac = function(S, c, hand, back)
	add(
		hand,
		box("Screen", { 0.2, 0.04, 0.3 }, { 0, 0.67, 0.12 }, "#9BFFB0", "Neon"),
		ball("Led1", 0.09, { 0, -0.2, -0.15 }, "#9BFFB0", "Neon"),
		ball("Led2", 0.09, { 0, -0.45, -0.15 }, "#FFD23F", "Neon"),
		ball("Led3", 0.09, { 0, -0.7, -0.15 }, "#FF6A6A", "Neon"),
		box("Lip", { 1.5, 0.1, 0.12 }, { 0, -3.2, -0.5 }, S.accent(c), S.accentMat),
		box("FlapL", { 0.08, 0.22, 0.5 }, { -0.78, -3.12, -0.08 }, S.dark, S.soft),
		box("FlapR", { 0.08, 0.22, 0.5 }, { 0.78, -3.12, -0.08 }, S.dark, S.soft),
		cyl("Collar1", 0.37, 0.1, { 0, -0.9, 0 }, S.trim, "Metal"),
		cyl("Collar2", 0.37, 0.1, { 0, -2.0, 0 }, S.trim, "Metal"),
		ball("HoseBall1", 0.22, { 0, 0.5, 0.5 }, S.dark, S.soft),
		ball("HoseBall2", 0.22, { 0, 0.6, 0.7 }, S.dark, S.soft),
		ball("HoseBall3", 0.22, { 0, 0.62, 0.9 }, S.dark, S.soft),
		ball("HoseBall4", 0.22, { 0, 0.55, 1.1 }, S.dark, S.soft)
	)
	add(
		back,
		cyl("BandHigh", 1.16, 0.1, { 0, 0.8, 1.1 }, S.accent(c), S.accentMat),
		cyl("BandLow", 1.16, 0.1, { 0, -0.4, 1.1 }, S.accent(c), S.accentMat),
		cyl("GaugeBezel", 0.42, 0.08, { 0, 0.88, 1.64 }, S.dark, "Metal", { 90, 0, 0 }),
		cyl("GaugeFace", 0.34, 0.04, { 0, 0.88, 1.68 }, "#FFFFFF", "SmoothPlastic", { 90, 0, 0 }),
		box(
			"GaugeNeedle",
			{ 0.03, 0.16, 0.02 },
			{ 0.04, 0.9, 1.71 },
			"#FF4D4D",
			"Neon",
			{ 0, 0, 30 }
		),
		cyl("WheelL", 0.4, 0.15, { -0.5, -0.95, 1.1 }, S.dark, S.soft, { 0, 0, 90 }),
		cyl("WheelR", 0.4, 0.15, { 0.5, -0.95, 1.1 }, S.dark, S.soft, { 0, 0, 90 }),
		ball("LidKnob", 0.22, { 0, 1.7, 1.1 }, S.accent(c), S.accentMat),
		cyl("Port", 0.3, 0.2, { 0, -0.2, 0.5 }, S.trim, "Metal", { 90, 0, 0 })
	)
end

details.turbo_vac = function(S, c, hand, back)
	add(
		hand,
		cyl("ExhaustL", 0.2, 0.3, { -0.3, -0.3, 0.6 }, S.dark, "Metal", { 90, 0, 0 }),
		cyl("ExhaustR", 0.2, 0.3, { 0.3, -0.3, 0.6 }, S.dark, "Metal", { 90, 0, 0 }),
		ball("ExhaustFlameL", 0.18, { -0.3, -0.3, 0.82 }, "#FFB020", "Neon"),
		ball("ExhaustFlameR", 0.18, { 0.3, -0.3, 0.82 }, "#FFB020", "Neon"),
		cyl("DialRim", 0.4, 0.06, { 0, 0.1, -0.5 }, S.dark, "Metal", { 90, 0, 0 }),
		cyl("DialFace", 0.32, 0.03, { 0, 0.1, -0.53 }, "#7DF0FF", "Neon", { 90, 0, 0 }),
		box(
			"DialNeedle",
			{ 0.03, 0.14, 0.02 },
			{ 0.03, 0.13, -0.56 },
			"#FFFFFF",
			"Neon",
			{ 0, 0, -40 }
		),
		box("Spoiler", { 1.0, 0.08, 0.3 }, { 0, 0.5, 0.62 }, S.accent(c), S.accentMat),
		box("StrutL", { 0.06, 0.3, 0.08 }, { -0.35, 0.36, 0.55 }, S.dark, "Metal"),
		box("StrutR", { 0.06, 0.3, 0.08 }, { 0.35, 0.36, 0.55 }, S.dark, "Metal"),
		box("Blade4", { 1.2, 0.06, 0.16 }, { 0, -3.85, 0 }, "#FFF0A0", "Neon", { 0, 30, 0 }),
		box("Blade5", { 1.2, 0.06, 0.16 }, { 0, -3.85, 0 }, "#FFF0A0", "Neon", { 0, 90, 0 }),
		box("Blade6", { 1.2, 0.06, 0.16 }, { 0, -3.85, 0 }, "#FFF0A0", "Neon", { 0, 150, 0 }),
		ball("Rivet1", 0.11, { -0.58, -3.5, -0.3 }, S.trim, "Metal"),
		ball("Rivet2", 0.11, { 0.58, -3.5, -0.3 }, S.trim, "Metal"),
		ball("Rivet3", 0.11, { -0.58, -3.5, 0.3 }, S.trim, "Metal"),
		ball("Rivet4", 0.11, { 0.58, -3.5, 0.3 }, S.trim, "Metal"),
		box(
			"FlameDecal1",
			{ 0.3, 0.3, 0.03 },
			{ -0.2, -0.35, -0.51 },
			"#FF4D4D",
			"Neon",
			{ 0, 0, 45 }
		),
		box(
			"FlameDecal2",
			{ 0.22, 0.22, 0.03 },
			{ 0.15, -0.3, -0.51 },
			"#FFD23F",
			"Neon",
			{ 0, 0, 45 }
		)
	)
	add(
		back,
		box("StrapHigh", { 1.4, 0.14, 0.2 }, { 0, 1.1, 0.95 }, S.dark, S.soft),
		box("StrapLow", { 1.4, 0.14, 0.2 }, { 0, 0.4, 0.95 }, S.dark, S.soft),
		ball("GaugeL", 0.16, { -0.38, 0.75, 1.24 }, "#7DF0FF", "Neon"),
		ball("GaugeR", 0.16, { 0.38, 0.75, 1.24 }, "#7DF0FF", "Neon"),
		ball("FlameCoreL", 0.26, { -0.38, -0.12, 0.95 }, "#FFFFFF", "Neon"),
		ball("FlameCoreR", 0.26, { 0.38, -0.12, 0.95 }, "#FFFFFF", "Neon"),
		cyl("NozzleL", 0.42, 0.12, { -0.38, 0.02, 0.95 }, S.dark, "Metal"),
		cyl("NozzleR", 0.42, 0.12, { 0.38, 0.02, 0.95 }, S.dark, "Metal")
	)
end

details.lava_mop = function(S, c, hand, _back)
	local hot = if S.id == "A" then c else S.accent(c)
	add(
		hand,
		cyl("Band1", 0.3, 0.14, { 0, 0.2, 0 }, "#FFB020", "Neon"),
		cyl("Band2", 0.3, 0.14, { 0, -0.6, 0 }, "#FFB020", "Neon"),
		cyl("Band3", 0.3, 0.14, { 0, -1.4, 0 }, "#FFB020", "Neon"),
		ball("Rivet1", 0.1, { 0.52, -3.05, 0 }, S.trim, "Metal"),
		ball("Rivet2", 0.1, { -0.52, -3.05, 0 }, S.trim, "Metal"),
		ball("Rivet3", 0.1, { 0, -3.05, 0.52 }, S.trim, "Metal"),
		ball("Rivet4", 0.1, { 0, -3.05, -0.52 }, S.trim, "Metal"),
		cyl("HeatRing1", 1.3, 0.03, { 0, -4.05, 0 }, "#FF8A2F", "Neon", nil, 0.5),
		cyl("HeatRing2", 1.0, 0.03, { 0, -4.3, 0 }, "#FFD23F", "Neon", nil, 0.55),
		ball("Ember1", 0.14, { 0.7, -3.4, 0.1 }, "#FFD23F", "Neon", 0.2),
		ball("Ember2", 0.1, { -0.75, -3.7, -0.1 }, "#FFB020", "Neon", 0.2),
		ball("Ember3", 0.12, { 0.6, -4.1, -0.5 }, "#FFD23F", "Neon", 0.25),
		ball("Ember4", 0.09, { -0.5, -4.4, 0.5 }, "#FFB020", "Neon", 0.25),
		ball("Ember5", 0.1, { 0.1, -4.6, 0.2 }, "#FFD23F", "Neon", 0.3),
		box("OuterStrand1", { 0.2, 0.95, 0.15 }, { 0.68, -3.8, 0 }, hot, "Neon", { 0, 0, -22 }),
		box("OuterStrand2", { 0.2, 0.95, 0.15 }, { -0.68, -3.8, 0 }, hot, "Neon", { 0, 0, 22 }),
		box("OuterStrand3", { 0.15, 0.95, 0.2 }, { 0, -3.8, 0.68 }, hot, "Neon", { 22, 0, 0 }),
		box("OuterStrand4", { 0.15, 0.95, 0.2 }, { 0, -3.8, -0.68 }, hot, "Neon", { -22, 0, 0 }),
		box("KnobFlame1", { 0.1, 0.3, 0.1 }, { 0, 1.1, 0 }, "#FFD23F", "Neon", { 0, 0, 12 }),
		box("KnobFlame2", { 0.1, 0.24, 0.1 }, { 0.08, 1.05, 0 }, "#FF8A2F", "Neon", { 0, 0, -18 })
	)
end

details.dragon_vac = function(S, c, hand, back)
	local purple = S.main(c)
	local belly = S.accent(c)
	add(
		hand,
		box(
			"CheekFinL",
			{ 0.08, 0.45, 0.5 },
			{ -0.55, -2.15, -0.1 },
			belly,
			S.accentMat,
			{ 0, 0, 20 }
		),
		box(
			"CheekFinR",
			{ 0.08, 0.45, 0.5 },
			{ 0.55, -2.15, -0.1 },
			belly,
			S.accentMat,
			{ 0, 0, -20 }
		),
		box("BrowL", { 0.3, 0.08, 0.18 }, { -0.3, -1.75, -0.68 }, S.dark, "SmoothPlastic"),
		box("BrowR", { 0.3, 0.08, 0.18 }, { 0.3, -1.75, -0.68 }, S.dark, "SmoothPlastic"),
		box("LowTooth1", { 0.1, 0.14, 0.1 }, { -0.22, -2.88, -1.12 }, "#FFFFFF", "SmoothPlastic"),
		box("LowTooth2", { 0.1, 0.14, 0.1 }, { 0.22, -2.88, -1.12 }, "#FFFFFF", "SmoothPlastic"),
		box("SideTooth1", { 0.1, 0.14, 0.1 }, { -0.38, -2.8, -0.92 }, "#FFFFFF", "SmoothPlastic"),
		box("SideTooth2", { 0.1, 0.14, 0.1 }, { 0.38, -2.8, -0.92 }, "#FFFFFF", "SmoothPlastic"),
		box("Tongue", { 0.2, 0.04, 0.4 }, { 0, -2.88, -0.98 }, "#FF4FA0", "SmoothPlastic"),
		ball("Smoke1", 0.22, { -0.18, -2.4, -1.4 }, "#D8D2D8", "SmoothPlastic", 0.5),
		ball("Smoke2", 0.18, { 0.18, -2.35, -1.5 }, "#D8D2D8", "SmoothPlastic", 0.55),
		box("Spike3", { 0.16, 0.3, 0.3 }, { 0, -0.3, 0.3 }, belly, S.accentMat, { 45, 0, 0 }),
		box("Spike4", { 0.16, 0.3, 0.3 }, { 0, -1.25, 0.27 }, belly, S.accentMat, { 45, 0, 0 }),
		box("Plate1", { 0.3, 0.08, 0.1 }, { 0, 0.2, -0.3 }, "#FFE14D", S.accentMat),
		box("Plate2", { 0.3, 0.08, 0.1 }, { 0, -0.3, -0.3 }, "#FFE14D", S.accentMat),
		box("Plate3", { 0.3, 0.08, 0.1 }, { 0, -0.8, -0.3 }, "#FFE14D", S.accentMat),
		box("Plate4", { 0.3, 0.08, 0.1 }, { 0, -1.3, -0.32 }, "#FFE14D", S.accentMat)
	)
	add(
		back,
		box("Dorsal1", { 0.14, 0.28, 0.28 }, { 0, 0.9, 0.68 }, belly, S.accentMat, { 45, 0, 0 }),
		box("Dorsal2", { 0.14, 0.28, 0.28 }, { 0, 0.4, 0.66 }, belly, S.accentMat, { 45, 0, 0 }),
		box("Dorsal3", { 0.14, 0.28, 0.28 }, { 0, -0.1, 0.64 }, belly, S.accentMat, { 45, 0, 0 }),
		ball("TailMid", 0.4, { 0, -1.2, 1.02 }, purple, S.bodyMat),
		box("TailSpike1", { 0.12, 0.2, 0.2 }, { 0, -0.75, 1.22 }, belly, S.accentMat, { 45, 0, 0 }),
		box("TailSpike2", { 0.12, 0.2, 0.2 }, { 0, -1.1, 1.3 }, belly, S.accentMat, { 45, 0, 0 }),
		box(
			"FingerL1",
			{ 0.08, 0.08, 0.8 },
			{ -1.1, 0.45, 1.3 },
			purple,
			S.bodyMat,
			{ 0, -40, -10 }
		),
		box("FingerL2", { 0.08, 0.08, 0.7 }, { -1.0, 0.1, 1.25 }, purple, S.bodyMat, { 0, -55, 10 }),
		box("FingerR1", { 0.08, 0.08, 0.8 }, { 1.1, 0.45, 1.3 }, purple, S.bodyMat, { 0, 40, 10 }),
		box("FingerR2", { 0.08, 0.08, 0.7 }, { 1.0, 0.1, 1.25 }, purple, S.bodyMat, { 0, 55, -10 })
	)
end

details.volcano_vac = function(S, c, hand, back)
	local gold = if S.id == "A" then c else S.main(c)
	local rock = if S.id == "C" then "#9A7DB0" elseif S.id == "B" then "#2A303C" else "#5A3E34"
	add(
		hand,
		ball("Rock1", 0.32, { 0.6, -2.62, 0.3 }, rock, "Metal"),
		ball("Rock2", 0.28, { -0.6, -2.62, -0.3 }, rock, "Metal"),
		ball("Rock3", 0.26, { 0.1, -2.6, -0.7 }, rock, "Metal"),
		ball("Rock4", 0.3, { -0.3, -2.6, 0.65 }, rock, "Metal"),
		ball("Gem1", 0.14, { 0, 0.3, -0.2 }, "#FF6A1F", "Neon"),
		ball("Gem2", 0.14, { 0, -0.7, -0.2 }, "#FF6A1F", "Neon"),
		ball("Gem3", 0.14, { 0, -1.7, -0.2 }, "#FF6A1F", "Neon"),
		box("Flow4", { 0.16, 0.6, 0.08 }, { 0.3, -3.4, -0.68 }, "#FFB020", "Neon", { 0, 20, 0 }),
		box("Flow5", { 0.16, 0.6, 0.08 }, { -0.3, -3.4, -0.68 }, "#FF8A2F", "Neon", { 0, -20, 0 }),
		box("RimSpike1", { 0.1, 0.2, 0.1 }, { 0.55, -4.0, 0 }, gold, S.accentMat),
		box("RimSpike2", { 0.1, 0.2, 0.1 }, { -0.55, -4.0, 0 }, gold, S.accentMat),
		box("RimSpike3", { 0.1, 0.2, 0.1 }, { 0, -4.0, 0.55 }, gold, S.accentMat),
		box("RimSpike4", { 0.1, 0.2, 0.1 }, { 0, -4.0, -0.55 }, gold, S.accentMat),
		ball("Puff3", 0.34, { 0.1, -4.9, 0.3 }, "#C4BCBE", "SmoothPlastic", 0.6),
		ball("Puff4", 0.28, { -0.2, -5.1, -0.1 }, "#D8D0D2", "SmoothPlastic", 0.65),
		ball("Spark1", 0.1, { 0.6, -4.25, 0.1 }, "#FFD23F", "Neon"),
		ball("Spark2", 0.08, { -0.65, -4.3, -0.1 }, "#FFB020", "Neon"),
		ball("Spark3", 0.09, { 0.05, -4.35, 0.6 }, "#FFD23F", "Neon")
	)
	add(
		back,
		cyl("BandHigh", 1.5, 0.1, { 0, 0.9, 1.1 }, S.accent(c), S.accentMat),
		cyl("BandLow", 1.5, 0.1, { 0, -0.2, 1.1 }, S.accent(c), S.accentMat),
		cyl("GaugeL", 0.36, 0.06, { -0.35, 1.2, 1.83 }, "#FFFFFF", "SmoothPlastic", { 90, 0, 0 }),
		cyl("GaugeR", 0.36, 0.06, { 0.35, 1.2, 1.83 }, "#FFFFFF", "SmoothPlastic", { 90, 0, 0 }),
		cyl("CollarL", 0.3, 0.1, { -0.5, 1.75, 0.95 }, S.accent(c), S.accentMat),
		cyl("CollarR", 0.3, 0.1, { 0.5, 1.75, 0.95 }, S.accent(c), S.accentMat),
		ball("CrystalL2", 0.2, { -0.3, 2.35, 0.95 }, "#FF8A2F", "Neon"),
		ball("CrystalR2", 0.2, { 0.3, 2.35, 0.95 }, "#FF8A2F", "Neon"),
		cyl("Valve", 0.5, 0.06, { 0, -0.3, 1.82 }, S.dark, "Metal", { 90, 0, 0 })
	)
end

-- Adds every detail part of tool `id` to `hand` / `back`. Unknown id: nothing.
function ToolDetails.add(
	id: string,
	S: ModelKit.Style,
	c: string,
	hand: { PartSpec },
	back: { PartSpec }
)
	local fn = details[id]
	if fn ~= nil then
		fn(S, c, hand, back)
	end
end

return ToolDetails
