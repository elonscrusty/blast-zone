--!strict
-- After a match: one strip under the Big Banner results that shows the coins just earned, the progress bar to the
-- next unlock, and one button (UNLOCK when you can afford the next tier, otherwise TRACK). Also a TRACK button in
-- the lobby. The server pays once per match (ClaimResults); this screen only shows the answer (ProgressState).
-- Sits in the free band under the results column (y 77-96%), above the results screen (DisplayOrder 55 > 50).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoinLooks = require(Shared.Progression.CoinLooks)
local Config = require(Shared.Config)
local MatchPhase = require(Shared.MatchPhase)
local Net = require(script.Parent.Parent.Core.Net)
local CoinView = require(script.Parent.CoinView)
local ProgressClient = require(script.Parent.ProgressClient)
local ProgressText = require(script.Parent.ProgressText)
local TrackPanel = require(script.Parent.TrackPanel)
local Ui = require(script.Parent.ProgressUi)

local ClaimUiSystem = {}
ClaimUiSystem.order = 220

function ClaimUiSystem.start()
	ProgressClient.ensureStarted()
	local coinName = CoinLooks.get(Config.Progression.look).name

	local gui = Instance.new("ScreenGui")
	gui.Name = "CoinClaim"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 55
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- ===== lobby TRACK button (under PLAY and SETTINGS) =====
	local trackSlot, trackButton = Ui.button(gui, gui, "Track", "TRACK", false)
	trackSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	trackSlot.Position = UDim2.fromScale(0.5, 0.88)
	trackSlot.Size = UDim2.fromScale(0.2, 0.11)
	trackSlot.Visible = false
	trackButton.Activated:Connect(TrackPanel.toggle)

	-- ===== results strip =====
	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Position = UDim2.fromScale(0.5, 0.96)
	strip.Size = UDim2.fromScale(0.64, 0.19)
	strip.BackgroundColor3 = Ui.hex(Ui.look.panel)
	strip.Visible = false
	strip.Parent = gui
	Ui.round(strip, 0.2)
	Ui.outline(gui, strip, 1)

	local coinHolder = Instance.new("Frame")
	coinHolder.BackgroundTransparency = 1
	coinHolder.Position = UDim2.fromScale(0.02, 0.08)
	coinHolder.Size = UDim2.fromScale(0.14, 0.84)
	coinHolder.Parent = strip
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = coinHolder
	local coin = CoinView.create(coinHolder, Config.Progression.look)
	coin.Size = UDim2.fromScale(1, 1)

	local amount = Ui.label(strip, "Amount", "", 40)
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.TextColor3 = Ui.hex("#C98400") -- darker gold: readable on cream
	amount.Position = UDim2.fromScale(0.19, 0.04)
	amount.Size = UDim2.fromScale(0.45, 0.4)

	local barBack = Instance.new("Frame")
	barBack.Name = "Bar"
	barBack.Position = UDim2.fromScale(0.19, 0.5)
	barBack.Size = UDim2.fromScale(0.45, 0.14)
	barBack.BackgroundColor3 = Ui.hex(Ui.look.outline)
	barBack.Parent = strip
	Ui.round(barBack, 0.5)
	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.BackgroundColor3 = Ui.hex(Ui.look.info)
	barFill.BorderSizePixel = 0
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.Parent = barBack
	Ui.round(barFill, 0.5)

	local hint = Ui.label(strip, "Hint", "", 24)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Position = UDim2.fromScale(0.19, 0.68)
	hint.Size = UDim2.fromScale(0.45, 0.24)

	local actionSlot, actionButton = Ui.button(gui, strip, "Action", "TRACK", false)
	actionSlot.AnchorPoint = Vector2.new(1, 0.5)
	actionSlot.Position = UDim2.fromScale(0.98, 0.5)
	actionSlot.Size = UDim2.fromScale(0.31, 0.62)

	local note = Ui.label(gui, "Note", "", 20)
	note.AnchorPoint = Vector2.new(0.5, 1)
	note.Position = UDim2.fromScale(0.5, 0.775)
	note.Size = UDim2.fromScale(0.64, 0.04)
	note.TextColor3 = Color3.new(1, 1, 1)
	Ui.outline(gui, note, 0.5)
	note.Visible = false

	-- ===== state =====
	local phase = MatchPhase.Waiting
	local matchId = 0
	local resultsMatch = -1
	local action = "track"
	local nextTierId: string? = nil
	local counted = -1 -- the match whose count-up already ran
	local token = 0

	local function countUp(gained: number)
		token += 1
		local mine = token
		task.spawn(function()
			local t0 = os.clock()
			local duration = 0.9
			while token == mine do
				local k = math.clamp((os.clock() - t0) / duration, 0, 1)
				amount.Text = `+{math.floor(gained * k + 0.5)} {coinName}`
				if k >= 1 then
					return
				end
				task.wait()
			end
		end)
	end

	local function refresh()
		local state = ProgressClient.get()
		trackSlot.Visible = phase == MatchPhase.Waiting
		local inResults = (phase == MatchPhase.Finished or phase == MatchPhase.Results)
			and resultsMatch == matchId
			and state ~= nil
		strip.Visible = inResults
		note.Visible = false
		if not inResults or state == nil then
			return
		end
		local nextTier = ProgressClient.nextTier()
		nextTierId = if nextTier then nextTier.id else nil
		local words = ProgressText.strip(state, coinName, nextTier)
		action = words.action
		hint.Text = words.hint
		barFill.Size = UDim2.fromScale(words.fill, 1)
		actionButton.Text = if words.action == "unlock" then "UNLOCK" else "TRACK"
		actionButton.BackgroundColor3 =
			Ui.hex(if words.action == "unlock" then Ui.look.accent else Ui.look.panel)
		local line = ProgressText.denied(state.denied, coinName) or words.note
		if line ~= nil then
			note.Text = line
			note.Visible = true
		end
		if state.gained and state.gained.matchId == matchId then
			if counted ~= matchId then
				counted = matchId
				countUp(state.gained.amount)
			end
		else
			token += 1
			amount.Text = words.amount
		end
	end

	actionButton.Activated:Connect(function()
		if action == "unlock" and nextTierId ~= nil then
			ProgressClient.unlock(nextTierId)
		else
			TrackPanel.toggle()
		end
	end)

	Net.on("MatchState", function(s: any)
		if s.matchId < matchId then
			return
		end
		matchId = s.matchId
		phase = s.phase
		refresh()
	end)
	Net.on("Results", function(payload: any)
		resultsMatch = payload.matchId
		refresh()
	end)
	ProgressClient.Changed:connect(refresh)
	refresh()
end

return ClaimUiSystem
