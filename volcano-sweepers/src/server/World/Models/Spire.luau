--!strict
-- Crater spire: a tall pointy landmark for the Crater Rim. 8 to 14 parts. v picks height and lean.

local Kit = require("./Kit")
local Styles = require("./Styles")

local Spire = {}

Spire.maxParts = 15

local V = Kit.v3

function Spire.spec(params: Kit.Params?): Kit.Model
	local opts: Kit.Params = params or {}
	local style = Styles.get(opts.style)
	local v = opts.v or 1
	local m = Kit.new("Spire", style, 4, 4)
	local p = Styles.pal[style]
	local tall = 0.85 + Kit.unit(v, 1) * 0.5
	if style == "toy" then
		-- bone-white stacked tiers with candy bands
		local y = 0
		local d = 5.0
		for i = 1, 5 do
			local h = 2.6 * tall
			Kit.cyl(
				m,
				"Tier",
				V(0, y + h / 2, 0),
				d,
				h,
				if i % 2 == 1 then "#F3E9D2" else "#E8D8B8",
				{ shadow = true, collide = i == 1 }
			)
			y += h
			d *= 0.74
		end
		Kit.ball(m, "Tip", V(0, y + 0.3, 0), 1.2, p.roof)
		Kit.cyl(m, "Band", V(0, 2.6 * tall, 0), 4.0, 0.3, p.roof)
		Kit.cyl(m, "Band", V(0, 7.8 * tall, 0), 2.2, 0.3, p.roof)
	elseif style == "tiki" then
		-- a curved bone tusk
		local pts = {
			V(0, 0, 0),
			V(0.4, 3.4 * tall, 0),
			V(1.5, 6.6 * tall, 0),
			V(3.2, 9.0 * tall, 0),
			V(5.4, 10.6 * tall, 0),
		}
		local thick = { 3.2, 2.5, 1.8, 1.2 }
		for i = 1, 4 do
			Kit.pole(
				m,
				"Tusk",
				pts[i],
				pts[i + 1],
				thick[i],
				if i % 2 == 1 then "#F3E9D2" else "#E6D5B0",
				{ shadow = true, collide = i == 1 }
			)
		end
		Kit.ball(m, "Tip", pts[5], 0.9, "#F3E9D2")
		Kit.block(
			m,
			"Foot",
			V(0.4, 0.6, 0),
			4.6,
			1.2,
			4.0,
			p.stone,
			{ mat = "Slate", rot = V(0, 0.4, 0) }
		)
		Kit.block(
			m,
			"Foot",
			V(-1.8, 0.4, 1.2),
			2.2,
			0.8,
			2.0,
			p.stoneDark,
			{ mat = "Slate", rot = V(0, 1.0, 0) }
		)
	else
		-- obsidian shards with a glowing vein
		local shards = { { 0, 0, 8.5, 0.0 }, { 2.2, 1.2, 5.2, 0.12 }, { -2.0, -0.8, 6.2, -0.1 } }
		for i, s in shards do
			local h = s[3] * tall
			local w = 2.4 - i * 0.3
			Kit.block(
				m,
				"Shard",
				V(s[1], h / 2, s[2]),
				w,
				h,
				w,
				if i == 1 then p.wall else p.wallDark,
				{ mat = "Basalt", shadow = true, collide = i == 1, rot = V(0, 0.4 * i, s[4]) }
			)
			Kit.gable(
				m,
				"ShardTip",
				s[1],
				h,
				s[2],
				w,
				w,
				w * 1.1,
				if i == 1 then p.wall else p.wallDark,
				{ mat = "Basalt" }
			)
			Kit.block(
				m,
				"Vein",
				V(s[1], h * 0.45, s[2] - w / 2 - 0.02),
				0.28,
				h * 0.55,
				0.12,
				p.glow,
				{ neon = true, rot = V(0, 0, s[4]) }
			)
		end
		Kit.block(
			m,
			"Base",
			V(0, 0.5, 0),
			5.6,
			1.0,
			4.6,
			p.stoneDark,
			{ mat = "Basalt", rot = V(0, 0.2, 0) }
		)
	end
	return m
end

return Spire
