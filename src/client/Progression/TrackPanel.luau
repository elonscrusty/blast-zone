--!strict
-- The unlock track screen: the free looks, then the six tiers in the order they are bought. Tap UNLOCK on the next
-- one (the server checks price and order), tap WEAR on anything you own. Looks only: no stats change.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoinLooks = require(Shared.Progression.CoinLooks)
local Config = require(Shared.Config)
local TrackDefs = require(Shared.Progression.TrackDefs)
local CoinView = require(script.Parent.CoinView)
local ProgressClient = require(script.Parent.ProgressClient)
local ProgressText = require(script.Parent.ProgressText)
local Ui = require(script.Parent.ProgressUi)
local ModalGate = require(script.Parent.Parent.Ui.ModalGate)
local UiLayers = require(script.Parent.Parent.Ui.UiLayers)

local TrackPanel = {}

local gui: ScreenGui? = nil
local list: ScrollingFrame
local totalLabel: TextLabel
local noteLabel: TextLabel
local coinName = CoinLooks.get(Config.Progression.look).name

local function swatch(parent: Instance, def: TrackDefs.Item)
	local box = Instance.new("Frame")
	box.Name = "Swatch"
	box.Size = UDim2.fromOffset(56, 40)
	box.BackgroundColor3 = Ui.hex(Ui.look.outline)
	box.Parent = parent
	Ui.round(box, 0.2)
	local color = Ui.hex(def.color)
	if def.slot == "trail" then
		for i = 1, 3 do
			local bar = Instance.new("Frame")
			bar.BackgroundColor3 = color
			bar.BackgroundTransparency = (i - 1) * 0.3
			bar.BorderSizePixel = 0
			bar.AnchorPoint = Vector2.new(0, 0.5)
			bar.Size = UDim2.fromScale(0.8 - (i - 1) * 0.2, 0.14)
			bar.Position = UDim2.fromScale(0.1, 0.25 * i)
			bar.Parent = box
			Ui.round(bar, 0.5)
		end
	else
		local beam = Instance.new("Frame")
		beam.BackgroundColor3 = color
		beam.BorderSizePixel = 0
		beam.AnchorPoint = Vector2.new(0, 0.5)
		beam.Size = UDim2.fromScale(0.62, 0.12)
		beam.Position = UDim2.fromScale(0.08, 0.5)
		beam.Parent = box
		Ui.round(beam, 0.5)
		local dot = Instance.new("Frame")
		dot.BackgroundColor3 = color
		dot.BorderSizePixel = 0
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Size = UDim2.fromOffset(12, 12)
		dot.Position = UDim2.fromScale(0.82, 0.5)
		dot.Parent = box
		Ui.round(dot, 0.5)
	end
end

local function addRow(def: TrackDefs.Item, order: number, state: any, nextId: string?)
	local g = gui :: ScreenGui
	local row = Instance.new("Frame")
	row.Name = def.id
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -8, 0, 64)
	row.BackgroundColor3 = Ui.hex("#FFFFFF")
	row.BackgroundTransparency = 0.55
	row.Parent = list
	Ui.round(row, 0.2)

	local sw = Instance.new("Frame")
	sw.BackgroundTransparency = 1
	sw.Size = UDim2.fromOffset(60, 44)
	sw.Position = UDim2.fromOffset(8, 10)
	sw.Parent = row
	swatch(sw, def)

	local name = Ui.label(row, "Name", def.name, 26)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Position = UDim2.new(0, 76, 0, 6)
	name.Size = UDim2.new(0.45, 0, 0, 30)
	local status = Ui.label(row, "Status", ProgressText.cardStatus(def, state, coinName), 20)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextTransparency = 0.25
	status.Position = UDim2.new(0, 76, 0, 36)
	status.Size = UDim2.new(0.45, 0, 0, 22)

	local owned = def.cost == 0
	for _, id in state.unlocked do
		if id == def.id then
			owned = true
		end
	end
	local worn = state.equipped[def.slot] == def.id

	local label: string
	local gold = false
	local action: string? = nil
	if worn then
		label = "WORN"
	elseif owned then
		label, action = "WEAR", "equip"
	elseif def.id == nextId then
		label, gold, action = "UNLOCK", state.coins >= def.cost, "unlock"
	else
		label = "LOCKED"
	end
	local slot, button = Ui.button(g, row, "Action", label, gold)
	slot.AnchorPoint = Vector2.new(1, 0.5)
	slot.Position = UDim2.new(1, -10, 0.5, -2)
	slot.Size = UDim2.new(0.3, 0, 0, 48)
	if action == nil then
		button.AutoButtonColor = false
		button.TextTransparency = 0.5
	end
	button.Activated:Connect(function()
		if action == "equip" then
			ProgressClient.equip(def.id)
		elseif action == "unlock" then
			ProgressClient.unlock(def.id)
		end
	end)
end

local function refresh()
	if gui == nil then
		return
	end
	local state = ProgressClient.get()
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if state == nil then
		totalLabel.Text = "..."
		noteLabel.Text = "Loading your coins..."
		return
	end
	totalLabel.Text = `{state.coins} {coinName}`
	local nextTier = ProgressClient.nextTier()
	local order = 0
	for _, def in TrackDefs.defaults do
		order += 1
		addRow(def, order, state, nil)
	end
	for _, def in TrackDefs.tiers do
		order += 1
		addRow(def, order, state, if nextTier then nextTier.id else nil)
	end
	noteLabel.Text = ProgressText.denied(state.denied, coinName)
		or ProgressText.noteFor(state.status)
		or ""
end

local function build()
	local g = Instance.new("ScreenGui")
	g.Name = "TrackPanel"
	g.ResetOnSpawn = false
	g.DisplayOrder = UiLayers.Modal
	g.IgnoreGuiInset = true
	g.Enabled = false
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = g

	local scrim = Instance.new("TextButton") -- a button so taps do not fall through to the game
	scrim.Name = "Scrim"
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Color3.new(0, 0, 0)
	scrim.BackgroundTransparency = 0.45
	scrim.Parent = g

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.8, 0.84)
	panel.BackgroundColor3 = Ui.hex(Ui.look.panel)
	panel.Parent = g
	Ui.round(panel, 0.04)
	Ui.outline(g, panel, 1.2)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(760, 460)
	limit.Parent = panel

	local title = Ui.label(panel, "Title", "REWARDS", 40)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.new(0, 16, 0, 8)
	title.Size = UDim2.new(0.5, 0, 0, 44)

	local coinBox = Instance.new("Frame")
	coinBox.BackgroundTransparency = 1
	coinBox.AnchorPoint = Vector2.new(1, 0)
	coinBox.Position = UDim2.new(1, -76, 0, 4)
	coinBox.Size = UDim2.fromOffset(150, 52)
	coinBox.Parent = panel
	local vp = CoinView.create(coinBox, Config.Progression.look)
	vp.Size = UDim2.fromOffset(52, 52)
	totalLabel = Ui.label(coinBox, "Total", "", 28)
	totalLabel.TextXAlignment = Enum.TextXAlignment.Left
	totalLabel.Position = UDim2.new(0, 56, 0, 8)
	totalLabel.Size = UDim2.new(1, -56, 0, 36)

	local closeSlot, close = Ui.button(g, panel, "Close", "X", false)
	closeSlot.AnchorPoint = Vector2.new(1, 0)
	closeSlot.Position = UDim2.new(1, -12, 0, 6)
	closeSlot.Size = UDim2.fromOffset(52, 48)
	close.Activated:Connect(function()
		g.Enabled = false
	end)

	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 12, 0, 62)
	list.Size = UDim2.new(1, -24, 1, -98)
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	noteLabel = Ui.label(panel, "Note", "", 22)
	noteLabel.AnchorPoint = Vector2.new(0.5, 1)
	noteLabel.Position = UDim2.new(0.5, 0, 1, -6)
	noteLabel.Size = UDim2.new(0.9, 0, 0, 26)

	ProgressClient.Changed:connect(refresh)
end

function TrackPanel.toggle()
	ProgressClient.ensureStarted()
	if gui == nil then
		build()
	end
	local g = gui :: ScreenGui
	g.Enabled = not g.Enabled
	if g.Enabled then
		refresh()
		ModalGate.opened("track", function()
			g.Enabled = false
		end)
	else
		ModalGate.closed("track")
	end
end

return TrackPanel
