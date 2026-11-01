--!strict
-- Trade Hut: the shop on the beach where players sell ash. Pure spec (Lune can run it).
-- Footprint about 15 x 13 studs, 12 tall; the counter faces -Z. Wiring code hangs the sell prompt on
-- the part named "Counter" (anchor "sell") and can use anchor "sign" for a billboard.

local Kit = require("./Kit")
local Styles = require("./Styles")

local TradeHut = {}

TradeHut.maxParts = 48

local V = Kit.v3

local function toy(m: Kit.Model, p: Styles.Palette, text: string)
	Kit.block(m, "Base", V(0, 0.25, -0.5), 15.5, 0.5, 12.5, p.stone, { collide = true })
	Kit.block(m, "Body", V(0, 4.2, 2), 12, 7.4, 7, p.wall, { collide = true, shadow = true })
	Kit.gable(m, "Roof", 0, 7.9, 2, 14.8, 9.6, 3.8, p.roof, { shadow = true })
	Kit.ball(m, "Beacon", V(0, 12.1, 2), 1.1, p.glow, { neon = true })
	Kit.block(
		m,
		"CounterBody",
		V(0, 1.9, -3.4),
		11,
		2.8,
		2.2,
		p.roofAlt,
		{ collide = true, shadow = true }
	)
	Kit.block(m, "Counter", V(0, 3.45, -3.5), 12, 0.4, 3, p.woodLight, { collide = true })
	Kit.anchor(m, "sell", V(0, 3.9, -3.5))
	for i = 0, 5 do
		local c = if i % 2 == 0 then p.cloth else p.clothAlt
		Kit.block(
			m,
			"Awning",
			V(-5 + i * 2, 5.0, -3.75),
			2.02,
			0.3,
			4.7,
			c,
			{ shadow = true, rot = V(-0.26, 0, 0) }
		)
		Kit.ball(m, "Scallop", V(-5 + i * 2, 4.5, -5.95), 1.15, c)
	end
	for _, side in { -1, 1 } do
		Kit.post(m, "AwningPost", side * 5.9, 0.5, -5.9, 0.5, 4.1, p.woodDark)
		Kit.block(m, "Window", V(side * 6.05, 4.4, 2), 0.2, 2.2, 2.2, p.glow, { neon = true })
	end
	Kit.block(
		m,
		"Sign",
		V(0, 7.0, -1.75),
		8.2,
		1.6,
		0.4,
		p.dark,
		{ shadow = true, text = text, textColor = p.gold }
	)
	Kit.anchor(m, "sign", V(0, 7.0, -2.1))
	-- props
	Kit.post(m, "Barrel", -7.6, 0.5, -1.2, 2.0, 2.2, p.wood, { shadow = true })
	Kit.post(m, "BarrelBand", -7.6, 1.4, -1.2, 2.1, 0.25, p.woodDark)
	Kit.block(m, "Crate", V(7.5, 1.4, -2.0), 1.9, 1.9, 1.9, p.wood, { shadow = true })
	Kit.block(m, "Crate", V(7.5, 3.2, -2.0), 1.5, 1.5, 1.5, p.woodLight, { rot = V(0, 0.5, 0) })
	Kit.ball(m, "AshSack", V(-7.4, 1.5, -3.6), 1.9, "#BDB3A6", { shadow = true })
	Kit.ball(m, "AshSackTie", V(-7.4, 2.6, -3.6), 0.55, p.cloth)
	for i = 0, 2 do
		Kit.cyl(m, "Coin", V(4.2, 3.8 + i * 0.22, -3.5), 1.3, 0.2, p.gold)
	end
end

local function tiki(m: Kit.Model, p: Styles.Palette, text: string)
	Kit.block(
		m,
		"Deck",
		V(0, 0.4, -0.5),
		15,
		0.8,
		12.5,
		p.woodDark,
		{ mat = "Wood", collide = true }
	)
	Kit.block(
		m,
		"BackWall",
		V(0, 3.3, 5.2),
		12.6,
		5,
		0.8,
		p.wall,
		{ mat = "Wood", collide = true, shadow = true }
	)
	for _, side in { -1, 1 } do
		Kit.block(
			m,
			"SideWall",
			V(side * 6.1, 3.3, 2),
			0.8,
			5,
			6.8,
			p.wallDark,
			{ mat = "Wood", collide = true, shadow = true }
		)
		Kit.post(
			m,
			"BackPole",
			side * 6.4,
			0.8,
			5.2,
			1.0,
			5.4,
			p.woodLight,
			{ collide = true, shadow = true }
		)
		Kit.post(
			m,
			"FrontPole",
			side * 6.6,
			0.8,
			-5.9,
			1.1,
			5.2,
			p.woodLight,
			{ collide = true, shadow = true }
		)
		-- torch
		Kit.post(m, "Torch", side * 8.1, 0.0, -6.6, 0.45, 3.8, p.woodDark)
		Kit.cyl(m, "TorchBowl", V(side * 8.1, 3.95, -6.6), 1.1, 0.5, p.stoneDark)
		Kit.ball(m, "Flame", V(side * 8.1, 4.8, -6.6), 1.2, p.glow, { neon = true })
		Kit.ball(m, "FlameCore", V(side * 8.1, 4.95, -6.6), 0.6, p.glowAlt, { neon = true })
	end
	Kit.gable(m, "Thatch", 0, 5.8, -0.5, 17.4, 14, 4.8, p.roof, { mat = "Grass", shadow = true })
	for i = 0, 6 do
		Kit.block(
			m,
			"Fringe",
			V(-6 + i * 2, 5.5, -7.55),
			1.9,
			0.9,
			0.4,
			if i % 2 == 0 then p.roofAlt else p.roof,
			{ mat = "Grass" }
		)
	end
	Kit.block(
		m,
		"CounterBody",
		V(0, 1.9, -3.6),
		11,
		2.2,
		2,
		p.wood,
		{ mat = "Wood", collide = true, shadow = true }
	)
	Kit.block(
		m,
		"Counter",
		V(0, 3.1, -3.8),
		12.2,
		0.35,
		2.9,
		p.woodLight,
		{ mat = "Wood", collide = true }
	)
	Kit.anchor(m, "sell", V(0, 3.6, -3.8))
	Kit.cyl(
		m,
		"Beam",
		V(0, 5.5, -5.9),
		0.6,
		13.4,
		p.wood,
		{ rot = V(0, 0, math.pi / 2), mat = "Wood" }
	)
	Kit.block(
		m,
		"Sign",
		V(0, 7.6, -7.75),
		6.8,
		1.8,
		0.4,
		p.woodDark,
		{ mat = "Wood", shadow = true, text = text, textColor = p.gold }
	)
	Kit.anchor(m, "sign", V(0, 7.6, -8.1))
	Kit.ball(m, "Coconut", V(-4.2, 3.55, -3.6), 0.9, "#6B4426")
	Kit.ball(m, "Coconut", V(-3.2, 3.55, -3.9), 0.9, "#6B4426")
	for i = 0, 2 do
		Kit.cyl(m, "Coin", V(4.2, 3.4 + i * 0.22, -3.8), 1.3, 0.2, p.gold)
	end
	Kit.ball(m, "Pot", V(-8.2, 1.5, -0.5), 2.6, "#C8643A", { shadow = true })
	Kit.post(m, "PotNeck", -8.2, 2.5, -0.5, 1.2, 0.5, "#C8643A")
	Kit.block(m, "Crate", V(8.0, 1.2, -0.5), 1.9, 1.9, 1.9, p.wood, { mat = "Wood", shadow = true })
	Kit.ball(m, "AshSack", V(7.9, 2.7, -0.5), 1.5, "#BDB3A6")
	Kit.ball(m, "Beacon", V(0, 10.9, -0.5), 1.0, p.glow, { neon = true })
end

local function basalt(m: Kit.Model, p: Styles.Palette, text: string)
	Kit.block(
		m,
		"Base",
		V(0, 0.5, -0.5),
		15.5,
		1.0,
		12.5,
		p.stoneDark,
		{ mat = "Basalt", collide = true }
	)
	Kit.block(m, "BaseGlow", V(0, 0.2, -6.8), 14.4, 0.25, 0.25, p.glow, { neon = true })
	Kit.block(
		m,
		"Body",
		V(0, 4.3, 2),
		12,
		6.6,
		7,
		p.wall,
		{ mat = "Slate", collide = true, shadow = true }
	)
	Kit.block(m, "Plinth", V(0, 8.0, 2), 13.4, 0.8, 8.4, p.roof, { mat = "Basalt", shadow = true })
	Kit.gable(m, "Roof", 0, 8.4, 2, 12, 7, 3.2, p.roofAlt, { mat = "Basalt", shadow = true })
	Kit.cyl(
		m,
		"Ridge",
		V(0, 11.7, 2),
		0.5,
		7.4,
		p.glow,
		{ neon = true, rot = V(math.pi / 2, 0, 0) }
	)
	for _, side in { -1, 1 } do
		Kit.block(m, "Eave", V(side * 6.75, 8.45, 2), 0.25, 0.25, 8.4, p.glow, { neon = true })
		Kit.block(
			m,
			"Pillar",
			V(side * 6.6, 3.2, -4.7),
			1.6,
			5.4,
			1.6,
			p.stoneDark,
			{ mat = "Basalt", collide = true, shadow = true }
		)
		Kit.block(
			m,
			"PillarGlow",
			V(side * 6.6, 6.0, -4.7),
			1.7,
			0.3,
			1.7,
			p.glowAlt,
			{ neon = true }
		)
		Kit.block(
			m,
			"Crystal",
			V(side * 8.2, 1.9, 0.5),
			1.1,
			2.8,
			1.1,
			p.glowAlt,
			{ neon = true, rot = V(0, 0.6, side * 0.2) }
		)
	end
	Kit.block(
		m,
		"CounterBody",
		V(0, 2.1, -3.4),
		11,
		2.2,
		2.2,
		p.stone,
		{ mat = "Slate", collide = true, shadow = true }
	)
	Kit.block(m, "CounterTrim", V(0, 1.9, -4.55), 10.4, 0.25, 0.2, p.glowAlt, { neon = true })
	Kit.block(
		m,
		"Counter",
		V(0, 3.4, -3.6),
		12,
		0.4,
		3,
		p.woodLight,
		{ mat = "Marble", collide = true }
	)
	Kit.anchor(m, "sell", V(0, 3.9, -3.6))
	Kit.block(
		m,
		"Awning",
		V(0, 6.1, -4.1),
		13.4,
		0.5,
		4.2,
		p.roof,
		{ mat = "Basalt", shadow = true, rot = V(-0.22, 0, 0) }
	)
	Kit.block(
		m,
		"AwningEdge",
		V(0, 5.3, -6.1),
		13.4,
		0.2,
		0.2,
		p.glow,
		{ neon = true, rot = V(-0.22, 0, 0) }
	)
	Kit.block(
		m,
		"Sign",
		V(0, 7.2, -1.75),
		8.0,
		1.5,
		0.4,
		p.dark,
		{ text = text, textColor = p.glow, shadow = true }
	)
	Kit.anchor(m, "sign", V(0, 7.2, -2.1))
	Kit.cyl(m, "Brazier", V(-9.2, 1.1, -3.0), 1.8, 1.2, p.stoneDark, { mat = "Basalt" })
	Kit.ball(m, "Ember", V(-9.2, 2.1, -3.0), 1.4, p.glow, { neon = true })
	Kit.block(m, "Window", V(6.05, 5.0, 2), 0.2, 2.0, 2.0, p.glowAlt, { neon = true })
	Kit.block(m, "Window", V(-6.05, 5.0, 2), 0.2, 2.0, 2.0, p.glowAlt, { neon = true })
	for i = 0, 2 do
		Kit.cyl(m, "Coin", V(4.2, 3.8 + i * 0.22, -3.6), 1.3, 0.2, p.gold)
	end
	Kit.ball(m, "AshSack", V(8.0, 1.5, -2.6), 2.0, "#8D8590", { shadow = true })
	Kit.block(
		m,
		"Crate",
		V(8.0, 1.3, 0.2),
		1.8,
		1.8,
		1.8,
		p.wood,
		{ mat = "Basalt", shadow = true }
	)
end

function TradeHut.spec(params: Kit.Params?): Kit.Model
	local opts: Kit.Params = params or {}
	local style = Styles.get(opts.style)
	local m = Kit.new("TradeHut", style, 7.8, 6.6)
	local p = Styles.pal[style]
	local text = opts.text or "TRADE HUT"
	if style == "tiki" then
		tiki(m, p, text)
	elseif style == "basalt" then
		basalt(m, p, text)
	else
		toy(m, p, text)
	end
	return m
end

return TradeHut
