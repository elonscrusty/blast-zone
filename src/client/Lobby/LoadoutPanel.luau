--!strict
-- PLACEHOLDER look for the loadout screen. Claude Design will replace how this looks; the logic is all in
-- LoadoutController, so a new look only needs to draw what the controller says and call its functions.
-- Plain, big, touch-friendly: tabs across the top, one row of cards, BACK. No art.
--   LoadoutPanel.open() / close() / toggle() / isOpen()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local LoadoutView = require(Shared.LoadoutView)

local Controller = require(script.Parent.LoadoutController)

local LoadoutPanel = {}

local PAL = Config.Palette
local CREAM = Color3.fromHex("#FFF4D6")
local NAVY = Color3.fromHex(PAL.Navy)
local GOLD = Color3.fromHex(PAL.RewardGold)
local CYAN = Color3.fromHex(PAL.Cyan)
local GREY = Color3.fromHex("#A9A193")
local MIN_TOUCH = 44 -- pixels: nothing you tap is smaller than this

local gui: ScreenGui? = nil
local root: Frame? = nil
local tabBar: Frame? = nil
local cardRow: ScrollingFrame? = nil
local coinLabel: TextLabel? = nil
local noteLabel: TextLabel? = nil
local open = false

local function style(frame: GuiObject, fill: Color3, radius: number)
	frame.BackgroundColor3 = fill
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = NAVY
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Text = text
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = NAVY
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, fill: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.TextColor3 = NAVY
	b.AutoButtonColor = true
	style(b, fill, 0.25)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(MIN_TOUCH * 1.5, MIN_TOUCH)
	limit.Parent = b
	b.Parent = parent
	return b
end

local function redraw()
	local bar, row = tabBar, cardRow
	if not root or not bar or not row then
		return
	end
	for _, child in bar:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local tabs = LoadoutView.tabs()
	local count = #tabs
	for i, t in tabs do
		local b = button(bar, t.label, if t.slot == Controller.getTab() then CYAN else CREAM)
		b.Size = UDim2.new(1 / count, -8, 1, 0)
		b.Position = UDim2.new((i - 1) / count, 4, 0, 0)
		b.Activated:Connect(function()
			Controller.setTab(t.slot)
		end)
	end

	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local cards = Controller.cards()
	local slot = Controller.getTab()
	for i, card in cards do
		local b =
			button(row, "", if card.locked then GREY elseif card.equipped then GOLD else CREAM)
		b.Size = UDim2.new(0.23, 0, 1, -8)
		b.Position = UDim2.new((i - 1) * 0.245, 0, 0, 4)
		label(b, card.name, UDim2.fromScale(0.9, 0.34), UDim2.fromScale(0.05, 0.08))
		local desc = label(b, card.desc, UDim2.fromScale(0.9, 0.32), UDim2.fromScale(0.05, 0.44))
		desc.Font = Enum.Font.GothamBold
		desc.TextTransparency = 0.25
		label(b, card.status, UDim2.fromScale(0.9, 0.2), UDim2.fromScale(0.05, 0.78))
		b.Activated:Connect(function()
			Controller.equip(slot, card.id)
		end)
	end
	row.CanvasSize = UDim2.fromScale(math.max(1, #cards * 0.245), 0)

	local state = Controller.getState()
	if coinLabel then
		coinLabel.Text = if state.coins then `Scrap: {state.coins}` else ""
	end
	if noteLabel and noteLabel.Text == "" then
		noteLabel.Text = LoadoutView.footer(state)
	end
end

local function build()
	if gui then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "Loadout"
	g.ResetOnSpawn = false
	g.DisplayOrder = 60 -- above match flow (50), below nothing else we know of
	g.IgnoreGuiInset = true
	g.Enabled = false
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = g

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = NAVY
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Parent = g

	-- The panel keeps clear of the screen edges (thumbs) and fits a phone held sideways.
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.86, 0.8)
	style(panel, Color3.fromHex("#1D3552"), 0.04)
	panel.Parent = g
	root = panel

	label(panel, "LOADOUT", UDim2.fromScale(0.3, 0.12), UDim2.fromScale(0.03, 0.03)).TextColor3 =
		GOLD
	local coins = label(panel, "", UDim2.fromScale(0.25, 0.09), UDim2.fromScale(0.36, 0.045))
	coins.TextColor3 = CREAM
	coinLabel = coins
	local back = button(panel, "BACK", CREAM)
	back.AnchorPoint = Vector2.new(1, 0)
	back.Position = UDim2.fromScale(0.97, 0.03)
	back.Size = UDim2.fromScale(0.18, 0.12)
	back.Activated:Connect(function()
		LoadoutPanel.close()
	end)

	local bar = Instance.new("Frame")
	bar.BackgroundTransparency = 1
	bar.Position = UDim2.fromScale(0.03, 0.2)
	bar.Size = UDim2.fromScale(0.94, 0.13)
	bar.Parent = panel
	tabBar = bar

	local row = Instance.new("ScrollingFrame")
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Position = UDim2.fromScale(0.03, 0.38)
	row.Size = UDim2.fromScale(0.94, 0.45)
	row.ScrollingDirection = Enum.ScrollingDirection.X
	row.ScrollBarThickness = 0
	row.Parent = panel
	cardRow = row

	local note = label(panel, "", UDim2.fromScale(0.94, 0.09), UDim2.fromScale(0.03, 0.87))
	note.TextColor3 = CREAM
	noteLabel = note

	Controller.Changed:connect(redraw)
	Controller.Notice:connect(function(text: string)
		if open and noteLabel then
			noteLabel.Text = text
			task.delay(3, function()
				if noteLabel and noteLabel.Text == text then
					noteLabel.Text = LoadoutView.footer(Controller.getState())
				end
			end)
		end
	end)
end

function LoadoutPanel.open()
	build()
	open = true
	if noteLabel then
		noteLabel.Text = ""
	end
	redraw()
	if gui then
		gui.Enabled = true
	end
end

function LoadoutPanel.close()
	open = false
	if gui then
		gui.Enabled = false
	end
end

function LoadoutPanel.toggle()
	if open then
		LoadoutPanel.close()
	else
		LoadoutPanel.open()
	end
end

function LoadoutPanel.isOpen(): boolean
	return open
end

return LoadoutPanel
