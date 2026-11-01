--!strict
-- Camp: a tent, a fire ring with log seats, crates, a lantern and a broom leaning on a post.
-- A resting spot for the beach / forest zones. Footprint about 15 x 13 studs.

local Kit = require("./Kit")
local Styles = require("./Styles")

local Camp = {}

Camp.maxParts = 34

local V = Kit.v3
local TAU = math.pi * 2

local function firePit(m: Kit.Model, p: Styles.Palette, cx: number, cz: number)
	for i = 0, 5 do
		local a = i * TAU / 6
		Kit.block(
			m,
			"FireStone",
			V(cx + math.cos(a) * 1.7, 0.45, cz + math.sin(a) * 1.7),
			1.1,
			0.9,
			1.0,
			p.stone,
			{ rot = V(0, a, 0), mat = "Slate" }
		)
	end
	Kit.cyl(m, "Ash", V(cx, 0.1, cz), 3.0, 0.2, p.dark)
	Kit.cyl(
		m,
		"Log",
		V(cx, 0.6, cz),
		0.45,
		2.4,
		p.woodDark,
		{ mat = "Wood", rot = V(0, 0, math.pi / 2 - 0.15) }
	)
	Kit.cyl(
		m,
		"Log",
		V(cx, 0.75, cz),
		0.45,
		2.4,
		p.wood,
		{ mat = "Wood", rot = V(math.pi / 2 - 0.15, 0, 0) }
	)
	Kit.ball(m, "Flame", V(cx, 1.5, cz), 1.5, p.glow, { neon = true })
	Kit.ball(m, "FlameCore", V(cx, 1.3, cz), 0.8, p.glowAlt, { neon = true })
end

local function seats(m: Kit.Model, p: Styles.Palette, cx: number, cz: number)
	for i = 0, 2 do
		local a = 0.4 + i * TAU / 3.4
		Kit.cyl(
			m,
			"LogSeat",
			V(cx + math.cos(a) * 4.4, 0.55, cz + math.sin(a) * 4.4),
			1.1,
			3.0,
			p.wood,
			{ mat = "Wood", shadow = true, rot = V(0, math.pi / 2 - a, math.pi / 2) }
		)
	end
end

local function extras(m: Kit.Model, p: Styles.Palette)
	Kit.block(
		m,
		"Crate",
		V(5.8, 0.95, 3.2),
		1.9,
		1.9,
		1.9,
		p.wood,
		{ mat = "Wood", shadow = true, collide = true }
	)
	Kit.block(
		m,
		"Crate",
		V(5.6, 2.55, 3.2),
		1.4,
		1.4,
		1.4,
		p.woodLight,
		{ mat = "Wood", rot = V(0, 0.6, 0) }
	)
	Kit.ball(m, "AshSack", V(4.0, 0.9, 4.6), 1.8, "#BDB3A6", { shadow = true })
	Kit.post(m, "LanternPost", 6.2, 0, -2.0, 0.3, 5.0, p.woodDark, { mat = "Wood" })
	Kit.ball(m, "Lantern", V(6.2, 5.3, -2.0), 1.0, p.glowAlt, { neon = true })
	-- a broom leaning on the post
	Kit.pole(m, "BroomStick", V(-6.4, 0.3, -4.4), V(-5.2, 4.6, -4.4), 0.25, p.woodLight)
	Kit.block(m, "BroomHead", V(-6.6, 0.5, -4.4), 1.8, 0.7, 0.7, p.trim, { rot = V(0, 0, 0.25) })
end

local function toy(m: Kit.Model, p: Styles.Palette)
	Kit.gable(m, "Tent", -3.5, 0, 2.5, 7.2, 7.6, 5.2, p.roof, { shadow = true })
	Kit.gable(m, "TentStripe", -3.5, 0, 2.5, 7.3, 2.0, 5.25, p.white, {})
	Kit.block(m, "TentDoor", V(-3.5, 1.5, -1.36), 1.8, 3.0, 0.1, p.dark, {})
	Kit.ball(m, "TentKnob", V(-3.5, 5.4, 2.5), 0.9, p.trim)
	firePit(m, p, 3.0, -1.5)
	seats(m, p, 3.0, -1.5)
	extras(m, p)
end

local function tiki(m: Kit.Model, p: Styles.Palette)
	Kit.gable(m, "Thatch", -3.5, 1.0, 2.5, 8.4, 8.0, 4.2, p.roof, { mat = "Grass", shadow = true })
	for _, x in { -6.6, -0.4 } do
		for _, z in { -1.2, 6.2 } do
			Kit.post(m, "TentPole", x, 0, z, 0.55, 1.5, p.woodLight, { mat = "Wood" })
		end
	end
	Kit.block(m, "Hammock", V(-3.5, 1.1, 3.0), 5.0, 0.3, 1.6, p.cloth, { rot = V(0, 0, 0.05) })
	Kit.block(m, "TentDoor", V(-3.5, 0.5, 6.35), 6.0, 0.9, 0.2, p.woodDark, { mat = "Wood" })
	firePit(m, p, 3.0, -1.5)
	seats(m, p, 3.0, -1.5)
	extras(m, p)
end

local function basalt(m: Kit.Model, p: Styles.Palette)
	Kit.cyl(
		m,
		"Hut",
		V(-3.5, 1.6, 2.5),
		8.0,
		3.2,
		p.wall,
		{ mat = "Slate", shadow = true, collide = true }
	)
	Kit.cyl(m, "HutMid", V(-3.5, 4.0, 2.5), 6.0, 1.6, p.roofAlt, { mat = "Basalt", shadow = true })
	Kit.cyl(m, "HutTop", V(-3.5, 5.4, 2.5), 3.6, 1.4, p.roof, { mat = "Basalt" })
	Kit.ball(m, "HutGem", V(-3.5, 6.7, 2.5), 1.6, p.glowAlt, { neon = true })
	Kit.cyl(m, "HutRing", V(-3.5, 3.25, 2.5), 6.3, 0.25, p.glow, { neon = true })
	Kit.block(
		m,
		"TentDoor",
		V(-3.5, 1.4, -1.5),
		1.8,
		2.8,
		0.3,
		p.glowAlt,
		{ neon = true, alpha = 0.2 }
	)
	firePit(m, p, 3.0, -1.5)
	seats(m, p, 3.0, -1.5)
	extras(m, p)
end

function Camp.spec(params: Kit.Params?): Kit.Model
	local opts: Kit.Params = params or {}
	local style = Styles.get(opts.style)
	local m = Kit.new("Camp", style, 8, 7)
	local p = Styles.pal[style]
	if style == "tiki" then
		tiki(m, p)
	elseif style == "basalt" then
		basalt(m, p)
	else
		toy(m, p)
	end
	Kit.anchor(m, "fire", V(3.0, 0.8, -1.5))
	return m
end

return Camp
