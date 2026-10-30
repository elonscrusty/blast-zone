--!strict
-- The level-up celebration in the world (piece 46): sparks, a ring that opens on the floor and an arrow
-- that rises over the fighter's head. Cosmetic only; the server already decided the level.
-- Capped by Config.Plates.burst.maxAtOnce, and smaller when "reduce flashes" is on.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PlateRules = require(Shared.Moments.PlateRules)

local MomentStyles = require(script.Parent.Parent.Ui.MomentStyles)
local Tokens = require(script.Parent.Parent.Ui.Tokens)
local UiKit = require(script.Parent.Parent.Hud.UiKit)
local Settings = require(script.Parent.Parent.Settings.Settings)

local LevelBurst = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local alive = 0

local function color(role: string): Color3
	return Color3.fromHex(Tokens.color(role))
end

local function folder(): Folder
	local found = Workspace:FindFirstChild("PlateFx")
	if found ~= nil and found:IsA("Folder") then
		return found
	end
	local made = Instance.new("Folder")
	made.Name = "PlateFx"
	made.Parent = Workspace
	return made
end

local function sparks(root: BasePart, style: MomentStyles.BurstStyle, count: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "LevelBurstAnchor"
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Speed = NumberRange.new(12, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -14, 0)
	emitter.LightEmission = 0.4
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, style.sparkSize),
		NumberSequenceKeypoint.new(1, 0),
	})
	local keys = {}
	for i, role in style.colors do
		table.insert(
			keys,
			ColorSequenceKeypoint.new((i - 1) / math.max(1, #style.colors - 1), color(role))
		)
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, keys[1].Value))
	end
	emitter.Color = ColorSequence.new(keys)
	emitter.Parent = attachment
	emitter:Emit(count)
	Debris:AddItem(attachment, 1.2)
end

local function floorRing(root: BasePart, humanoid: Humanoid?, style: MomentStyles.BurstStyle)
	local burst = Config.Plates.burst
	local floorY = PlateRules.floorY(
		root.Position.Y,
		root.Size.Y,
		if humanoid ~= nil then humanoid.HipHeight else 0
	) + Config.Plates.ringLift
	local ring = Instance.new("Part")
	ring.Name = "LevelBurstRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = color(style.ring)
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.15, 2, 2)
	ring.CFrame = CFrame.new(root.Position.X, floorY, root.Position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder()
	local open = TweenService:Create(
		ring,
		TweenInfo.new(burst.ringSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.15, burst.ringDiameter, burst.ringDiameter), Transparency = 1 }
	)
	open:Play()
	Debris:AddItem(ring, burst.ringSeconds + 0.1)
end

local function arrow(root: BasePart, style: MomentStyles.BurstStyle, level: number)
	local burst = Config.Plates.burst
	local gui = Instance.new("BillboardGui")
	gui.Name = "LevelBurstArrow"
	gui.Size = UDim2.fromOffset(72, 72)
	gui.StudsOffset = Vector3.new(0, Config.Plates.plateLift + 0.6, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.MaxDistance = Config.Plates.maxDistance
	gui.Adornee = root
	gui.Parent = folder()

	local font = UiKit.fontEnum(Tokens.get(nil).fonts.display)
	local sign = Instance.new("TextLabel")
	sign.BackgroundTransparency = 1
	sign.Size = UDim2.fromScale(1, 0.62)
	sign.Font = font
	sign.Text = "▲"
	sign.TextScaled = true
	sign.TextColor3 = color(style.arrowInk)
	sign.TextStrokeColor3 = color(style.arrowOutline)
	sign.TextStrokeTransparency = 0
	sign.Parent = gui
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0, 0.62)
	label.Size = UDim2.fromScale(1, 0.38)
	label.Font = font
	label.Text = "LV " .. PlateRules.levelText(level)
	label.TextScaled = true
	label.TextColor3 = color(style.arrowInk)
	label.TextStrokeColor3 = color(style.arrowOutline)
	label.TextStrokeTransparency = 0
	label.Parent = gui

	local info = TweenInfo.new(burst.arrowSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = gui.StudsOffset + Vector3.new(0, 2.4, 0) })
		:Play()
	local fade = TweenInfo.new(burst.arrowSeconds * 0.4, Enum.EasingStyle.Linear)
	task.delay(burst.arrowSeconds * 0.6, function()
		if gui.Parent == nil then
			return
		end
		TweenService:Create(sign, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 })
			:Play()
	end)
	Debris:AddItem(gui, burst.arrowSeconds + 0.1)
end

-- A fighter's model just gained a level. `level` is the new one.
function LevelBurst.play(model: Model, level: number)
	local burst = Config.Plates.burst
	if alive >= burst.maxAtOnce then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local style = MomentStyles.get(Config.Moments.style).burst
	local calm = Settings.flag("reduceFlashes")
	alive += 1
	task.delay(math.max(burst.arrowSeconds, burst.ringSeconds) + 0.2, function()
		alive -= 1
	end)
	arrow(root, style, level)
	if calm then
		sparks(root, style, math.floor(burst.particles / 3))
		return
	end
	sparks(root, style, burst.particles)
	floorRing(root, model:FindFirstChildOfClass("Humanoid"), style)
end

return LevelBurst
