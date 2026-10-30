--!strict
-- A small 3D icon for each challenge kind in a ViewportFrame, built from plain parts (no art assets).
-- It turns slowly only while it is on screen. elims = target, crates = violet crate, orbs = XP orb,
-- matches = arena ring, top3 = podium, wins = trophy.

local RunService = game:GetService("RunService")

local DailyIcon = {}

local function part(
	model: Model,
	shape: Enum.PartType,
	size: Vector3,
	cf: CFrame,
	hex: string,
	neon: boolean?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = Color3.fromHex(hex)
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Parent = model
	return p
end

local BLOCK = Enum.PartType.Block
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local FACE = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis X -> Z (toward the camera)
local UP = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis X -> Y (standing)

local builders: { [string]: (Model) -> () } = {
	elims = function(m)
		part(m, CYL, Vector3.new(0.3, 3.2, 3.2), FACE, "#FF4D5E")
		part(m, CYL, Vector3.new(0.34, 2.3, 2.3), FACE, "#FFFFFF")
		part(m, CYL, Vector3.new(0.38, 1.4, 1.4), FACE, "#FF4D5E")
		part(m, CYL, Vector3.new(0.42, 0.5, 0.5), FACE, "#FFD23F", true)
	end,
	crates = function(m)
		part(m, BLOCK, Vector3.new(2.4, 2.4, 2.4), CFrame.new(), "#6B3FD6")
		for _, x in { -1.15, 1.15 } do
			for _, y in { -1.15, 1.15 } do
				part(m, BLOCK, Vector3.new(0.25, 0.25, 2.5), CFrame.new(x, y, 0), "#C9A8FF", true)
				part(m, BLOCK, Vector3.new(0.25, 2.5, 0.25), CFrame.new(x, 0, y), "#C9A8FF", true)
				part(m, BLOCK, Vector3.new(2.5, 0.25, 0.25), CFrame.new(0, x, y), "#C9A8FF", true)
			end
		end
	end,
	orbs = function(m)
		part(m, BALL, Vector3.new(2.2, 2.2, 2.2), CFrame.new(), "#3FF2FF", true)
		part(m, CYL, Vector3.new(0.15, 3.2, 3.2), CFrame.Angles(0.5, 0, 0.3) * UP, "#B8FBFF")
	end,
	matches = function(m)
		part(m, CYL, Vector3.new(0.4, 3.2, 3.2), CFrame.Angles(0.6, 0, 0) * UP, "#2B3A67")
		part(m, CYL, Vector3.new(0.45, 2.6, 2.6), CFrame.Angles(0.6, 0, 0) * UP, "#3FF2FF", true)
		part(m, CYL, Vector3.new(0.5, 2.2, 2.2), CFrame.Angles(0.6, 0, 0) * UP, "#2B3A67")
	end,
	top3 = function(m)
		part(m, BLOCK, Vector3.new(1, 2.2, 1), CFrame.new(0, 0.1, 0), "#FFD23F")
		part(m, BLOCK, Vector3.new(1, 1.6, 1), CFrame.new(-1.05, -0.2, 0), "#C9D1E0")
		part(m, BLOCK, Vector3.new(1, 1.1, 1), CFrame.new(1.05, -0.45, 0), "#D98A4E")
	end,
	wins = function(m)
		part(m, BLOCK, Vector3.new(1.6, 0.4, 1.0), CFrame.new(0, -1.3, 0), "#2B3A67")
		part(m, CYL, Vector3.new(0.9, 0.35, 0.35), CFrame.new(0, -0.7, 0) * UP, "#FFD23F", true)
		part(m, CYL, Vector3.new(1.3, 1.7, 1.7), CFrame.new(0, 0.35, 0) * UP, "#FFD23F", true)
		part(m, CYL, Vector3.new(0.2, 0.9, 0.9), CFrame.new(-1, 0.45, 0) * FACE, "#FFB800")
		part(m, CYL, Vector3.new(0.2, 0.9, 0.9), CFrame.new(1, 0.45, 0) * FACE, "#FFB800")
	end,
}

local function onScreen(obj: Instance): boolean
	local node: Instance? = obj
	while node ~= nil do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

-- Returns the ViewportFrame; it stops turning by itself when destroyed or hidden.
function DailyIcon.create(parent: Instance, kind: string): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Icon"
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(160, 160, 170)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-0.4, -0.7, -1)
	vp.Parent = parent

	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, 7.2), Vector3.zero)
	camera.Parent = vp
	vp.CurrentCamera = camera

	local model = Instance.new("Model")
	local build = builders[kind] or builders.matches
	build(model)
	model.Parent = vp

	local base: { [BasePart]: CFrame } = {}
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			base[p] = p.CFrame
		end
	end

	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if vp.Parent == nil then
			conn:Disconnect()
			return
		end
		if not onScreen(vp) then
			return
		end
		local turn = CFrame.Angles(0, math.sin(os.clock() * 1.2) * 0.6, 0)
		for p, cf in base do
			p.CFrame = turn * cf
		end
	end)
	return vp
end

return DailyIcon
