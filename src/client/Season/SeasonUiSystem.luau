--!strict
-- The season pass screen (video 3 gap 20). PLACEHOLDER LOOK: built only from Ui/Components, so the real look
-- comes from the UI system (Claude Design swaps the skin). The server adds XP and pays; this screen only shows
-- SeasonState and asks (SeasonRequest, SeasonClaimRequest).
--   * PASS button in the lobby slot "season" (LobbyMenu), opens a full panel (Components.modal + ModalGate).
--   * The panel: tier, time left, bar, TAKE ALL, and one row per tier with a free cell and a paid cell.
--   * A short strip (UiLayers.Toast) says what was taken. A dot on the button says something is ready.
--   * The paid cell says SOON while Config.Season.forSale is false (nothing sells it yet).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchPhase = require(Shared.MatchPhase)
local SeasonDefs = require(Shared.Season.SeasonDefs)
local SeasonText = require(Shared.Season.SeasonText)
local Types = require(Shared.Types)
local Net = require(script.Parent.Parent.Core.Net)
local Components = require(script.Parent.Parent.Ui.Components)
local LobbyMenu = require(script.Parent.Parent.Ui.LobbyMenu)
local Tokens = require(script.Parent.Parent.Ui.Tokens)

local SeasonUiSystem = {}
SeasonUiSystem.order = 235

local MODAL = "season"
local ROW_HEIGHT = 56 -- px; big enough for a thumb

type Cell = { reward: TextLabel, button: TextButton, ready: boolean }
type Row = { free: Cell, paid: Cell }

local function color(role: string): Color3
	return Color3.fromHex(Tokens.color(role))
end

function SeasonUiSystem.start()
	local coinName = Config.Rewards.currencyName
	local draw: () -> () = function() end -- set below; closing the panel brings the ready dot back
	local modal = Components.modal(MODAL, "PASS", function()
		draw()
	end)
	local root = modal.root
	modal.panel.Size = UDim2.fromScale(0.84, 0.96)
	modal.body.Position = UDim2.fromScale(0.5, 0.17)
	modal.body.Size = UDim2.fromScale(0.94, 0.62)
	local body = modal.body

	-- ===== header =====
	local tierText = Components.text(body, root, "Tier", "title", {
		align = Enum.TextXAlignment.Left,
		size = UDim2.fromScale(0.3, 0.09),
	})
	local statusText = Components.text(body, root, "Status", "caption", {
		color = "danger",
		size = UDim2.fromScale(0.36, 0.09),
		position = UDim2.fromScale(0.32, 0),
	})
	local timerText = Components.text(body, root, "Timer", "caption", {
		align = Enum.TextXAlignment.Right,
		size = UDim2.fromScale(0.3, 0.09),
		position = UDim2.fromScale(0.7, 0),
	})
	local track, setBar = Components.bar(body, "Progress", "info")
	track.Position = UDim2.fromScale(0, 0.11)
	track.Size = UDim2.fromScale(0.82, 0.045)
	local barText = Components.text(body, root, "BarText", "caption", {
		align = Enum.TextXAlignment.Left,
		size = UDim2.fromScale(0.16, 0.075),
		position = UDim2.fromScale(0.84, 0.095),
	})
	Components.text(body, root, "FreeHead", "caption", {
		text = "FREE",
		size = UDim2.fromScale(0.43, 0.06),
		position = UDim2.fromScale(0.09, 0.18),
	})
	Components.text(body, root, "PassHead", "caption", {
		text = "PASS",
		size = UDim2.fromScale(0.43, 0.06),
		position = UDim2.fromScale(0.54, 0.18),
	})

	-- ===== TAKE ALL (bottom left, beside DONE) =====
	local takeAll = Components.button(modal.panel, root, "TakeAll", {
		text = "TAKE ALL",
		style = "primary",
		onPress = function()
			Net.send("SeasonClaimRequest", 0, "free")
		end,
	})
	takeAll.AnchorPoint = Vector2.new(0, 1)
	takeAll.Position = UDim2.fromScale(0.04, 0.95)
	takeAll.Size = UDim2.fromScale(0.28, 0.14)
	takeAll.Visible = false

	-- ===== the tiers =====
	local list = Instance.new("ScrollingFrame")
	list.Name = "Tiers"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromScale(0, 0.25)
	list.Size = UDim2.fromScale(1, 0.75)
	list.CanvasSize = UDim2.fromScale(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local rows: { Row } = {}
	local function makeCell(parent: Frame, x: number, tier: number, rowName: string): Cell
		local cell, _ = Components.panel(parent, root, rowName, "panelAlt")
		cell.Position = UDim2.fromScale(x, 0)
		cell.Size = UDim2.fromScale(0.43, 1)
		local reward = Components.text(cell, root, "Reward", "body", {
			size = UDim2.fromScale(0.5, 0.8),
			position = UDim2.fromScale(0.04, 0.1),
		})
		local record = { reward = reward, ready = false } :: any
		local b = Components.button(cell, root, "Take", {
			text = "",
			style = "secondary",
			onPress = function()
				if record.ready then
					Net.send("SeasonClaimRequest", tier, rowName)
				end
			end,
		})
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.fromScale(0.97, 0.5)
		b.Size = UDim2.fromScale(0.42, 0.8)
		record.button = b
		return record :: Cell
	end

	for n = 1, SeasonDefs.count() do
		local f = Instance.new("Frame")
		f.Name = "Tier" .. n
		f.BackgroundTransparency = 1
		f.LayoutOrder = n
		f.Size = UDim2.new(1, -10, 0, ROW_HEIGHT)
		f.Parent = list
		Components.text(f, root, "Number", "title", {
			text = tostring(n),
			size = UDim2.fromScale(0.08, 0.8),
			position = UDim2.fromScale(0, 0.1),
		})
		rows[n] = {
			free = makeCell(f, 0.09, n, "free"),
			paid = makeCell(f, 0.54, n, "paid"),
		}
	end

	-- ===== lobby button and dot =====
	local openButton = Components.button(LobbyMenu.slot("season"), root, "Season", {
		text = "PASS",
		style = "primary",
		onPress = function()
			if modal.isOpen() then
				modal.close()
			else
				modal.open()
				Net.send("SeasonRequest")
				draw()
			end
		end,
	})
	openButton.Size = UDim2.fromScale(1, 1)
	local dot = Instance.new("Frame")
	dot.Name = "ReadyDot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(1, 0)
	dot.Size = UDim2.fromScale(0.3, 0.3)
	dot.SizeConstraint = Enum.SizeConstraint.RelativeYY
	dot.BackgroundColor3 = color("good")
	dot.Visible = false
	dot.Parent = openButton

	-- ===== "taken" strip =====
	local toastGui, toastRoot = Components.screen("SeasonToast", "Toast")
	local strip = Components.panel(toastRoot, toastRoot, "Strip", "good")
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.Position = UDim2.fromScale(0.5, 0.02)
	strip.Size = UDim2.fromScale(0.5, 0.1)
	strip.Active = false
	strip.Visible = false
	local stripText = Components.text(strip, toastRoot, "Text", "title", { color = "inkOnAccent" })

	-- ===== state =====
	local state: Types.SeasonState? = nil
	local endsAt = 0 -- os.clock() when the season turns
	local asked = false
	local toastToken = 0
	local matchId = 0

	local function showToast(text: string)
		toastToken += 1
		local mine = toastToken
		stripText.Text = text
		strip.Visible = true
		task.delay(3, function()
			if toastToken == mine then
				strip.Visible = false
			end
		end)
	end

	local function rewardText(r: Types.SeasonRewardView): string
		return SeasonText.reward(r.kind, r.amount, r.name, coinName)
	end

	local function drawCell(cell: Cell, reward: Types.SeasonRewardView, cellState: string)
		cell.reward.Text = rewardText(reward)
		cell.reward.TextColor3 = color(if reward.kind == "scrap" then "coin" else "ink")
		cell.ready = cellState == "ready"
		local words: { [string]: string } = {
			locked = "LOCKED",
			ready = "TAKE",
			claimed = "DONE",
			needPass = if Config.Season.forSale then "GET PASS" else "SOON",
		}
		cell.button.Text = words[cellState] or ""
		Components.restyle(
			cell.button,
			if cellState == "ready"
				then "primary"
				elseif cellState == "claimed" then "quiet"
				else "secondary"
		)
	end

	local function anyReady(current: Types.SeasonState): boolean
		for _, t in current.tiers do
			if t.freeState == "ready" or t.paidState == "ready" then
				return true
			end
		end
		return false
	end

	draw = function()
		local current = state
		if current == nil then
			return
		end
		tierText.Text = SeasonText.tier(current.tier, current.maxTier)
		barText.Text = SeasonText.xp(current.intoTier, current.forNext)
		setBar(
			if current.forNext == nil then 1 else current.intoTier / math.max(1, current.forNext)
		)
		for n, view in current.tiers do
			local row = rows[n]
			if row ~= nil then
				drawCell(row.free, view.free, view.freeState)
				drawCell(row.paid, view.paid, view.paidState)
			end
		end
		local ready = anyReady(current)
		takeAll.Visible = ready
		dot.Visible = ready and not modal.isOpen()
		local words: { [string]: string } = {
			temporary = "Test mode: not saved",
			loading = "Loading...",
			failed = "Progress not loaded",
			lost = "Progress not loaded",
		}
		statusText.Text = words[current.status] or ""
	end

	Net.on("SeasonState", function(incoming: Types.SeasonState)
		state = incoming
		endsAt = os.clock() + incoming.secondsLeft
		asked = false
		local taken = incoming.justClaimed
		if taken ~= nil and #taken > 0 then
			if #taken == 1 then
				showToast(`TAKEN! {rewardText(taken[1].reward)}`)
			else
				showToast(`TAKEN! {#taken} rewards`)
			end
		elseif incoming.denied ~= nil then
			showToast(SeasonText.denied(incoming.denied))
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

	-- The timer, and a fresh pass when the season turns (asks once, then waits for the answer).
	task.spawn(function()
		while toastGui.Parent ~= nil do
			if state ~= nil then
				local left = endsAt - os.clock()
				timerText.Text = SeasonText.timer(left)
				if left <= 0 and not asked then
					asked = true
					Net.send("SeasonRequest")
				end
			end
			task.wait(1)
		end
	end)

	Net.send("SeasonRequest")
end

return SeasonUiSystem
