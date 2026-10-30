--!strict
-- Name plates (piece 46): a name, a level badge and a health bar over every other fighter, always on
-- (while they are alive and close), and a ring under your own feet. Reads only the attributes the server
-- keeps on each fighter's model (PlateName, Level, Health, MaxHealth, Alive). Also plays the level-up
-- burst when a model's Level goes up. The look is Ui/MomentStyles; PlateRules decides what shows.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PlateRules = require(Shared.Moments.PlateRules)

local HealthBars = require(script.Parent.Parent.Combat.HealthBars)
local LevelBurst = require(script.Parent.LevelBurst)
local MomentStyles = require(script.Parent.Parent.Ui.MomentStyles)
local Tokens = require(script.Parent.Parent.Ui.Tokens)
local UiKit = require(script.Parent.Parent.Hud.UiKit)

local PlateSystem = {}
PlateSystem.order = 220

local function color(role: string): Color3
	return Color3.fromHex(Tokens.color(role))
end

type Ring = { model: Model, root: BasePart, humanoid: Humanoid?, part: Part, mine: boolean }
local rings: { Ring } = {}
local ringFolder: Folder? = nil

local function fxFolder(): Folder
	if ringFolder ~= nil and ringFolder.Parent ~= nil then
		return ringFolder
	end
	local found = Workspace:FindFirstChild("PlateFx")
	if found ~= nil and found:IsA("Folder") then
		ringFolder = found
		return found
	end
	local made = Instance.new("Folder")
	made.Name = "PlateFx"
	made.Parent = Workspace
	ringFolder = made
	return made
end

local function plateConfig(): PlateRules.Config
	return {
		maxNameLength = Config.Plates.maxNameLength,
		lowHealthFraction = Config.Plates.lowHealthFraction,
		showOwnPlate = Config.Plates.showOwnPlate,
	}
end

local function attributesOf(model: Model): PlateRules.Attributes
	return {
		Health = model:GetAttribute("Health"),
		MaxHealth = model:GetAttribute("MaxHealth"),
		Alive = model:GetAttribute("Alive"),
		Level = model:GetAttribute("Level"),
		PlateName = model:GetAttribute("PlateName"),
	}
end

type Plate = {
	gui: BillboardGui,
	name: TextLabel,
	badge: TextLabel,
	fill: Frame,
}

local function buildPlate(model: Model, root: BasePart): Plate
	local style = MomentStyles.get(Config.Moments.style).plate
	local font = UiKit.fontEnum(Tokens.get(nil).fonts.display)
	local top = style.badgeSide == "top"

	local gui = Instance.new("BillboardGui")
	gui.Name = "NamePlate"
	gui.Size = if top then UDim2.fromOffset(96, 66) else UDim2.fromOffset(124, 38)
	gui.StudsOffset = Vector3.new(0, Config.Plates.plateLift, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = Config.Plates.maxDistance
	gui.Enabled = false
	gui.Adornee = root
	gui.Active = false
	gui.Parent = model

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundColor3 = color(style.fill)
	body.BackgroundTransparency = style.fillAlpha
	body.BorderSizePixel = 0
	body.Active = false
	if top then
		body.AnchorPoint = Vector2.new(0.5, 1)
		body.Position = UDim2.fromScale(0.5, 1)
		body.Size = UDim2.fromScale(1, 0.46)
	else
		body.Size = UDim2.fromScale(1, 1)
	end
	body.Parent = gui
	UiKit.round(body, style.corner)
	if style.outlineThickness > 0 then
		local stroke = Instance.new("UIStroke")
		stroke.Color = color(style.outline)
		stroke.Thickness = style.outlineThickness
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = body
	end

	-- the level badge
	local badgeBox = Instance.new("Frame")
	badgeBox.Name = "Badge"
	badgeBox.BackgroundColor3 = color(style.badgeFill)
	badgeBox.BorderSizePixel = 0
	badgeBox.Active = false
	if top then
		badgeBox.AnchorPoint = Vector2.new(0.5, 0)
		badgeBox.Position = UDim2.fromScale(0.5, 0)
		badgeBox.Size = UDim2.fromOffset(28, 28)
		badgeBox.Parent = gui
	else
		badgeBox.AnchorPoint = Vector2.new(0, 0.5)
		badgeBox.Position = UDim2.fromOffset(4, 19)
		badgeBox.Size = UDim2.fromOffset(28, 28)
		badgeBox.Parent = body
	end
	UiKit.round(badgeBox, style.badgeCorner)
	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = color(style.outline)
	badgeStroke.Thickness = 2
	badgeStroke.Parent = badgeBox
	local badge = Instance.new("TextLabel")
	badge.BackgroundTransparency = 1
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.5, 0.5)
	badge.Size = UDim2.fromScale(0.8, 0.7)
	badge.Font = font
	badge.TextScaled = true
	badge.Text = "1"
	badge.TextColor3 = color(style.badgeInk)
	badge.Parent = badgeBox

	-- the name
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Font = font
	name.TextScaled = true
	name.TextColor3 = color(style.ink)
	name.TextXAlignment = if top then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	if style.fillAlpha >= 1 then
		name.TextStrokeColor3 = color(style.outline)
		name.TextStrokeTransparency = 0
	end
	if top then
		name.Position = UDim2.fromScale(0.04, 0.02)
		name.Size = UDim2.fromScale(0.92, 0.5)
	else
		name.Position = UDim2.fromOffset(38, 3)
		name.Size = UDim2.new(1, -44, 0, 17)
	end
	name.Parent = body
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 16
	cap.MinTextSize = 8
	cap.Parent = name

	-- the health bar
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = color(style.barTrack)
	track.BackgroundTransparency = if style.fillAlpha >= 1 then 0.35 else 0
	track.BorderSizePixel = 0
	track.Active = false
	if top then
		track.AnchorPoint = Vector2.new(0.5, 1)
		track.Position = UDim2.fromScale(0.5, 0.88)
		track.Size = UDim2.fromScale(0.84, 0.2)
	else
		track.Position = UDim2.fromOffset(38, 24)
		track.Size = UDim2.new(1, -46, 0, 8)
	end
	track.Parent = body
	UiKit.round(track, 0.5)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = color(style.barFill)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Active = false
	fill.Parent = track
	UiKit.round(fill, 0.5)

	return { gui = gui, name = name, badge = badge, fill = fill }
end

local function addRing(model: Model, root: BasePart, mine: boolean)
	local style = MomentStyles.get(Config.Moments.style).ring
	local part = Instance.new("Part")
	part.Name = "PlateRing"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Material = Enum.Material.Neon
	part.Color = color(if mine then style.mine else style.other)
	part.Transparency = style.transparency
	local d = Config.Plates.ringDiameter
	part.Size = Vector3.new(Config.Plates.ringThickness, d, d)
	part.Parent = fxFolder()
	table.insert(rings, {
		model = model,
		root = root,
		humanoid = model:FindFirstChildOfClass("Humanoid"),
		part = part,
		mine = mine,
	})
end

local function follow(time: number)
	local style = MomentStyles.get(Config.Moments.style).ring
	for i = #rings, 1, -1 do
		local ring = rings[i]
		if ring.model.Parent == nil or ring.root.Parent == nil then
			ring.part:Destroy()
			table.remove(rings, i)
		else
			local alive = ring.model:GetAttribute("Alive") ~= false
			local hip = if ring.humanoid ~= nil then ring.humanoid.HipHeight else 0
			local pos = ring.root.Position
			local y = PlateRules.floorY(pos.Y, ring.root.Size.Y, hip) + Config.Plates.ringLift
			ring.part.CFrame = CFrame.new(pos.X, y, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
			if not alive then
				ring.part.Transparency = 1
			elseif style.pulse then
				ring.part.Transparency = style.transparency + 0.2 * (0.5 + 0.5 * math.sin(time * 3))
			else
				ring.part.Transparency = style.transparency
			end
		end
	end
end

local function onFighter(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		root = model:WaitForChild("HumanoidRootPart", 5)
		if root == nil or not root:IsA("BasePart") then
			return
		end
	end
	local rootPart = root :: BasePart
	local isSelf = model == Players.LocalPlayer.Character
	local style = MomentStyles.get(Config.Moments.style).plate
	local cfg = plateConfig()

	if PlateRules.wantsRing(isSelf, Config.Plates.ownRing, Config.Plates.enemyRing) then
		addRing(model, rootPart, isSelf)
	end

	local plate: Plate? = nil
	local function refresh()
		local view = PlateRules.view(attributesOf(model), isSelf, cfg)
		if not view.visible then
			if plate ~= nil then
				plate.gui.Enabled = false
			end
			return
		end
		if plate == nil then
			plate = buildPlate(model, rootPart)
		end
		local p = plate :: Plate
		p.name.Text = view.name
		p.badge.Text = view.levelText
		p.fill.Size = UDim2.fromScale(view.fraction, 1)
		p.fill.BackgroundColor3 = color(if view.low then style.barLow else style.barFill)
		p.gui.Enabled = true
	end

	local lastLevel: any = model:GetAttribute("Level")
	model:GetAttributeChangedSignal("Level"):Connect(function()
		local level = model:GetAttribute("Level")
		if
			PlateRules.leveledUp(lastLevel, level)
			and model:GetAttribute("Alive") ~= false
			and model.Parent ~= nil
		then
			LevelBurst.play(model, level :: number)
		end
		lastLevel = level
		refresh()
	end)
	for _, attribute in { "Health", "MaxHealth", "Alive", "PlateName" } do
		model:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()
end

function PlateSystem.start()
	if not Config.Plates.enabled then
		return
	end
	RunService.RenderStepped:Connect(function()
		if #rings > 0 then
			follow(os.clock())
		end
	end)
	HealthBars.onFighter(onFighter)
end

return PlateSystem
