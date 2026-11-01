--!strict
-- Signpost: a board with text on a post. Params: text. 4 to 8 parts. The board is the part named
-- "Board" (text on its Front); anchor "board" is its centre.

local Kit = require("./Kit")
local Styles = require("./Styles")

local Sign = {}

Sign.maxParts = 9

local V = Kit.v3

function Sign.spec(params: Kit.Params?): Kit.Model
	local opts: Kit.Params = params or {}
	local style = Styles.get(opts.style)
	local m = Kit.new("Sign", style, 3, 1)
	local p = Styles.pal[style]
	local text = opts.text or "SWEEP!"
	if style == "toy" then
		Kit.post(m, "Post", 0, 0, 0, 0.55, 4.6, p.woodDark, { mat = "Wood", collide = true })
		Kit.ball(m, "Knob", V(0, 4.9, 0), 0.9, p.trim)
		Kit.block(
			m,
			"Board",
			V(0, 3.3, -0.4),
			5.4,
			1.9,
			0.3,
			p.wall,
			{ shadow = true, text = text, textColor = p.cloth }
		)
		Kit.block(m, "Frame", V(0, 3.3, -0.25), 5.8, 2.3, 0.2, p.roof, {})
		Kit.block(
			m,
			"ArrowFrame",
			V(2.9, 3.3, -0.25),
			1.9,
			1.9,
			0.2,
			p.roof,
			{ rot = V(0, 0, math.pi / 4) }
		)
		Kit.block(
			m,
			"ArrowTip",
			V(2.9, 3.3, -0.4),
			1.5,
			1.5,
			0.3,
			p.wall,
			{ rot = V(0, 0, math.pi / 4) }
		)
	elseif style == "tiki" then
		Kit.post(m, "Post", 0, 0, 0, 0.6, 5.0, p.woodLight, { mat = "Wood", collide = true })
		Kit.block(
			m,
			"Board",
			V(0, 3.9, -0.5),
			5.0,
			1.5,
			0.3,
			p.woodDark,
			{ mat = "Wood", shadow = true, text = text, textColor = p.gold }
		)
		Kit.block(
			m,
			"PlankLow",
			V(0.3, 2.1, -0.5),
			3.4,
			0.9,
			0.25,
			p.wood,
			{ mat = "Wood", rot = V(0, 0, 0.06) }
		)
		Kit.cyl(m, "Rope", V(-1.2, 3.0, -0.4), 0.14, 1.0, p.woodLight, {})
		Kit.cyl(m, "Rope", V(1.4, 3.0, -0.4), 0.14, 1.0, p.woodLight, {})
		Kit.ball(m, "Skull", V(0, 5.3, 0), 0.8, p.white)
	else
		Kit.block(
			m,
			"Base",
			V(0, 0.4, 0),
			2.4,
			0.8,
			1.4,
			p.stoneDark,
			{ mat = "Basalt", collide = true }
		)
		Kit.block(
			m,
			"Board",
			V(0, 2.5, -0.1),
			4.6,
			3.2,
			0.6,
			p.dark,
			{ mat = "Slate", shadow = true, text = text, textColor = p.glow, collide = true }
		)
		Kit.block(m, "EdgeGlow", V(0, 0.95, -0.4), 4.9, 0.18, 0.18, p.glow, { neon = true })
		Kit.block(m, "EdgeGlow", V(0, 4.15, -0.4), 4.9, 0.18, 0.18, p.glowAlt, { neon = true })
	end
	Kit.anchor(m, "board", V(0, 3.3, -0.5))
	return m
end

return Sign
