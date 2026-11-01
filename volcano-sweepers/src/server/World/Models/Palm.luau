--!strict
-- Beach palm: a leaning trunk and a crown of flat leaves. 12 parts or fewer. Params: v picks the
-- lean direction, height and leaf colours (same v = same palm).

local Kit = require("./Kit")
local Styles = require("./Styles")

local Palm = {}

Palm.maxParts = 13

local V = Kit.v3
local TAU = math.pi * 2

-- Trunk points go up with a gentle lean towards (lx, lz).
local function trunkPoints(h: number, lean: number, ang: number): { Kit.V3 }
	local lx, lz = math.cos(ang), math.sin(ang)
	local pts: { Kit.V3 } = {}
	for i = 0, 3 do
		local t = i / 3
		local off = lean * t * t
		table.insert(pts, V(lx * off, h * t, lz * off))
	end
	return pts
end

local function fronds(
	m: Kit.Model,
	top: Kit.V3,
	count: number,
	len: number,
	wide: number,
	pitch: number,
	c1: string,
	c2: string,
	ang0: number,
	mat: string?,
	neon: boolean?
)
	for j = 0, count - 1 do
		local a = ang0 + j * TAU / count
		local dir = V(math.cos(a) * math.cos(pitch), math.sin(pitch), math.sin(a) * math.cos(pitch))
		Kit.leaf(
			m,
			"Frond",
			top,
			dir,
			len,
			wide,
			0.25,
			if j % 2 == 0 then c1 else c2,
			{ mat = mat, neon = neon, shadow = false }
		)
	end
end

function Palm.spec(params: Kit.Params?): Kit.Model
	local opts: Kit.Params = params or {}
	local style = Styles.get(opts.style)
	local v = opts.v or 1
	local m = Kit.new("Palm", style, 8, 8)
	local p = Styles.pal[style]
	local ang = Kit.unit(v, 1) * TAU
	local h = 8.5 + Kit.unit(v, 2) * 3
	local pts = trunkPoints(h, 1.6 + Kit.unit(v, 3) * 1.6, ang)
	local top = pts[4]
	if style == "toy" then
		local thick = { 1.7, 1.45, 1.2 }
		for i = 1, 3 do
			Kit.pole(
				m,
				"Trunk",
				pts[i],
				pts[i + 1],
				thick[i],
				if i % 2 == 1 then p.wood else p.woodLight,
				{ collide = i == 1, shadow = true, mat = "Wood" }
			)
		end
		Kit.ball(m, "Joint", pts[2], thick[1] * 0.98, p.wood)
		Kit.ball(m, "Joint", pts[3], thick[2] * 0.98, p.woodLight)
		Kit.ball(m, "Crown", top, 2.2, p.leafAlt)
		fronds(m, top, 5, 6.4, 3.6, math.rad(-18), p.leaf, p.leafAlt, ang + 0.3)
		Kit.ball(m, "Coconut", V(top.x + 0.7, top.y - 1.0, top.z), 0.95, "#8A5A3C")
	elseif style == "tiki" then
		local thick = { 1.4, 1.15, 0.95 }
		for i = 1, 3 do
			Kit.pole(
				m,
				"Trunk",
				pts[i],
				pts[i + 1],
				thick[i],
				if i % 2 == 1 then p.woodDark else p.wood,
				{ collide = i == 1, shadow = true, mat = "Wood" }
			)
		end
		Kit.ball(m, "Joint", pts[2], thick[1] * 1.02, p.woodLight)
		Kit.ball(m, "Joint", pts[3], thick[2] * 1.02, p.woodLight)
		fronds(m, top, 6, 7.6, 3.0, math.rad(-22), p.leaf, p.leafAlt, ang, "Grass")
		Kit.ball(m, "Coconut", V(top.x + 0.6, top.y - 0.8, top.z), 0.9, "#5E3B22")
		Kit.ball(m, "Coconut", V(top.x - 0.4, top.y - 0.9, top.z - 0.7), 0.9, "#5E3B22")
	else
		local thick = { 1.6, 1.3, 1.05 }
		for i = 1, 3 do
			Kit.pole(
				m,
				"Trunk",
				pts[i],
				pts[i + 1],
				thick[i],
				if i % 2 == 1 then p.wall else p.wallDark,
				{ collide = i == 1, shadow = true, mat = "Slate" }
			)
			Kit.cyl(
				m,
				"Glow",
				V(pts[i].x, pts[i].y + 0.1, pts[i].z),
				thick[i] + 0.25,
				0.28,
				p.glowAlt,
				{ neon = true }
			)
		end
		fronds(m, top, 5, 6.8, 3.2, math.rad(18), p.glowAlt, p.leaf, ang + 0.4, nil, true)
		Kit.ball(m, "Gem", V(top.x, top.y + 0.2, top.z), 1.5, p.glow, { neon = true })
	end
	Kit.anchor(m, "top", top)
	return m
end

return Palm
