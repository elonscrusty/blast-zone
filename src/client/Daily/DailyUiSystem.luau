--!strict
-- The daily challenge board (piece 25). Look: Street Sticker+ colours and fonts from Ui/Look. The server counts and pays; this screen
-- only shows DailyState and asks (DailyRequest).
--   * DAILY button in the lobby slot "daily" (LobbyMenu), opens a full panel (UiLayers.Modal + ModalGate).
--   * A short strip (UiLayers.Toast) says when a challenge paid: "DAILY DONE! +35 Scrap".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DailyText = require(Shared.Daily.DailyText)
local MatchPhase = require(Shared.MatchPhase)
local Types = require(Shared.Types)
local Net = require(script.Parent.Parent.Core.Net)
local Look = require(script.Parent.Parent.Ui.Look)
local LobbyMenu = require(script.Parent.Parent.Ui.LobbyMenu)
local ModalGate = require(script.Parent.Parent.Ui.ModalGate)
local UiLayers = require(script.Parent.Parent.Ui.UiLayers)

local DailyUiSystem = {}
DailyUiSystem.order = 225

local MODAL = "daily"
local INK = Look.color("ink")
local PANEL = Look.color("panel")
local PANEL_ALT = Look.color("panelAlt")
local GREEN = Look.color("good")
local BAR = Look.color("info")

-- Street Sticker+: round corners and a thick navy outline.
local function sticker(obj: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius or 0.14, 0)
	corner.Parent = obj
	local stroke = Instance.new("UIStroke")
	stroke.Color = Look.color("outline")
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = obj
end

type Card = { frame: Frame, line: TextLabel, count: TextLabel, fill: Frame, reward: TextLabel }

local function label(parent: Instance, name: string, maxSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.TextColor3 = INK
	l.Font = Look.font("body")
	l.TextScaled = true
	l.Text = ""
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = maxSize
	cap.Parent = l
	l.Parent = parent
	return l
end

local function screen(name: string, layer: string): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = UiLayers.get(layer)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function DailyUiSystem.start()
	local coinName = Config.Rewards.currencyName

	-- ===== lobby button =====
	local openButton = Instance.new("TextButton")
	openButton.Name = "Daily"
	openButton.Size = UDim2.fromScale(1, 1)
	openButton.Text = "DAILY"
	openButton.Font = Look.font("body")
	openButton.TextScaled = true
	openButton.TextColor3 = INK
	openButton.BackgroundColor3 = PANEL
	openButton.Parent = LobbyMenu.slot("daily")
	sticker(openButton, 0.3)
	local dot = Instance.new("Frame")
	dot.Name = "NewDot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(1, 0)
	dot.Size = UDim2.fromScale(0.3, 0.3)
	dot.SizeConstraint = Enum.SizeConstraint.RelativeYY
	dot.BackgroundColor3 = GREEN
	dot.Visible = false
	dot.Parent = openButton

	-- ===== panel =====
	local gui = screen("Daily", "Modal")
	local dim = Instance.new("TextButton") -- tap outside to close
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Look.color("backdrop")
	dim.BackgroundTransparency = 0.4
	dim.Visible = false
	dim.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Board"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.6, 0.75)
	panel.BackgroundColor3 = PANEL
	panel.Visible = false
	panel.Parent = gui
	sticker(panel, 0.06)

	local title = label(panel, "Title", 40)
	title.Text = "DAILY"
	title.Font = Look.font("display")
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromScale(0.04, 0.02)
	title.Size = UDim2.fromScale(0.4, 0.12)

	local timer = label(panel, "Timer", 22)
	timer.TextXAlignment = Enum.TextXAlignment.Right
	timer.Position = UDim2.fromScale(0.4, 0.04)
	timer.Size = UDim2.fromScale(0.38, 0.08)

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = "X"
	close.Font = Look.font("display")
	close.TextScaled = true
	close.TextColor3 = Look.color("inkOnAccent")
	close.BackgroundColor3 = Look.color("danger")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(0.98, 0.02)
	close.Size = UDim2.fromScale(0.14, 0.14)
	close.SizeConstraint = Enum.SizeConstraint.RelativeYY
	close.Parent = panel
	sticker(close, 0.3)
	local minSize = Instance.new("UISizeConstraint")
	minSize.MinSize = Vector2.new(Config.Settings.minTouchTarget, Config.Settings.minTouchTarget)
	minSize.Parent = close

	local status = label(panel, "Status", 20)
	status.TextColor3 = Look.color("inkSoft")
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.fromScale(0.5, 0.99)
	status.Size = UDim2.fromScale(0.9, 0.06)

	local cards: { Card } = {}
	for i = 1, 3 do
		local f = Instance.new("Frame")
		f.Name = "Card" .. i
		f.BackgroundColor3 = PANEL_ALT
		f.Position = UDim2.fromScale(0.04, 0.18 + (i - 1) * 0.25)
		f.Size = UDim2.fromScale(0.92, 0.22)
		f.Parent = panel
		sticker(f, 0.12)

		local line = label(f, "Line", 28)
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.Position = UDim2.fromScale(0.04, 0.08)
		line.Size = UDim2.fromScale(0.66, 0.42)

		local back = Instance.new("Frame")
		back.Name = "Bar"
		back.BackgroundColor3 = Look.color("dim")
		back.Position = UDim2.fromScale(0.04, 0.6)
		back.Size = UDim2.fromScale(0.5, 0.14)
		back.Parent = f
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BorderSizePixel = 0
		fill.BackgroundColor3 = BAR
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = back

		local count = label(f, "Count", 20)
		count.TextXAlignment = Enum.TextXAlignment.Left
		count.Position = UDim2.fromScale(0.56, 0.52)
		count.Size = UDim2.fromScale(0.14, 0.3)

		local reward = label(f, "Reward", 28)
		reward.TextColor3 = INK
		reward.Font = Look.font("display")
		reward.Position = UDim2.fromScale(0.72, 0.15)
		reward.Size = UDim2.fromScale(0.26, 0.7)

		table.insert(cards, { frame = f, line = line, count = count, fill = fill, reward = reward })
	end

	-- ===== "done" strip =====
	local toastGui = screen("DailyToast", "Toast")
	local toast = label(toastGui, "Strip", 32)
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.fromScale(0.5, 0.02)
	toast.Size = UDim2.fromScale(0.5, 0.08)
	toast.BackgroundTransparency = 0
	toast.BackgroundColor3 = GREEN
	toast.TextColor3 = Look.color("inkOnAccent")
	toast.Font = Look.font("display")
	sticker(toast, 0.3)
	toast.Visible = false

	-- ===== state =====
	local phase = MatchPhase.Waiting
	local matchId = 0
	local open = false
	local state: Types.DailyState? = nil
	local endsAt = 0 -- os.clock() when the day turns
	local asked = false
	local toastToken = 0
	local lastPaidShown: string? = nil

	local function showToast(text: string)
		toastToken += 1
		local mine = toastToken
		toast.Text = text
		toast.Visible = true
		task.delay(3, function()
			if toastToken == mine then
				toast.Visible = false
			end
		end)
	end

	local function draw()
		local current = state
		if current == nil then
			return
		end
		for i, card in cards do
			local c = current.challenges[i]
			card.frame.Visible = c ~= nil
			if c ~= nil then
				card.line.Text = DailyText.line(c.kind, c.goal)
				card.count.Text = DailyText.progress(c.progress, c.goal)
				card.fill.Size =
					UDim2.fromScale(math.clamp(c.progress / math.max(1, c.goal), 0, 1), 1)
				card.fill.BackgroundColor3 = if c.paid then GREEN else BAR
				card.reward.Text = if c.paid then "DONE" else `+{c.reward} {coinName}`
				card.reward.TextColor3 = INK
			end
		end
		local words: { [string]: string } = {
			temporary = "Test mode: not saved",
			loading = "Loading...",
			failed = "Progress not loaded",
			lost = "Progress not loaded",
		}
		status.Text = words[current.status] or ""
	end

	local function setOpen(value: boolean)
		if open == value then
			return
		end
		open = value
		if value then
			ModalGate.opened(MODAL, function()
				setOpen(false)
			end)
			dot.Visible = false
			Net.send("DailyRequest")
		else
			ModalGate.closed(MODAL)
		end
		panel.Visible = value
		dim.Visible = value
		draw()
	end

	openButton.Activated:Connect(function()
		setOpen(not open)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	dim.Activated:Connect(function()
		setOpen(false)
	end)

	Net.on("DailyState", function(incoming: Types.DailyState)
		state = incoming
		endsAt = os.clock() + incoming.secondsLeft
		asked = false
		local paid = incoming.justPaid
		if paid ~= nil and paid ~= lastPaidShown then
			lastPaidShown = paid
			for _, c in incoming.challenges do
				if c.id == paid then
					showToast(`DAILY DONE! +{c.reward} {coinName}`)
				end
			end
			if not open then
				dot.Visible = true
			end
		end
		draw()
	end)

	Net.on("MatchState", function(m: any)
		if m.matchId < matchId then
			return
		end
		matchId = m.matchId
		phase = m.phase
		if phase ~= MatchPhase.Waiting then
			setOpen(false)
		end
	end)

	-- The timer, and a fresh board when the day turns (asks once, then waits for the answer).
	task.spawn(function()
		while gui.Parent ~= nil do
			if state ~= nil then
				local left = endsAt - os.clock()
				timer.Text = DailyText.timer(left)
				if left <= 0 and not asked then
					asked = true
					Net.send("DailyRequest")
				end
			end
			task.wait(1)
		end
	end)

	Net.send("DailyRequest")
end

return DailyUiSystem
