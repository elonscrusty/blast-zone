--!strict
-- A lava pool: a glowing pond with a stone edge. Decor only (the builder never makes it hurt).
-- Base size: about 18 studs radius.
--   A  Stone Ring       rough dark stones around a pool, stepping stones and floating crust
--   B  Basalt Columns   a crowd of tall stone columns, a few stand inside as an island
--   C  Rock Bridge      a stone arch over the pool with lava drips
-- Parts in the "glow" group are the lava itself.

local Parts = require("./Parts")

local LavaPool = {}

LavaPool.variants = { "A", "B", "C" }
LavaPool.baseRadius = 18

local TAU = Parts.TAU
local ORANGE = "#FF6A1F"
local EMBER = "#FFC24D"
local LAVA = "#FF7A2F"

local function lava(list: Parts.List, r: number)
	Parts.disc(list, "PoolLava", 0, 0.6, 0, r * 2, 0.6, ORANGE, {
		material = "Neon",
		group = "glow",
		shadow = false,
	})
	Parts.disc(list, "PoolGlow", 0, 0.9, 0, r * 0.8, 0.4, EMBER, {
		material = "Neon",
		group = "glow",
		shadow = false,
	})
	for i = 1, 3 do
		local a = i * 2.1
		Parts.ball(
			list,
			`Bubble{i}`,
			{ math.cos(a) * r * 0.4, 1.4, math.sin(a) * r * 0.4 },
			2.4 + i * 0.6,
			EMBER,
			{ material = "Neon", group = "glow", shadow = false }
		)
	end
	Parts.fx(list, "embers", { 0, 1.5, 0 }, r * 0.7)
	Parts.fx(list, "smoke", { 0, 4, 0 }, r * 0.6)
end

local DARK = { "#5B4652", "#6A5360", "#4C3B46", "#7A6270" }

local function buildA(): Parts.List
	local list = Parts.new("LavaPool", "A")
	local r = 15
	lava(list, r)
	for i = 0, 13 do
		local a = i / 14 * TAU
		local w = 7 + Parts.rand(1, i) * 3
		local h = 3.5 + Parts.rand(2, i) * 3
		Parts.block(
			list,
			"EdgeStone",
			{ math.cos(a) * (r + 1.5), h / 2 - 0.4, math.sin(a) * (r + 1.5) },
			{ w, h, 5 + Parts.rand(3, i) * 2 },
			DARK[1 + i % #DARK],
			{
				rot = { 0, math.pi / 2 - a + (Parts.rand(4, i) - 0.5) * 0.4, 0 },
				material = "Basalt",
				collide = true,
			}
		)
	end
	-- stepping stones across the middle
	for i = 0, 3 do
		Parts.disc(
			list,
			"StepStone",
			-9 + i * 6,
			1.6,
			(i % 2 == 0) and -1.5 or 1.5,
			5 - i % 2,
			1,
			"#5A4650",
			{
				material = "Basalt",
			}
		)
	end
	-- crust plates drifting on the lava
	for i = 0, 2 do
		local a = i * 2.3 + 0.7
		Parts.block(
			list,
			"Crust",
			{ math.cos(a) * 7, 1.1, math.sin(a) * 7 },
			{ 4, 0.5, 3 },
			"#2E2229",
			{ rot = { 0, a, 0 }, material = "Basalt", shadow = false }
		)
	end
	return list
end

local function buildB(): Parts.List
	local list = Parts.new("LavaPool", "B")
	local r = 14
	lava(list, r)
	-- outer ring: tall hexagon-like columns, taller on the outside
	for i = 0, 17 do
		local a = i / 18 * TAU
		local h = 5 + Parts.rand(11, i) * 11
		local d = 4.2 + Parts.rand(12, i) * 1.4
		Parts.cyl(
			list,
			"Column",
			{ math.cos(a) * (r + 2.2), h / 2, math.sin(a) * (r + 2.2) },
			d,
			h,
			DARK[1 + i % #DARK],
			{ material = "Basalt", collide = true }
		)
		Parts.cyl(
			list,
			"ColumnCap",
			{ math.cos(a) * (r + 2.2), h + 0.2, math.sin(a) * (r + 2.2) },
			d * 0.8,
			0.5,
			"#6A5560",
			{ material = "Basalt", shadow = false }
		)
	end
	-- second, lower ring behind them
	for i = 0, 11 do
		local a = (i + 0.5) / 12 * TAU
		local h = 3 + Parts.rand(13, i) * 5
		Parts.cyl(
			list,
			"Column",
			{ math.cos(a) * (r + 6.2), h / 2, math.sin(a) * (r + 6.2) },
			5.4,
			h,
			DARK[1 + (i + 1) % #DARK],
			{ material = "Basalt", collide = true }
		)
	end
	-- a little island of short columns in the middle
	for i = 0, 5 do
		local a = i / 6 * TAU
		local rr = if i == 0 then 0 else 3.2
		local h = 1.8 + (i % 3) * 1.1
		Parts.cyl(
			list,
			"IslandColumn",
			{ math.cos(a) * rr, h / 2 + 0.4, math.sin(a) * rr },
			3.4,
			h,
			DARK[1 + i % #DARK],
			{ material = "Basalt" }
		)
	end
	return list
end

local function buildC(): Parts.List
	local list = Parts.new("LavaPool", "C")
	local r = 15
	lava(list, r)
	for i = 0, 9 do
		local a = i / 10 * TAU + 0.3
		Parts.ball(
			list,
			"EdgeRock",
			{ math.cos(a) * (r + 1.2), 1.6, math.sin(a) * (r + 1.2) },
			5.5 + Parts.rand(21, i) * 2.5,
			DARK[1 + i % #DARK],
			{ material = "Basalt", collide = true }
		)
	end
	-- the arch: two stout legs, a flat top stone and two corner braces
	local legH = 14
	for _, s in { -1, 1 } do
		Parts.block(
			list,
			"ArchLeg",
			{ s * (r + 1.5), legH / 2, 0 },
			{ 6, legH, 8 },
			"#6A5360",
			{ material = "Basalt", collide = true }
		)
		Parts.block(
			list,
			"ArchFoot",
			{ s * (r + 1.5), 2, 0 },
			{ 9, 4, 11 },
			"#5B4652",
			{ material = "Basalt", collide = true }
		)
		Parts.block(
			list,
			"ArchBrace",
			{ s * (r - 3), legH - 2.4, 0 },
			{ 7.5, 3, 7 },
			"#7A6270",
			{ rot = { 0, 0, s * -0.7 }, material = "Basalt" }
		)
	end
	Parts.block(
		list,
		"ArchTop",
		{ 0, legH + 1.7, 0 },
		{ 2 * (r + 4.5), 3.6, 8 },
		"#6A5360",
		{ material = "Basalt" }
	)
	-- lava drips hang from the arch into the pool
	for i = 0, 4 do
		local x = -9 + i * 4.5
		local len = 6 + Parts.rand(22, i) * 6
		Parts.block(
			list,
			"Drip",
			{ x, legH - len / 2, 0 },
			{ 1.1, len, 1.1 },
			LAVA,
			{ material = "Neon", group = "glow", shadow = false }
		)
		Parts.ball(
			list,
			"DripBlob",
			{ x, legH - len, 0 },
			2.2,
			EMBER,
			{ material = "Neon", group = "glow", shadow = false }
		)
	end
	return list
end

function LavaPool.spec(variant: string, scale: number?): Parts.List
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

return LavaPool
