--!strict
-- Neon Pop Night toy look (client only, cosmetic): a thin dark outline around every fighter, and a
-- green ring under your own feet. Nothing here is read by the server, hit checks or shots: the ring
-- is a client-side part with every query switched off, and the outline is a Highlight with no fill.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local CharacterOutlineSystem = {}
CharacterOutlineSystem.order = 135

local settings = Config.Art.outline
local OUTLINE_NAME = "NeonOutline"

local localId = "p" .. tostring(Players.LocalPlayer.UserId)

local function outline(model: Model)
	if model:FindFirstChild(OUTLINE_NAME) ~= nil then
		return
	end
	local h = Instance.new("Highlight")
	h.Name = OUTLINE_NAME
	h.Adornee = model
	h.FillTransparency = 1
	h.OutlineColor = Color3.fromHex(settings.color)
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = model
end

local function makeRing(): Part
	local ring = Instance.new("Part")
	ring.Name = "NeonRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromHex(settings.ring.color)
	ring.Transparency = settings.ring.transparency
	ring.Size = Vector3.new(settings.ring.thickness, settings.ring.diameter, settings.ring.diameter)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = Workspace
	return ring
end

local function consider(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local function check()
		if type(inst:GetAttribute(Config.Attributes.ParticipantId)) == "string" then
			outline(inst)
		end
	end
	check()
	inst:GetAttributeChangedSignal(Config.Attributes.ParticipantId):Connect(check)
end

function CharacterOutlineSystem.start()
	if not settings.enabled then
		return
	end
	for _, d in Workspace:GetDescendants() do
		consider(d)
	end
	Workspace.DescendantAdded:Connect(consider)

	if not settings.ring.enabled then
		return
	end
	local ring = makeRing()
	local lying = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder stands along X; lay it flat
	RunService.RenderStepped:Connect(function()
		local character = Players.LocalPlayer.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if character ~= nil
			then character:FindFirstChildOfClass("Humanoid")
			else nil
		local alive = character ~= nil and character:GetAttribute("Alive") ~= false
		if
			root == nil
			or humanoid == nil
			or not root:IsA("BasePart")
			or not alive
			or character:GetAttribute(Config.Attributes.ParticipantId) ~= localId
		then
			ring.Transparency = 1
			return
		end
		ring.Transparency = settings.ring.transparency
		local footY = root.Position.Y
			- humanoid.HipHeight
			- root.Size.Y / 2
			+ settings.ring.thickness
		ring.CFrame = CFrame.new(root.Position.X, footY, root.Position.Z) * lying
	end)
end

return CharacterOutlineSystem
