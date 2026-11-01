--!strict
-- Small helpers the four shop panels (Upgrades, Tools, Helpers, Gates) share, so they all look and
-- behave the same way. Everything is built from Ui/Components + Ui/Theme.
--
--   PanelKit.header(parent) -> Header           coin counter on the left, one friendly hint line
--   PanelKit.scroll(parent, top) -> ScrollList  scrolling area under the header
--   PanelKit.newGrid(parent) -> UIGridLayout    a grid layout (left to right, wraps)
--   PanelKit.useGrid(list) -> UIGridLayout      swap the list layout for a grid (cards in columns)
--   PanelKit.setGrid(grid, cols, cellH)         columns + card height
--   PanelKit.slot(parent, order) -> (slot, card)  a layout cell with a centred card inside it, so a
--                                               "pop" scales the card around its middle
--   PanelKit.watchSize(body, fn) -> stop        fn(virtualSize) now and whenever the panel resizes
--   PanelKit.celebrate(target, text?)           gold flash + pop + floating text (level up!)
--   PanelKit.glow(stroke) -> stop               pulsing outline
--   PanelKit.wobble(inst, degrees) -> stop      gentle rocking (robots, tool previews)
--   PanelKit.stroke(inst) -> UIStroke?          the card's outline
--
-- Panel layout is decided from the panel's own size in "virtual px" (the size before UIScale),
-- found by dividing out every UIScale above the panel (the screen scale and the pop-in scale).

local TweenService = game:GetService("TweenService")

local Components = require(script.Parent.Parent.Parent.Ui.Components)
local Theme = require(script.Parent.Parent.Parent.Ui.Theme)

local PanelKit = {}

PanelKit.HEADER_H = 34
PanelKit.WIDE_FROM = 560 -- panel body at least this wide (virtual px) = landscape layout
PanelKit.SHORT_BELOW = 300 -- panel body shorter than this = squeeze the cards a little

local COIN_W = 124
local GLOW_SECONDS = 0.8
local WOBBLE_SECONDS = 1.3
-- used until the panel has a real size: a phone in landscape / in portrait
local FALLBACK_LANDSCAPE = Vector2.new(656, 244) -- 800x360 with the slim (short screen) title bar
local FALLBACK_PORTRAIT = Vector2.new(312, 606)
local FLOAT_SECONDS = 0.9

export type Header = {
	root: Frame,
	setCoins: (coins: number) -> (),
	setHint: (text: string) -> (),
}

-- ===== size =====

-- Product of every UIScale from `inst` up to its ScreenGui.
function PanelKit.scaleOf(inst: Instance): number
	local factor = 1
	local node: Instance? = inst
	while node ~= nil do
		for _, child in node:GetChildren() do
			if child:IsA("UIScale") then
				factor *= (child :: UIScale).Scale
			end
		end
		if node:IsA("LayerCollector") then
			break
		end
		node = node.Parent
	end
	return math.max(factor, 0.01)
end

-- Calls fn(virtualSize) right away and again whenever the size changes by 2 px or more.
function PanelKit.watchSize(body: GuiObject, fn: (size: Vector2) -> ()): () -> ()
	local last = Vector2.new(-100, -100)
	local function check()
		local abs = body.AbsoluteSize
		local size = FALLBACK_LANDSCAPE
		if abs.X >= 8 and abs.Y >= 8 then
			size = abs / PanelKit.scaleOf(body)
		else
			local cam = workspace.CurrentCamera
			if cam ~= nil and cam.ViewportSize.Y > cam.ViewportSize.X then
				size = FALLBACK_PORTRAIT
			end
		end
		if (size - last).Magnitude >= 2 then
			last = size
			fn(size)
		end
	end
	local conn = body:GetPropertyChangedSignal("AbsoluteSize"):Connect(check)
	check()
	return function()
		conn:Disconnect()
	end
end

-- ===== header and lists =====

function PanelKit.header(parent: Instance): Header
	local root = Instance.new("Frame")
	root.Name = "Header"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.new(1, 0, 0, PanelKit.HEADER_H)
	root.Parent = parent

	local pill = Components.Pill({
		parent = root,
		name = "Coins",
		position = UDim2.fromOffset(0, 2),
		size = UDim2.fromOffset(COIN_W, PanelKit.HEADER_H - 4),
		icon = "@coin",
		text = "0",
		textSize = Theme.text.body,
	})
	pill.label.TextColor3 = Theme.color.goldLight

	local hint = Components.Label({
		parent = root,
		name = "Hint",
		text = "",
		textSize = Theme.text.small,
		font = Theme.font.bold,
		color = Theme.color.charcoalSoft,
		align = Enum.TextXAlignment.Left,
		wrap = true,
		position = UDim2.fromOffset(COIN_W + Theme.size.pad, 0),
		size = UDim2.new(1, -(COIN_W + Theme.size.pad), 1, 0),
	})

	local shown = -1
	return {
		root = root,
		setCoins = function(coins: number)
			if coins == shown then
				return
			end
			if shown >= 0 and coins > shown then
				Components.punch(pill.root, 0.06)
			end
			shown = coins
			pill.setText(Theme.fmt(coins))
		end,
		setHint = function(text: string)
			hint.Text = text
		end,
	}
end

function PanelKit.scroll(parent: Instance, top: number): Components.ScrollList
	return Components.ScrollList({
		parent = parent,
		name = "Scroll",
		position = UDim2.fromOffset(0, top),
		size = UDim2.new(1, 0, 1, -top),
		gap = Theme.size.gap,
		padding = 2,
	})
end

function PanelKit.newGrid(parent: Instance): UIGridLayout
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.CellPadding = UDim2.fromOffset(Theme.size.gap, Theme.size.gap)
	grid.Parent = parent
	return grid
end

function PanelKit.useGrid(list: Components.ScrollList): UIGridLayout
	list.layout:Destroy()
	return PanelKit.newGrid(list.root)
end

function PanelKit.setGrid(grid: UIGridLayout, cols: number, cellHeight: number)
	local n = math.max(1, cols)
	local gap = Theme.size.gap
	grid.FillDirectionMaxCells = n
	grid.CellSize = UDim2.new(1 / n, -math.ceil(gap * (n - 1) / n), 0, cellHeight)
end

-- A layout cell with the card inside, inset a few px so a pop never gets clipped by the list.
function PanelKit.slot(parent: Instance, order: number): (Frame, Frame)
	local slot = Instance.new("Frame")
	slot.Name = "Slot"
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	slot.LayoutOrder = order
	slot.Parent = parent
	local card = Components.Card({
		parent = slot,
		name = "Card",
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.new(1, -6, 1, -6),
	})
	return slot, card
end

function PanelKit.stroke(inst: Instance): UIStroke?
	return inst:FindFirstChildOfClass("UIStroke")
end

-- ===== motion =====

function PanelKit.glow(stroke: UIStroke): () -> ()
	stroke.Transparency = 0
	local tween = TweenService:Create(
		stroke,
		TweenInfo.new(GLOW_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.7 }
	)
	tween:Play()
	return function()
		tween:Cancel()
	end
end

function PanelKit.wobble(inst: GuiObject, degrees: number): () -> ()
	inst.Rotation = -degrees
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(WOBBLE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Rotation = degrees }
	)
	tween:Play()
	return function()
		tween:Cancel()
	end
end

-- Pop + gold flash over `target`, with optional text that floats up and fades ("Level 5!").
function PanelKit.celebrate(target: GuiObject, text: string?)
	Components.punch(target, 0.04)

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BackgroundColor3 = Theme.color.goldLight
	flash.BackgroundTransparency = 0.25
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 20
	flash.Active = false
	local round = Instance.new("UICorner")
	round.CornerRadius = Theme.radius.md
	round.Parent = flash
	flash.Parent = target
	Components.tween(flash, { BackgroundTransparency = 1 }, Theme.ease.slow).Completed
		:Connect(function()
			flash:Destroy()
		end)

	if text ~= nil and text ~= "" then
		local label = Components.Label({
			parent = target,
			name = "Float",
			text = text,
			textSize = Theme.text.big,
			font = Theme.font.title,
			color = Theme.color.gold,
			outline = Theme.color.ink,
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(0.5, 0.6),
			size = UDim2.new(0.8, 0, 0, 30),
			zIndex = 22,
		})
		local info = TweenInfo.new(FLOAT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		Components.tween(label, { Position = UDim2.fromScale(0.5, 0.15) }, info)
		local fade = Components.tween(label, { TextTransparency = 1 }, info)
		local outline = label:FindFirstChildOfClass("UIStroke")
		if outline then
			Components.tween(outline, { Transparency = 1 }, info)
		end
		fade.Completed:Connect(function()
			label:Destroy()
		end)
	end
end

return PanelKit
