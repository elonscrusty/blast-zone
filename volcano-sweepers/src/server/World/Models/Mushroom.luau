--!strict
-- Giant mushroom. 4 to 9 parts. v picks the cap colour.

local Kit = require("./Kit")
local Styles = require("./Styles")

local Mushroom = {}

Mushroom.maxParts = 10

local V = Kit.v3

function Mushroom.spec(params: Kit.Params?): Kit.Model
	local opts: Kit.Params = params or {}
	local style = Styles.get(opts.style)
	local v = opts.v or 1
	local m = Kit.new("Mushroom", style, 2, 2)
	local p = Styles.pal[style]
	if style == "toy" then
		local caps = { "#F0463C", "#B06CFF", "#FF9A3C", "#5BE6D0" }
		local cap = Kit.pick(caps, v)
		Kit.post(m, "Stem", 0, 0, 0, 1.0, 2.2, "#FFF4E0", { shadow = true })
		Kit.ball(m, "Cap", V(0, 2.5, 0), 3.4, cap, { shadow = true })
		for j = 0, 3 do
			local a = j * 1.7 + v
			local d = V(math.cos(a) * 0.62, 0.78, math.sin(a) * 0.62)
			Kit.ball(m, "Spot", V(d.x * 1.7, 2.5 + d.y * 1.7, d.z * 1.7), 0.6, p.white)
		end
	elseif style == "tiki" then
		-- stepped cap: three flat discs, earthy colours
		local caps = { "#C8643A", "#D9A441", "#A8483A" }
		local cap = Kit.pick(caps, v)
		Kit.post(m, "Stem", 0, 0, 0, 1.0, 2.0, "#F2E3C0", { shadow = true })
		Kit.cyl(m, "Ring", V(0, 1.3, 0), 1.5, 0.3, "#E8D6A8")
		Kit.cyl(m, "Cap", V(0, 2.2, 0), 3.8, 0.7, cap, { shadow = true })
		Kit.cyl(m, "Cap", V(0, 2.8, 0), 2.8, 0.6, cap)
		Kit.cyl(m, "Cap", V(0, 3.3, 0), 1.6, 0.5, "#F2E3C0")
	else
		-- glowing cave mushroom
		Kit.post(m, "Stem", 0, 0, 0, 0.9, 2.2, p.wallDark, { mat = "Slate" })
		Kit.ball(m, "Cap", V(0, 2.5, 0), 3.2, p.glowAlt, { neon = true })
		Kit.cyl(m, "Ring", V(0, 1.5, 0), 1.9, 0.25, p.glow, { neon = true })
		Kit.post(m, "BabyStem", 1.9, 0, 0.8, 0.4, 0.9, p.wallDark)
		Kit.ball(m, "BabyCap", V(1.9, 1.0, 0.8), 1.3, p.glow, { neon = true })
	end
	return m
end

return Mushroom
