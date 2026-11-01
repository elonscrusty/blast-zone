--!strict
-- Builds one cute helper bot out of plain Parts (no assets, no asset ids): a round body, two eyes
-- with pupils, a little antenna with a glowing Neon tip, a tiny broom and a soft hover glow.
-- The body is the only anchored part; everything else is welded to it and weightless, so moving
-- the bot is one CFrame change and costs the network one assembly, not eight parts.
--
--   BotModel.build(colorHex) -> Model          PrimaryPart = Body, facing -Z (like a character)
--   BotModel.setColor(model, colorHex)         repaint (body colour; glowing bits are a lighter shade)
--   BotModel.floatLabel(model) -> TextLabel?   the "+12" label over the bot (starts invisible)

local BotModel = {}

local FALLBACK_COLOR = Color3.fromRGB(169, 128, 91)
local BROOM_STICK = Color3.fromRGB(138, 90, 51)
local BROOM_BRUSH = Color3.fromRGB(232, 196, 106)
local WHITE = Color3.fromRGB(255, 255, 255)
local PUPIL = Color3.fromRGB(40, 36, 52)
local FLOAT_GOLD = Color3.fromRGB(255, 215, 64)

local function colorOf(hex: string): Color3
	local ok, color = pcall(Color3.fromHex, hex)
	if ok and typeof(color) == "Color3" then
		return color
	end
	return FALLBACK_COLOR
end

local function glowOf(color: Color3): Color3
	return color:Lerp(WHITE, 0.5)
end

local function newPart(
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.Anchored = false
	return p
end

function BotModel.build(colorHex: string): Model
	local color = colorOf(colorHex)
	local model = Instance.new("Model")
	model.Name = "HelperBot"

	local body = newPart(
		"Body",
		Enum.PartType.Ball,
		Vector3.new(2.2, 2.2, 2.2),
		color,
		Enum.Material.SmoothPlastic
	)
	body.Anchored = true
	body.CastShadow = true
	body:SetAttribute("Tint", "body")
	body.CFrame = CFrame.new()
	body.Parent = model
	model.PrimaryPart = body

	-- every other part: (name, part, position relative to the body)
	local function attach(part: Part, offset: CFrame)
		part.CFrame = offset
		local weld = Instance.new("Weld")
		weld.Name = "Weld"
		weld.Part0 = body
		weld.Part1 = part
		weld.C0 = offset -- the body sits at the origin, so its object space is the world
		weld.C1 = CFrame.new()
		weld.Parent = part
		part.Parent = model
	end

	for _, side in { -1, 1 } do
		local eye = newPart(
			if side < 0 then "EyeL" else "EyeR",
			Enum.PartType.Ball,
			Vector3.new(0.6, 0.6, 0.6),
			WHITE,
			Enum.Material.SmoothPlastic
		)
		attach(eye, CFrame.new(side * 0.5, 0.35, -0.95))
		local pupil = newPart(
			if side < 0 then "PupilL" else "PupilR",
			Enum.PartType.Ball,
			Vector3.new(0.3, 0.3, 0.3),
			PUPIL,
			Enum.Material.SmoothPlastic
		)
		attach(pupil, CFrame.new(side * 0.5, 0.35, -1.22))
	end

	-- antenna: a thin stick (cylinders lie along X, so turn it upright) and a glowing tip
	local stick = newPart(
		"AntennaStick",
		Enum.PartType.Cylinder,
		Vector3.new(0.9, 0.14, 0.14),
		BROOM_STICK,
		Enum.Material.SmoothPlastic
	)
	attach(stick, CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.pi / 2))
	local tip = newPart(
		"AntennaTip",
		Enum.PartType.Ball,
		Vector3.new(0.42, 0.42, 0.42),
		glowOf(color),
		Enum.Material.Neon
	)
	tip:SetAttribute("Tint", "glow")
	attach(tip, CFrame.new(0, 2.05, 0))

	-- the tiny broom, held out to the side
	local handle = newPart(
		"BroomHandle",
		Enum.PartType.Cylinder,
		Vector3.new(1.7, 0.1, 0.1),
		BROOM_STICK,
		Enum.Material.Wood
	)
	attach(handle, CFrame.new(1.35, -0.1, -0.35) * CFrame.Angles(0, 0, math.pi / 2 + 0.3))
	local brush = newPart(
		"BroomBrush",
		Enum.PartType.Block,
		Vector3.new(0.8, 0.2, 0.45),
		BROOM_BRUSH,
		Enum.Material.Fabric
	)
	attach(brush, CFrame.new(1.6, -0.95, -0.35) * CFrame.Angles(0, 0, 0.3))

	-- soft hover glow under the body (a flat disc: turn the cylinder so its axis points up)
	local glow = newPart(
		"HoverGlow",
		Enum.PartType.Cylinder,
		Vector3.new(0.08, 1.5, 1.5),
		glowOf(color),
		Enum.Material.Neon
	)
	glow.Transparency = 0.35
	glow:SetAttribute("Tint", "glow")
	attach(glow, CFrame.new(0, -1.25, 0) * CFrame.Angles(0, 0, math.pi / 2))

	-- "+12" label over the head
	local gui = Instance.new("BillboardGui")
	gui.Name = "FloatGui"
	gui.Adornee = body
	gui.Size = UDim2.fromOffset(140, 44)
	gui.StudsOffset = Vector3.new(0, 3.4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0, 0)
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 26
	label.TextColor3 = FLOAT_GOLD
	label.TextStrokeColor3 = PUPIL
	label.TextStrokeTransparency = 1
	label.TextTransparency = 1
	label.Text = ""
	label.Parent = gui
	gui.Parent = body

	return model
end

function BotModel.setColor(model: Model, colorHex: string)
	local color = colorOf(colorHex)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local tint = d:GetAttribute("Tint")
			if tint == "body" then
				d.Color = color
			elseif tint == "glow" then
				d.Color = glowOf(color)
			end
		end
	end
end

function BotModel.floatLabel(model: Model): TextLabel?
	local body = model.PrimaryPart
	local gui = body and body:FindFirstChild("FloatGui")
	local label = gui and gui:FindFirstChild("Label")
	if label ~= nil and label:IsA("TextLabel") then
		return label
	end
	return nil
end

return BotModel
