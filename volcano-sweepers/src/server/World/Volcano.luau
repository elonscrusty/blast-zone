--!strict
-- The volcano: carter's picked look of Models/BigVolcano (A "Chunky Tiers": toy steps, boulders at
-- the foot, lava streaks, a glowing crater with smoke and embers), scaled so its whole foot fits
-- inside the Lava Heart's inner edge (WorldPlan coneRadius, 60 studs on the big island).
--
--   Volcano.buildCore(root, plan)   the invisible solid core (radius = coneRadius): ESSENTIAL, built
--                                   with the ground so nobody can ever walk into the mountain
--   Volcano.build(folder, plan)     the mountain itself (built later, with the scenery); returns the
--                                   parts World pulses with the Glow attribute
--
-- Lava here is DECOR ONLY: no scripts, no touch, never hurts anyone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local WorldPlan = require(Shared.WorldPlan)

local Landmarks = require(script.Parent.Models.Landmarks)
local Wiring = require(script.Parent.Models.Wiring)
local WorldUtil = require(script.Parent.WorldUtil)

local Volcano = {}

export type Refs = {
	model: Model,
	lava: BasePart,
	glow: BasePart,
	light: PointLight,
	bubbles: { BasePart },
}

local P = WorldUtil.Palette
local CORE_MIN_HEIGHT = 90

-- The folder "Volcano" with the solid core in it. Taller than the mountain so nobody climbs over.
function Volcano.buildCore(root: Instance, plan: WorldPlan.Plan): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Volcano"
	local scale = Wiring.volcanoScale(plan.coneRadius)
	local _, top = Wiring.volcanoBounds(scale)
	local h = math.max(CORE_MIN_HEIGHT, top + 10)
	local gy = Config.World.groundY
	WorldUtil.cylinder(
		folder,
		"ConeCollision",
		Vector3.new(0, gy + h / 2, 0),
		(plan.coneRadius - 0.2) * 2,
		h,
		"#FFFFFF",
		{ collide = true, transparency = 1 }
	)
	folder.Parent = root
	return folder
end

local function partIn(model: Instance, name: string): BasePart?
	local inst = model:FindFirstChild(name, true)
	if inst ~= nil and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

function Volcano.build(folder: Instance, plan: WorldPlan.Plan): Refs?
	local scale = Wiring.volcanoScale(plan.coneRadius)
	local origin = CFrame.new(0, Config.World.groundY, 0)
	local refs =
		Landmarks.build("volcano", folder, origin, { variant = Wiring.LOOK, scale = scale })
	if refs == nil then
		return nil
	end
	local model = refs.model

	-- the core from buildCore keeps everyone out; the model's own (smaller) one is not needed
	local ownCore = model:FindFirstChild(Wiring.PART.cone)
	if ownCore ~= nil then
		ownCore:Destroy()
	end

	local lava = partIn(model, Wiring.PART.craterLava)
	local glow = partIn(model, Wiring.PART.craterGlow)
	if lava == nil or glow == nil then
		warn("[Volcano] the volcano model has no crater lava: the glow will not pulse")
		return nil
	end
	local bubbles: { BasePart } = {}
	for _, part in refs.glow do
		if part ~= lava and part ~= glow then
			table.insert(bubbles, part)
		end
	end

	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex(P.orange)
	light.Brightness = 3
	light.Range = 60 -- the most a PointLight reaches
	light.Shadows = false
	light.Parent = glow

	return { model = model, lava = lava, glow = glow, light = light, bubbles = bubbles }
end

return Volcano
