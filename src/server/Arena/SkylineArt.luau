--!strict
-- The far city beyond the arena wall (piece 14): a dark ground plate and towers with lit window
-- ribbons, neon crowns and antennas, so the map never ends in empty sky. Towers on the south
-- side stay low, because the game camera sits south of the player and a tall tower there would
-- block the view. Everything stays outside the arena. Pure planning, no Roblox types.
local ArtKit = require("./ArtKit")

local SkylineArt = {}

local P = ArtKit.P
local G = "Skyline"

export type Cfg = { towers: number, innerGap: number, outerReach: number }

local BODY = { "#1D3150", "#233A5E", "#2A4570", "#1A2C48" }
local WINDOWS = { "#FFD98A", "#8FE3EC", "#FFB3A7", "#FFE9B8", "#9FE8D0" }

export type Tower = { x: number, z: number, w: number, d: number, h: number, side: string }

local function overlaps(a: Tower, b: Tower, pad: number): boolean
	return math.abs(a.x - b.x) < (a.w + b.w) / 2 + pad
		and math.abs(a.z - b.z) < (a.d + b.d) / 2 + pad
end

-- Where the towers go. Pure and checked by tests: all outside the arena wall, none overlapping.
function SkylineArt.layoutTowers(plan: ArtKit.Plan, half: number, cfg: Cfg): { Tower }
	local towers: { Tower } = {}
	local tries = 0
	local sides = { "N", "N", "E", "W", "S" } -- more on the far (north) side
	while #towers < cfg.towers and tries < cfg.towers * 30 do
		tries += 1
		local side = ArtKit.pick(plan, sides)
		local w = ArtKit.range(plan, 14, 28)
		local d = ArtKit.range(plan, 14, 24)
		local gap = cfg.innerGap + ArtKit.rand(plan) * cfg.outerReach
		local along = ArtKit.range(plan, -half - 40, half + 40)
		local h = ArtKit.range(plan, 26, 74)
		local x, z = along, 0
		if side == "N" then
			z = -(half + 4 + gap + d / 2)
		elseif side == "S" then
			z = half + 4 + gap + d / 2
			h = ArtKit.range(plan, 5, 9)
		elseif side == "E" then
			x, z = half + 4 + gap + w / 2, along
		else
			x, z = -(half + 4 + gap + w / 2), along
		end
		local t: Tower = { x = x, z = z, w = w, d = d, h = h, side = side }
		local ok = true
		for _, o in towers do
			if overlaps(t, o, 3) then
				ok = false
				break
			end
		end
		if ok then
			table.insert(towers, t)
		end
	end
	return towers
end

local function towerFace(t: Tower, side: string): ArtKit.Face
	local alongX = side == "S" or side == "N"
	local u0 = if alongX then t.x - t.w / 2 else t.z - t.d / 2
	local u1 = if alongX then t.x + t.w / 2 else t.z + t.d / 2
	local at = if side == "S"
		then t.z + t.d / 2
		elseif side == "N" then t.z - t.d / 2
		elseif side == "E" then t.x + t.w / 2
		else t.x - t.w / 2
	return { side = side, u0 = u0, u1 = u1, at = at, h = t.h, group = G, fadeWith = nil }
end

local function tower(plan: ArtKit.Plan, t: Tower, half: number)
	local body = ArtKit.pick(plan, BODY)
	ArtKit.box(plan, G, t.x, t.h / 2, t.z, t.w, t.h, t.d, body, { shadow = t.h > 20 })
	-- the two faces that look toward the middle of the arena get window ribbons
	local faces: { { string } } = {}
	if t.z < -half then
		table.insert(faces, { "S" })
	elseif t.z > half then
		table.insert(faces, { "N" })
	end
	if t.x > half then
		table.insert(faces, { "W" })
	elseif t.x < -half then
		table.insert(faces, { "E" })
	end
	if #faces == 0 then
		table.insert(faces, { "S" })
	end
	for _, fd in faces do
		local side = fd[1] :: string
		local f = towerFace(t, side)
		local len = f.u1 - f.u0
		local y = 4
		while y + 2.4 < t.h - 2 do
			local mid = (f.u0 + f.u1) / 2
			for k = -1, 0 do
				local color = ArtKit.pick(plan, WINDOWS)
				ArtKit.fbox(
					plan,
					f,
					mid + (k + 0.5) * len / 2,
					y,
					0.08,
					len / 2 - 1.4,
					2.2,
					0.16,
					color,
					{
						material = "Neon",
						neon = ArtKit.glow(color, "#16243C", ArtKit.range(plan, 0.1, 0.95), false),
					}
				)
			end
			y += 4.6
		end
	end
	-- crown: neon rim and an antenna with a blinking light
	local on = if ArtKit.chance(plan, 0.5) then P.cyan else P.coral
	local off = if on == P.cyan then P.cyanDim else P.coralDim
	local n = ArtKit.glow(on, off, 0, true)
	ArtKit.box(
		plan,
		G,
		t.x,
		t.h + 0.12,
		t.z - t.d / 2 + 0.2,
		t.w,
		0.24,
		0.4,
		on,
		{ material = "Neon", neon = n }
	)
	ArtKit.box(
		plan,
		G,
		t.x,
		t.h + 0.12,
		t.z + t.d / 2 - 0.2,
		t.w,
		0.24,
		0.4,
		on,
		{ material = "Neon", neon = n }
	)
	ArtKit.box(
		plan,
		G,
		t.x - t.w / 2 + 0.2,
		t.h + 0.12,
		t.z,
		0.4,
		0.24,
		t.d,
		on,
		{ material = "Neon", neon = n }
	)
	ArtKit.box(
		plan,
		G,
		t.x + t.w / 2 - 0.2,
		t.h + 0.12,
		t.z,
		0.4,
		0.24,
		t.d,
		on,
		{ material = "Neon", neon = n }
	)
	if t.h > 20 then
		local ah = ArtKit.range(plan, 5, 11)
		ArtKit.vcyl(plan, G, t.x, t.h, t.z, 0.2, ah, P.steel)
		ArtKit.ball(plan, G, t.x, t.h + ah + 0.3, t.z, 0.5, P.coral, {
			material = "Neon",
			neon = ArtKit.glow(P.coral, P.coralDim, 0.35, false),
		})
	end
end

function SkylineArt.build(plan: ArtKit.Plan, half: number, cfg: Cfg)
	-- the ground out past the wall, just under the arena floor so the two never fight
	ArtKit.box(
		plan,
		G,
		0,
		-3.1,
		0,
		900,
		6,
		900,
		"#10203A",
		{ material = "Concrete", name = "SkylineGround" }
	)
	for _, t in SkylineArt.layoutTowers(plan, half, cfg) do
		tower(plan, t, half)
	end
end

return SkylineArt
