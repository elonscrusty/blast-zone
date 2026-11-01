--!strict
-- A lighthouse for the beach. About 72 studs tall, 9 studs radius at the foot. The sweeping light is
-- in the "beam" group (the world may spin it around List.pivots.beam); the lamp itself is "glow".
--   A  Classic Stripes   red and white tower, round lantern room, red cap
--   B  Stone Watchtower  eight stone faces, copper dome, stone steps
--   C  Pier Beacon       a wooden frame tower on a pier, a hanging lantern, a peaked roof

local Parts = require("./Parts")

local Lighthouse = {}

Lighthouse.variants = { "A", "B", "C" }
Lighthouse.baseRadius = 10
Lighthouse.height = 72

local TAU = Parts.TAU
local LAMP = "#FFE27A"

local function beam(list: Parts.List, y: number)
	list.pivots.beam = { 0, y, 0 }
	for _, s in { -1, 1 } do
		Parts.block(
			list,
			"BeamLong",
			{ s * 28, y, 0 },
			{ 50, 2.4, 5 },
			"#FFF3B0",
			{ material = "Neon", transparency = 0.8, group = "beam", shadow = false }
		)
		Parts.block(
			list,
			"BeamCore",
			{ s * 21, y, 0 },
			{ 36, 1.4, 2.4 },
			"#FFFFFF",
			{ material = "Neon", transparency = 0.5, group = "beam", shadow = false }
		)
	end
end

local function rocks(list: Parts.List, r: number, n: number)
	for i = 0, n - 1 do
		local a = i / n * TAU + 0.2
		local d = 7 + Parts.rand(91, i) * 5
		Parts.ball(
			list,
			"BaseRock",
			{ math.cos(a) * r, d * 0.25, math.sin(a) * r },
			d,
			Parts.lerpHex("#8D8E94", "#B9B7B4", Parts.rand(92, i)),
			{ material = "Slate", collide = true }
		)
	end
end

local function buildA(): Parts.List
	local list = Parts.new("Lighthouse", "A")
	rocks(list, 10, 8)
	local rows = 5
	local rowH = 9
	for i = 0, rows - 1 do
		local t = i / (rows - 1)
		local d = 17 - t * 6
		Parts.cyl(
			list,
			`Tower{i + 1}`,
			{ 0, 2 + i * rowH + rowH / 2, 0 },
			d,
			rowH,
			(i % 2 == 0) and "#F4F1EA" or "#E8453C",
			{ material = "SmoothPlastic", collide = true }
		)
	end
	local top = 2 + rows * rowH
	-- door and windows
	Parts.block(list, "Door", { 0, 6.5, -8.2 }, { 3.4, 6, 1 }, "#5A3A2A", { material = "Wood" })
	for i = 1, 3 do
		local a = i * 2.1
		local y = 2 + i * rowH + 3
		local r = (17 - (i / (rows - 1)) * 6) / 2
		Parts.block(
			list,
			"Window",
			{ math.cos(a) * r, y, math.sin(a) * r },
			{ 1.8, 3, 1 },
			"#2B3A55",
			{ rot = { 0, math.pi / 2 - a, 0 }, shadow = false }
		)
	end
	-- gallery with a rail
	Parts.cyl(list, "Gallery", { 0, top + 0.5, 0 }, 16, 1.4, "#2B2230", { material = "Metal" })
	for i = 0, 15 do
		local a = i / 16 * TAU
		Parts.cyl(
			list,
			"RailPost",
			{ math.cos(a) * 7.4, top + 2.4, math.sin(a) * 7.4 },
			0.5,
			3.2,
			"#2B2230",
			{ material = "Metal", shadow = false }
		)
	end
	Parts.cyl(list, "RailTop", { 0, top + 4, 0 }, 15.4, 0.4, "#2B2230", {
		material = "Metal",
		transparency = 0.5,
		shadow = false,
	})
	-- lantern room
	Parts.cyl(list, "LanternGlass", { 0, top + 5.2, 0 }, 8.4, 7.6, "#CFEFFF", {
		material = "Glass",
		transparency = 0.5,
		shadow = false,
	})
	Parts.ball(list, "Lamp", { 0, top + 5.2, 0 }, 4.6, LAMP, {
		material = "Neon",
		group = "glow",
		shadow = false,
	})
	for i = 0, 3 do
		local a = i / 4 * TAU + 0.78
		Parts.cyl(
			list,
			"LanternPost",
			{ math.cos(a) * 4.1, top + 5.2, math.sin(a) * 4.1 },
			0.7,
			7.8,
			"#E8453C",
			{ shadow = false }
		)
	end
	-- red cap
	Parts.cyl(list, "Cap1", { 0, top + 9.6, 0 }, 10.4, 1.6, "#E8453C")
	Parts.cyl(list, "Cap2", { 0, top + 11.2, 0 }, 7.4, 1.6, "#E8453C")
	Parts.cyl(list, "Cap3", { 0, top + 12.8, 0 }, 4.2, 1.6, "#E8453C")
	Parts.ball(list, "CapTop", { 0, top + 14.2, 0 }, 2.4, "#FFD23F", { material = "Metal" })
	beam(list, top + 5.2)
	return list
end

local function buildB(): Parts.List
	local list = Parts.new("Lighthouse", "B")
	rocks(list, 11, 10)
	-- steps up to the door
	for i = 0, 3 do
		Parts.block(
			list,
			"Step",
			{ 0, 0.8 + i * 1.2, -12 + i * 1.8 },
			{ 6, 1.2, 2 },
			"#B9B7B4",
			{ material = "Slate", collide = true }
		)
	end
	-- eight stone faces, narrowing upwards
	local sides = 8
	local r0, r1, y0, y1 = 9.5, 6, 2, 52
	for i = 0, sides - 1 do
		local a = i / sides * TAU + TAU / 16
		local w = 2 * (r0 + r1) / 2 * math.tan(math.pi / sides) * 1.1 + 1
		Parts.slab(
			list,
			"StoneFace",
			r0,
			y0,
			r1,
			y1,
			a,
			w,
			2.6,
			(i % 2 == 0) and "#C9C5BD" or "#B7B2A9",
			0,
			{
				material = "Slate",
				collide = true,
			}
		)
	end
	Parts.cyl(
		list,
		"InnerCore",
		{ 0, 27, 0 },
		9,
		50,
		"#A9A59D",
		{ material = "Slate", collide = true }
	)
	-- stone bands every so often
	for i = 1, 4 do
		local y = 2 + i * 10
		local r = r0 + (r1 - r0) * ((y - y0) / (y1 - y0))
		Parts.cyl(list, "Band", { 0, y, 0 }, r * 2 + 1.2, 1.2, "#8E8A82", { material = "Slate" })
	end
	Parts.block(
		list,
		"Door",
		{ 0, 5, -9.6 },
		{ 3.4, 6.4, 1.2 },
		"#6B3E2A",
		{ material = "Wood", rot = { 0.1, 0, 0 } }
	)
	for i = 0, 2 do
		local a = 0.6 + i * 2.1
		local y = 20 + i * 11
		local r = r0 + (r1 - r0) * ((y - y0) / (y1 - y0)) - 0.1
		Parts.block(
			list,
			"Slit",
			{ math.cos(a) * r, y, math.sin(a) * r },
			{ 1.2, 4, 1 },
			"#1F2430",
			{ rot = { 0, math.pi / 2 - a, 0 }, shadow = false }
		)
	end
	-- top deck, lantern room, copper dome
	Parts.cyl(list, "Deck", { 0, 52.6, 0 }, 17, 1.8, "#8E8A82", { material = "Slate" })
	Parts.cyl(list, "Parapet", { 0, 54.2, 0 }, 16.4, 1.2, "#A9A59D", { material = "Slate" })
	Parts.cyl(list, "LanternGlass", { 0, 58.5, 0 }, 9.5, 7.6, "#CFEFFF", {
		material = "Glass",
		transparency = 0.5,
		shadow = false,
	})
	Parts.ball(
		list,
		"Lamp",
		{ 0, 58.5, 0 },
		5,
		LAMP,
		{ material = "Neon", group = "glow", shadow = false }
	)
	for i = 0, 5 do
		local a = i / 6 * TAU
		Parts.cyl(
			list,
			"LanternPost",
			{ math.cos(a) * 4.6, 58.5, math.sin(a) * 4.6 },
			0.8,
			7.8,
			"#6B7B78",
			{ material = "Metal", shadow = false }
		)
	end
	Parts.cyl(list, "DomeBase", { 0, 62.6, 0 }, 11.4, 1.6, "#5E9C8C", { material = "Metal" })
	Parts.ball(list, "Dome", { 0, 62.4, 0 }, 10.6, "#6FB7A5", { material = "Metal" })
	Parts.cyl(list, "Spike", { 0, 69, 0 }, 0.8, 5.5, "#E8C75A", { material = "Metal" })
	beam(list, 58.5)
	return list
end

local function buildC(): Parts.List
	local list = Parts.new("Lighthouse", "C")
	-- a pier running out to sea along +X
	for i = 0, 9 do
		Parts.block(
			list,
			"PierPlank",
			{ 8 + i * 2.4, 1.5, 0 },
			{ 2.2, 0.6, 8 },
			(i % 2 == 0) and "#B77A44" or "#C98A4B",
			{ material = "WoodPlanks", collide = true }
		)
	end
	for i = 0, 3 do
		for _, s in { -3.6, 3.6 } do
			Parts.cyl(
				list,
				"PierPost",
				{ 10 + i * 6.4, 0.2, s },
				1,
				6,
				"#6E4A2E",
				{ material = "Wood" }
			)
		end
	end
	-- a stone footing and four legs that lean in a little
	Parts.cyl(
		list,
		"Footing",
		{ 0, 1.2, 0 },
		19,
		2.4,
		"#9B968E",
		{ material = "Slate", collide = true }
	)
	local legH = 40
	local rBottom, rTop = 8.2, 5.2
	local tilt = math.atan2(rBottom - rTop, legH)
	for i = 0, 3 do
		local a = i / 4 * TAU + math.pi / 4
		local rm = (rBottom + rTop) / 2
		Parts.block(
			list,
			"Leg",
			{ math.cos(a) * rm, 2.4 + legH / 2, math.sin(a) * rm },
			{ 1.8, legH / math.cos(tilt), 1.8 },
			"#8A5A3C",
			{ rot = { -tilt, math.pi / 2 - a, 0 }, material = "Wood", collide = true }
		)
	end
	-- square braces at three heights
	for lv = 1, 3 do
		local y = 2.4 + lv * 10
		local half = (rBottom - (rBottom - rTop) * (y - 2.4) / legH) * 0.7071
		for k = 0, 3 do
			local b = k * math.pi / 2
			local alongZ = k % 2 == 0
			Parts.block(
				list,
				"Brace",
				{ math.cos(b) * half, y, math.sin(b) * half },
				if alongZ then { 0.9, 0.9, half * 2 } else { half * 2, 0.9, 0.9 },
				"#6E4A2E",
				{ material = "Wood" }
			)
		end
	end
	-- platform, lantern hut, peaked roof
	local top = 2.4 + legH
	Parts.block(
		list,
		"Platform",
		{ 0, top + 0.5, 0 },
		{ 12, 1.2, 12 },
		"#C98A4B",
		{ material = "WoodPlanks", collide = true }
	)
	Parts.block(list, "HutBack", { 0, top + 4.2, 4.6 }, { 9, 6.4, 0.9 }, "#E8D6B0")
	Parts.block(list, "HutLeft", { -4.6, top + 4.2, 0 }, { 0.9, 6.4, 9 }, "#E8D6B0")
	Parts.block(list, "HutRight", { 4.6, top + 4.2, 0 }, { 0.9, 6.4, 9 }, "#E8D6B0")
	Parts.block(list, "HutFront", { 0, top + 4.2, -4.6 }, { 9, 6.4, 0.9 }, "#CFEFFF", {
		material = "Glass",
		transparency = 0.5,
		shadow = false,
	})
	Parts.ball(
		list,
		"Lamp",
		{ 0, top + 4.4, 0 },
		4.4,
		LAMP,
		{ material = "Neon", group = "glow", shadow = false }
	)
	Parts.block(
		list,
		"RoofL",
		{ -3.3, top + 9.7, 0 },
		{ 6.6, 0.9, 11.4 },
		"#E8453C",
		{ rot = { 0, 0, 0.62 } }
	)
	Parts.block(
		list,
		"RoofR",
		{ 3.3, top + 9.7, 0 },
		{ 6.6, 0.9, 11.4 },
		"#E8453C",
		{ rot = { 0, 0, -0.62 } }
	)
	Parts.cyl(list, "FlagPole", { 0, top + 14, 0 }, 0.5, 6, "#6E4A2E", { material = "Wood" })
	Parts.block(
		list,
		"Flag",
		{ 1.8, top + 15.6, 0 },
		{ 3.4, 1.8, 0.3 },
		"#FFD23F",
		{ shadow = false }
	)
	-- railing round the platform
	for _, s in { -1, 1 } do
		Parts.block(
			list,
			"RailX",
			{ 0, top + 2.2, s * 6 },
			{ 12, 0.5, 0.5 },
			"#6E4A2E",
			{ material = "Wood", shadow = false }
		)
		Parts.block(
			list,
			"RailZ",
			{ s * 6, top + 2.2, 0 },
			{ 0.5, 0.5, 12 },
			"#6E4A2E",
			{ material = "Wood", shadow = false }
		)
	end
	-- a lantern hanging off the pier end
	Parts.cyl(list, "LampPost", { 31, 5.5, 0 }, 0.7, 9, "#6E4A2E", { material = "Wood" })
	Parts.ball(
		list,
		"PierLamp",
		{ 31, 10.4, 0 },
		2.6,
		LAMP,
		{ material = "Neon", group = "glow", shadow = false }
	)
	beam(list, top + 4.4)
	return list
end

function Lighthouse.spec(variant: string, scale: number?): Parts.List
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

return Lighthouse
