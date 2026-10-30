--!strict
-- Building fronts for the Neon Night city (piece 14): plinth, piers, storefronts, awnings,
-- windows that light up one by one at dusk, cornices, neon trim, door headers, corner strips.
-- Every piece is visual paint on the wall: low parts stay within `flushStuds` of the wall face
-- (tests check it) and nothing collides. Pure planning, no Roblox types.
local ArtKit = require("./ArtKit")

local FacadeArt = {}

local P = ArtKit.P

export type RunOpts = {
	groundHeight: number?,
	detail: number?, -- 1 = full, 0.5 = back of a building: fewer parts
	bay: number?, -- target bay width
	alley: boolean?, -- pipes and lamps for the narrow service alleys
	shops: boolean?, -- ground floor storefronts (false = blank service wall)
	lamps: boolean?,
}

local SHOP_NAMES =
	{ "NOODLES", "PIXEL", "TOKENS", "REPAIR", "CAFE", "VINYL", "24H", "RAMEN", "GAMES" }
local SHOP_GLASS = { "#8FE3EC", "#FFB3A7", "#E8F1FA", "#9FE8D0" } -- no warm gold at street level
local UPPER_GLOW = { "#FFD98A", "#8FE3EC", "#FFB3A7", "#FFE9B8" } -- high up, so fine

local function neonStrip(
	plan: ArtKit.Plan,
	f: ArtKit.Face,
	u: number,
	y: number,
	len: number,
	thick: number,
	color: string,
	dim: string
)
	ArtKit.fbox(plan, f, u, y, 0.1, len, thick, 0.2, color, {
		material = "Neon",
		neon = ArtKit.glow(color, dim, 0, true),
	})
end

-- A sign plate with text. Counts against the sign budget.
function FacadeArt.sign(
	plan: ArtKit.Plan,
	f: ArtKit.Face,
	text: string,
	u: number,
	y: number,
	w: number,
	h: number,
	textColor: string,
	bg: string,
	rim: string
)
	if plan.signs >= 26 then
		return
	end
	ArtKit.fbox(plan, f, u, y, 0.55, w, h, 0.3, bg, {
		sign = { text = text, color = textColor, face = ArtKit.guiFace(f.side), background = bg },
	})
	local dim = ArtKit.mix(rim, "#2E4A70", 0.6)
	for _, yy in { y + h / 2 + 0.12, y - h / 2 - 0.12 } do
		ArtKit.fbox(
			plan,
			f,
			u,
			yy,
			0.55,
			w + 0.5,
			0.22,
			0.34,
			rim,
			{ material = "Neon", neon = ArtKit.glow(rim, dim, 0, true) }
		)
	end
end

local function groundBay(
	plan: ArtKit.Plan,
	f: ArtKit.Face,
	uc: number,
	bw: number,
	gh: number,
	o: RunOpts,
	index: number
)
	local roll = ArtKit.rand(plan)
	local awnColor = if index % 2 == 0 then P.coral else "#5A7390"
	if roll < 0.6 then
		-- shop window
		local glass = ArtKit.pick(plan, SHOP_GLASS)
		ArtKit.fbox(plan, f, uc, 3, 0.28, bw - 2.2, 3.4, 0.2, P.glassDark)
		ArtKit.fbox(plan, f, uc, 3, 0.4, bw - 2.6, 3, 0.08, glass, {
			material = "Neon",
			neon = ArtKit.glow(glass, "#27405F", ArtKit.range(plan, 0.05, 0.5), false),
		})
		ArtKit.fbox(plan, f, uc, 3, 0.48, 0.16, 3, 0.12, P.plinth)
		ArtKit.fbox(
			plan,
			f,
			uc,
			gh - 0.1,
			0.5,
			bw - 1.4,
			0.45,
			1.0,
			awnColor,
			{ material = "Fabric" }
		)
		if o.detail ~= nil and o.detail < 1 then
			return
		end
		ArtKit.fbox(plan, f, uc, 1.55, 0.45, bw - 2.6, 0.18, 0.2, P.trim) -- window ledge
		if ArtKit.chance(plan, 0.4) and plan.signs < 26 then
			FacadeArt.sign(
				plan,
				f,
				ArtKit.pick(plan, SHOP_NAMES),
				uc,
				gh + 1.4,
				math.min(bw - 2, 6.2),
				1.2,
				"#FFFFFF",
				"#1B2A44",
				if index % 2 == 0 then P.cyan else P.coral
			)
		end
	elseif roll < 0.8 then
		-- shut roller door with ribs and a stencil stripe
		ArtKit.fbox(
			plan,
			f,
			uc,
			2.7,
			0.28,
			bw - 2.2,
			4.8,
			0.2,
			P.steel,
			{ material = "CorrodedMetal" }
		)
		for i = 0, 5 do
			ArtKit.fbox(plan, f, uc, 0.9 + i * 0.75, 0.4, bw - 2.2, 0.14, 0.12, P.steelDark)
		end
		ArtKit.fbox(plan, f, uc, 5.0, 0.34, bw - 1.6, 0.4, 0.4, P.plinth)
	else
		-- door with a glowing frame above head height
		ArtKit.fbox(plan, f, uc, 2.4, 0.3, 2.6, 4.8, 0.2, P.plinth)
		ArtKit.fbox(
			plan,
			f,
			uc,
			2.4,
			0.4,
			2.0,
			4.4,
			0.08,
			"#2B4A6B",
			{ material = "Glass", transparency = 0.15, reflectance = 0.15 }
		)
		neonStrip(plan, f, uc, gh + 0.1, 3.4, 0.3, P.cyan, P.cyanDim)
	end
end

local function upperWindow(
	plan: ArtKit.Plan,
	f: ArtKit.Face,
	uc: number,
	y: number,
	bw: number,
	o: RunOpts
)
	local w = math.max(2.4, math.min(bw - 3.4, 5))
	local glowColor = ArtKit.pick(plan, UPPER_GLOW)
	local litAt = ArtKit.range(plan, 0.08, 0.95)
	ArtKit.fbox(plan, f, uc, y, 0.28, w + 0.6, 2.9, 0.22, P.trimDark)
	ArtKit.fbox(plan, f, uc, y, 0.4, w, 2.4, 0.1, P.glassDark, {
		material = "Neon",
		neon = ArtKit.glow(glowColor, "#1B2B44", litAt, false),
	})
	if o.detail ~= nil and o.detail < 1 then
		return
	end
	ArtKit.fbox(plan, f, uc, y, 0.5, 0.12, 2.4, 0.1, P.trimDark)
	ArtKit.fbox(plan, f, uc, y - 1.55, 0.42, w + 1.1, 0.25, 0.55, P.trim)
	if ArtKit.chance(plan, 0.3) then
		ArtKit.fbox(
			plan,
			f,
			uc,
			y + 0.6,
			0.47,
			w - 0.2,
			1.1,
			0.06,
			"#1A2236",
			{ transparency = 0.1 }
		)
	end
	if ArtKit.chance(plan, 0.12) then
		ArtKit.fbox(plan, f, uc + w * 0.28, y - 2.1, 0.4, 1.9, 1.1, 0.7, P.steel)
	end
end

-- One run of wall. `f.h` is the wall top. Returns nothing; everything is added to the plan.
function FacadeArt.run(plan: ArtKit.Plan, f: ArtKit.Face, o: RunOpts)
	local len = f.u1 - f.u0
	if len < 3 then
		return
	end
	local gh = o.groundHeight or 5.4
	local mid = (f.u0 + f.u1) / 2
	local top = f.h

	-- plinth, floor band, cornice
	ArtKit.fbox(plan, f, mid, 0.7, 0.2, len, 1.4, 0.4, P.plinth, { material = "Concrete" })
	ArtKit.fbox(plan, f, mid, gh, 0.3, len, 0.5, 0.6, P.trimDark)
	ArtKit.fbox(plan, f, mid, top - 0.6, 0.45, len, 1.2, 0.9, P.trim, { material = "Concrete" })
	neonStrip(plan, f, mid, top - 1.5, len - 0.6, 0.26, P.cyan, P.cyanDim)
	if top > 10 then
		neonStrip(plan, f, mid, gh + 0.55, len - 0.6, 0.18, P.coral, P.coralDim)
	end

	-- piers between bays
	local bayTarget = o.bay or 9
	local nb = math.max(1, math.floor(len / bayTarget + 0.5))
	local bw = len / nb
	for i = 0, nb do
		local u = f.u0 + i * bw
		local w = if i == 0 or i == nb then 0.5 else 0.9
		local uu = if i == 0 then u + w / 2 elseif i == nb then u - w / 2 else u
		ArtKit.fbox(plan, f, uu, (1.4 + top - 1.2) / 2, 0.25, w, top - 2.6, 0.5, P.wallDark)
	end

	-- bays
	for i = 1, nb do
		local uc = f.u0 + (i - 0.5) * bw
		if o.shops ~= false then
			groundBay(plan, f, uc, bw, gh, o, i)
		else
			ArtKit.fbox(
				plan,
				f,
				uc,
				2.6,
				0.28,
				bw - 2,
				2.2,
				0.14,
				P.steelDark,
				{ material = "Metal" }
			)
		end
		local y = gh + 2.4
		while y + 1.45 < top - 1.7 do
			upperWindow(plan, f, uc, y, bw, o)
			y += 4
		end
	end

	-- wall lamps (small, flush)
	if o.lamps ~= false and len > 14 and (o.detail or 1) >= 1 then
		for i = 1, nb - 1, 2 do
			local u = f.u0 + i * bw
			ArtKit.fbox(plan, f, u, 4.4, 0.18, 0.4, 0.7, 0.36, P.steelDark)
			local lamp: ArtKit.Opts =
				{ material = "Neon", neon = ArtKit.glow(P.coolLamp, "#6C7C93", 0.25, true) }
			if plan.lights < 22 and ArtKit.chance(plan, 0.3) then
				lamp.light = { color = P.coolLamp, range = 16, brightness = 1.4 }
			end
			ArtKit.fball(plan, f, u, 4.9, 0.22, 0.3, P.coolLamp, lamp)
		end
	end

	-- service alley: pipes and vents
	if o.alley then
		for i = 1, math.max(1, math.floor(len / 18)) do
			local u = f.u0 + (i - 0.5) * (len / math.max(1, math.floor(len / 18)))
			ArtKit.fvcyl(plan, f, u, 0, 0.3, 0.3, top - 1.2, P.steelDark, { material = "Metal" })
			ArtKit.fbox(plan, f, u, 3.2, 0.3, 1.4, 0.4, 0.5, P.steel)
		end
	end
end

-- Open door slots in a building wall get a header above them and posts at the sides.
function FacadeArt.doorHeader(
	plan: ArtKit.Plan,
	f: ArtKit.Face,
	u0: number,
	u1: number,
	fadeWith: string?,
	label: string?
)
	local w = u1 - u0
	local mid = (u0 + u1) / 2
	local sf: ArtKit.Face = {
		side = f.side,
		u0 = u0,
		u1 = u1,
		at = f.at,
		h = f.h,
		group = f.group,
		fadeWith = fadeWith,
	}
	-- header sits above head height; the opening below stays clear
	ArtKit.fbox(
		plan,
		sf,
		mid,
		(7.4 + f.h) / 2,
		0.2,
		w + 1.4,
		f.h - 7.4,
		0.5,
		P.wallDark,
		{ material = "Concrete" }
	)
	ArtKit.fbox(plan, sf, mid, 7.4, 0.4, w + 1.8, 0.45, 0.7, P.trim)
	neonStrip(plan, sf, mid, 7.1, w + 0.4, 0.28, P.coral, P.coralDim)
	if label ~= nil then
		FacadeArt.sign(
			plan,
			sf,
			label,
			mid,
			9.6,
			math.min(w + 1, 9),
			1.8,
			"#FFFFFF",
			"#1B2A44",
			P.cyan
		)
	end
	-- posts: thin and flush with the wall edge
	for _, u in { u0 - 0.2, u1 + 0.2 } do
		ArtKit.fbox(plan, sf, u, 3.4, 0.3, 0.4, 6.8, 0.6, P.plinth, { material = "Metal" })
	end
end

-- Thin neon strips up the corners of a box, above the shopfronts.
function FacadeArt.corners(
	plan: ArtKit.Plan,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	h: number,
	fadeWith: string?,
	gh: number
)
	local color = { P.cyan, P.coral }
	local dim = { P.cyanDim, P.coralDim }
	local k = 0
	for _, c in { { x0, z0 }, { x1, z0 }, { x1, z1 }, { x0, z1 } } do
		k += 1
		local cx, cz = c[1] :: number, c[2] :: number
		local ox = if cx == x0 then -0.15 else 0.15
		local oz = if cz == z0 then -0.15 else 0.15
		local y0, y1 = gh + 0.9, h - 2
		if y1 > y0 + 1 then
			ArtKit.box(
				plan,
				"Facades",
				cx + ox,
				(y0 + y1) / 2,
				cz + oz,
				0.3,
				y1 - y0,
				0.3,
				color[(k % 2) + 1] :: string,
				{
					material = "Neon",
					fadeWith = fadeWith,
					neon = ArtKit.glow(
						color[(k % 2) + 1] :: string,
						dim[(k % 2) + 1] :: string,
						0,
						true
					),
				}
			)
		end
	end
end

return FacadeArt
