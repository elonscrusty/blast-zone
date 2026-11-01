--!strict
-- Pure logic for the tool every character holds (client/Vfx/HeldTool builds and animates it).
-- No Roblox types, so Lune can test it. Colours are hex strings, sizes/offsets are {x, y, z} studs,
-- rotations are {x, y, z} degrees (applied as CFrame.Angles after the offset).
--
-- Two anchors:
--   "hand"  tool space: the grip is the origin, the tool hangs along -Y (the business end is at the
--           bottom), -Z is the character's forward. The glue tilts the whole thing forward.
--   "back"  torso space: origin at the torso centre, +Z is BEHIND the character (backpacks, wings).
--
-- Every tool has its own charming look built only from Parts (no asset ids):
--   twig_broom   stick + twine + a fan of straw twigs
--   push_broom   yellow pole + wide wooden head + dark bristle strip
--   leaf_blower  blue motor box + long white tube + orange nozzle with a glowing vent
--   dust_vac     green wand + floor head, and a green canister backpack with a window full of ash
--   turbo_vac    racing-stripe body + chrome tube + spinning gold ring, twin rocket tanks on the back
--   lava_mop     dark handle + glowing lava strands
--   dragon_vac   purple dragon head (eyes, horns, glowing mouth) + little wings on the back
--   volcano_vac  gold handle + a mini volcano nozzle with a lava crater, big gold tank on the back
--
--   HeldToolLogic.blueprint(id) -> Blueprint        (unknown id -> the twig broom)
--   HeldToolLogic.resolve(attr, fallback) -> string  a valid tool id
--   HeldToolLogic.pose(style, t, amp) -> (pitch, roll, arm)   degrees; 0 at t = 0 and t = 1
--   HeldToolLogic.swingTime(interval) -> number
--   HeldToolLogic.wantModel(dist, has) / canAnimate(dist)     distance rules (hysteresis)
--   HeldToolLogic.wantLite(dist, isLite)                       lite model far away (hysteresis)
-- The glue now draws the Part-built models of Shared/Models/SweeperTools (look A); a blueprint
-- still gives each tool its swing style, swing size and resting tilt.

local Tools = require("../Catalog/Tools")

export type Shape = "Block" | "Cylinder" | "Ball" | "Wedge"
export type Material = "Wood" | "SmoothPlastic" | "Neon" | "Metal" | "Fabric" | "Glass"
export type Anchor = "hand" | "back"
export type Style = "sweep" | "blow" | "vac" | "mop" | "roar" | "mega"

export type PartSpec = {
	name: string,
	shape: Shape,
	size: { number },
	pos: { number },
	rot: { number },
	color: string,
	material: Material,
	transparency: number,
	anchor: Anchor,
}

export type Blueprint = {
	id: string,
	style: Style,
	amp: number, -- swing size in degrees
	tilt: number, -- resting forward tilt of the tool, degrees
	parts: { PartSpec },
}

local HeldToolLogic = {}

HeldToolLogic.MAX_PARTS = 16
HeldToolLogic.BUILD_RADIUS = 140 -- build other players' tools within this many studs
HeldToolLogic.DROP_RADIUS = 170 -- ... and drop them beyond this (hysteresis)
HeldToolLogic.ANIM_RADIUS = 110 -- swing animations only this close
HeldToolLogic.MAX_MODELS = 16
HeldToolLogic.LITE_RADIUS = 60 -- other players' tools farther than this use the lite (basic) model
HeldToolLogic.FULL_RADIUS = 50 -- ... and go back to full detail closer than this (hysteresis)

-- ===== tiny builders =====

local function part(
	name: string,
	shape: Shape,
	size: { number },
	pos: { number },
	rot: { number },
	color: string,
	material: Material,
	transparency: number?,
	anchor: Anchor?
): PartSpec
	return {
		name = name,
		shape = shape,
		size = size,
		pos = pos,
		rot = rot,
		color = color,
		material = material,
		transparency = transparency or 0,
		anchor = anchor or "hand",
	}
end

-- A round rod along Y from yTop down `len` studs (a Roblox cylinder's axis is X: roll it 90 degrees).
local function rod(
	name: string,
	len: number,
	dia: number,
	yTop: number,
	color: string,
	material: Material,
	x: number?,
	z: number?,
	anchor: Anchor?
): PartSpec
	return part(
		name,
		"Cylinder",
		{ len, dia, dia },
		{ x or 0, yTop - len / 2, z or 0 },
		{ 0, 0, 90 },
		color,
		material,
		0,
		anchor
	)
end

local function ball(
	name: string,
	dia: number,
	pos: { number },
	color: string,
	material: Material,
	anchor: Anchor?
): PartSpec
	return part(name, "Ball", { dia, dia, dia }, pos, { 0, 0, 0 }, color, material, 0, anchor)
end

local function colorOf(id: string, fallback: string): string
	local tool = Tools.byId[id]
	return if tool ~= nil then tool.color else fallback
end

-- ===== the eight looks =====

local builders: { [string]: () -> Blueprint } = {}

builders.twig_broom = function(): Blueprint
	local wood = colorOf("twig_broom", "#A9805B")
	local parts = {
		rod("Stick", 3.6, 0.22, 0.6, wood, "Wood"),
		rod("Twine", 0.25, 0.42, -2.75, "#E8D9A8", "Fabric"),
	}
	-- a fan of five straw twigs
	local xs = { -0.3, -0.15, 0, 0.15, 0.3 }
	local tilt = { 14, 7, 0, -7, -14 }
	for k = 1, 5 do
		table.insert(
			parts,
			part(
				"Twig" .. k,
				"Block",
				{ 0.12, 1.1, 0.12 },
				{ xs[k], -3.45, 0 },
				{ 0, 0, tilt[k] },
				if k % 2 == 0 then "#E0BE78" else "#C9A25A",
				"Wood"
			)
		)
	end
	return { id = "twig_broom", style = "sweep", amp = 38, tilt = 38, parts = parts }
end

builders.push_broom = function(): Blueprint
	local pole = colorOf("push_broom", "#E0B040")
	return {
		id = "push_broom",
		style = "sweep",
		amp = 32,
		tilt = 40,
		parts = {
			rod("Pole", 3.8, 0.22, 0.6, pole, "SmoothPlastic"),
			part(
				"Bracket",
				"Block",
				{ 0.3, 0.4, 0.3 },
				{ 0, -3.05, 0 },
				{ 0, 0, 0 },
				"#C99A2E",
				"Metal"
			),
			part(
				"Head",
				"Block",
				{ 2.6, 0.35, 0.55 },
				{ 0, -3.3, 0 },
				{ 0, 0, 0 },
				"#8A5A32",
				"Wood"
			),
			part(
				"Bristles",
				"Block",
				{ 2.5, 0.45, 0.45 },
				{ 0, -3.65, 0 },
				{ 0, 0, 0 },
				"#3A2E28",
				"Fabric"
			),
		},
	}
end

builders.leaf_blower = function(): Blueprint
	local body = colorOf("leaf_blower", "#4FB3E8")
	return {
		id = "leaf_blower",
		style = "blow",
		amp = 24,
		tilt = 52,
		parts = {
			part(
				"Handle",
				"Block",
				{ 0.2, 0.5, 0.6 },
				{ 0, 0.15, 0 },
				{ 0, 0, 0 },
				"#2B2430",
				"SmoothPlastic"
			),
			part(
				"Motor",
				"Block",
				{ 0.9, 1.1, 0.8 },
				{ 0, -0.5, 0 },
				{ 0, 0, 0 },
				body,
				"SmoothPlastic"
			),
			part(
				"Cap",
				"Cylinder",
				{ 0.3, 0.7, 0.7 },
				{ 0.55, -0.5, 0 },
				{ 0, 0, 0 },
				"#FFFFFF",
				"SmoothPlastic"
			),
			rod("Tube", 2.6, 0.38, -1.0, "#E8F4FA", "SmoothPlastic"),
			rod("Nozzle", 0.25, 0.52, -3.5, "#FF7A2F", "SmoothPlastic"),
			ball("Vent", 0.3, { 0, -3.72, 0 }, "#BFF0FF", "Neon"),
		},
	}
end

builders.dust_vac = function(): Blueprint
	local green = colorOf("dust_vac", "#6BCB77")
	return {
		id = "dust_vac",
		style = "vac",
		amp = 22,
		tilt = 42,
		parts = {
			rod("Wand", 3.2, 0.26, 0.3, green, "SmoothPlastic"),
			part(
				"FloorHead",
				"Block",
				{ 1.3, 0.3, 0.6 },
				{ 0, -3.0, 0 },
				{ 0, 0, 0 },
				"#3E8E4A",
				"SmoothPlastic"
			),
			part(
				"Slot",
				"Block",
				{ 1.1, 0.06, 0.1 },
				{ 0, -3.16, -0.22 },
				{ 0, 0, 0 },
				"#C8FFB0",
				"Neon"
			),
			-- the vac backpack
			rod("Canister", 1.8, 1.1, 0.9, green, "SmoothPlastic", 0, 1.05, "back"),
			ball("Lid", 1.1, { 0, 0.9, 1.05 }, "#F4FFF2", "SmoothPlastic", "back"),
			part(
				"Window",
				"Block",
				{ 0.5, 1.0, 0.1 },
				{ 0, -0.1, 1.6 },
				{ 0, 0, 0 },
				"#B8B2AA",
				"Glass",
				0.35,
				"back"
			),
			part(
				"Strap",
				"Block",
				{ 1.25, 0.18, 1.25 },
				{ 0, -0.55, 1.05 },
				{ 0, 0, 0 },
				"#2B2430",
				"Fabric",
				0,
				"back"
			),
		},
	}
end

builders.turbo_vac = function(): Blueprint
	local orange = colorOf("turbo_vac", "#FF7A59")
	return {
		id = "turbo_vac",
		style = "vac",
		amp = 26,
		tilt = 45,
		parts = {
			rod("Body", 1.3, 1.0, 0.05, orange, "SmoothPlastic"),
			rod("Stripe", 0.2, 1.04, -0.5, "#FFFFFF", "SmoothPlastic"),
			part(
				"FinL",
				"Wedge",
				{ 0.15, 0.7, 0.6 },
				{ -0.55, -0.6, 0.2 },
				{ 0, 0, 0 },
				"#C94A30",
				"SmoothPlastic"
			),
			part(
				"FinR",
				"Wedge",
				{ 0.15, 0.7, 0.6 },
				{ 0.55, -0.6, 0.2 },
				{ 0, 0, 0 },
				"#C94A30",
				"SmoothPlastic"
			),
			rod("Tube", 2.4, 0.34, -1.25, "#D8D8E0", "Metal"),
			rod("TurboRing", 0.2, 0.9, -3.6, "#FFD23F", "Neon"),
			-- twin rocket tanks on the back
			rod("TankL", 1.5, 0.55, 0.75, orange, "SmoothPlastic", -0.35, 0.85, "back"),
			rod("TankR", 1.5, 0.55, 0.75, orange, "SmoothPlastic", 0.35, 0.85, "back"),
			ball("FlameL", 0.45, { -0.35, -0.8, 0.85 }, "#FFB020", "Neon", "back"),
			ball("FlameR", 0.45, { 0.35, -0.8, 0.85 }, "#FFB020", "Neon", "back"),
		},
	}
end

builders.lava_mop = function(): Blueprint
	local handle = "#6E2A1E"
	local parts = {
		rod("Handle", 3.6, 0.24, 0.6, handle, "Wood"),
		rod("Collar", 0.3, 0.5, -2.85, "#3A2E28", "Metal"),
	}
	local hot = colorOf("lava_mop", "#FF5A36")
	for k = 0, 5 do
		local a = math.rad(k * 60)
		local x, z = math.cos(a) * 0.25, math.sin(a) * 0.25
		table.insert(
			parts,
			part(
				"Strand" .. (k + 1),
				"Block",
				{ 0.16, 1.0, 0.16 },
				{ x, -3.55, z },
				{ z * 40, 0, -x * 40 }, -- lean out a little
				if k % 2 == 0 then hot else "#FFB020",
				"Neon"
			)
		)
	end
	return { id = "lava_mop", style = "mop", amp = 30, tilt = 36, parts = parts }
end

builders.dragon_vac = function(): Blueprint
	local purple = colorOf("dragon_vac", "#9B5DE5")
	return {
		id = "dragon_vac",
		style = "roar",
		amp = 26,
		tilt = 44,
		parts = {
			rod("Neck", 2.0, 0.32, 0.4, purple, "SmoothPlastic"),
			part(
				"Head",
				"Block",
				{ 0.9, 0.9, 0.9 },
				{ 0, -2.0, 0 },
				{ 0, 0, 0 },
				purple,
				"SmoothPlastic"
			),
			part(
				"Snout",
				"Block",
				{ 0.7, 0.8, 0.6 },
				{ 0, -2.75, -0.1 },
				{ 0, 0, 0 },
				"#B07EF0",
				"SmoothPlastic"
			),
			part(
				"Mouth",
				"Block",
				{ 0.5, 0.08, 0.4 },
				{ 0, -3.17, -0.1 },
				{ 0, 0, 0 },
				"#FF7AC8",
				"Neon"
			),
			ball("EyeL", 0.24, { -0.28, -1.85, -0.47 }, "#FFE14D", "Neon"),
			ball("EyeR", 0.24, { 0.28, -1.85, -0.47 }, "#FFE14D", "Neon"),
			part(
				"HornL",
				"Wedge",
				{ 0.15, 0.5, 0.3 },
				{ -0.3, -1.4, 0.2 },
				{ -20, 0, 0 },
				"#FFF4DC",
				"SmoothPlastic"
			),
			part(
				"HornR",
				"Wedge",
				{ 0.15, 0.5, 0.3 },
				{ 0.3, -1.4, 0.2 },
				{ -20, 0, 0 },
				"#FFF4DC",
				"SmoothPlastic"
			),
			-- little wings on the back
			part(
				"WingL",
				"Wedge",
				{ 0.15, 1.4, 1.2 },
				{ -0.6, 0.3, 0.8 },
				{ 0, -25, 20 },
				"#7A3FC4",
				"SmoothPlastic",
				0,
				"back"
			),
			part(
				"WingR",
				"Wedge",
				{ 0.15, 1.4, 1.2 },
				{ 0.6, 0.3, 0.8 },
				{ 0, 25, -20 },
				"#7A3FC4",
				"SmoothPlastic",
				0,
				"back"
			),
		},
	}
end

builders.volcano_vac = function(): Blueprint
	local gold = colorOf("volcano_vac", "#FFD23F")
	return {
		id = "volcano_vac",
		style = "mega",
		amp = 30,
		tilt = 46,
		parts = {
			rod("Handle", 1.4, 0.3, 0.4, gold, "Metal"),
			rod("Band", 0.12, 1.0, -0.95, gold, "Metal"),
			rod("Cone1", 0.6, 0.9, -1.0, "#7A4A3A", "SmoothPlastic"),
			rod("Cone2", 0.6, 1.3, -1.6, "#6A4034", "SmoothPlastic"),
			rod("Cone3", 0.6, 1.7, -2.2, "#5E3A30", "SmoothPlastic"),
			rod("Crater", 0.12, 1.75, -2.8, "#FF7A2F", "Neon"),
			ball("LavaCore", 0.9, { 0, -2.85, 0 }, "#FFB020", "Neon"),
			-- the big gold tank with a lava window and a tiny volcano on top
			rod("Tank", 2.0, 1.3, 1.0, gold, "Metal", 0, 1.1, "back"),
			part(
				"LavaWindow",
				"Block",
				{ 0.5, 1.2, 0.1 },
				{ 0, 0, 1.76 },
				{ 0, 0, 0 },
				"#FF5A1F",
				"Neon",
				0,
				"back"
			),
			rod("Peak1", 0.3, 1.0, 1.3, "#6E4A3E", "SmoothPlastic", 0, 1.1, "back"),
			rod("Peak2", 0.3, 0.6, 1.6, "#6E4A3E", "SmoothPlastic", 0, 1.1, "back"),
			ball("Ember", 0.35, { 0, 1.72, 1.1 }, "#FF7A2F", "Neon", "back"),
		},
	}
end

-- ===== API =====

-- The look for a tool id. Unknown ids get the twig broom (never nil, never an error).
function HeldToolLogic.blueprint(id: any): Blueprint
	local make = if type(id) == "string" then builders[id] else nil
	if make == nil then
		make = builders.twig_broom
	end
	return make()
end

function HeldToolLogic.hasBlueprint(id: string): boolean
	return builders[id] ~= nil
end

-- A valid tool id: the attribute when it names a real tool, else the fallback, else the twig broom.
function HeldToolLogic.resolve(attr: any, fallback: any): string
	if type(attr) == "string" and Tools.byId[attr] ~= nil then
		return attr
	end
	if type(fallback) == "string" and Tools.byId[fallback] ~= nil then
		return fallback
	end
	return "twig_broom"
end

local function ease(k: number): number
	return k * k * (3 - 2 * k)
end

-- Swing pose at t in [0, 1] for a style, scaled by amp (degrees).
-- Returns pitch (tip swings forward +), roll (tip swings sideways), arm (shoulder raises forward +).
-- Every style starts and ends at exactly (0, 0, 0) so the tool always settles back to rest.
function HeldToolLogic.pose(style: Style, t: number, amp: number): (number, number, number)
	if t ~= t or t <= 0 or t >= 1 then
		return 0, 0, 0
	end
	local a = if amp == amp then math.clamp(amp, 0, 60) else 0
	local hump = math.sin(math.pi * t) -- 0 -> 1 -> 0
	if style == "sweep" then
		-- wind up to one side, swish across, settle back
		local roll
		if t < 0.2 then
			roll = 0.45 * a * ease(t / 0.2)
		elseif t < 0.55 then
			roll = 0.45 * a + (-a - 0.45 * a) * ease((t - 0.2) / 0.35)
		else
			roll = -a * (1 - ease((t - 0.55) / 0.45))
		end
		return 0.25 * a * hump, roll, 18 * hump
	elseif style == "blow" then
		-- a quick side-to-side "whoosh" with the nozzle pushed forward
		return 0.4 * a * hump, a * math.sin(2 * math.pi * t) * 0.8, 24 * hump
	elseif style == "vac" then
		-- push the nozzle forward and pull back, with a little wiggle
		return a * hump, 0.3 * a * math.sin(2 * math.pi * t), 30 * hump
	elseif style == "mop" then
		-- a loopy figure eight
		return 0.4 * a * math.sin(2 * math.pi * t) * hump, a * math.sin(2 * math.pi * t), 16 * hump
	elseif style == "roar" then
		-- lunge forward and shake the head
		return a * hump, 7 * math.sin(6 * math.pi * t) * hump, 28 * hump
	else -- mega
		return 0.75 * a * hump, 0.5 * a * math.sin(2 * math.pi * t), 34 * hump
	end
end

-- How long one swing animation lasts for a swing interval (seconds).
function HeldToolLogic.swingTime(interval: any): number
	local i = if type(interval) == "number" and interval == interval then interval else 0.34
	return math.clamp(i * 0.85, 0.16, 0.32)
end

-- Should another player's tool model exist at this distance? `has` = it exists now (hysteresis).
function HeldToolLogic.wantModel(dist: number, has: boolean): boolean
	if dist ~= dist then
		return false
	end
	if has then
		return dist <= HeldToolLogic.DROP_RADIUS
	end
	return dist <= HeldToolLogic.BUILD_RADIUS
end

-- Should another player's tool be the lite (far away) model? `isLite` = it is lite now (hysteresis).
function HeldToolLogic.wantLite(dist: number, isLite: boolean): boolean
	if dist ~= dist then
		return true
	end
	if isLite then
		return dist > HeldToolLogic.FULL_RADIUS
	end
	return dist > HeldToolLogic.LITE_RADIUS
end

function HeldToolLogic.canAnimate(dist: number): boolean
	return dist == dist and dist <= HeldToolLogic.ANIM_RADIUS
end

return HeldToolLogic
