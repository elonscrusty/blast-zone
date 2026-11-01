--!strict
-- Turns a list of PartSpec (see ModelKit) into a real Model. Roblox only; the spec modules stay pure.
-- Every part is non-colliding, can't be queried or touched, casts no shadow (phone-light).
-- A tiny see-through "Root" part sits at the model's origin and is the PrimaryPart.
--   weld = true   parts are WeldConstrained to Root and unanchored (held tools, bots that move)
--   weld = false  parts stay Anchored (a model that is placed and moved with PivotTo of anchored parts
--                 should use weld = true; plain scenery can stay anchored)

local WorldUtil = require(script.Parent.Parent.WorldUtil)
local ModelKit = require(script.Parent.ModelKit)

local ModelBuilder = {}

export type Opts = {
	cf: CFrame?, -- where the model's origin goes (default: the world origin)
	weld: boolean?, -- default true
	parent: Instance?,
	name: string?,
}

local MATERIALS: { [string]: Enum.Material } = {
	Wood = Enum.Material.Wood,
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Neon = Enum.Material.Neon,
	Metal = Enum.Material.Metal,
	Fabric = Enum.Material.Fabric,
	Glass = Enum.Material.Glass,
}

-- Local CFrame of one spec, relative to the model origin.
function ModelBuilder.localCFrame(p: ModelKit.PartSpec): CFrame
	local cf = CFrame.new(p.pos[1], p.pos[2], p.pos[3])
		* CFrame.Angles(math.rad(p.rot[1]), math.rad(p.rot[2]), math.rad(p.rot[3]))
	if p.kind == "Cyl" then
		-- a spec cylinder's axis is Y; a Roblox cylinder's axis is X
		cf = cf * CFrame.Angles(0, 0, math.pi / 2)
	end
	return cf
end

function ModelBuilder.partSize(p: ModelKit.PartSpec): Vector3
	if p.kind == "Cyl" then
		return Vector3.new(p.size[2], p.size[1], p.size[3])
	end
	return Vector3.new(p.size[1], p.size[2], p.size[3])
end

local function makePart(model: Model, origin: CFrame, p: ModelKit.PartSpec): BasePart
	local shape = Enum.PartType.Block
	if p.kind == "Cyl" then
		shape = Enum.PartType.Cylinder
	elseif p.kind == "Ball" then
		shape = Enum.PartType.Ball
	end
	return WorldUtil.part(model, {
		name = p.name,
		size = ModelBuilder.partSize(p),
		cf = origin * ModelBuilder.localCFrame(p),
		color = p.color,
		material = MATERIALS[p.mat] or Enum.Material.SmoothPlastic,
		shape = shape,
		transparency = p.alpha,
	})
end

function ModelBuilder.build(name: string, parts: { ModelKit.PartSpec }, opts: Opts?): Model
	local o: Opts = opts or {}
	local origin = o.cf or CFrame.new()
	local model = Instance.new("Model")
	model.Name = o.name or name
	local root = WorldUtil.block(
		model,
		"Root",
		origin,
		Vector3.new(0.2, 0.2, 0.2),
		"#FFFFFF",
		{ transparency = 1 }
	)
	model.PrimaryPart = root
	local weld = o.weld ~= false
	for _, p in parts do
		local inst = makePart(model, origin, p)
		if weld then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = inst
			w.Parent = inst
			inst.Anchored = false
		end
	end
	if weld then
		root.Anchored = false
	end
	model.Parent = o.parent
	return model
end

-- Every direct child part whose name starts with `prefix` (e.g. "Spin" for propellers and brushes).
function ModelBuilder.partsNamed(model: Model, prefix: string): { BasePart }
	local out: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, #prefix) == prefix then
			table.insert(out, child)
		end
	end
	return out
end

return ModelBuilder
