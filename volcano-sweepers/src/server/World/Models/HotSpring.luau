--!strict
-- A hot spring: warm blue water, steam, pink rocks. Base size: about 18 studs radius.
--   A  Terraces       three stacked basins with little waterfalls between them
--   B  Crystal Pond   one round pool ringed with glowing crystals
--   C  Geyser Deck    a pool with a rock chimney, a water jet and a wooden deck with a shelter
-- Parts in the "glow" group are the water surfaces.

local Parts = require("./Parts")

local HotSpring = {}

HotSpring.variants = { "A", "B", "C" }
HotSpring.baseRadius = 18

local TAU = Parts.TAU
local WATER = "#45C8F5"
local PINK = { "#FF9EC7", "#FF7AB8", "#F7B6D8" }

local function water(list: Parts.List, name: string, x: number, topY: number, z: number, r: number)
	Parts.disc(list, name, x, topY, z, r * 2, 0.3, WATER, {
		transparency = 0.15,
		group = "glow",
		shadow = false,
		material = "Glass",
	})
end

local function buildA(): Parts.List
	local list = Parts.new("HotSpring", "A")
	local levels = { { 17, 3 }, { 12, 6 }, { 7.5, 9 } } -- radius, top height of each basin
	for i, lv in levels do
		local r, top = lv[1], lv[2]
		-- stone body, then a glowing lip, then the water
		Parts.cyl(list, `Basin{i}`, { 0, top / 2 - 0.2, 0 }, r * 2 + 3, top - 0.4, "#F7D4DF", {
			material = "Marble",
			collide = i == 1,
		})
		Parts.disc(list, `Lip{i}`, 0, top, 0, r * 2 + 1.4, 0.5, "#7DF0FF", {
			material = "Neon",
			shadow = false,
		})
		water(list, `Water{i}`, 0, top + 0.15, 0, r)
	end
	-- little waterfalls over the lips
	for i = 1, 2 do
		for k = 0, 3 do
			local a = k / 4 * TAU + i
			local r = levels[i][1] + 1.5
			Parts.block(
				list,
				"Fall",
				{ math.cos(a) * r, levels[i][2] - 1.4, math.sin(a) * r },
				{ 2.2, levels[i][2] - 1, 0.5 },
				WATER,
				{
					rot = { 0, math.pi / 2 - a, 0 },
					transparency = 0.3,
					shadow = false,
					material = "Glass",
				}
			)
		end
	end
	for i = 0, 7 do
		local a = i / 8 * TAU + 0.2
		local d = 4 + Parts.rand(61, i) * 3.5
		Parts.ball(
			list,
			"PinkRock",
			{ math.cos(a) * 21, d * 0.3, math.sin(a) * 21 },
			d,
			PINK[1 + i % #PINK],
			{ material = "Rock", collide = true }
		)
	end
	Parts.fx(list, "steam", { 0, 11, 0 }, 7)
	Parts.fx(list, "steam", { 4, 4, 5 }, 7)
	return list
end

local function buildB(): Parts.List
	local list = Parts.new("HotSpring", "B")
	local r = 14
	Parts.disc(
		list,
		"PoolRim",
		0,
		0.5,
		0,
		r * 2 + 4,
		0.5,
		"#7DF0FF",
		{ material = "Neon", shadow = false }
	)
	water(list, "PoolWater", 0, 0.7, 0, r)
	for i = 0, 13 do
		local a = i / 14 * TAU
		local d = 5 + Parts.rand(71, i) * 2.5
		Parts.ball(
			list,
			"RimRock",
			{ math.cos(a) * (r + 2.5), d * 0.28, math.sin(a) * (r + 2.5) },
			d,
			PINK[1 + i % #PINK],
			{ material = "Rock", collide = true }
		)
	end
	-- crystal clusters: tall tilted glass spikes
	local glass = { "#9FF7FF", "#FFB3E6", "#B9A6FF" }
	for i = 0, 8 do
		local a = i / 9 * TAU + 0.35
		local cx, cz = math.cos(a) * (r + 4), math.sin(a) * (r + 4)
		local h = 9 + Parts.rand(72, i) * 8
		Parts.block(list, "Crystal", { cx, h / 2, cz }, { 3, h, 3 }, glass[1 + i % #glass], {
			rot = { -0.22, math.pi / 2 - a, 0.18 },
			material = "Glass",
			transparency = 0.25,
			shadow = false,
		})
		Parts.block(
			list,
			"CrystalSmall",
			{ cx + math.cos(a + 1.2) * 2.4, h * 0.3, cz + math.sin(a + 1.2) * 2.4 },
			{ 2, h * 0.6, 2 },
			glass[1 + (i + 1) % #glass],
			{ rot = { 0.3, a, -0.25 }, material = "Glass", transparency = 0.25, shadow = false }
		)
	end
	-- the big middle crystal sits on a rock
	Parts.ball(list, "CentreRock", { 0, 0.8, 0 }, 7, "#F7B6D8", { material = "Rock" })
	Parts.block(list, "BigCrystal", { 0, 11, 0 }, { 5, 22, 5 }, "#9FF7FF", {
		rot = { 0, 0.6, 0.08 },
		material = "Glass",
		transparency = 0.2,
		group = "glow",
		shadow = false,
	})
	Parts.fx(list, "steam", { 0, 2, 0 }, 11)
	return list
end

local function buildC(): Parts.List
	local list = Parts.new("HotSpring", "C")
	local r = 15
	Parts.disc(list, "PoolRim", 0, 0.5, 0, r * 2 + 3, 0.5, "#F7D4DF", { material = "Marble" })
	water(list, "PoolWater", 0, 0.7, 0, r)
	for i = 0, 11 do
		local a = i / 12 * TAU
		if not (a > 3.4 and a < 4.6) then -- leave a gap for the deck
			local d = 4.6 + Parts.rand(81, i) * 2
			Parts.ball(
				list,
				"RimRock",
				{ math.cos(a) * (r + 1.8), d * 0.3, math.sin(a) * (r + 1.8) },
				d,
				PINK[1 + i % #PINK],
				{ material = "Rock", collide = true }
			)
		end
	end
	-- rock chimney with a water jet
	Parts.cyl(list, "Chimney1", { 0, 2, 0 }, 9, 4, "#E8A6C4", { material = "Rock", collide = true })
	Parts.cyl(list, "Chimney2", { 0, 5, 0 }, 6, 3, "#F7B6D8", { material = "Rock", collide = true })
	Parts.cyl(list, "Jet", { 0, 16, 0 }, 3, 20, "#BFEFFF", {
		transparency = 0.35,
		material = "Glass",
		group = "glow",
		shadow = false,
	})
	Parts.ball(list, "JetTop", { 0, 27, 0 }, 7, "#E8FAFF", {
		transparency = 0.3,
		material = "Glass",
		group = "glow",
		shadow = false,
	})
	for i = 0, 5 do
		local a = i / 6 * TAU
		Parts.ball(
			list,
			"Drop",
			{ math.cos(a) * 6.5, 20 - (i % 2) * 5, math.sin(a) * 6.5 },
			2,
			"#BFEFFF",
			{ transparency = 0.3, material = "Glass", shadow = false }
		)
	end
	-- wooden deck leading out to a shelter
	for i = 0, 5 do
		Parts.block(
			list,
			"Plank",
			{ 0.7 * (i % 2) - 0.3, 0.9, -(r + 3) - i * 2.4 },
			{ 7.4, 0.7, 2.2 },
			(i % 2 == 0) and "#C98A4B" or "#D99C5B",
			{ material = "WoodPlanks", collide = true }
		)
	end
	local sz = -(r + 3) - 14.5
	for _, sx in { -3.6, 3.6 } do
		for _, dz in { -3, 3 } do
			Parts.cyl(
				list,
				"Post",
				{ sx, 4.5, sz + dz },
				0.9,
				7.6,
				"#8A5A3C",
				{ material = "Wood" }
			)
		end
	end
	Parts.block(list, "ShelterRoofA", { -2.7, 8.8, sz }, { 5, 0.7, 8.4 }, "#FF7A59", {
		rot = { 0, 0, -0.45 },
	})
	Parts.block(list, "ShelterRoofB", { 2.7, 8.8, sz }, { 5, 0.7, 8.4 }, "#FF7A59", {
		rot = { 0, 0, 0.45 },
	})
	Parts.block(
		list,
		"Bench",
		{ 0, 2.2, sz - 2.4 },
		{ 6, 0.7, 1.6 },
		"#8A5A3C",
		{ material = "Wood" }
	)
	Parts.fx(list, "steam", { 0, 2, 0 }, 11)
	Parts.fx(list, "spray", { 0, 28, 0 }, 4)
	return list
end

function HotSpring.spec(variant: string, scale: number?): Parts.List
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

return HotSpring
