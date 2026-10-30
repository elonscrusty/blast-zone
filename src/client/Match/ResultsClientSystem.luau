--!strict
-- What the player sees around a match: PLAY button, countdown, phase banners, kill feed, the ELIMINATED banner,
-- and the results screen. Results look = "Big Banner" (carter's pick C): giant title, three small numbers, one
-- huge Play again button. Colors and fonts come from piece 10's Hud/Theme when it is there (Street Sticker look).
-- The server decides everything; the buttons only ask (PlayRequest, ReplayRequest, ReturnToLobbyRequest, ClaimResults).
-- Kept clear of the upgrade card band (x 26-74%, y 76-96%): nothing here sits in it while a match is live.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local MatchPhase = require(Shared.MatchPhase)
local Net = require(script.Parent.Parent.Core.Net)
local ResultsText = require(script.Parent.ResultsText)

local ResultsClientSystem = {}
ResultsClientSystem.order = 210

local player = Players.LocalPlayer
local localId = Ids.player(player.UserId)

-- ===== look =====
type Look = {
	panel: string,
	ink: string,
	outline: string,
	accent: string,
	danger: string,
	info: string,
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
	local p = Config.Palette
	return {
		panel = "#FFF4D6",
		ink = p.Navy,
		outline = p.Navy,
		accent = p.RewardGold,
		danger = p.DangerCoral,
		info = p.Cyan,
		strokeScale = 0.0085,
		shadowOffset = 0.011,
	}
end

local look = loadLook()
local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local TONES: { [string]: { top: Color3, bottom: Color3 } } = {
	win = { top = hex(Config.Palette.Cyan), bottom = hex("#1E8FA0") },
	lose = { top = hex(Config.Palette.DangerCoral), bottom = hex("#A23A42") },
	draw = { top = hex(Config.Palette.Pavement), bottom = hex("#8A6D45") },
}

local FONT = Enum.Font.FredokaOne
local MIN_TOUCH = Config.Settings.minTouchTarget

local gui: ScreenGui

local function round(obj: Instance, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = obj
end

-- Outline that follows the screen height, like the HUD's.
local function outline(obj: Instance, factor: number, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Color = color or hex(look.outline)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = obj
	local function apply()
		s.Thickness = math.max(2, math.floor(gui.AbsoluteSize.Y * look.strokeScale * factor + 0.5))
	end
	apply()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
end

local function text(parent: Instance, name: string, str: string, maxSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Text = str
	l.Font = FONT
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Active = false
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = maxSize
	cap.MinTextSize = 8
	cap.Parent = l
	l.Parent = parent
	return l
end

-- A tappable sticker: a slot that holds a hard shadow and the button on top of it.
local function sticker(
	parent: Instance,
	name: string,
	label: string,
	filled: boolean
): (Frame, TextButton)
	local slot = Instance.new("Frame")
	slot.Name = name .. "Slot"
	slot.BackgroundTransparency = 1
	slot.Parent = parent
	local minSize = Instance.new("UISizeConstraint")
	minSize.MinSize = Vector2.new(MIN_TOUCH * 2, MIN_TOUCH)
	minSize.Parent = slot

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = hex(look.outline)
	shadow.BorderSizePixel = 0
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Parent = slot
	round(shadow, 0.3)
	local function sync()
		local px = math.max(2, math.floor(gui.AbsoluteSize.Y * look.shadowOffset + 0.5))
		shadow.Position = UDim2.fromOffset(0, px)
	end
	sync()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync)

	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromScale(1, 1)
	b.Text = label
	b.Font = FONT
	b.TextScaled = true
	b.AutoButtonColor = true
	b.BackgroundColor3 = if filled then hex(look.accent) else hex(look.panel)
	b.TextColor3 = hex(look.ink)
	b.Parent = slot
	round(b, 0.3)
	outline(b, 1)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.18, 0)
	pad.PaddingBottom = UDim.new(0.18, 0)
	pad.Parent = b
	return slot, b
end

local function pop(target: GuiObject)
	local existing = target:FindFirstChild("PopScale")
	local s: UIScale = if existing and existing:IsA("UIScale")
		then existing
		else Instance.new("UIScale")
	s.Name = "PopScale"
	s.Scale = 0.6
	s.Parent = target
	TweenService
		:Create(
			s,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
		:Play()
end

-- A cream sticker with a caption over a value: KILLS / 3.
local function pill(parent: Instance, order: number, caption: string): TextLabel
	local frame = Instance.new("Frame")
	frame.Name = caption
	frame.LayoutOrder = order
	frame.Size = UDim2.fromScale(0.3, 1)
	frame.BackgroundColor3 = hex(look.panel)
	frame.Parent = parent
	round(frame, 0.2)
	outline(frame, 0.8)
	local c = text(frame, "Caption", string.upper(caption), 18)
	c.TextColor3 = hex(look.ink)
	c.TextTransparency = 0.25
	c.Size = UDim2.fromScale(0.9, 0.28)
	c.Position = UDim2.fromScale(0.05, 0.08)
	local v = text(frame, "Value", "0", 44)
	v.TextColor3 = hex(look.ink)
	v.Size = UDim2.fromScale(0.9, 0.52)
	v.Position = UDim2.fromScale(0.05, 0.38)
	return v
end

function ResultsClientSystem.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "MatchFlow"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ===== lobby: PLAY, settings, status =====
	local lobby = Instance.new("Frame")
	lobby.Name = "Lobby"
	lobby.Size = UDim2.fromScale(1, 1)
	lobby.BackgroundTransparency = 1
	lobby.Visible = false
	lobby.Parent = gui

	local playSlot, playButton = sticker(lobby, "Play", "PLAY", true)
	playSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	playSlot.Position = UDim2.fromScale(0.5, 0.6)
	playSlot.Size = UDim2.fromScale(0.3, 0.17)

	local settingsSlot, settingsButton = sticker(lobby, "Settings", "SETTINGS", false)
	settingsSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	settingsSlot.Position = UDim2.fromScale(0.5, 0.74)
	settingsSlot.Size = UDim2.fromScale(0.2, 0.11)
	settingsButton.Activated:Connect(function()
		local folder = script.Parent.Parent:FindFirstChild("Settings")
		local module = if folder then folder:FindFirstChild("SettingsPanel") else nil
		if module and module:IsA("ModuleScript") then
			local ok, panel = pcall(require, module)
			if ok and panel.toggle then
				panel.toggle()
			end
		end
	end)

	local status = text(lobby, "Status", "", 26)
	status.AnchorPoint = Vector2.new(0.5, 0.5)
	status.Position = UDim2.fromScale(0.5, 0.47)
	status.Size = UDim2.fromScale(0.7, 0.07)
	outline(status, 0.6)

	local countdown = text(gui, "Countdown", "", 120)
	countdown.AnchorPoint = Vector2.new(0.5, 0.5)
	countdown.Position = UDim2.fromScale(0.5, 0.32)
	countdown.Size = UDim2.fromScale(0.4, 0.26)
	countdown.Visible = false
	outline(countdown, 1.6)

	-- ===== banners, kill feed, ELIMINATED =====
	local banner = text(gui, "Banner", "", 72)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.3)
	banner.Size = UDim2.fromScale(0.6, 0.16)
	banner.Visible = false
	outline(banner, 1.4)
	local bannerToken = 0

	local feed = Instance.new("Frame")
	feed.Name = "KillFeed"
	feed.AnchorPoint = Vector2.new(0.5, 0)
	feed.Position = UDim2.fromScale(0.5, 0.22)
	feed.Size = UDim2.fromScale(0.5, 0.15)
	feed.BackgroundTransparency = 1
	feed.Parent = gui
	local feedLayout = Instance.new("UIListLayout")
	feedLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	feedLayout.Padding = UDim.new(0.02, 0)
	feedLayout.Parent = feed

	local defeat = Instance.new("Frame")
	defeat.Name = "Defeat"
	defeat.AnchorPoint = Vector2.new(0.5, 0.5)
	defeat.Position = UDim2.fromScale(0.5, 0.4)
	defeat.Size = UDim2.fromScale(0.5, 0.32)
	defeat.BackgroundColor3 = hex(look.danger)
	defeat.Visible = false
	defeat.Parent = gui
	round(defeat, 0.15)
	outline(defeat, 1.2)
	local defeatTitle = text(defeat, "Title", "ELIMINATED", 64)
	defeatTitle.Size = UDim2.fromScale(0.9, 0.44)
	defeatTitle.Position = UDim2.fromScale(0.05, 0.06)
	local defeatLine = text(defeat, "Line", "", 30)
	defeatLine.Size = UDim2.fromScale(0.9, 0.2)
	defeatLine.Position = UDim2.fromScale(0.05, 0.52)
	local defeatHits = text(defeat, "Hits", "", 26)
	defeatHits.Size = UDim2.fromScale(0.9, 0.18)
	defeatHits.Position = UDim2.fromScale(0.05, 0.76)
	defeatHits.TextTransparency = 0.1
	local defeatToken = 0
	local pendingHits = "" -- DefeatSummary can land just before or after Eliminated

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

	-- The column ends above y 74%, so it never touches the upgrade card band.
	local column = Instance.new("Frame")
	column.Name = "Column"
	column.AnchorPoint = Vector2.new(0.5, 0)
	column.Position = UDim2.fromScale(0.5, 0.06)
	column.Size = UDim2.fromScale(0.86, 0.68)
	column.BackgroundTransparency = 1
	column.Parent = results
	local columnLimit = Instance.new("UISizeConstraint")
	columnLimit.MaxSize = Vector2.new(760, 420)
	columnLimit.Parent = column

	local title = text(column, "Title", "", 120)
	title.Size = UDim2.fromScale(1, 0.34)
	outline(title, 1.8)

	local subSlot = Instance.new("Frame")
	subSlot.Name = "SubPill"
	subSlot.AnchorPoint = Vector2.new(0.5, 0)
	subSlot.Position = UDim2.fromScale(0.5, 0.37)
	subSlot.Size = UDim2.fromScale(0.8, 0.11)
	subSlot.BackgroundColor3 = hex(look.panel)
	subSlot.Parent = column
	round(subSlot, 0.5)
	outline(subSlot, 0.8)
	local sub = text(subSlot, "Sub", "", 30)
	sub.TextColor3 = hex(look.ink)
	sub.Size = UDim2.fromScale(0.92, 0.7)
	sub.Position = UDim2.fromScale(0.04, 0.15)

	local pills = Instance.new("Frame")
	pills.Name = "Pills"
	pills.AnchorPoint = Vector2.new(0.5, 0)
	pills.Position = UDim2.fromScale(0.5, 0.52)
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

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.AnchorPoint = Vector2.new(0.5, 1)
	buttons.Position = UDim2.fromScale(0.5, 0.97)
	buttons.Size = UDim2.fromScale(1, 0.22)
	buttons.BackgroundTransparency = 1
	buttons.Parent = column
	local replaySlot, replay = sticker(buttons, "PlayAgain", "PLAY AGAIN", true)
	replaySlot.Size = UDim2.fromScale(0.58, 1)
	replaySlot.Position = UDim2.fromScale(0.05, 0)
	local menuSlot, menu = sticker(buttons, "Loadout", "LOADOUT", false)
	menuSlot.Size = UDim2.fromScale(0.3, 0.8)
	menuSlot.Position = UDim2.fromScale(0.67, 0.1)

	local closing = text(results, "Closing", "", 22)
	closing.AnchorPoint = Vector2.new(0.5, 0)
	closing.Position = UDim2.fromScale(0.5, 0.01)
	closing.Size = UDim2.fromScale(0.5, 0.05)
	closing.TextTransparency = 0.15
	outline(closing, 0.6)

	-- ===== state =====
	local phase = MatchPhase.Waiting
	local phaseEndsAt: number? = nil
	local matchId = 0
	local queued = false -- I pressed PLAY / PLAY AGAIN for the next match
	local shownResults: any = nil
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

	local function refresh()
		local inResults = (phase == MatchPhase.Finished or phase == MatchPhase.Results)
			and shownResults ~= nil
			and shownResults.matchId == matchId
			and not dismissed
		if inResults and not results.Visible then
			pop(title)
		end
		results.Visible = inResults
		local inLobby = phase == MatchPhase.Waiting or phase == MatchPhase.Countdown
		lobby.Visible = inLobby
		countdown.Visible = phase == MatchPhase.Countdown
		if inLobby then
			playButton.Text = if queued then "READY" else "PLAY"
			settingsSlot.Visible = phase == MatchPhase.Waiting
		end
		if phase ~= MatchPhase.Active and phase ~= MatchPhase.FinalPressure then
			defeat.Visible = false
		end
	end

	local function setStatus(note: string?)
		local words = ""
		if note == "aborted_too_few" then
			words = "Not enough players. Try again!"
		elseif queued and phase == MatchPhase.Waiting then
			words = "Waiting for players..."
		end
		status.Text = words
		status.Visible = words ~= ""
	end

	local function showBanner(words: string)
		bannerToken += 1
		local mine = bannerToken
		banner.Text = words
		banner.Visible = true
		pop(banner)
		task.delay(1.6, function()
			if bannerToken == mine then
				banner.Visible = false
			end
		end)
	end

	local function addFeed(words: string)
		-- At most three lines; each fades after a few seconds.
		for _, child in feed:GetChildren() do
			if child:IsA("TextLabel") and #feed:GetChildren() > 3 then
				child:Destroy()
				break
			end
		end
		local line = text(feed, "Line", words, 26)
		line.Size = UDim2.fromScale(1, 0.3)
		outline(line, 0.6)
		task.delay(4, function()
			if line.Parent then
				line:Destroy()
			end
		end)
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
				pendingHits = ""
			end
		end
		setStatus(state.note)
		refresh()
	end)

	Net.on("Announce", function(payload: any)
		if payload.kind == "kill" then
			addFeed(payload.text)
		else
			showBanner(payload.text)
		end
	end)

	Net.on("Eliminated", function(payload: any)
		local line = ResultsText.defeatLine(payload, localId)
		if line == nil then
			return
		end
		defeatLine.Text = line
		defeatHits.Text = pendingHits
		defeat.Visible = true
		pop(defeat)
		defeatToken += 1
		local mine = defeatToken
		task.delay(3.5, function()
			if defeatToken == mine then
				defeat.Visible = false
				pendingHits = ""
			end
		end)
	end)

	-- Piece 03 sends who hit you and for how much. Its remote only exists once piece 03 is in, so ask carefully.
	pcall(function()
		Net.on("DefeatSummary", function(summary: any)
			pendingHits = ResultsText.hitsLine(summary) or ""
			if defeat.Visible then
				defeatHits.Text = pendingHits
			end
		end)
	end)

	Net.on("Results", function(payload: any)
		shownResults = payload
		dismissed = false
		defeat.Visible = false
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

	-- Countdown digits and the "next match" line follow the server's clock.
	task.spawn(function()
		while true do
			task.wait(0.2)
			local now = workspace:GetServerTimeNow()
			local endsAt = phaseEndsAt
			if endsAt and phase == MatchPhase.Countdown then
				local left = math.max(0, math.ceil(endsAt - now))
				countdown.Text = if left > 0 then tostring(left) else "GO!"
			end
			if results.Visible and shownResults and shownResults.endsAt then
				closing.Text = `Next match in {math.max(0, math.ceil(shownResults.endsAt - now))}s`
			end
		end
	end)

	refresh()
end

return ResultsClientSystem
