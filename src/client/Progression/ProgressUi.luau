--!strict
-- Small building blocks for the coin screens, in the Street Sticker look (cream panels, thick navy outlines,
-- hard shadows). Colors come from Hud/Theme when it exists, else from the shared palette.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Look = require(script.Parent.Parent.Ui.Look)

local ProgressUi = {}

export type Look = {
	panel: string,
	ink: string,
	outline: string,
	accent: string,
	danger: string,
	info: string,
	dim: string,
	strokeScale: number,
	shadowOffset: number,
}

local function loadLook(): Look
	local hud = script.Parent.Parent:FindFirstChild("Hud")
	local module = if hud then hud:FindFirstChild("Theme") else nil
	if module and module:IsA("ModuleScript") then
		local ok, theme = pcall(require, module)
		if ok then
			return theme.get(nil)
		end
	end
	return {
		panel = Look.hex("panel"),
		ink = Look.hex("ink"),
		outline = Look.hex("outline"),
		accent = Look.hex("accent"),
		danger = Look.hex("danger"),
		info = Look.hex("info"),
		dim = Look.hex("dim"),
		strokeScale = 0.0085,
		shadowOffset = 0.011,
	}
end

ProgressUi.look = loadLook()
ProgressUi.font = Look.font("display")
ProgressUi.minTouch = Config.Settings.minTouchTarget

function ProgressUi.hex(h: string): Color3
	return Color3.fromHex(h)
end

function ProgressUi.round(obj: Instance, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = obj
end

-- Outline that follows the screen height.
function ProgressUi.outline(gui: ScreenGui, obj: Instance, factor: number, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Color = color or ProgressUi.hex(ProgressUi.look.outline)
	-- a button gets a border; Contextual would outline its words (smeared text). Labels keep the text outline.
	s.ApplyStrokeMode = if obj:IsA("TextButton")
		then Enum.ApplyStrokeMode.Border
		else Enum.ApplyStrokeMode.Contextual
	s.Parent = obj
	local function apply()
		s.Thickness =
			math.max(2, math.floor(gui.AbsoluteSize.Y * ProgressUi.look.strokeScale * factor + 0.5))
	end
	apply()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
end

function ProgressUi.label(parent: Instance, name: string, str: string, maxSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Text = str
	l.Font = ProgressUi.font
	l.TextScaled = true
	l.TextColor3 = ProgressUi.hex(ProgressUi.look.ink)
	l.Active = false
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = maxSize
	cap.MinTextSize = 8
	cap.Parent = l
	l.Parent = parent
	return l
end

-- A tappable sticker: a slot holding a hard shadow and the button on top. At least minTouch tall.
function ProgressUi.button(
	gui: ScreenGui,
	parent: Instance,
	name: string,
	str: string,
	gold: boolean
): (Frame, TextButton)
	local slot = Instance.new("Frame")
	slot.Name = name .. "Slot"
	slot.BackgroundTransparency = 1
	slot.Parent = parent
	local minSize = Instance.new("UISizeConstraint")
	minSize.MinSize = Vector2.new(ProgressUi.minTouch * 2, ProgressUi.minTouch)
	minSize.Parent = slot

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = ProgressUi.hex(ProgressUi.look.outline)
	shadow.BorderSizePixel = 0
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Parent = slot
	ProgressUi.round(shadow, 0.3)
	local function sync()
		local px = math.max(2, math.floor(gui.AbsoluteSize.Y * ProgressUi.look.shadowOffset + 0.5))
		shadow.Position = UDim2.fromOffset(0, px)
	end
	sync()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync)

	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromScale(1, 1)
	b.Text = str
	b.Font = ProgressUi.font
	b.TextScaled = true
	b.AutoButtonColor = true
	b.BackgroundColor3 =
		ProgressUi.hex(if gold then ProgressUi.look.accent else ProgressUi.look.panel)
	b.TextColor3 = ProgressUi.hex(ProgressUi.look.ink)
	b.Parent = slot
	ProgressUi.round(b, 0.3)
	ProgressUi.outline(gui, b, 1)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.18, 0)
	pad.PaddingBottom = UDim.new(0.18, 0)
	pad.Parent = b
	return slot, b
end

return ProgressUi
