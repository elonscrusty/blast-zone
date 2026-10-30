--!strict
-- On-screen controls for phones, in look B: move stick (left), aim-and-fire stick (right),
-- Slide, Reload, and a tap target over the weapon panel to swap weapons.
-- Sticks measure how far the finger moved from where it first touched, so they work the same on
-- every phone and notch. Shown only on touch devices while controls are on.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Layout = require(script.Parent.Parent.Hud.Layout)
local UiKit = require(script.Parent.Parent.Hud.UiKit)
local Settings = require(script.Parent.Parent.Settings.Settings)
local Controls = require(script.Parent.Controls)
local InputMath = require("./InputMath")

local TouchControls = {}

local gui: ScreenGui
local root: Frame
local pieces: { [string]: GuiObject } = {}
local slideDial: Frame
local slideText: TextLabel
local visible = false
local wasSlideReady = true

local function applyLayout()
	local left = Settings.flag("leftHanded")
	local scale = Settings.number("touchScale")
	for name, obj in pieces do
		local rect = if name == "weapon" then Layout.regions.weapon else Layout.regions[name]
		UiKit.place(obj, rect, left)
		local found = obj:FindFirstChild("TouchScale")
		local s: UIScale
		if found and found:IsA("UIScale") then
			s = found
		else
			s = Instance.new("UIScale")
			s.Name = "TouchScale"
			s.Parent = obj
		end
		s.Scale = scale
	end
end

-- A stick. `onChange(x, y, active)` gets a vector of length 0..1 with y UP.
local function makeStick(
	name: string,
	label: string?,
	fillHex: string,
	onChange: (number, number, boolean) -> ()
)
	local look = UiKit.look()
	local base, shadow = UiKit.sticker(root, root, name, fillHex, 0.5)
	base.BackgroundTransparency = 0.25
	UiKit.followShadow(base, shadow, root)
	pieces[name] = base

	if label then
		UiKit.label(base, "Label", {
			text = label,
			size = UDim2.fromScale(0.6, 0.3),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			color = look.panel,
			maxTextSize = 34,
		})
	end

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromScale(0.42, 0.42)
	knob.BackgroundColor3 = UiKit.color(look.panel)
	knob.BorderSizePixel = 0
	knob.Active = false
	knob.Parent = base
	UiKit.circle(knob)
	local ks = Instance.new("UIStroke")
	ks.Color = UiKit.color(look.outline)
	ks.Parent = knob
	UiKit.styleStroke(ks, root)

	-- Catches the finger. Bigger than the picture so a thumb that drifts is not lost.
	local zone = Instance.new("Frame")
	zone.Name = "Zone"
	zone.AnchorPoint = Vector2.new(0.5, 0.5)
	zone.Position = UDim2.fromScale(0.5, 0.5)
	zone.Size = UDim2.fromScale(1.5, 1.5)
	zone.BackgroundTransparency = 1
	zone.Active = true
	zone.Parent = base

	local tracked: InputObject? = nil
	local startX, startY = 0, 0

	local function release()
		tracked = nil
		knob.Position = UDim2.fromScale(0.5, 0.5)
		onChange(0, 0, false)
	end

	local function move(input: InputObject)
		local radius = base.AbsoluteSize.X / 2
		local dx, dy = input.Position.X - startX, input.Position.Y - startY
		local x, y = InputMath.stickFromOffset(dx, dy, radius)
		-- Draw the knob where the (clamped) finger offset says, not through the deadzone.
		local mag = math.sqrt(dx * dx + dy * dy)
		local clamp = if mag > radius then radius / mag else 1
		knob.Position = UDim2.new(0.5, dx * clamp, 0.5, dy * clamp)
		onChange(x, y, true)
	end

	zone.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch and tracked == nil then
			tracked = input
			startX, startY = input.Position.X, input.Position.Y
			Controls.noteDevice("touch")
			move(input)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if tracked ~= nil and input == tracked then
			move(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if tracked ~= nil and input == tracked then
			release()
		end
	end)
	-- Hiding the stick mid-touch must not leave it "held".
	base:GetPropertyChangedSignal("Visible"):Connect(function()
		if not base.Visible and tracked ~= nil then
			release()
		end
	end)
end

local function makeButton(name: string, text: string, fillHex: string, action: string): TextButton
	local look = UiKit.look()
	local panel, shadow = UiKit.sticker(root, root, name .. "Frame", fillHex, 0.5)
	UiKit.followShadow(panel, shadow, root)
	pieces[name] = panel

	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 5
	button.Parent = panel
	button.Activated:Connect(function()
		Controls.noteDevice("touch")
		Controls.trigger(action)
		UiKit.pop(panel, 0.92)
	end)

	UiKit.label(panel, "Label", {
		text = text,
		size = UDim2.fromScale(0.8, 0.3),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = look.ink,
		maxTextSize = 22,
	})
	return button
end

local function build()
	local look = UiKit.look()
	gui = Instance.new("ScreenGui")
	gui.Name = "TouchControls"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = require(script.Parent.Parent.Ui.UiLayers).TouchControls
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Active = false
	root.Parent = gui

	makeStick("moveStick", nil, look.panel, function(x, y, _active)
		Controls.setTouchMove(x, y)
	end)
	makeStick("fireStick", "FIRE", look.danger, function(x, y, active)
		Controls.setTouchAim(x, y, active)
	end)

	makeButton("slide", "SLIDE", look.accent, "slide")
	makeButton("reload", "RELOAD", look.panel, "reload")

	-- Slide cooldown: a navy veil that drains upward, and the seconds left.
	local slide = pieces.slide
	local clip = Instance.new("CanvasGroup")
	clip.Name = "Clip"
	clip.BackgroundTransparency = 1
	clip.Size = UDim2.fromScale(1, 1)
	clip.Active = false
	clip.ZIndex = 3
	clip.Parent = slide
	UiKit.circle(clip)
	slideDial = Instance.new("Frame")
	slideDial.Name = "Veil"
	slideDial.AnchorPoint = Vector2.new(0, 1)
	slideDial.Position = UDim2.fromScale(0, 1)
	slideDial.Size = UDim2.fromScale(1, 0.6)
	slideDial.BackgroundColor3 = UiKit.color(look.outline)
	slideDial.BackgroundTransparency = 0.35
	slideDial.BorderSizePixel = 0
	slideDial.Active = false
	slideDial.Parent = clip
	slideText = UiKit.label(slide, "Seconds", {
		text = "",
		size = UDim2.fromScale(0.7, 0.4),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = look.panel,
		maxTextSize = 26,
	})
	slideText.ZIndex = 4

	-- Tap target over the weapon panel (the picture is drawn by the HUD).
	local swap = Instance.new("TextButton")
	swap.Name = "weapon"
	swap.Text = ""
	swap.AutoButtonColor = false
	swap.BackgroundTransparency = 1
	swap.Parent = root
	swap.Activated:Connect(function()
		Controls.noteDevice("touch")
		Controls.trigger("swap")
	end)
	pieces.weapon = swap

	applyLayout()
	Settings.Changed:connect(function(key: string)
		if key == "leftHanded" or key == "touchScale" then
			applyLayout()
		end
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function TouchControls.start()
	build()
	Controls.DeviceChanged:connect(function()
		gui.Enabled = visible and Controls.device() == "touch"
	end)
	gui.Enabled = visible and Controls.device() == "touch"
end

-- Called every frame by HudSystem. `show` = the HUD wants controls on screen.
function TouchControls.update(
	show: boolean,
	slideReady: boolean,
	slideFraction: number,
	slideSeconds: number
)
	visible = show
	local want = show and Controls.device() == "touch"
	if gui.Enabled ~= want then
		gui.Enabled = want
	end
	if not want then
		return
	end
	if slideReady and not wasSlideReady then
		UiKit.pop(pieces.slide, 1.18) -- ready again
	end
	wasSlideReady = slideReady
	slideDial.Size = UDim2.fromScale(1, if slideReady then 0 else 1 - slideFraction)
	local text = if slideReady then "" else tostring(math.ceil(slideSeconds))
	if slideText.Text ~= text then
		slideText.Text = text
	end
end

return TouchControls
