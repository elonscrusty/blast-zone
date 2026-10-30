--!strict
-- The Roblox-only parts of the bots: the Crash Dummy body with its BOT tag, walking, and the
-- "can a shot get there?" check. Nothing here changes health, damage, speed or ammo.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BotTuning = require("./BotTuning")

local LOOK = BotTuning.LOOK
local EYE_HEIGHT = 2.5

local BotRoblox = {}

local function hex(text: string): Color3
	return Color3.fromHex(text)
end

-- A bullseye sticker on the chest. CanQuery is off so a shot never stops on it.
local function addTarget(torso: BasePart)
	local rings = {
		{ size = 1.3, color = hex(LOOK.targetRing) },
		{ size = 0.9, color = hex(LOOK.target) },
		{ size = 0.45, color = hex(LOOK.targetRing) },
	}
	for i, ring in rings do
		local disc = Instance.new("Part")
		disc.Name = "TargetRing"
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.05, ring.size, ring.size)
		disc.Color = ring.color
		disc.Material = Enum.Material.SmoothPlastic
		disc.CanCollide = false
		disc.CanQuery = false
		disc.CanTouch = false
		disc.Massless = true
		disc.CFrame = torso.CFrame
			* CFrame.new(0, 0.2, -(torso.Size.Z / 2 + 0.02 + i * 0.01))
			* CFrame.Angles(0, math.rad(90), 0)
		disc.Parent = torso
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = disc
		weld.Parent = disc
	end
end

-- The name tag above the head. It always starts with the BOT label (the roster name carries it).
local function addTag(head: BasePart, displayName: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BotTag"
	gui.Size = UDim2.fromOffset(170, 34)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.ResetOnSpawn = false

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = hex(LOOK.tagBack)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = hex(LOOK.tagText)
	stroke.Thickness = 2
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = displayName
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = hex(LOOK.tagText)
	label.Parent = frame
	gui.Parent = head
end

-- Builds a Crash Dummy (yields while Roblox builds the rig). The caller tags nothing else: this
-- sets the ParticipantId / IsBot attributes from Config.Attributes, and the match flow places it.
function BotRoblox.makeRig(participantId: string, displayName: string, parent: Instance): Model
	local description = Instance.new("HumanoidDescription")
	local body = hex(LOOK.body)
	local legs = hex(LOOK.legs)
	description.HeadColor = body
	description.TorsoColor = body
	description.LeftArmColor = body
	description.RightArmColor = body
	description.LeftLegColor = legs
	description.RightLegColor = legs

	local rig = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	rig.Name = displayName
	rig:SetAttribute(Config.Attributes.ParticipantId, participantId)
	rig:SetAttribute(Config.Attributes.IsBot, true)

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = displayName
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local head = rig:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		addTag(head, displayName)
	end
	local torso = rig:FindFirstChild("UpperTorso")
	if torso and torso:IsA("BasePart") then
		addTarget(torso)
	end
	rig.Parent = parent
	return rig
end

function BotRoblox.rootOf(model: Model?): BasePart?
	if not model then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function BotRoblox.move(rig: Model, x: number, z: number)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.new(x, 0, z), false)
	end
end

-- True when nothing that blocks shots sits between the two points. `params` is the same
-- RaycastParams the firearm uses, so a bot never notices someone it could not shoot.
function BotRoblox.clearBetween(
	params: RaycastParams,
	groundY: number,
	ax: number,
	az: number,
	bx: number,
	bz: number
): boolean
	local from = Vector3.new(ax, groundY + EYE_HEIGHT, az)
	local to = Vector3.new(bx, groundY + EYE_HEIGHT, bz)
	return Workspace:Raycast(from, to - from, params) == nil
end

-- Fallback when the firearm piece does not share its own params: only things that block shots
-- (Config.Tags: BlocksShots walls and cover, supply containers) stop a look. Low cover, roofs and
-- characters do not, matching Config.ShotRules. The list is rebuilt every couple of seconds.
local cachedParams: RaycastParams? = nil
local cachedAt = -10

function BotRoblox.fallbackShotParams(): RaycastParams
	local now = os.clock()
	if cachedParams and now - cachedAt < 2 then
		return cachedParams
	end
	local blockers: { Instance } = {}
	for _, tag in { Config.Tags.BlocksShots, Config.Tags.SupplyContainer } do
		for _, inst in CollectionService:GetTagged(tag) do
			table.insert(blockers, inst)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = blockers
	cachedParams = params
	cachedAt = now
	return params
end

return BotRoblox
