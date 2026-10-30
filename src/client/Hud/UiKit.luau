--!strict
-- Small helpers that dress Roblox GUI objects in look B (cream panel, thick navy outline, hard
-- shadow). Shared by the HUD, the touch controls and the settings panel.
-- Everything is sized as a share of the screen HEIGHT and sticks to its nearest screen edge
-- (see Layout.luau), so phones of any shape get the same sizes.

local TweenService = game:GetService("TweenService")

local Theme = require("./Theme")
local Layout = require("./Layout")

local UiKit = {}

UiKit.FONT = Enum.Font.FredokaOne

function UiKit.look(): Theme.Look
	return Theme.get(nil)
end

function UiKit.color(hex: string): Color3
	return Color3.fromHex(hex)
end

-- Sizes and places a piece from a Layout rect. Parent must be a full-screen container.
function UiKit.place(obj: GuiObject, rect: Layout.Rect, leftHanded: boolean?)
	local p = Layout.place(rect, leftHanded)
	obj.AnchorPoint = Vector2.new(p.anchorX, p.anchorY)
	obj.Position = UDim2.fromScale(p.posX, p.posY)
	obj.Size = UDim2.fromScale(p.sizeY * p.aspect * (Layout.HEIGHT / Layout.WIDTH), p.sizeY)
	local ratio = obj:FindFirstChildOfClass("UIAspectRatioConstraint")
		or Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = p.aspect
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.Parent = obj
end

-- Outline thickness in pixels for the current screen height.
local function strokePixels(screenHeight: number, factor: number): number
	return math.max(2, math.floor(screenHeight * UiKit.look().strokeScale * factor + 0.5))
end

-- Keeps a stroke's thickness in step with the screen. `root` is the full-screen container.
function UiKit.styleStroke(stroke: UIStroke, root: GuiObject, factor: number?)
	local f = factor or 1
	local function apply()
		stroke.Thickness = strokePixels(root.AbsoluteSize.Y, f)
	end
	apply()
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
end

local function corner(obj: GuiObject, radius: number)
	local c = obj:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	c.CornerRadius = UDim.new(radius, 0)
	c.Parent = obj
end

-- A cream sticker panel. Returns the panel and its hard shadow (a navy copy shifted down).
-- `parent` must be the container that also holds `root`-relative placement.
function UiKit.sticker(
	parent: Instance,
	root: GuiObject,
	name: string,
	fill: string?,
	round: number?
): (Frame, Frame)
	local look = UiKit.look()
	local radius = round or look.cornerScale

	local shadow = Instance.new("Frame")
	shadow.Name = name .. "Shadow"
	shadow.BackgroundColor3 = UiKit.color(look.outline)
	shadow.BorderSizePixel = 0
	shadow.Active = false
	shadow.Parent = parent
	corner(shadow, radius)

	local panel = Instance.new("Frame")
	panel.Name = name
	panel.BackgroundColor3 = UiKit.color(fill or look.panel)
	panel.BorderSizePixel = 0
	panel.Parent = parent
	corner(panel, radius)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiKit.color(look.outline)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = panel
	UiKit.styleStroke(stroke, root)
	return panel, shadow
end

-- Keeps a shadow frame under its panel (same size and anchor, pushed down a few pixels).
-- `root` is the full-screen container, so the depth follows the screen height.
function UiKit.followShadow(panel: GuiObject, shadow: GuiObject, root: GuiObject)
	local depth = UiKit.look().shadowOffset
	local function sync()
		shadow.AnchorPoint = panel.AnchorPoint
		shadow.Size = panel.Size
		local px = math.max(2, math.floor(root.AbsoluteSize.Y * depth + 0.5))
		shadow.Position = UDim2.new(
			panel.Position.X.Scale,
			panel.Position.X.Offset,
			panel.Position.Y.Scale,
			panel.Position.Y.Offset + px
		)
		shadow.Visible = panel.Visible
		shadow.ZIndex = panel.ZIndex - 1
	end
	sync()
	panel:GetPropertyChangedSignal("Position"):Connect(sync)
	panel:GetPropertyChangedSignal("Size"):Connect(sync)
	panel:GetPropertyChangedSignal("Visible"):Connect(sync)
	panel:GetPropertyChangedSignal("AnchorPoint"):Connect(sync)
	panel:GetPropertyChangedSignal("ZIndex"):Connect(sync)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync)
end

export type LabelOptions = {
	text: string?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	color: string?,
	align: Enum.TextXAlignment?,
	maxTextSize: number?,
}

function UiKit.label(parent: Instance, name: string, opts: LabelOptions): TextLabel
	local look = UiKit.look()
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = UiKit.FONT
	l.TextScaled = true
	l.Text = opts.text or ""
	l.TextColor3 = UiKit.color(opts.color or look.ink)
	l.TextXAlignment = opts.align or Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Size = opts.size or UDim2.fromScale(1, 1)
	l.Position = opts.position or UDim2.new()
	l.AnchorPoint = opts.anchor or Vector2.zero
	l.Active = false
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = opts.maxTextSize or 48
	cap.MinTextSize = 6
	cap.Parent = l
	l.Parent = parent
	return l
end

function UiKit.circle(obj: GuiObject)
	corner(obj, 0.5)
end

function UiKit.round(obj: GuiObject, radius: number)
	corner(obj, radius)
end

-- Quick scale pop (press, ready, new warning). Cancels the one before it.
local pops: { [GuiObject]: Tween } = {}
function UiKit.pop(obj: GuiObject, scale: number?)
	local existing = pops[obj]
	if existing then
		existing:Cancel()
	end
	local found = obj:FindFirstChild("PopScale")
	local s: UIScale
	if found and found:IsA("UIScale") then
		s = found
	else
		s = Instance.new("UIScale")
		s.Name = "PopScale"
		s.Parent = obj
	end
	s.Scale = scale or 1.12
	local tween = TweenService:Create(
		s,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	pops[obj] = tween
	tween:Play()
end

return UiKit
