--!strict
-- What the player sees around a match: the PLAY button, the countdown, and the results screen.
-- Results look = "Big Banner" (carter's pick C): giant title, three small numbers, one huge Play again button.
-- The server decides everything; these buttons only ask (PlayRequest, ReplayRequest, ReturnToLobbyRequest, ClaimResults).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchPhase = require(Shared.MatchPhase)
local Net = require(script.Parent.Parent.Core.Net)
local ResultsText = require(script.Parent.ResultsText)

local ResultsClientSystem = {}
ResultsClientSystem.order = 210

local player = Players.LocalPlayer
local palette = Config.Palette
local BUTTON_HEIGHT = Config.Settings.minTouchTarget + 16

local TONES: { [string]: { top: Color3, bottom: Color3 } } = {
	win = { top = Color3.fromHex(palette.Cyan), bottom = Color3.fromHex("#1E8FA0") },
	lose = { top = Color3.fromHex(palette.DangerCoral), bottom = Color3.fromHex("#A23A42") },
	draw = { top = Color3.fromHex(palette.Pavement), bottom = Color3.fromHex("#8A6D45") },
}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, name: string, text: string, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = font
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Parent = parent
	return l
end

local function stroke(target: Instance, thickness: number, color: Color3)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
	s.Parent = target
end

local function button(parent: Instance, name: string, text: string, filled: boolean): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 14)
	if filled then
		b.BackgroundColor3 = Color3.fromHex(palette.RewardGold)
		b.TextColor3 = Color3.fromHex(palette.Navy)
	else
		b.BackgroundTransparency = 1
		b.TextColor3 = Color3.new(1, 1, 1)
		stroke(b, 3, Color3.new(1, 1, 1))
	end
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 40
	limit.MinTextSize = 14
	limit.Parent = b
	return b
end

-- A small number with its name above it: KILLS / 3.
local function pill(parent: Instance, order: number, name: string): TextLabel
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.LayoutOrder = order
	frame.Size = UDim2.fromScale(0.3, 1)
	frame.BackgroundColor3 = Color3.fromHex(palette.Navy)
	frame.BackgroundTransparency = 0.2
	frame.Parent = parent
	corner(frame, 12)
	local caption = label(frame, "Caption", string.upper(name), Enum.Font.GothamBold)
	caption.Size = UDim2.fromScale(1, 0.3)
	caption.Position = UDim2.fromScale(0, 0.08)
	caption.TextTransparency = 0.25
	local value = label(frame, "Value", "0", Enum.Font.FredokaOne)
	value.Size = UDim2.fromScale(1, 0.5)
	value.Position = UDim2.fromScale(0, 0.4)
	return value
end

function ResultsClientSystem.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MatchFlow"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ===== PLAY button + countdown (Waiting / Countdown) =====
	local lobby = Instance.new("Frame")
	lobby.Name = "Lobby"
	lobby.Size = UDim2.fromScale(1, 1)
	lobby.BackgroundTransparency = 1
	lobby.Visible = false
	lobby.Parent = gui

	local playButton = button(lobby, "Play", "PLAY", true)
	playButton.AnchorPoint = Vector2.new(0.5, 1)
	playButton.Position = UDim2.new(0.5, 0, 1, -48)
	playButton.Size = UDim2.new(0.4, 0, 0, BUTTON_HEIGHT)
	local playLimit = Instance.new("UISizeConstraint")
	playLimit.MinSize = Vector2.new(180, BUTTON_HEIGHT)
	playLimit.MaxSize = Vector2.new(360, BUTTON_HEIGHT)
	playLimit.Parent = playButton

	local status = label(lobby, "Status", "", Enum.Font.GothamBold)
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.new(0.5, 0, 1, -48 - BUTTON_HEIGHT - 8)
	status.Size = UDim2.new(0.7, 0, 0, 28)
	stroke(status, 2, Color3.fromHex(palette.Navy))

	local countdown = label(gui, "Countdown", "", Enum.Font.FredokaOne)
	countdown.AnchorPoint = Vector2.new(0.5, 0)
	countdown.Position = UDim2.fromScale(0.5, 0.16)
	countdown.Size = UDim2.fromScale(0.5, 0.2)
	countdown.Visible = false
	stroke(countdown, 4, Color3.fromHex(palette.Navy))
	local countdownLimit = Instance.new("UITextSizeConstraint")
	countdownLimit.MaxTextSize = 96
	countdownLimit.Parent = countdown

	-- ===== results (Finished / Results) =====
	local results = Instance.new("Frame")
	results.Name = "Results"
	results.Size = UDim2.fromScale(1, 1)
	results.BorderSizePixel = 0
	results.BackgroundColor3 = Color3.new(1, 1, 1)
	results.Visible = false
	results.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 70
	gradient.Parent = results

	local column = Instance.new("Frame")
	column.Name = "Column"
	column.AnchorPoint = Vector2.new(0.5, 0.5)
	column.Position = UDim2.fromScale(0.5, 0.5)
	column.Size = UDim2.fromScale(0.86, 0.8)
	column.BackgroundTransparency = 1
	column.Parent = results
	local columnLimit = Instance.new("UISizeConstraint")
	columnLimit.MaxSize = Vector2.new(760, 460)
	columnLimit.Parent = column

	local title = label(column, "Title", "", Enum.Font.FredokaOne)
	title.Size = UDim2.fromScale(1, 0.34)
	stroke(title, 6, Color3.fromHex(palette.Navy))

	local sub = label(column, "Sub", "", Enum.Font.GothamBold)
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.fromScale(0.5, 0.37)
	sub.Size = UDim2.fromScale(0.8, 0.1)
	sub.BackgroundTransparency = 0
	sub.BackgroundColor3 = Color3.new(1, 1, 1)
	sub.TextColor3 = Color3.fromHex(palette.Navy)
	corner(sub, 20)

	local pills = Instance.new("Frame")
	pills.Name = "Pills"
	pills.AnchorPoint = Vector2.new(0.5, 0)
	pills.Position = UDim2.fromScale(0.5, 0.51)
	pills.Size = UDim2.fromScale(0.9, 0.2)
	pills.BackgroundTransparency = 1
	pills.Parent = column
	local pillLayout = Instance.new("UIListLayout")
	pillLayout.FillDirection = Enum.FillDirection.Horizontal
	pillLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pillLayout.Padding = UDim.new(0.03, 0)
	pillLayout.Parent = pills
	local killsValue = pill(pills, 1, "Kills")
	local timeValue = pill(pills, 2, "Time")
	local rewardValue = pill(pills, 3, Config.Rewards.currencyName)
	rewardValue.TextColor3 = Color3.fromHex(palette.RewardGold)

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.AnchorPoint = Vector2.new(0.5, 1)
	buttons.Position = UDim2.fromScale(0.5, 1)
	buttons.Size = UDim2.fromScale(1, 0.24)
	buttons.BackgroundTransparency = 1
	buttons.Parent = column
	local replay = button(buttons, "PlayAgain", "PLAY AGAIN", true)
	replay.Size = UDim2.fromScale(0.58, 1)
	replay.Position = UDim2.fromScale(0.05, 0)
	local menu = button(buttons, "Loadout", "LOADOUT", false)
	menu.Size = UDim2.fromScale(0.3, 0.8)
	menu.Position = UDim2.fromScale(0.67, 0.1)

	local closing = label(column, "Closing", "", Enum.Font.GothamBold)
	closing.AnchorPoint = Vector2.new(0.5, 0)
	closing.Position = UDim2.fromScale(0.5, 1.02)
	closing.Size = UDim2.fromScale(0.6, 0.06)
	closing.TextTransparency = 0.2
	stroke(closing, 2, Color3.fromHex(palette.Navy))

	-- ===== state =====
	local phase = MatchPhase.Waiting
	local phaseEndsAt: number? = nil
	local matchId = 0
	local queued = false -- I pressed PLAY / PLAY AGAIN for the next match
	local shownResults: any = nil -- the Results payload of the screen on show
	local dismissed = false

	local function paintResults(payload: any)
		local words = ResultsText.describe(payload)
		local tone = TONES[words.tone]
		gradient.Color = ColorSequence.new(tone.top, tone.bottom)
		title.Text = words.title
		sub.Text = words.sub
		killsValue.Text = tostring(words.kills)
		timeValue.Text = words.time
		rewardValue.Text = `+{words.reward}`
		replay.Text = "PLAY AGAIN"
		queued = false
	end

	local function pop(target: GuiObject)
		local scale = Instance.new("UIScale")
		scale.Scale = 0.6
		scale.Parent = target
		local tween = TweenService:Create(
			scale,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
		tween.Completed:Connect(function()
			scale:Destroy()
		end)
		tween:Play()
	end

	local function refresh()
		local inResults = (phase == MatchPhase.Finished or phase == MatchPhase.Results)
			and shownResults ~= nil
			and shownResults.matchId == matchId
			and not dismissed
		if inResults and not results.Visible then
			pop(title)
		end
		results.Visible = inResults
		lobby.Visible = phase == MatchPhase.Waiting or phase == MatchPhase.Countdown
		countdown.Visible = phase == MatchPhase.Countdown

		if phase == MatchPhase.Waiting or phase == MatchPhase.Countdown then
			playButton.Text = if queued then "READY" else "PLAY"
			playButton.Active = not queued
		end
	end

	local function setStatus(note: string?)
		local text = ""
		if note == "waiting_players" then
			text = if queued then "Waiting for more players..." else ""
		elseif note == "aborted_too_few" then
			text = "Not enough players. Try again!"
		elseif queued and phase == MatchPhase.Waiting then
			text = "Waiting for players..."
		end
		status.Text = text
	end

	Net.on("MatchState", function(state: any)
		if state.matchId < matchId then
			return -- an old message that arrived late
		end
		local previous = phase
		matchId = state.matchId
		phase = state.phase
		phaseEndsAt = state.phaseEndsAt
		if previous ~= phase then
			if phase == MatchPhase.Spawning or phase == MatchPhase.Waiting then
				dismissed = false
			end
			if phase == MatchPhase.Spawning then
				queued = false
			end
		end
		setStatus(state.note)
		refresh()
	end)

	Net.on("Results", function(payload: any)
		shownResults = payload
		dismissed = false
		paintResults(payload)
		refresh()
		-- One combined claim: the server pays once even if this fires again.
		Net.send("ClaimResults", payload.matchId)
	end)

	playButton.Activated:Connect(function()
		if queued then
			return
		end
		queued = true
		Net.send("PlayRequest")
		setStatus(nil)
		refresh()
	end)

	replay.Activated:Connect(function()
		if queued then
			return
		end
		queued = true
		replay.Text = "READY!"
		Net.send("ReplayRequest")
	end)

	menu.Activated:Connect(function()
		queued = false
		dismissed = true
		Net.send("ReturnToLobbyRequest")
		refresh()
	end)

	-- Countdown digits and the "closes in" line follow the server's clock.
	task.spawn(function()
		while true do
			task.wait(0.2)
			local endsAt = phaseEndsAt
			if endsAt then
				local left = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
				if phase == MatchPhase.Countdown then
					countdown.Text = if left > 0 then tostring(left) else "GO!"
				end
				if results.Visible then
					closing.Text = if shownResults and shownResults.endsAt
						then `Next match in {math.max(
							0,
							math.ceil(shownResults.endsAt - workspace:GetServerTimeNow())
						)}s`
						else ""
				end
			end
		end
	end)

	refresh()
end

return ResultsClientSystem
