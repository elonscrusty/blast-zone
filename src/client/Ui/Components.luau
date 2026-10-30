--!strict
-- The building blocks every screen is made of: screen, panel, text, button, bar, modal.
-- They take ROLES ("accent", "title", "primary"), never colours or fonts, and read the look from
-- Tokens (the current skin). So a new skin from Claude Design restyles every screen built here,
-- and a view file only says WHAT goes WHERE. Rule: plans/CONTRACTS.md, "Look and logic".
--
-- Sizes follow the HUD: shares of the screen height (design phone 780 x 360, see Hud/Layout).
-- Buttons never shrink under Tokens.MIN_TOUCH design points, so they stay easy to hit on a phone.

local Players = game:GetService("Players")

local Tokens = require(script.Parent.Tokens)
local UiLayers = require(script.Parent.UiLayers)
local ModalGate = require(script.Parent.ModalGate)
local UiKit = require(script.Parent.Parent.Hud.UiKit)
local Layout = require(script.Parent.Parent.Hud.Layout)

local Components = {}

export type ButtonStyle = "primary" | "secondary" | "danger" | "quiet"

local BUTTON_FILL: { [string]: string } = {
	primary = "accent",
	secondary = "panel",
	danger = "danger",
	quiet = "panelAlt",
}
local BUTTON_INK: { [string]: string } = {
	primary = "inkOnAccent",
	secondary = "ink",
	danger = "inkOnAccent",
	quiet = "ink",
}

local function color(role: string): Color3
	return Color3.fromHex(Tokens.color(role))
end

-- Text size cap in pixels for a text role on this screen height.
local function textPixels(role: Tokens.TextRole, screenHeight: number): number
	local skin = Tokens.get(nil)
	local points = (skin.text :: any)[role] :: number
	return math.max(Tokens.MIN_TEXT, math.floor(points * screenHeight / Layout.HEIGHT + 0.5))
end

local function fontFor(role: Tokens.TextRole): Enum.Font
	local skin = Tokens.get(nil)
	local name = if role == "body" or role == "caption" then skin.fonts.body else skin.fonts.display
	return UiKit.fontEnum(name)
end

-- A full-screen ScreenGui on a named layer (see UiLayers) with an empty Root frame inside.
function Components.screen(name: string, layer: string): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = UiLayers.get(layer)
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Active = false
	root.Parent = gui

	local player = Players.LocalPlayer
	if player then
		gui.Parent = player:WaitForChild("PlayerGui")
	end
	return gui, root
end

export type TextOptions = {
	text: string?,
	color: string?, -- a colour role, default "ink"
	align: Enum.TextXAlignment?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
}

-- A label in a text role. `root` is the full-screen frame (text size follows its height).
function Components.text(
	parent: Instance,
	root: GuiObject,
	name: string,
	role: Tokens.TextRole,
	opts: TextOptions?
): TextLabel
	local o: TextOptions = opts or {}
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = fontFor(role)
	l.TextScaled = true
	l.Text = o.text or ""
	l.TextColor3 = color(o.color or "ink")
	l.TextXAlignment = o.align or Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Size = o.size or UDim2.fromScale(1, 1)
	l.Position = o.position or UDim2.new()
	l.AnchorPoint = o.anchor or Vector2.zero
	l.Active = false
	local cap = Instance.new("UITextSizeConstraint")
	cap.MinTextSize = Tokens.MIN_TEXT
	cap.Parent = l
	local function sync()
		cap.MaxTextSize = textPixels(role, root.AbsoluteSize.Y)
	end
	sync()
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync)
	l.Parent = parent
	return l
end

-- A sticker panel (fill, outline, hard shadow) in a colour role. Returns panel and shadow.
function Components.panel(
	parent: Instance,
	root: GuiObject,
	name: string,
	fill: string?
): (Frame, Frame)
	local panel, shadow = UiKit.sticker(parent, root, name, Tokens.color(fill or "panel"))
	UiKit.followShadow(panel, shadow, root)
	return panel, shadow
end

export type ButtonOptions = {
	text: string,
	style: ButtonStyle?,
	onPress: (() -> ())?,
}

-- A big button. Fires `onPress` on tap, click or gamepad A (Roblox `Activated`).
-- Keeps at least Tokens.MIN_TOUCH design points on its short side.
function Components.button(
	parent: Instance,
	root: GuiObject,
	name: string,
	opts: ButtonOptions
): TextButton
	local skin = Tokens.get(nil)
	local style = opts.style or "primary"

	local shadow = Instance.new("Frame")
	shadow.Name = name .. "Shadow"
	shadow.BackgroundColor3 = color("shadow")
	shadow.BorderSizePixel = 0
	shadow.Active = false
	shadow.Parent = parent
	UiKit.round(shadow, skin.shape.cornerScale)

	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BackgroundColor3 = color(BUTTON_FILL[style])
	b.BorderSizePixel = 0
	b.Font = fontFor("title")
	b.TextScaled = true
	b.Text = opts.text
	b.TextColor3 = color(BUTTON_INK[style])
	b.Selectable = true
	UiKit.round(b, skin.shape.cornerScale)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color("outline")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	UiKit.styleStroke(stroke, root)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.08, 0)
	pad.PaddingRight = UDim.new(0.08, 0)
	pad.PaddingTop = UDim.new(0.14, 0)
	pad.PaddingBottom = UDim.new(0.14, 0)
	pad.Parent = b
	local minSize = Instance.new("UISizeConstraint")
	minSize.Parent = b
	local function syncMin()
		local px = math.floor(Tokens.MIN_TOUCH * root.AbsoluteSize.Y / Layout.HEIGHT + 0.5)
		minSize.MinSize = Vector2.new(px, px)
	end
	syncMin()
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncMin)
	b.Parent = parent
	UiKit.followShadow(b, shadow, root)

	b.Activated:Connect(function()
		UiKit.pop(b, 0.92)
		if opts.onPress then
			opts.onPress()
		end
	end)
	return b
end

-- Recolours a button to another style (for example "primary" -> "quiet" once pressed).
function Components.restyle(b: TextButton, style: ButtonStyle)
	b.BackgroundColor3 = color(BUTTON_FILL[style])
	b.TextColor3 = color(BUTTON_INK[style])
end

-- A bar with a track and a fill. Returns the track and a setter for 0..1.
function Components.bar(parent: Instance, name: string, fill: string): (Frame, (number) -> ())
	local track = Instance.new("Frame")
	track.Name = name
	track.BackgroundColor3 = color("dim")
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Active = false
	track.Parent = parent
	UiKit.round(track, 0.5)

	local bar = Instance.new("Frame")
	bar.Name = "Fill"
	bar.BackgroundColor3 = color(fill)
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromScale(1, 1)
	bar.Active = false
	bar.Parent = track
	UiKit.round(bar, 0.5)

	return track,
		function(fraction: number)
			bar.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		end
end

export type Modal = {
	gui: ScreenGui,
	root: Frame,
	panel: Frame,
	body: Frame, -- put the panel's content here
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
}

-- A full panel on the Modal layer: dim backdrop, centred sticker panel, title and a DONE button.
-- Only one is open at a time (ModalGate). `onClose` runs every time it closes.
function Components.modal(name: string, title: string, onClose: (() -> ())?): Modal
	local skin = Tokens.get(nil)
	local gui, root = Components.screen(name, "Modal")
	gui.Enabled = false

	local dim = Instance.new("TextButton")
	dim.Name = "Backdrop"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Selectable = false
	dim.BackgroundColor3 = color("backdrop")
	dim.BackgroundTransparency = skin.shape.backdropAlpha
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.Parent = root

	local panel = Components.panel(root, root, "Panel", "panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.6, 0.82)
	panel.ZIndex = 3

	Components.text(panel, root, "Title", "title", {
		text = title,
		size = UDim2.fromScale(0.9, 0.14),
		position = UDim2.fromScale(0.5, 0.04),
		anchor = Vector2.new(0.5, 0),
	})

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.fromScale(0.5, 0.2)
	body.Size = UDim2.fromScale(0.9, 0.58)
	body.Parent = panel

	local isOpen = false
	local function close()
		if not isOpen then
			return
		end
		isOpen = false
		gui.Enabled = false
		ModalGate.closed(name)
		if onClose then
			onClose()
		end
	end
	local function open()
		if isOpen then
			return
		end
		isOpen = true
		gui.Enabled = true
		ModalGate.opened(name, close)
		UiKit.pop(panel, 1.06)
	end

	local done = Components.button(
		panel,
		root,
		"Done",
		{ text = "DONE", style = "primary", onPress = close }
	)
	done.AnchorPoint = Vector2.new(0.5, 1)
	done.Position = UDim2.fromScale(0.5, 0.95)
	done.Size = UDim2.fromScale(0.4, 0.14)
	dim.Activated:Connect(close)

	local modal: Modal = {
		gui = gui,
		root = root,
		panel = panel,
		body = body,
		open = open,
		close = close,
		isOpen = function()
			return isOpen
		end,
	}
	return modal
end

return Components
