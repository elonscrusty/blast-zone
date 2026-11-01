--!strict
-- Rock cluster: a few chunky stones that sit on the ground. 3 to 8 parts. v picks little differences.

local Kit = require("./Kit")
local Styles = require("./Styles")

local Rocks = {}

Rocks.maxParts = 9

local V = Kit.v3

function Rocks.spec(params: Kit.Params?): Kit.Model
	local opts: Kit.Params = params or {}
	local style = Styles.get(opts.style)
	local v = Kit.variant(opts.v)
	local m = Kit.new("Rocks", style, 3, 3)
	local p = Styles.pal[style]
	local u = Kit.unit
	if style == "toy" then
		-- smooth pebbles, like toy blocks
		local tint = { "#CFC4AE", "#B9AD96", "#DDD2BC" }
		Kit.ball(
			m,
			"Rock",
			V(0, 1.5, 0),
			3.4 + u(v, 1) * 0.8,
			tint[1],
			{ shadow = true, collide = true }
		)
		Kit.ball(m, "Rock", V(2.3, 0.95, 0.6), 2.2 + u(v, 2) * 0.5, tint[2], { shadow = true })
		Kit.ball(m, "Rock", V(-1.4, 0.7, 1.7), 1.5 + u(v, 3) * 0.4, tint[3])
	elseif style == "tiki" then
		-- faceted boulders with a moss cap
		local dark, light = "#8E8472", "#B3A892"
		local big = V(0.25 + u(v, 1) * 0.2, u(v, 2) * 3, 0.18)
		Kit.block(
			m,
			"Rock",
			V(0, 1.7, 0),
			4.2,
			3.4,
			3.8,
			light,
			{ mat = "Slate", shadow = true, collide = true, rot = big }
		)
		Kit.block(
			m,
			"Rock",
			V(0.2, 3.1, 0),
			3.0,
			2.2,
			2.8,
			dark,
			{ mat = "Slate", shadow = true, rot = V(0.3, 0.9 + u(v, 3), 0.25) }
		)
		Kit.block(
			m,
			"Rock",
			V(3.0, 1.0, 1.0),
			2.6,
			2.2,
			2.4,
			dark,
			{ mat = "Slate", shadow = true, rot = V(0.2, 0.8 + u(v, 3), 0.3) }
		)
		Kit.block(
			m,
			"Rock",
			V(-2.4, 0.8, 2.0),
			2.0,
			1.7,
			1.9,
			light,
			{ mat = "Slate", rot = V(0.1, 0.4, 0.3) }
		)
		Kit.wedge(
			m,
			"Moss",
			V(0.1, 4.3, -0.1),
			2.6,
			0.7,
			2.2,
			p.leaf,
			{ mat = "Grass", rot = V(0, u(v, 4) * 3, 0) }
		)
	else
		-- basalt columns with glowing tops
		local spots = {
			{ 0, 0, 4.6 },
			{ 1.5, 0.4, 3.2 },
			{ -1.4, 0.5, 2.8 },
			{ 0.5, 1.6, 2.0 },
			{ -0.4, -1.5, 3.6 },
			{ 1.7, -1.3, 1.6 },
		}
		for i, s in spots do
			local h = s[3] * (0.8 + u(v, i) * 0.5)
			Kit.block(
				m,
				"Column",
				V(s[1], h / 2, s[2]),
				1.5,
				h,
				1.5,
				if i % 2 == 0 then p.wall else p.wallDark,
				{ mat = "Basalt", shadow = true, collide = i == 1, rot = V(0, 0.5 + i, 0) }
			)
			if i % 3 == 1 then
				Kit.block(
					m,
					"ColumnGlow",
					V(s[1], h + 0.05, s[2]),
					1.0,
					0.12,
					1.0,
					p.glow,
					{ neon = true, rot = V(0, 0.5 + i, 0) }
				)
			end
		end
	end
	return m
end

return Rocks
