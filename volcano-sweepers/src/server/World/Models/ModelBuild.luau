--!strict
-- Turns a pure part list (Models/Parts) into real Parts. Roblox only (Lune tests do not load this).
-- Every part is Anchored and Massless; only parts marked `collide` collide or answer queries.
-- Lava, water and glass here are decor: no scripts, no touch events, nothing that hurts anyone.

local Parts = require(script.Parent.Parts)
local WorldUtil = require(script.Parent.Parent.WorldUtil)

local ModelBuild = {}

export type Refs = {
	model: Model,
	glow: { BasePart }, -- the lava / water / lamp surfaces the world may pulse
	beam: Model?, -- the lighthouse beam (turn it with beam:PivotTo)
}

local function material(name: string): Enum.Material
	local ok, value = pcall(function(): Enum.Material
		return (Enum.Material :: any)[name]
	end)
	if ok and value ~= nil then
		return value
	end
	return Enum.Material.SmoothPlastic
end

local function partFrom(parent: Instance, p: Parts.Part, origin: CFrame): BasePart
	local rot = CFrame.fromEulerAnglesYXZ(p.rot[1], p.rot[2], p.rot[3])
	local cf = origin * CFrame.new(p.pos[1], p.pos[2], p.pos[3]) * rot
	local extra: WorldUtil.Extra = {
		material = material(p.material),
		transparency = p.transparency,
		collide = p.collide,
		shadow = p.shadow,
	}
	local size = Vector3.new(p.size[1], p.size[2], p.size[3])
	if p.kind == "wedge" then
		return WorldUtil.wedge(parent, p.name, cf, size, p.color, extra)
	elseif p.kind == "ball" then
		local ball = WorldUtil.part(parent, {
			name = p.name,
			size = size,
			cf = cf,
			color = p.color,
			shape = Enum.PartType.Ball,
			material = extra.material,
			transparency = extra.transparency,
			collide = extra.collide,
			shadow = extra.shadow,
		})
		return ball
	elseif p.kind == "cyl" then
		-- Roblox cylinders lie along X, so turn the upright spec 90 degrees
		return WorldUtil.part(parent, {
			name = p.name,
			size = Vector3.new(p.size[2], p.size[1], p.size[3]),
			cf = cf * CFrame.Angles(0, 0, math.pi / 2),
			color = p.color,
			shape = Enum.PartType.Cylinder,
			material = extra.material,
			transparency = extra.transparency,
			collide = extra.collide,
			shadow = extra.shadow,
		})
	end
	return WorldUtil.block(parent, p.name, cf, size, p.color, extra)
end

local EMITTERS: { [string]: WorldUtil.EmitterOpts } = {
	smoke = {
		colorA = "#8A7B84",
		colorB = "#3C333A",
		rate = 7,
		lifeMin = 6,
		lifeMax = 9,
		speedMin = 5,
		speedMax = 9,
		sizeA = 8,
		sizeB = 22,
		spread = 14,
		accel = Vector3.new(1.2, 0.8, 0),
		alpha = 0.5,
		texture = WorldUtil.SMOKE_TEXTURE,
	},
	embers = {
		colorA = "#FFC24D",
		colorB = "#FF4A1F",
		rate = 8,
		lifeMin = 2,
		lifeMax = 3.5,
		speedMin = 10,
		speedMax = 22,
		sizeA = 0.7,
		sizeB = 0.15,
		spread = 28,
		accel = Vector3.new(0, -12, 0),
		light = 1,
		alpha = 0,
	},
	steam = {
		colorA = "#FFFFFF",
		colorB = "#DFF6FF",
		rate = 5,
		lifeMin = 3,
		lifeMax = 4.5,
		speedMin = 2.5,
		speedMax = 4,
		sizeA = 3,
		sizeB = 8,
		spread = 12,
		accel = Vector3.new(0, 0.6, 0),
		alpha = 0.55,
		texture = WorldUtil.SMOKE_TEXTURE,
	},
	spray = {
		colorA = "#FFFFFF",
		colorB = "#BFEFFF",
		rate = 14,
		lifeMin = 1.5,
		lifeMax = 2.4,
		speedMin = 6,
		speedMax = 12,
		sizeA = 1,
		sizeB = 0.3,
		spread = 35,
		accel = Vector3.new(0, -16, 0),
		alpha = 0.2,
	},
}

-- Build a list under `parent`, standing at `origin` (the middle of the footprint on the ground).
-- The model's PrimaryPart is left empty; the beam, when there is one, is its own child Model whose
-- pivot is the lamp, so beam:PivotTo(beam:GetPivot() * CFrame.Angles(0, dt, 0)) spins it.
function ModelBuild.build(parent: Instance, list: Parts.List, origin: CFrame): Refs
	local model = Instance.new("Model")
	model.Name = list.name
	model:SetAttribute("Variant", list.variant)

	local glow: { BasePart } = {}
	local beamModel: Model? = nil
	local beamPivot = list.pivots.beam
	for _, p in list.parts do
		local target: Instance = model
		if p.group == "beam" then
			if beamModel == nil then
				local m = Instance.new("Model")
				m.Name = "Beam"
				m.Parent = model
				beamModel = m
			end
			target = beamModel :: Model
		end
		local inst = partFrom(target, p, origin)
		if p.group == "glow" then
			table.insert(glow, inst)
		end
	end
	if beamModel ~= nil and beamPivot ~= nil then
		beamModel.WorldPivot = origin * CFrame.new(beamPivot[1], beamPivot[2], beamPivot[3])
	end

	for i, f in list.fx do
		local opts = EMITTERS[f.kind]
		if opts ~= nil then
			local anchor = WorldUtil.emitterAnchor(
				model,
				`Fx{i}`,
				origin * CFrame.new(f.pos[1], f.pos[2], f.pos[3]),
				Vector3.new(math.max(f.radius, 1), 1, math.max(f.radius, 1))
			)
			WorldUtil.emitter(anchor, opts)
		end
	end

	model.Parent = parent
	return { model = model, glow = glow, beam = beamModel }
end

return ModelBuild
