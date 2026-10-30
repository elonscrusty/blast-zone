--!strict
-- The settings screen: a small gear on the HUD opens a cream sticker panel with sliders and
-- switches. Every value goes through Settings (checked and clamped there). Big tap targets.
-- Opening it clears held input so the character does not run off while the panel is open.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local ModalGate = require(script.Parent.Parent.Ui.ModalGate)
local UiLayers = require(script.Parent.Parent.Ui.UiLayers)
local Controls = require(script.Parent.Parent.Controls.Controls)
local Layout = require(script.Parent.Parent.Hud.Layout)
local UiKit = require(script.Parent.Parent.Hud.UiKit)
local Settings = require(script.Parent.Settings)
local SettingsModel = require(script.Parent.SettingsModel)

local SettingsPanel = {}

local PANEL: Layout.Rect = { x = 120, y = 34, w = 540, h = 292 }
local ROW_H = 44

local gui: ScreenGui
local dimButton: TextButton
local root: Frame
local panel: Frame
local isOpen = false
local rowUpdaters: { [string]: (number | boolean) -> () } = {}

local function setOpen(open: boolean)
	isOpen = open
	panel.Visible = open
	dimButton.Visible = open
	if open then
		Controls.reset()
		ModalGate.opened("settings", function()
			setOpen(false)
		end)
	else
		ModalGate.closed("settings")
	end
end

function SettingsPanel.toggle()
	setOpen(not isOpen)
end

local function makeSlider(parent: Frame, def: SettingsModel.Def)
	local look = UiKit.look()
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.fromScale(1, 0.5)
	track.Size = UDim2.fromScale(0.5, 0.42)
	track.BackgroundColor3 = UiKit.color(look.dim)
	track.BorderSizePixel = 0
	track.Active = true
	track.Parent = parent
	UiKit.circle(track)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiKit.color(look.outline)
	stroke.Parent = track
	UiKit.styleStroke(stroke, root, 0.6)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = UiKit.color(look.accent)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0.5, 1)
	fill.Active = false
	fill.Parent = track
	UiKit.circle(fill)

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromScale(0.09, 1.7)
	knob.BackgroundColor3 = UiKit.color(look.panel)
	knob.BorderSizePixel = 0
	knob.Active = false
	knob.Parent = track
	UiKit.circle(knob)
	local kstroke = Instance.new("UIStroke")
	kstroke.Color = UiKit.color(look.outline)
	kstroke.Parent = knob
	UiKit.styleStroke(kstroke, root, 0.8)

	local valueLabel = UiKit.label(parent, "Value", {
		size = UDim2.fromScale(0.12, 0.6),
		position = UDim2.fromScale(0.47, 0.5),
		anchor = Vector2.new(1, 0.5),
		align = Enum.TextXAlignment.Right,
		maxTextSize = 18,
	})

	local function show(value: number | boolean)
		local f = SettingsModel.toFraction(def.key, if type(value) == "number" then value else 0)
		fill.Size = UDim2.fromScale(f, 1)
		knob.Position = UDim2.fromScale(f, 0.5)
		valueLabel.Text = string.format("%d%%", math.floor((value :: number) * 100 + 0.5))
	end
	rowUpdaters[def.key] = show
	show(Settings.get(def.key))

	-- Drag: position comes from the finger's X on the track (the panel is not inset-shifted).
	local dragging = false
	local function setFrom(inputX: number)
		local w = track.AbsoluteSize.X
		if w <= 0 then
			return
		end
		local f = (inputX - track.AbsolutePosition.X) / w
		local v = SettingsModel.fromFraction(def.key, f)
		if v ~= nil then
			Settings.set(def.key, v)
		end
	end
	track.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = true
			setFrom(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			setFrom(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local function makeToggle(parent: Frame, def: SettingsModel.Def)
	local look = UiKit.look()
	local button = Instance.new("TextButton")
	button.Name = "Toggle"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.fromScale(1, 0.5)
	button.Size = UDim2.fromScale(0.3, 0.74)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Font = UiKit.FONT
	button.TextScaled = true
	button.Parent = parent
	UiKit.circle(button)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiKit.color(look.outline)
	stroke.Parent = button
	UiKit.styleStroke(stroke, root, 0.7)
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 20
	cap.Parent = button

	local function show(value: number | boolean)
		local on = value == true
		button.Text = if on then "ON" else "OFF"
		button.BackgroundColor3 = UiKit.color(if on then look.accent else look.dim)
		button.TextColor3 = UiKit.color(look.ink)
	end
	rowUpdaters[def.key] = show
	show(Settings.get(def.key))
	button.Activated:Connect(function()
		Settings.set(def.key, not Settings.flag(def.key))
		UiKit.pop(button, 1.1)
	end)
end

local function build()
	local look = UiKit.look()
	local player = Players.LocalPlayer

	gui = Instance.new("ScreenGui")
	gui.Name = "Settings"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = UiLayers.Modal -- over the lobby buttons (MatchFlow) so they cannot show through
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Dim layer behind the panel; tapping it closes the settings.
	dimButton = Instance.new("TextButton")
	dimButton.Name = "Dim"
	dimButton.Text = ""
	dimButton.AutoButtonColor = false
	dimButton.Size = UDim2.fromScale(1, 1)
	dimButton.BackgroundColor3 = UiKit.color(look.outline)
	dimButton.BackgroundTransparency = 0.45
	dimButton.BorderSizePixel = 0
	dimButton.Visible = false
	dimButton.Parent = gui
	dimButton.Activated:Connect(function()
		setOpen(false)
	end)

	root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Active = false
	root.Parent = gui

	local shadow
	panel, shadow = UiKit.sticker(root, root, "Panel", nil, 0.06)
	UiKit.place(panel, PANEL)
	UiKit.followShadow(panel, shadow, root)
	panel.Visible = false
	panel.Active = true

	UiKit.label(panel, "Title", {
		text = "SETTINGS",
		size = UDim2.fromScale(0.5, 0.11),
		position = UDim2.fromScale(0.04, 0.03),
		align = Enum.TextXAlignment.Left,
		maxTextSize = 30,
	})

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = "DONE"
	close.Font = UiKit.FONT
	close.TextScaled = true
	close.TextColor3 = UiKit.color(look.ink)
	close.BackgroundColor3 = UiKit.color(look.accent)
	close.BorderSizePixel = 0
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(0.97, 0.03)
	close.Size = UDim2.fromScale(0.2, 0.13)
	close.Parent = panel
	UiKit.circle(close)
	local cs = Instance.new("UIStroke")
	cs.Color = UiKit.color(look.outline)
	cs.Parent = close
	UiKit.styleStroke(cs, root)
	local ccap = Instance.new("UITextSizeConstraint")
	ccap.MaxTextSize = 22
	ccap.Parent = close
	close.Activated:Connect(function()
		setOpen(false)
	end)

	-- Two columns of rows.
	local perColumn = math.ceil(#SettingsModel.defs / 2)
	for i, def in SettingsModel.defs do
		local col = (i - 1) // perColumn
		local row = (i - 1) % perColumn
		local frame = Instance.new("Frame")
		frame.Name = def.key
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromScale(0.44, ROW_H / PANEL.h)
		frame.Position = UDim2.fromScale(0.04 + col * 0.48, 0.2 + row * (ROW_H + 8) / PANEL.h)
		frame.Parent = panel
		UiKit.label(frame, "Label", {
			text = def.label,
			size = UDim2.fromScale(0.5, 0.7),
			position = UDim2.fromScale(0, 0.5),
			anchor = Vector2.new(0, 0.5),
			align = Enum.TextXAlignment.Left,
			maxTextSize = 20,
		})
		if def.kind == "slider" then
			makeSlider(frame, def)
		else
			makeToggle(frame, def)
		end
	end

	Settings.Changed:connect(function(key: string, value: number | boolean)
		local update = rowUpdaters[key]
		if update then
			update(value)
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function SettingsPanel.start()
	build()
end

return SettingsPanel
