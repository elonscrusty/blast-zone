--!strict
-- Turns a list of PartSpec (see ModelKit) into a real Model. Roblox only; the spec modules stay pure.
-- Lives in Shared so the server (helper bots) and every client (held tools) can build the same models.
-- Every part is non-colliding, can't be queried or touched, casts no shadow (phone-light).
-- A tiny see-through "Root" part sits at the model's origin and is the PrimaryPart.
--   weld = true   parts are Welded to Root (a "PartWeld" in each part) and unanchored (held tools, bots that move)
--   weld = false  parts stay Anchored (a model that is placed and moved with PivotTo of anchored parts
--                 should use weld = true; plain scenery can stay anchored)

local ModelKit = require(script.Parent.ModelKit)

local ModelBuilder = {}

export type Opts = {
	cf: CFrame?, -- where the model's origin goes (default: the world origin)
	weld: boolean?, -- default true
	parent: Instance?,
	name: string?,
	lite: boolean?, -- true = only the basic shape (far away); default = all the detail
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

-- One quiet part: anchored for now (build() welds it), no collisions, queries, touches or shadows.
local function newPart(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cf: CFrame,
	color: string,
	material: Enum.Material,
	transparency: number
): BasePart
	local inst = Instance.new("Part")
	inst.Shape = shape
	inst.Anchored = true
	inst.CanCollide = false
	inst.CanQuery = false
	inst.CanTouch = false
	inst.Massless = true
	inst.CastShadow = false
	inst.Material = material
	inst.Color = Color3.fromHex(color)
	inst.Transparency = transparency
	inst.TopSurface = Enum.SurfaceType.Smooth
	inst.BottomSurface = Enum.SurfaceType.Smooth
	inst.Size = size
	inst.CFrame = cf
	inst.Name = name
	inst.Parent = parent
	return inst
end

local function makePart(model: Model, origin: CFrame, p: ModelKit.PartSpec): BasePart
	local shape = Enum.PartType.Block
	if p.kind == "Cyl" then
		shape = Enum.PartType.Cylinder
	elseif p.kind == "Ball" then
		shape = Enum.PartType.Ball
	end
	return newPart(
		model,
		p.name,
		shape,
		ModelBuilder.partSize(p),
		origin * ModelBuilder.localCFrame(p),
		p.color,
		MATERIALS[p.mat] or Enum.Material.SmoothPlastic,
		p.alpha
	)
end

function ModelBuilder.build(name: string, parts: { ModelKit.PartSpec }, opts: Opts?): Model
	local o: Opts = opts or {}
	local origin = o.cf or CFrame.new()
	local model = Instance.new("Model")
	model.Name = o.name or name
	local root = newPart(
		model,
		"Root",
		Enum.PartType.Block,
		Vector3.new(0.2, 0.2, 0.2),
		origin,
		"#FFFFFF",
		Enum.Material.SmoothPlastic,
		1
	)
	model.PrimaryPart = root
	local weld = o.weld ~= false
	for _, p in parts do
		local inst = makePart(model, origin, p)
		if weld then
			-- A plain Weld (not a WeldConstraint): its C0 is the part's place on the model, so a part
			-- can be moved later by changing C0 without moving the rest of the model.
			local w = Instance.new("Weld")
			w.Name = "PartWeld"
			w.Part0 = root
			w.Part1 = inst
			w.C0 = root.CFrame:ToObjectSpace(inst.CFrame)
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
