--!strict
-- Neon Pop Night toy look (client only, cosmetic): a thin dark outline around every fighter. Nothing
-- here is read by the server, hit checks or shots: the outline is a Highlight with no fill. (The ring
-- under your own feet is drawn by Moments/PlateSystem, piece 46.)
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local CharacterOutlineSystem = {}
CharacterOutlineSystem.order = 135

local settings = Config.Art.outline
local OUTLINE_NAME = "NeonOutline"

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
end

return CharacterOutlineSystem
