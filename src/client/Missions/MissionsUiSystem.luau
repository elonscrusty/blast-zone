--!strict
-- Weekly missions, awards and login days (piece 48). PLACEHOLDER LAYOUT: built from Ui/Components with colour
-- roles only, so the skin from Claude Design restyles it. The server counts and pays; this screen only shows
-- MissionsState and asks (MissionsRequest, MissionClaim).
--   * MISSIONS button in the lobby slot "missions" (LobbyMenu) with a dot when something can be claimed.
--   * One modal (Components.modal, one panel at a time) with three tabs: WEEK (3 missions + a bonus), AWARDS, LOGIN.
--   * A short strip (UiLayers.Toast) says what was claimed: "CLAIMED! +90 Scrap".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchPhase = require(Shared.MatchPhase)
local MissionRules = require(Shared.Missions.MissionRules)
local MissionText = require(Shared.Missions.MissionText)
local Types = require(Shared.Types)
local Net = require(script.Parent.Parent.Core.Net)
local UiKit = require(script.Parent.Parent.Hud.UiKit)
local Components = require(script.Parent.Parent.Ui.Components)
local LobbyMenu = require(script.Parent.Parent.Ui.LobbyMenu)
local Tokens = require(script.Parent.Parent.Ui.Tokens)

local MissionsUiSystem = {}
MissionsUiSystem.order = 227

local ROW_SHARE = 0.2 -- a row is this share of the screen height (the claim button inside is 70% of it)

type Tab = "week" | "awards" | "login"
type Row = {
	frame: Frame,
	line: TextLabel,
	count: TextLabel,
	setBar: (number) -> (),
	button: TextButton,
	what: string,
	id: string?,
}

local function color(role: string): Color3
	return Color3.fromHex(Tokens.color(role))
end

function MissionsUiSystem.start()
	local coinName = Config.Rewards.currencyName

	local modal = Components.modal("Missions", "MISSIONS")
	local root = modal.root
	modal.panel.Size = UDim2.fromScale(0.7, 0.92)
	local body = modal.body
	body.Position = UDim2.fromScale(0.5, 0.17)
	body.Size = UDim2.fromScale(0.94, 0.62)

	-- ===== lobby button =====
	local openButton = Components.button(LobbyMenu.slot("missions"), root, "Missions", {
		text = "MISSIONS",
		style = "secondary",
		onPress = function()
			if modal.isOpen() then
				modal.close()
			else
				modal.open()
			end
		end,
	})
	openButton.Size = UDim2.fromScale(1, 1)
	local dot = Instance.new("Frame")
	dot.Name = "NewDot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(1, 0)
	dot.Size = UDim2.fromScale(0.3, 0.3)
	dot.SizeConstraint = Enum.SizeConstraint.RelativeYY
	dot.BackgroundColor3 = color("good")
	dot.BorderSizePixel = 0
	dot.Visible = false
	dot.Parent = openButton
	UiKit.round(dot, 0.5)

	-- ===== tabs =====
	local tab: Tab = "week"
	local tabButtons: { [Tab]: TextButton } = {}
	local tabNames: { Tab } = { "week", "awards", "login" }
	local tabText: { [Tab]: string } = { week = "WEEK", awards = "AWARDS", login = "LOGIN" }
	local draw: () -> () = function() end
	for i, name in tabNames do
		local b = Components.button(body, root, "Tab_" .. name, {
			text = tabText[name],
			style = "secondary",
			onPress = function()
				tab = name
				draw()
			end,
		})
		b.Position = UDim2.fromScale((i - 1) / 3, 0)
		b.Size = UDim2.fromScale(0.32, 0.2)
		tabButtons[name] = b
	end

	local timer = Components.text(modal.panel, root, "Timer", "caption", {
		color = "dim",
		align = Enum.TextXAlignment.Right,
		size = UDim2.fromScale(0.3, 0.06),
		position = UDim2.fromScale(0.96, 0.03),
		anchor = Vector2.new(1, 0),
	})
	local status = Components.text(modal.panel, root, "Status", "caption", {
		color = "danger",
		size = UDim2.fromScale(0.5, 0.05),
		position = UDim2.fromScale(0.04, 0.97),
		anchor = Vector2.new(0, 1),
	})

	-- ===== WEEK and AWARDS: one scrolling list of rows =====
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromScale(0, 0.24)
	list.Size = UDim2.fromScale(1, 0.76)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local rows: { Row } = {}
	local function rowHeight(): number
		return math.floor(root.AbsoluteSize.Y * ROW_SHARE + 0.5)
	end
	local function makeRow(): Row
		local f = Instance.new("Frame")
		f.Name = "Row"
		f.BackgroundColor3 = color("panelAlt")
		f.BorderSizePixel = 0
		f.Size = UDim2.new(1, -10, 0, rowHeight())
		f.Parent = list
		UiKit.round(f, 0.15)

		local line = Components.text(f, root, "Line", "body", {
			align = Enum.TextXAlignment.Left,
			size = UDim2.fromScale(0.62, 0.45),
			position = UDim2.fromScale(0.03, 0.08),
		})
		local track, setBar = Components.bar(f, "Bar", "good")
		track.Position = UDim2.fromScale(0.03, 0.66)
		track.Size = UDim2.fromScale(0.42, 0.16)
		local count = Components.text(f, root, "Count", "caption", {
			align = Enum.TextXAlignment.Left,
			size = UDim2.fromScale(0.14, 0.34),
			position = UDim2.fromScale(0.48, 0.58),
		})

		local row: Row = {
			frame = f,
			line = line,
			count = count,
			setBar = setBar,
			button = nil :: any,
			what = "",
			id = nil,
		}
		row.button = Components.button(f, root, "Claim", {
			text = "",
			style = "quiet",
			onPress = function()
				if row.what ~= "" and row.button.Active then
					row.button.Active = false -- one tap per answer; the next MissionsState turns it back on
					Net.send("MissionClaim", row.what, row.id)
				end
			end,
		})
		row.button.AnchorPoint = Vector2.new(1, 0.5)
		row.button.Position = UDim2.fromScale(0.985, 0.46)
		row.button.Size = UDim2.fromScale(0.32, 0.7)
		return row
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		for _, row in rows do
			row.frame.Size = UDim2.new(1, -10, 0, rowHeight())
		end
	end)

	-- ===== LOGIN tab =====
	local loginFrame = Instance.new("Frame")
	loginFrame.Name = "Login"
	loginFrame.BackgroundTransparency = 1
	loginFrame.Position = UDim2.fromScale(0, 0.24)
	loginFrame.Size = UDim2.fromScale(1, 0.76)
	loginFrame.Visible = false
	loginFrame.Parent = body

	local DAY_CELLS = #Config.Missions.loginRewards
	local cells: { { frame: Frame, day: TextLabel, reward: TextLabel } } = {}
	for i = 1, DAY_CELLS do
		local f = Instance.new("Frame")
		f.Name = "Day" .. i
		f.BackgroundColor3 = color("panelAlt")
		f.BorderSizePixel = 0
		f.Size = UDim2.fromScale(1 / DAY_CELLS - 0.012, 0.5)
		f.Position = UDim2.fromScale((i - 1) / DAY_CELLS, 0)
		f.Parent = loginFrame
		UiKit.round(f, 0.15)
		local day = Components.text(f, root, "Day", "caption", {
			size = UDim2.fromScale(1, 0.35),
			position = UDim2.fromScale(0, 0.08),
		})
		local reward = Components.text(f, root, "Reward", "body", {
			color = "coin",
			size = UDim2.fromScale(1, 0.4),
			position = UDim2.fromScale(0, 0.5),
		})
		table.insert(cells, { frame = f, day = day, reward = reward })
	end
	local loginButton = Components.button(loginFrame, root, "LoginClaim", {
		text = "CLAIM",
		style = "primary",
		onPress = function()
			if modal.isOpen() then
				Net.send("MissionClaim", "login")
			end
		end,
	})
	loginButton.AnchorPoint = Vector2.new(0.5, 0)
	loginButton.Position = UDim2.fromScale(0.5, 0.58)
	loginButton.Size = UDim2.fromScale(0.5, 0.3)
	local loginTimer = Components.text(loginFrame, root, "LoginTimer", "caption", {
		color = "dim",
		size = UDim2.fromScale(0.6, 0.1),
		position = UDim2.fromScale(0.5, 0.92),
		anchor = Vector2.new(0.5, 0),
	})

	-- ===== "claimed" strip =====
	local toastGui, toastRoot = Components.screen("MissionsToast", "Toast")
	toastGui.Name = "MissionsToast"
	local toast = Components.text(toastRoot, toastRoot, "Strip", "title", {
		color = "inkOnAccent",
		size = UDim2.fromScale(0.5, 0.1),
		position = UDim2.fromScale(0.5, 0.02),
		anchor = Vector2.new(0.5, 0),
	})
	toast.BackgroundTransparency = 0
	toast.BackgroundColor3 = color("good")
	toast.Visible = false

	-- ===== state =====
	local matchId = 0
	local state: Types.MissionsState? = nil
	local weekEndsAt = 0 -- os.clock() when the week turns
	local loginEndsAt = 0 -- os.clock() when the login day turns
	local asked = false
	local toastToken = 0

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

	-- Ready first, then still going, then already claimed. Keeps the list order otherwise.
	local function ordered(source: { Types.MissionRow }): { Types.MissionRow }
		local out: { Types.MissionRow } = {}
		for _, wanted in { "ready", "open", "claimed" } do
			for _, row in source do
				local kind = if row.ready then "ready" elseif row.claimed then "claimed" else "open"
				if kind == wanted then
					table.insert(out, row)
				end
			end
		end
		return out
	end

	local function setRow(row: Row, what: string, id: string?, data: Types.MissionRow)
		row.frame.Visible = true
		row.what = what
		row.id = id
		row.line.Text = if what == "bonus"
			then `Claim all {data.goal} missions`
			else MissionText.goal(data.kind, data.goal)
		row.count.Text = MissionText.progress(data.progress, data.goal)
		row.setBar(data.progress / math.max(1, data.goal))
		row.button.Active = data.ready
		row.button.Text = if data.claimed
			then "DONE"
			elseif data.ready then "CLAIM " .. MissionText.reward(data.reward, coinName)
			else MissionText.reward(data.reward, coinName)
		Components.restyle(row.button, if data.ready then "primary" else "quiet")
	end

	draw = function()
		local current = state
		if current == nil then
			return
		end
		list.Visible = tab ~= "login"
		loginFrame.Visible = tab == "login"
		for name, b in tabButtons do
			Components.restyle(b, if name == tab then "primary" else "secondary")
		end
		timer.Text = if tab == "week" then MissionText.weekTimer(weekEndsAt - os.clock()) else ""

		local shown: { { what: string, id: string?, data: Types.MissionRow } } = {}
		if tab == "week" then
			for _, m in current.weekly do
				table.insert(shown, { what = "week", id = m.id, data = m })
			end
			local b = current.bonus
			table.insert(shown, {
				what = "bonus",
				id = nil,
				data = {
					id = "bonus",
					kind = "bonus",
					goal = b.need,
					progress = b.have,
					reward = b.reward,
					claimed = b.claimed,
					ready = b.ready,
				},
			})
		elseif tab == "awards" then
			for _, a in ordered(current.awards) do
				table.insert(shown, { what = "award", id = a.id, data = a })
			end
		end
		while #rows < #shown do
			table.insert(rows, makeRow())
		end
		for i, row in rows do
			local item = shown[i]
			if item == nil then
				row.frame.Visible = false
				row.what = ""
			else
				row.frame.LayoutOrder = i
				setRow(row, item.what, item.id, item.data)
			end
		end

		if tab == "login" then
			local login = current.login
			for i, cell in cells do
				local isNext = i == login.next and login.canClaim
				cell.day.Text = MissionText.day(i)
				cell.reward.Text = tostring(login.rewards[i] or "")
				cell.frame.BackgroundColor3 = if isNext
					then color("accent")
					elseif i < login.next then color("good")
					else color("panelAlt")
				cell.day.TextColor3 = if isNext then color("inkOnAccent") else color("ink")
				cell.reward.TextColor3 = if isNext then color("inkOnAccent") else color("coin")
			end
			loginButton.Active = login.canClaim
			loginButton.Text = if login.canClaim then "CLAIM" else "DONE TODAY"
			Components.restyle(loginButton, if login.canClaim then "primary" else "quiet")
			loginTimer.Text = if login.canClaim
				then ""
				else MissionText.loginTimer(loginEndsAt - os.clock())
		end

		local words: { [string]: string } = {
			temporary = "Test mode: not saved",
			loading = "Loading...",
			failed = "Progress not loaded",
			lost = "Progress not loaded",
		}
		status.Text = words[current.status] or ""
		dot.Visible = not modal.isOpen() and MissionRules.readyCount(current) > 0
	end

	-- A fresh board every time the panel opens or closes.
	modal.gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if modal.gui.Enabled then
			Net.send("MissionsRequest")
		end
		draw()
	end)

	Net.on("MissionsState", function(incoming: Types.MissionsState)
		state = incoming
		weekEndsAt = os.clock() + incoming.weekSecondsLeft
		loginEndsAt = os.clock() + incoming.login.secondsLeft
		asked = false
		local just = incoming.justClaimed
		if just ~= nil then
			showToast(MissionText.claimed(just, incoming.justAmount or 0, coinName))
		end
		draw()
	end)

	Net.on("MatchState", function(m: any)
		if m.matchId < matchId then
			return
		end
		matchId = m.matchId
		if m.phase ~= MatchPhase.Waiting then
			modal.close()
		end
	end)

	-- The timers, and a fresh board when the login day or the week turns (asks once, then waits for the answer).
	task.spawn(function()
		while toastGui.Parent ~= nil do
			if state ~= nil then
				if modal.isOpen() then
					draw()
				end
				if
					not asked and (loginEndsAt - os.clock() <= 0 or weekEndsAt - os.clock() <= 0)
				then
					asked = true
					Net.send("MissionsRequest")
				end
			end
			task.wait(1)
		end
	end)

	Net.send("MissionsRequest")
end

return MissionsUiSystem
