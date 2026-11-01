--!strict
-- The big volcano, three looks. Pure part list (see Parts). Base size: about 90 studs wide at the
-- foot (radius) and 150 tall, so it reads from across a very large island.
--   A  Chunky Tiers   stacked toy steps, boulders at the foot, lava streaks down the steps
--   B  Faceted Peak   low-poly flat faces, glowing lava rivers, jagged crown
--   C  Dragon Crown   tall and steep, dark claws around the crater, floating rocks, a lava waterfall
-- Every look has the same invisible solid core ("ConeCollision") so nobody walks into the mountain,
-- a "glow" group (the crater lava the world may pulse) and smoke + ember fx over the crater.

local Parts = require("./Parts")

local BigVolcano = {}

BigVolcano.variants = { "A", "B", "C" }
BigVolcano.baseRadius = 90
BigVolcano.height = 150

local TAU = Parts.TAU
local LAVA = "#FF7A2F"
local ORANGE = "#FF6A1F"
local EMBER = "#FFC24D"

local function core(list: Parts.List, radius: number, height: number)
	Parts.cyl(
		list,
		"ConeCollision",
		{ 0, height / 2, 0 },
		radius * 2,
		height,
		"#FFFFFF",
		{ collide = true, transparency = 1, shadow = false }
	)
end

local function crater(list: Parts.List, y: number, lavaR: number)
	Parts.disc(list, "CraterLava", 0, y + 0.1, 0, lavaR * 2, 1, ORANGE, {
		material = "Neon",
		group = "glow",
		shadow = false,
	})
	Parts.disc(list, "CraterGlow", 0, y + 0.6, 0, lavaR * 1.1, 0.6, EMBER, {
		material = "Neon",
		group = "glow",
		shadow = false,
	})
	local spots = { { 7, 4 }, { -6, 8 }, { -2, -10 } }
	for i, s in spots do
		Parts.ball(
			list,
			`LavaBubble{i}`,
			{ s[1] * lavaR / 14, y + 1.2, s[2] * lavaR / 14 },
			3.4 + i,
			EMBER,
			{ material = "Neon", group = "glow", shadow = false }
		)
	end
	Parts.fx(list, "smoke", { 0, y + 8, 0 }, lavaR)
	Parts.fx(list, "embers", { 0, y + 2, 0 }, lavaR * 0.7)
end

-- ===== A: Chunky Tiers =====

local function buildA(): Parts.List
	local list = Parts.new("BigVolcano", "A")
	local count, tierH = 12, 11
	local baseR, topR = 88, 26
	local topY = count * tierH
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local r = topR + (baseR - topR) * (1 - t) ^ 1.5
		local color = Parts.lerpHex("#5E403E", "#C2492F", t ^ 0.9)
		if i % 2 == 1 then
			color = Parts.lerpHex(color, "#FFFFFF", 0.08)
		end
		Parts.cyl(list, `Tier{i + 1}`, { 0, i * tierH + tierH / 2, 0 }, r * 2, tierH, color, {
			material = "Basalt",
		})
	end
	-- boulders at the foot make a chunky skirt
	for i = 0, 11 do
		local a = i / 12 * TAU + Parts.rand(7, i) * 0.3
		local d = 12 + Parts.rand(8, i) * 12
		local r = baseR + 4 + Parts.rand(9, i) * 8
		Parts.ball(
			list,
			"Boulder",
			{ math.cos(a) * r, d * 0.3, math.sin(a) * r },
			d,
			Parts.lerpHex("#5A4048", "#7B5A58", Parts.rand(10, i)),
			{ material = "Basalt" }
		)
	end
	-- lava streaks hugging the steps
	for k = 0, 6 do
		local a = k / 7 * TAU + 0.2
		for i = 4, count - 1 do
			if Parts.rand(20 + k, i) < 0.8 then
				local t = i / (count - 1)
				local r = topR + (baseR - topR) * (1 - t) ^ 1.5 + 0.5
				Parts.block(
					list,
					"LavaStreak",
					{ math.cos(a) * r, i * tierH + tierH / 2, math.sin(a) * r },
					{ 5, tierH - 1, 1.2 },
					LAVA,
					{ rot = { 0, math.pi / 2 - a, 0 }, material = "Neon", shadow = false }
				)
			end
		end
	end
	-- three glowing puddles where streaks reach the ground
	for k = 0, 2 do
		local a = k / 3 * TAU + 0.2 + TAU / 7
		Parts.disc(
			list,
			"LavaPuddle",
			math.cos(a) * (baseR + 8),
			0.5,
			math.sin(a) * (baseR + 8),
			22,
			0.5,
			LAVA,
			{ material = "Neon", shadow = false }
		)
	end
	-- crater: dark rim, then the lava
	Parts.cyl(
		list,
		"CraterRim",
		{ 0, topY + 4, 0 },
		(topR + 1) * 2,
		8,
		"#4A2E34",
		{ material = "Basalt" }
	)
	crater(list, topY + 8, 22)
	core(list, baseR - 0.5, topY + 8)
	return list
end

-- ===== B: Faceted Peak =====

local function buildB(): Parts.List
	local list = Parts.new("BigVolcano", "B")
	local sides = 10
	-- (radius, height) of the corners of the mountain's profile, foot to rim
	local prof = { { 92, 0 }, { 64, 40 }, { 44, 86 }, { 31, 130 }, { 25, 146 } }
	for L = 1, #prof - 1 do
		local a, b = prof[L], prof[L + 1]
		local t = (L - 1) / (#prof - 2)
		local rm = (a[1] + b[1]) / 2
		local width = 2 * rm * math.tan(math.pi / sides) * 1.12 + 1.5
		for i = 0, sides - 1 do
			local ang = i / sides * TAU
			local base = Parts.lerpHex("#5A3F45", "#B8452E", t ^ 0.8)
			local color = Parts.lerpHex(base, if i % 2 == 0 then "#FFFFFF" else "#000000", 0.07)
			Parts.slab(list, `Face{L}`, a[1], a[2], b[1], b[2], ang, width, 3, color, 0, {
				material = "Slate",
			})
		end
	end
	-- jagged crown: leaning dark teeth around the rim
	for i = 0, 13 do
		local a = i / 14 * TAU
		local h = 9 + Parts.rand(31, i) * 8
		Parts.block(
			list,
			"CrownTooth",
			{ math.cos(a) * 24, 146 + h / 2 - 2, math.sin(a) * 24 },
			{ 8, h, 5 },
			"#3B2830",
			{
				rot = { 0.25, math.pi / 2 - a, 0.08 * (Parts.rand(32, i) - 0.5) * 6 },
				material = "Basalt",
			}
		)
	end
	-- glowing lava rivers lie on the faces (they follow the faces, a little bent)
	for k = 0, 4 do
		local ang = k / 5 * TAU + 0.31
		for L = 1, #prof - 1 do
			local a, b = prof[L], prof[L + 1]
			local bend = (Parts.rand(40 + k, L) - 0.5) * 0.12
			Parts.slab(list, "LavaRiver", a[1], a[2], b[1], b[2], ang + bend, 4.5, 0.8, LAVA, 1.9, {
				material = "Neon",
				shadow = false,
			})
		end
		Parts.disc(
			list,
			"LavaPuddle",
			math.cos(ang) * 99,
			0.5,
			math.sin(ang) * 99,
			16,
			0.5,
			LAVA,
			{ material = "Neon", shadow = false }
		)
	end
	crater(list, 144, 20)
	core(list, 89.5, 146)
	return list
end

-- ===== C: Dragon Crown =====

local function buildC(): Parts.List
	local list = Parts.new("BigVolcano", "C")
	local count, tierH = 9, 15
	local baseR, topR = 84, 26
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local r = topR + (baseR - topR) * (1 - t) ^ 1.35
		local color = Parts.lerpHex("#4A3A52", "#9E433E", t ^ 1.1)
		Parts.cyl(list, `Tier{i + 1}`, { 0, i * tierH + tierH / 2, 0 }, r * 2, tierH, color, {
			material = "Slate",
		})
	end
	local topY = count * tierH
	Parts.cyl(
		list,
		"CraterRim",
		{ 0, topY + 3, 0 },
		(topR + 2) * 2,
		6,
		"#2A1F2E",
		{ material = "Basalt" }
	)
	crater(list, topY + 6, 21)
	-- six dark claws curl in over the crater: a leaning base and a thinner tip leaning further in
	for i = 0, 5 do
		local a = i / 6 * TAU + 0.5
		local cx, cz = math.cos(a), math.sin(a)
		Parts.block(
			list,
			"ClawLow",
			{ cx * 29, topY + 15, cz * 29 },
			{ 8, 30, 7 },
			"#3A2B44",
			{ rot = { 0.2, math.pi / 2 - a, 0 }, material = "Basalt" }
		)
		Parts.block(
			list,
			"ClawTip",
			{ cx * 23, topY + 41, cz * 23 },
			{ 5, 26, 5 },
			"#2A1F34",
			{ rot = { -0.45, math.pi / 2 - a, 0 }, material = "Basalt" }
		)
		Parts.block(
			list,
			"ClawGlow",
			{ cx * 25.6, topY + 18, cz * 25.6 },
			{ 1.8, 22, 1.8 },
			LAVA,
			{ rot = { 0.2, math.pi / 2 - a, 0 }, material = "Neon", shadow = false }
		)
	end
	-- a light column and floating rocks over the crater
	Parts.cyl(list, "CraterBeam", { 0, topY + 40, 0 }, 9, 70, EMBER, {
		material = "Neon",
		transparency = 0.7,
		group = "glow",
		shadow = false,
	})
	for i = 0, 4 do
		local a = i / 5 * TAU
		local h = topY + 54 + Parts.rand(51, i) * 20
		local r = 12 + Parts.rand(52, i) * 10
		Parts.block(
			list,
			"FloatRock",
			{ math.cos(a) * r, h, math.sin(a) * r },
			{ 9, 7, 8 },
			"#3B2830",
			{
				rot = { Parts.rand(53, i), Parts.rand(54, i) * 3, Parts.rand(55, i) },
				material = "Basalt",
			}
		)
		Parts.ball(
			list,
			"FloatCore",
			{ math.cos(a) * r, h - 0.5, math.sin(a) * r },
			3.5,
			EMBER,
			{ material = "Neon", shadow = false, group = "glow" }
		)
	end
	-- lava waterfall down one side into a lake at the foot
	local fa = math.pi * 0.25
	local fx, fz = math.cos(fa), math.sin(fa)
	for i = 2, count - 1 do
		local t = i / (count - 1)
		local r = topR + (baseR - topR) * (1 - t) ^ 1.35 + 0.6
		Parts.block(
			list,
			"LavaFall",
			{ fx * r, i * tierH + tierH / 2, fz * r },
			{ 11, tierH - 1, 1.4 },
			LAVA,
			{ rot = { 0, math.pi / 2 - fa, 0 }, material = "Neon", shadow = false, group = "glow" }
		)
	end
	Parts.block(
		list,
		"LavaSpill",
		{ fx * (baseR + 3), 5, fz * (baseR + 3) },
		{ 11, 10, 1.4 },
		LAVA,
		{ rot = { 0, math.pi / 2 - fa, 0 }, material = "Neon", shadow = false }
	)
	Parts.disc(
		list,
		"LavaLake",
		fx * (baseR + 22),
		0.5,
		fz * (baseR + 22),
		58,
		0.5,
		ORANGE,
		{ material = "Neon", shadow = false, group = "glow" }
	)
	for i = 1, 4 do
		local a = i * 1.6
		Parts.ball(
			list,
			"LakeBubble",
			{ fx * (baseR + 22) + math.cos(a) * 12, 1, fz * (baseR + 22) + math.sin(a) * 12 },
			4 + i * 0.5,
			EMBER,
			{ material = "Neon", shadow = false }
		)
	end
	Parts.fx(list, "embers", { fx * (baseR + 22), 2, fz * (baseR + 22) }, 18)
	core(list, baseR - 0.5, topY + 6)
	return list
end

function BigVolcano.spec(variant: string, scale: number?): Parts.List
	local list: Parts.List
	if variant == "B" then
		list = buildB()
	elseif variant == "C" then
		list = buildC()
	else
		list = buildA()
	end
	return Parts.scale(list, scale or 1)
end

return BigVolcano
