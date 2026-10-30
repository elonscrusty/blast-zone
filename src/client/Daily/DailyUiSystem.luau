--!strict
-- The daily challenge board (piece 25). The server counts and pays; this screen only shows DailyState and asks
-- (DailyRequest). Look from Config.Daily.look (DailyLooks): A Sticker Stack / B Ticket Row open from a DAILY
-- button in the lobby; C Big Board is always open on the left of the lobby. A top strip says when one paid.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DailyLooks = require(Shared.Daily.DailyLooks)
local DailyText = require(Shared.Daily.DailyText)
local MatchPhase = require(Shared.MatchPhase)
local Types = require(Shared.Types)
local Net = require(script.Parent.Parent.Core.Net)
local Ui = require(script.Parent.Parent.Progression.ProgressUi)
local DailyIcon = require(script.Parent.DailyIcon)

local DailyUiSystem = {}
DailyUiSystem.order = 225

type Card = {
	frame: Frame,
	iconHolder: Frame,
	icon: ViewportFrame?,
	kind: string,
	line: TextLabel,
	count: TextLabel,
	fill: Frame,
	reward: TextLabel,
}

function DailyUiSystem.start()
	local look = DailyLooks.get(Config.Daily.look)
	local coinName = Config.Rewards.currencyName
	local board = look.layout == "board"
	local dark = board

	local gui = Instance.new("ScreenGui")
	gui.Name = "Daily"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 56
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local ink = Ui.hex(if dark then "#FFFFFF" else Ui.look.ink)

	-- ===== lobby DAILY button (A and B only) =====
	local openSlot, openButton = Ui.button(gui, gui, "DailyOpen", "DAILY", false)
	openSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	openSlot.Position = UDim2.fromScale(0.26, 0.88)
	openSlot.Size = UDim2.fromScale(0.2, 0.11)
	openSlot.Visible = false
	local dot = Instance.new("Frame")
	dot.Name = "NewDot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.96, 0.08)
	dot.Size = UDim2.fromScale(0.16, 0.16)
	dot.SizeConstraint = Enum.SizeConstraint.RelativeYY
	dot.BackgroundColor3 = Ui.hex(Ui.look.accent)
	dot.Visible = false
	dot.ZIndex = 5
	dot.Parent = openSlot
	Ui.round(dot, 0.5)
	Ui.outline(gui, dot, 0.6)

	-- ===== the panel =====
	local panel = Instance.new("Frame")
	panel.Name = "Board"
	panel.BackgroundColor3 = Ui.hex(if dark then look.cardColor else Ui.look.panel)
	panel.Visible = false
	panel.Parent = gui
	if board then
		panel.AnchorPoint = Vector2.new(0, 0.5)
		panel.Position = UDim2.fromScale(0.02, 0.55)
		panel.Size = UDim2.fromScale(0.27, 0.6)
		panel.BackgroundTransparency = 0.08
	elseif look.layout == "row" then
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.fromScale(0.5, 0.5)
		panel.Size = UDim2.fromScale(0.78, 0.62)
	else
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.fromScale(0.5, 0.5)
		panel.Size = UDim2.fromScale(0.6, 0.7)
	end
	Ui.round(panel, 0.06)
	Ui.outline(gui, panel, 1)

	local title = Ui.label(panel, "Title", "DAILY", 44)
	title.TextColor3 = ink
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromScale(0.05, 0.03)
	title.Size = UDim2.fromScale(0.45, 0.12)

	local timer = Ui.label(panel, "Timer", "", 24)
	timer.TextColor3 = Ui.hex(if dark then "#B8C4E0" else Ui.look.dim)
	timer.TextXAlignment = if board then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
	timer.Position = if board then UDim2.fromScale(0.05, 0.14) else UDim2.fromScale(0.45, 0.05)
	timer.Size = if board then UDim2.fromScale(0.9, 0.06) else UDim2.fromScale(0.36, 0.08)

	local closeSlot, closeButton = Ui.button(gui, panel, "Close", "X", false)
	closeSlot.AnchorPoint = Vector2.new(1, 0)
	closeSlot.Position = UDim2.fromScale(0.97, 0.03)
	closeSlot.Size = UDim2.fromScale(0.12, 0.12)
	closeSlot.SizeConstraint = Enum.SizeConstraint.RelativeYY
	closeSlot.Visible = not board

	local status = Ui.label(panel, "Status", "", 22)
	status.TextColor3 = Ui.hex(Ui.look.danger)
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.fromScale(0.5, 0.99)
	status.Size = UDim2.fromScale(0.9, 0.06)

	-- ===== cards =====
	local cards: { Card } = {}
	local top = if board then 0.22 else 0.18
	local bottom = 0.92
	for i = 1, 3 do
		local f = Instance.new("Frame")
		f.Name = "Card" .. i
		f.BackgroundColor3 = Ui.hex(if dark then "#2B3A67" else look.cardColor)
		if look.layout == "row" then
			local w = 0.9 / 3
			f.Position = UDim2.fromScale(0.05 + (i - 1) * w, top)
			f.Size = UDim2.fromScale(w - 0.02, bottom - top)
		else
			local h = (bottom - top) / 3
			f.Position = UDim2.fromScale(0.05, top + (i - 1) * h)
			f.Size = UDim2.fromScale(0.9, h - 0.02)
		end
		f.Parent = panel
		Ui.round(f, 0.12)
		Ui.outline(gui, f, 0.7)

		local tall = look.layout == "row"
		local iconHolder = Instance.new("Frame")
		iconHolder.Name = "IconHolder"
		iconHolder.BackgroundTransparency = 1
		iconHolder.Position = if tall
			then UDim2.fromScale(0.2, 0.04)
			else UDim2.fromScale(0.02, 0.08)
		iconHolder.Size = if tall then UDim2.fromScale(0.6, 0.36) else UDim2.fromScale(0.2, 0.84)
		iconHolder.Parent = f
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = iconHolder

		local line = Ui.label(f, "Line", "", 30)
		line.TextColor3 = ink
		line.TextXAlignment = if tall then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
		line.Position = if tall then UDim2.fromScale(0.06, 0.42) else UDim2.fromScale(0.25, 0.08)
		line.Size = if tall then UDim2.fromScale(0.88, 0.2) else UDim2.fromScale(0.5, 0.4)
		line.TextWrapped = true

		local barBack = Instance.new("Frame")
		barBack.Name = "Bar"
		barBack.BackgroundColor3 = Ui.hex(Ui.look.outline)
		barBack.Position = if tall then UDim2.fromScale(0.1, 0.66) else UDim2.fromScale(0.25, 0.56)
		barBack.Size = if tall then UDim2.fromScale(0.8, 0.07) else UDim2.fromScale(0.5, 0.16)
		barBack.Parent = f
		Ui.round(barBack, 0.5)
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = barBack
		Ui.round(fill, 0.5)

		local count = Ui.label(f, "Count", "", 22)
		count.TextColor3 = ink
		count.TextXAlignment = if tall then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
		count.Position = if tall then UDim2.fromScale(0.1, 0.74) else UDim2.fromScale(0.25, 0.74)
		count.Size = if tall then UDim2.fromScale(0.8, 0.08) else UDim2.fromScale(0.5, 0.2)

		local reward = Ui.label(f, "Reward", "", 30)
		reward.TextColor3 = Ui.hex(if dark then Ui.look.accent else "#C98400")
		reward.Position = if tall then UDim2.fromScale(0.05, 0.84) else UDim2.fromScale(0.77, 0.2)
		reward.Size = if tall then UDim2.fromScale(0.9, 0.12) else UDim2.fromScale(0.21, 0.6)

		table.insert(cards, {
			frame = f,
			iconHolder = iconHolder,
			icon = nil,
			kind = "",
			line = line,
			count = count,
			fill = fill,
			reward = reward,
		})
	end

	-- ===== "done!" strip at the top (any time) =====
	local toast = Ui.label(gui, "DailyToast", "", 36)
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.fromScale(0.5, 0.02)
	toast.Size = UDim2.fromScale(0.5, 0.08)
	toast.BackgroundTransparency = 0
	toast.BackgroundColor3 = Ui.hex(look.doneColor)
	toast.Visible = false
	Ui.round(toast, 0.3)
	Ui.outline(gui, toast, 0.8)

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

	local function drawCards()
		local current = state
		if current == nil then
			return
		end
		for i, card in cards do
			local c = current.challenges[i]
			card.frame.Visible = c ~= nil
			if c ~= nil then
				if card.kind ~= c.kind then
					card.kind = c.kind
					if card.icon then
						card.icon:Destroy()
					end
					local icon = DailyIcon.create(card.iconHolder, c.kind)
					icon.Size = UDim2.fromScale(1, 1)
					card.icon = icon
				end
				card.line.Text = DailyText.line(c.kind, c.goal)
				card.count.Text = DailyText.progress(c.progress, c.goal)
				card.fill.Size =
					UDim2.fromScale(math.clamp(c.progress / math.max(1, c.goal), 0, 1), 1)
				card.fill.BackgroundColor3 = Ui.hex(
					if c.paid then look.doneColor else look.tierColors[c.tier] or Ui.look.info
				)
				card.reward.Text = if c.paid then "DONE" else `+{c.reward}`
				card.reward.TextColor3 = Ui.hex(
					if c.paid then look.doneColor elseif dark then Ui.look.accent else "#C98400"
				)
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

	local function refresh()
		local inLobby = phase == MatchPhase.Waiting
		openSlot.Visible = inLobby and not board
		if not inLobby then
			open = false
		end
		panel.Visible = inLobby and (board or open) and state ~= nil
		if panel.Visible then
			dot.Visible = false
		end
		drawCards()
	end

	openButton.Activated:Connect(function()
		open = not open
		if open then
			Net.send("DailyRequest")
		end
		refresh()
	end)
	closeButton.Activated:Connect(function()
		open = false
		refresh()
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
			if not panel.Visible then
				dot.Visible = true
			end
		end
		refresh()
	end)

	Net.on("MatchState", function(m: any)
		if m.matchId < matchId then
			return
		end
		matchId = m.matchId
		phase = m.phase
		refresh()
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
	refresh()
end

return DailyUiSystem
