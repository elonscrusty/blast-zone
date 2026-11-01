--!strict
-- Zone gate: an arch you walk through (18 stud opening, about 17 tall). The part named "GatePlate" is the
-- glowing floor plate the wiring code tags and hangs the "Open gate" prompt on; "Beam" carries the
-- price sign (anchor "sign"). Params: accent = the zone's glow colour, ground = the zone's ground colour.

local Kit = require("./Kit")
local Styles = require("./Styles")

local Gate = {}

Gate.maxParts = 32

local V = Kit.v3

local function toy(m: Kit.Model, p: Styles.Palette, accent: string, ground: string)
	for _, side in { -1, 1 } do
		local x = side * 9.2
		Kit.block(
			m,
			"PillarBase",
			V(x, 0.5, 0),
			3.8,
			1,
			3.8,
			p.stone,
			{ collide = true, shadow = true }
		)
		for i = 0, 3 do
			local c = if i % 2 == 0 then ground else p.white
			Kit.cyl(
				m,
				"Pillar",
				V(x, 2.2 + i * 2.6, 0),
				2.7,
				2.6,
				c,
				{ collide = i < 2, shadow = true }
			)
		end
		Kit.cyl(m, "PillarBand", V(x, 12.7, 0), 3.1, 0.5, accent, { neon = true })
		Kit.ball(m, "PillarCap", V(x, 13.9, 0), 3.2, accent, { neon = true })
	end
	Kit.block(m, "Beam", V(0, 14.8, 0), 22.6, 2.2, 3, ground, { shadow = true })
	Kit.block(m, "BeamStrip", V(0, 13.55, -1.4), 21.4, 0.3, 0.3, accent, { neon = true })
	for i = 0, 5 do
		local c = if i % 2 == 0 then p.cloth else p.trim
		Kit.block(
			m,
			"Pennant",
			V(-8.5 + i * 3.4, 12.6, -1.55),
			1.6,
			1.6,
			0.2,
			c,
			{ rot = V(0, 0, math.pi / 4) }
		)
	end
	Kit.anchor(m, "sign", V(0, 17.6, -1.6))
end

local function tiki(m: Kit.Model, p: Styles.Palette, accent: string, ground: string)
	for _, side in { -1, 1 } do
		local x = side * 9.2
		Kit.block(
			m,
			"PillarBase",
			V(x, 0.5, 0),
			3.6,
			1,
			3.6,
			p.stoneDark,
			{ mat = "Slate", collide = true }
		)
		Kit.cyl(
			m,
			"Totem",
			V(x, 6.6, 0),
			2.7,
			11.2,
			p.wood,
			{ mat = "Wood", collide = true, shadow = true }
		)
		Kit.cyl(m, "TotemBand", V(x, 3.4, 0), 2.95, 0.5, accent, { neon = true })
		Kit.cyl(m, "TotemBand", V(x, 8.6, 0), 2.95, 0.5, accent, { neon = true })
		Kit.block(m, "Brow", V(x, 11.0, -1.3), 2.8, 0.5, 0.7, p.woodDark, { mat = "Wood" })
		for _, e in { -0.6, 0.6 } do
			Kit.ball(m, "Eye", V(x + e, 10.2, -1.25), 0.8, p.white)
			Kit.ball(m, "Pupil", V(x + e, 10.2, -1.62), 0.4, p.dark)
		end
		Kit.block(m, "Mouth", V(x, 9.3, -1.35), 1.4, 0.45, 0.5, p.dark)
		Kit.wedge(
			m,
			"Wing",
			V(x + side * 1.9, 11.2, 0),
			0.6,
			2.2,
			2.4,
			p.woodDark,
			{ mat = "Wood", rot = V(0, side * math.pi / 2, 0) }
		)
		Kit.cyl(m, "TotemTop", V(x, 12.5, 0), 2.2, 1.3, ground, { mat = "Wood" })
	end
	Kit.cyl(
		m,
		"Beam",
		V(0, 13.6, 0),
		1.3,
		22.6,
		p.wood,
		{ mat = "Wood", shadow = true, rot = V(0, 0, math.pi / 2) }
	)
	Kit.cyl(
		m,
		"BeamLow",
		V(0, 12.1, 0),
		0.7,
		19.0,
		p.woodLight,
		{ mat = "Wood", rot = V(0, 0, math.pi / 2) }
	)
	for _, side in { -1, 1 } do
		Kit.block(
			m,
			"Banner",
			V(side * 5.5, 10.9, -0.2),
			1.9,
			3.0,
			0.15,
			if side < 0 then p.cloth else p.clothAlt,
			{}
		)
		Kit.ball(m, "Flame", V(side * 11.8, 13.8, 0), 1.2, p.glow, { neon = true })
	end
	Kit.anchor(m, "sign", V(0, 16.0, -1.0))
end

local function basalt(m: Kit.Model, p: Styles.Palette, accent: string, ground: string)
	for _, side in { -1, 1 } do
		local x = side * 9.4
		Kit.block(
			m,
			"PillarBase",
			V(x, 0.6, 0),
			4.2,
			1.2,
			4.2,
			p.stoneDark,
			{ mat = "Basalt", collide = true }
		)
		Kit.block(
			m,
			"Monolith",
			V(x, 7.6, 0),
			3.0,
			12.8,
			3.0,
			p.wall,
			{ mat = "Slate", collide = true, shadow = true, rot = V(0, 0.18 * side, 0) }
		)
		Kit.gable(m, "MonolithTip", x, 14.0, 0, 3.0, 3.0, 2.0, p.wallDark, { mat = "Slate" })
		for i = 0, 2 do
			Kit.block(
				m,
				"Rune",
				V(x, 4.0 + i * 3.4, -1.55),
				1.2,
				0.35,
				0.15,
				accent,
				{ neon = true }
			)
		end
	end
	Kit.block(m, "Beam", V(0, 15.2, 0), 17.2, 1.8, 3, p.roofAlt, { mat = "Basalt", shadow = true })
	Kit.block(m, "BeamGlow", V(0, 14.2, -1.35), 17.0, 0.25, 0.25, accent, { neon = true })
	Kit.wedge(
		m,
		"Crystal",
		V(-3.2, 17.4, 0),
		1.2,
		2.8,
		1.4,
		ground,
		{ neon = true, rot = V(0, math.pi / 2, 0) }
	)
	Kit.wedge(
		m,
		"Crystal",
		V(3.2, 17.4, 0),
		1.2,
		2.8,
		1.4,
		ground,
		{ neon = true, rot = V(0, -math.pi / 2, 0) }
	)
	Kit.ball(m, "Gem", V(0, 17.6, 0), 1.8, accent, { neon = true })
	Kit.anchor(m, "sign", V(0, 17.9, -1.7))
end

function Gate.spec(params: Kit.Params?): Kit.Model
	local opts: Kit.Params = params or {}
	local style = Styles.get(opts.style)
	local m = Kit.new("Gate", style, 12, 3)
	local p = Styles.pal[style]
	local accent = opts.accent or "#FFE9A8"
	local ground = opts.ground or "#F2D9A0"
	Kit.block(m, "GatePlate", V(0, 0.15, 0), 16, 0.3, 5, accent, { neon = true, alpha = 0.35 })
	Kit.anchor(m, "plate", V(0, 0.3, 0))
	if style == "tiki" then
		tiki(m, p, accent, ground)
	elseif style == "basalt" then
		basalt(m, p, accent, ground)
	else
		toy(m, p, accent, ground)
	end
	return m
end

return Gate
