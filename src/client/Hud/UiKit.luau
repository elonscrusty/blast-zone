--!strict
-- Small helpers that dress Roblox GUI objects in look B (cream panel, thick navy outline, hard
-- shadow). Shared by the HUD, the touch controls and the settings panel.
-- Everything is sized as a share of the screen HEIGHT and sticks to its nearest screen edge
-- (see Layout.luau), so phones of any shape get the same sizes.

local TweenService = game:GetService("TweenService")

local Theme = require("./Theme")
local Layout = require("./Layout")

local UiKit = {}

-- The display face from the current skin (Ui/Tokens). Unknown names fall back to FredokaOne.
local function fontEnum(name: string): Enum.Font
	local ok, font = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	return if ok and typeof(font) == "EnumItem" then font :: Enum.Font else Enum.Font.FredokaOne
end
UiKit.fontEnum = fontEnum
UiKit.FONT = fontEnum(Theme.fontName)

function UiKit.look(): Theme.Look
	return Theme.get(nil)
end

function UiKit.color(hex: string): Color3
	return Color3.fromHex(hex)
end

-- Width / height of the box a placed piece lives in (its parent, else the whole screen).
local function aspectOf(obj: GuiObject): number
	local parent = obj.Parent
	if parent and parent:IsA("GuiBase2d") then
		local s = parent.AbsoluteSize
		if s.X > 0 and s.Y > 0 then
			return s.X / s.Y
		end
	end
	local camera = workspace.CurrentCamera
	if camera and camera.ViewportSize.Y > 0 then
		return camera.ViewportSize.X / camera.ViewportSize.Y
	end
	return Layout.WIDTH / Layout.HEIGHT
end

type Placed = { rect: Layout.Rect, leftHanded: boolean?, minAspect: number? }
local placed: { [GuiObject]: Placed } = {}
local watchedParents: { [GuiBase2d]: boolean } = {}
local watchedCamera: Camera? = nil
local relayoutQueued = false

local function applyPlacement(obj: GuiObject, entry: Placed)
	local aspect = aspectOf(obj)
	local p = Layout.place(entry.rect, entry.leftHanded, aspect, entry.minAspect)
	obj.AnchorPoint = Vector2.new(p.anchorX, p.anchorY)
	obj.Position = UDim2.fromScale(p.posX, p.posY)
	obj.Size = UDim2.fromScale(p.sizeY * p.aspect / aspect, p.sizeY)
	local ratio = obj:FindFirstChildOfClass("UIAspectRatioConstraint")
		or Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = p.aspect
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.Parent = obj
end

-- Every placed piece is laid out again from the screen it is on NOW. A real phone starts the game
-- upright (tall), turns sideways a moment later and can turn again; a layout made for the tall screen
-- must never survive that (it came out five times too small, piled at the bottom). Studio never turns.
local function relayoutAll()
	if relayoutQueued then
		return
	end
	relayoutQueued = true
	task.defer(function()
		relayoutQueued = false
		for obj, entry in placed do
			applyPlacement(obj, entry)
		end
	end)
end

-- One watcher per parent: its size changing (a turn, a resize, the safe area) places everything inside again.
local function watchParent(obj: GuiObject)
	local parent = obj.Parent
	if parent and parent:IsA("GuiBase2d") and not watchedParents[parent] then
		watchedParents[parent] = true
		parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayoutAll)
		parent.Destroying:Connect(function()
			watchedParents[parent] = nil
		end)
	end
end

-- The camera's own size is a second cue (and the fallback for a piece with no parent yet). The camera can
-- be replaced, so the latest one is the one watched.
local function watchCamera()
	local camera = workspace.CurrentCamera
	if camera and camera ~= watchedCamera then
		watchedCamera = camera
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayoutAll)
	end
end

local watchingScreen = false
local function watchScreen()
	watchCamera()
	if watchingScreen then
		return
	end
	watchingScreen = true
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watchCamera()
		relayoutAll()
	end)
end

-- Sizes and places a piece from a Layout rect. Parent must be a full-screen container. Placed again
-- whenever the screen or its parent changes size (turning the phone), and when the piece moves into a screen.
function UiKit.place(obj: GuiObject, rect: Layout.Rect, leftHanded: boolean?, minAspect: number?)
	local isNew = placed[obj] == nil
	local entry: Placed = { rect = rect, leftHanded = leftHanded, minAspect = minAspect }
	placed[obj] = entry
	applyPlacement(obj, entry)
	watchScreen()
	watchParent(obj)
	if isNew then
		obj.AncestryChanged:Connect(function()
			local current = placed[obj]
			if current then
				watchParent(obj)
				task.defer(applyPlacement, obj, current)
			end
		end)
		obj.Destroying:Connect(function()
			placed[obj] = nil
		end)
	end
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
