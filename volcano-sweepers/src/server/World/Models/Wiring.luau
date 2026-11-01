--!strict
-- Which picked-look model stands where. PURE (Lune runs it): the World builders ask this module for
-- the model, its scale and whether it may collide; the tests ask it for exact part counts.
--
-- carter picked look A for both model sets: "toy" (Toy Pop) for the island props (Models/Registry)
-- and "A" (Toy) for the big landmarks (BigVolcano, LavaPool, HotSpring, Lighthouse).
--
--   Wiring.decor[kind]              the model behind a WorldPlan decor kind (nil = plain DecorKinds)
--   Wiring.decorScale(kind, s)      model scale for a decor item drawn at WorldPlan scale s
--   Wiring.kitSpec(name, v, text?)  Registry spec in the picked style
--   Wiring.landmarkSpec(kind, k)    landmark part list in the picked look
--   Wiring.volcanoScale(radius)     scale that fits the whole volcano foot inside `radius`
--   Wiring.lighthouseSpot(plan)     where the lighthouse stands (on a little island off the hub)
--   Wiring.postHutZ(counterA)       where the small Trade Hut stands in a Trade Post's frame
--   Wiring.partCount(plan, cost)    exact Part count of the whole world built from `plan`

local BigVolcano = require("./BigVolcano")
local HotSpring = require("./HotSpring")
local Kit = require("./Kit")
local LavaPool = require("./LavaPool")
local Lighthouse = require("./Lighthouse")
local Parts = require("./Parts")
local Registry = require("./Registry")

local Wiring = {}

Wiring.STYLE = "toy" -- island props: Toy Pop
Wiring.LOOK = "A" -- landmarks: Toy

Wiring.HUT_SCALE = 1 -- the Trade Hut at the hub
Wiring.POST_SCALE = 0.7 -- the small Trade Hut that makes a Trade Post

-- Part names the server hangs tags, prompts and signs on. tests/world_models checks every model
-- still has them, so a model change can never silently drop the sell prompt or a gate.
Wiring.PART = {
	counter = "Counter", -- TradeHut: VSSellPrompt goes on it
	gatePlate = "GatePlate", -- Gate: tagged VSGate, ZoneId attribute, GatePrompt child
	gateBeam = "Beam", -- Gate: the price sign billboard
	signBoard = "Board", -- Sign: the text board
	craterLava = "CraterLava", -- BigVolcano: pulses with the Glow attribute
	craterGlow = "CraterGlow", -- BigVolcano: carries the crater light
	cone = "ConeCollision", -- BigVolcano: the model's own core (the world builds a bigger one)
}

export type DecorModel = {
	name: string, -- Registry name, or landmark kind when `landmark`
	landmark: boolean,
	k: number, -- model scale = WorldPlan item scale x k (drawn about as big as the old decor)
	solid: boolean, -- false: nothing in it collides (small props never trap or block)
}

Wiring.decor = {
	palm = { name = "Palm", landmark = false, k = 1, solid = true }, -- only the trunk foot
	rock = { name = "Rocks", landmark = false, k = 0.6, solid = true }, -- only the big stone
	mushroom = { name = "Mushroom", landmark = false, k = 0.75, solid = false },
	spire = { name = "Spire", landmark = false, k = 0.8, solid = true }, -- only the bottom tier
	camp = { name = "Camp", landmark = false, k = 1, solid = false },
	pool = { name = "spring", landmark = true, k = 0.4, solid = true }, -- basin + a few rocks
	lavapool = { name = "lava", landmark = true, k = 0.4, solid = true }, -- a low stone ring
} :: { [string]: DecorModel }

type LandmarkModule = { spec: (variant: string, scale: number?) -> Parts.List }

local LANDMARKS: { [string]: LandmarkModule } = {
	volcano = BigVolcano,
	lava = LavaPool,
	spring = HotSpring,
	lighthouse = Lighthouse,
}

function Wiring.decorScale(kind: string, itemScale: number): number
	local d = Wiring.decor[kind]
	return itemScale * (if d ~= nil then d.k else 1)
end

function Wiring.kitSpec(name: string, v: number?, text: string?): Kit.Model
	return Registry.spec(name, { style = Wiring.STYLE, v = v, text = text })
end

function Wiring.landmarkSpec(kind: string, scale: number?): Parts.List
	local m = LANDMARKS[kind]
	if m == nil then
		error(`unknown landmark '{kind}'`)
	end
	return m.spec(Wiring.LOOK, scale)
end

-- Parts ModelBuild makes for a landmark list: its parts plus one emitter anchor per effect.
function Wiring.landmarkParts(list: Parts.List): number
	local n = #list.parts
	for _, f in list.fx do
		if Parts.FX_KINDS[f.kind] then
			n += 1
		end
	end
	return n
end

-- ===== the volcano =====

local volcanoReach: number? = nil

-- How far the volcano's foot (tiers, boulders, lava puddles) reaches from the middle at scale 1.
function Wiring.volcanoReach(): number
	local r = volcanoReach
	if r == nil then
		local reach = Parts.bounds(Wiring.landmarkSpec("volcano", 1))
		volcanoReach = reach
		return reach
	end
	return r
end

-- Scale so the whole foot fits 1 stud inside `radius` (the Lava Heart's inner edge = the core).
function Wiring.volcanoScale(radius: number): number
	return (radius - 1) / Wiring.volcanoReach()
end

-- (reach, top) of the volcano drawn at `scale` (generous: every part counted as its biggest side).
function Wiring.volcanoBounds(scale: number): (number, number)
	return Parts.bounds(Wiring.landmarkSpec("volcano", scale))
end

-- ===== the lighthouse =====

export type Spot = { x: number, z: number, y: number, ux: number, uz: number, isletRadius: number }

Wiring.LIGHTHOUSE_DEG = 8 -- degrees around the coast from the hub
Wiring.LIGHTHOUSE_OUT = 30 -- studs out to sea past the beach edge
Wiring.ISLET_RADIUS = 15
Wiring.ISLET_TOP = -0.3 -- a hair above the water (water top is groundY - 1.2)

-- On its own little sand island just off the beach, a short walk round the coast from the hub
-- (outside the invisible wall: nobody reaches it, it covers no ash). `u` points out to sea.
function Wiring.lighthouseSpot(hubAngleDeg: number, outerRadius: number): Spot
	local a = math.rad(hubAngleDeg + Wiring.LIGHTHOUSE_DEG)
	local r = outerRadius + Wiring.LIGHTHOUSE_OUT
	local ux, uz = math.cos(a), math.sin(a)
	return {
		x = r * ux,
		z = r * uz,
		y = Wiring.ISLET_TOP,
		ux = ux,
		uz = uz,
		isletRadius = Wiring.ISLET_RADIUS,
	}
end

-- ===== Trade Posts =====

local function partNamed(m: Kit.Model, name: string): Kit.Spec?
	for _, s in m.parts do
		if s.name == name then
			return s
		end
	end
	return nil
end

-- In a post's frame (local -Z looks inland at the pad, +Z goes out to sea) the small hut's origin
-- stands this far out, so its counter is exactly `counterA` (WorldPlan Post.counterA) studs out.
function Wiring.postHutZ(counterA: number): number
	local counter = partNamed(Wiring.kitSpec("TradeHut", 1, "TRADE POST"), Wiring.PART.counter)
	local cz = if counter ~= nil then counter.z else 0
	return counterA - cz * Wiring.POST_SCALE
end

-- ===== part count =====

-- Parts the World modules add around the models (kept in step with them by hand).
Wiring.EXTRA = {
	sea = 6, -- sea floor, water, two foams, wet sand, sand under
	ground = 2, -- the invisible walking disc and the Lava Heart disc
	spawn = 2, -- SpawnLocation + glow
	pad = 2, -- sell pad + its base
	hubSign = 2, -- the glowing arrow over each hub signpost
	postFlag = 3, -- pole, flag, top ball
	islet = 1, -- the lighthouse's sand island
	vent = 2,
	core = 1, -- the world's volcano core (the model's own one is removed)
}

export type Count = { total: number, parts: { [string]: number } }

-- Exact Part count of the world built from `plan`. `cost` = WorldPlan.partCost for the plain decor.
function Wiring.partCount(plan: any, cost: { [string]: number }): Count
	local E = Wiring.EXTRA
	local out: { [string]: number } = {}

	local ground = E.sea + E.ground + #plan.wall
	for _, ring in plan.rings do
		ground += #ring.segs
	end
	for _, rope in plan.ropes do
		ground += #rope.segs
	end
	out.ground = ground

	local hut = #Wiring.kitSpec("TradeHut", 1, "TRADE HUT").parts
	local sign = #Wiring.kitSpec("Sign", 1, "SIGN").parts
	out.hub = #plan.hub.spawns * E.spawn + #plan.hub.pads * E.pad + hut + 2 * (sign + E.hubSign)

	local gates = 0
	for _ in plan.gates do
		gates += #Wiring.kitSpec("Gate", 1).parts
	end
	out.gates = gates

	local postHut = #Wiring.kitSpec("TradeHut", 1, "TRADE POST").parts
	out.posts = #plan.posts * (postHut + E.pad + E.postFlag)
	out.signs = #plan.signs * sign
	out.vents = #plan.vents * E.vent

	local volcano = Wiring.landmarkSpec("volcano", Wiring.volcanoScale(plan.coneRadius))
	out.volcano = Wiring.landmarkParts(volcano) - 1 + E.core
	out.lighthouse = Wiring.landmarkParts(Wiring.landmarkSpec("lighthouse", 1)) + E.islet

	local decor = 0
	for _, it in plan.decor do
		local d = Wiring.decor[it.kind]
		if d == nil then
			decor += cost[it.kind] or 1
		elseif d.landmark then
			decor += Wiring.landmarkParts(Wiring.landmarkSpec(d.name, 1))
		else
			decor += #Wiring.kitSpec(d.name, it.v).parts
		end
	end
	out.decor = decor

	local total = 0
	for _, n in out do
		total += n
	end
	return { total = total, parts = out }
end

return Wiring
