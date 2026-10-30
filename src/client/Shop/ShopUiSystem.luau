--!strict
-- The Scrap Shop screen (video 3 gap 18). PLACEHOLDER LOOK: built only from Ui/Components (colour roles), so the
-- Claude Design skin restyles it; keep the data flow, swap the drawing. The server decides everything: this screen
-- only shows ShopState + ProgressState and asks (BuyRequest, EquipRequest).
--   * SHOP button in the lobby slot "shop" (LobbyMenu) with a "new" dot until today's shop was opened.
--   * A full panel (Components.modal on UiLayers.Modal): six looks, each BUY / WEAR / WORN, your Scrap, a timer.
--   * A short strip (UiLayers.Toast) says what you just bought.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchPhase = require(Shared.MatchPhase)
local ShopDefs = require(Shared.Shop.ShopDefs)
local ShopText = require(Shared.Shop.ShopText)
local Types = require(Shared.Types)
local Net = require(script.Parent.Parent.Core.Net)
local ProgressClient = require(script.Parent.Parent.Progression.ProgressClient)
local Components = require(script.Parent.Parent.Ui.Components)
local LobbyMenu = require(script.Parent.Parent.Ui.LobbyMenu)
local Tokens = require(script.Parent.Parent.Ui.Tokens)

local ShopUiSystem = {}
ShopUiSystem.order = 226

local COLUMNS = 3
local GAP = 0.02 -- between cards, as a share of the body
local RARITY_ROLE: { [string]: string } = { common = "ink", rare = "info", epic = "accent" }

type Card = {
	panel: Frame,
	swatch: Frame,
	name: TextLabel,
	rarity: TextLabel,
	button: TextButton,
	itemId: string?,
}

local function color(role: string): Color3
	return Color3.fromHex(Tokens.color(role))
end

function ShopUiSystem.start()
	local coinName = Config.Rewards.currencyName
	local cardCount = #ShopDefs.always() + #Config.Shop.dailySlots
	local rows = math.ceil(cardCount / COLUMNS)

	local modal = Components.modal("Shop", "SHOP")
	local root, panel, body = modal.root, modal.panel, modal.body
	panel.Size = UDim2.fromScale(0.8, 0.9)
	body.Size = UDim2.fromScale(0.94, 0.6)
	body.Position = UDim2.fromScale(0.5, 0.17)

	-- The title shares its row with your Scrap (left) and the timer (right).
	local title = panel:FindFirstChild("Title") :: TextLabel?
	if title ~= nil then
		title.Size = UDim2.fromScale(0.34, 0.12)
		title.Position = UDim2.fromScale(0.5, 0.03)
	end
	local wallet = Components.text(panel, root, "Wallet", "body", {
		color = "coin",
		align = Enum.TextXAlignment.Left,
		size = UDim2.fromScale(0.3, 0.1),
		position = UDim2.fromScale(0.04, 0.04),
	})
	local timer = Components.text(panel, root, "Timer", "caption", {
		align = Enum.TextXAlignment.Right,
		size = UDim2.fromScale(0.3, 0.08),
		position = UDim2.fromScale(0.66, 0.05),
	})
	local status = Components.text(panel, root, "Status", "caption", {
		color = "danger",
		size = UDim2.fromScale(0.9, 0.06),
		position = UDim2.fromScale(0.5, 0.79),
		anchor = Vector2.new(0.5, 0),
	})

	-- ===== cards =====
	local cards: { Card } = {}
	local cellW = (1 - GAP * (COLUMNS - 1)) / COLUMNS
	local cellH = (1 - GAP * (rows - 1)) / rows
	for i = 1, cardCount do
		local col, row = (i - 1) % COLUMNS, (i - 1) // COLUMNS
		local cardPanel = Components.panel(body, root, "Card" .. i, "panelAlt")
		cardPanel.Position = UDim2.fromScale(col * (cellW + GAP), row * (cellH + GAP))
		cardPanel.Size = UDim2.fromScale(cellW, cellH)

		local swatch = Instance.new("Frame")
		swatch.Name = "Swatch"
		swatch.BorderSizePixel = 0
		swatch.Position = UDim2.fromScale(0.04, 0.06)
		swatch.Size = UDim2.fromScale(0.2, 0.34)
		swatch.Parent = cardPanel

		local nameLabel = Components.text(cardPanel, root, "Name", "body", {
			align = Enum.TextXAlignment.Left,
			size = UDim2.fromScale(0.68, 0.22),
			position = UDim2.fromScale(0.28, 0.05),
		})
		local rarity = Components.text(cardPanel, root, "Rarity", "caption", {
			align = Enum.TextXAlignment.Left,
			size = UDim2.fromScale(0.68, 0.16),
			position = UDim2.fromScale(0.28, 0.27),
		})

		local card: Card = {
			panel = cardPanel,
			swatch = swatch,
			name = nameLabel,
			rarity = rarity,
			button = nil :: any,
			itemId = nil,
		}
		local button = Components.button(cardPanel, root, "Buy", {
			text = "",
			style = "primary",
			onPress = function()
				local id = card.itemId
				if id == nil then
					return
				end
				if ProgressClient.owns(id) then
					ProgressClient.equip(id)
				else
					Net.send("BuyRequest", id)
				end
			end,
		})
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.Position = UDim2.fromScale(0.5, 0.95)
		button.Size = UDim2.fromScale(0.92, 0.46)
		card.button = button
		table.insert(cards, card)
	end

	-- ===== lobby button =====
	local setOpen: (boolean) -> () = function() end -- replaced below, once the screen state exists
	local open = Components.button(LobbyMenu.slot("shop"), root, "Shop", {
		text = "SHOP",
		style = "secondary",
		onPress = function()
			setOpen(not modal.isOpen())
		end,
	})
	open.Size = UDim2.fromScale(1, 1)
	local dot = Instance.new("Frame")
	dot.Name = "NewDot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(1, 0)
	dot.Size = UDim2.fromScale(0.3, 0.3)
	dot.SizeConstraint = Enum.SizeConstraint.RelativeYY
	dot.BackgroundColor3 = color("danger")
	dot.Visible = false
	dot.ZIndex = 5
	dot.Parent = open

	-- ===== "bought" strip =====
	local toastGui, toastRoot = Components.screen("ShopToast", "Toast")
	local strip = Components.panel(toastRoot, toastRoot, "Strip", "good")
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.Position = UDim2.fromScale(0.5, 0.03)
	strip.Size = UDim2.fromScale(0.5, 0.1)
	strip.Active = false
	strip.Visible = false
	local stripText = Components.text(strip, toastRoot, "Text", "title", {
		color = "inkOnAccent",
		size = UDim2.fromScale(0.9, 0.8),
		position = UDim2.fromScale(0.05, 0.1),
	})

	-- ===== state =====
	local matchId = 0
	local state: Types.ShopState? = nil
	local endsAt = 0 -- os.clock() when the shop changes
	local asked = false
	local toastToken = 0
	local lastBoughtShown: string? = nil
	local note = "" -- why the last buy was refused; cleared by the next answer

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

	local function draw()
		local current = state
		if current == nil then
			return
		end
		local progress = ProgressClient.get()
		local coins = if progress then progress.coins else 0
		wallet.Text = `{coins} {coinName}`
		for i, card in cards do
			local o = current.offers[i]
			card.panel.Visible = o ~= nil
			card.itemId = if o then o.id else nil
			if o ~= nil then
				local owned = ProgressClient.owns(o.id)
				local worn = progress ~= nil and progress.equipped[o.slot] == o.id
				card.swatch.BackgroundColor3 = Color3.fromHex(o.color)
				card.name.Text = o.name
				card.rarity.Text = string.upper(o.rarity)
					.. (if o.slot == "trail" then " TRAIL" else " SHOT")
				card.rarity.TextColor3 = color(RARITY_ROLE[o.rarity] or "ink")
				card.button.Text = ShopText.button(owned, worn, o.price, coins)
				Components.restyle(
					card.button,
					if worn then "quiet" elseif owned then "secondary" else "primary"
				)
			end
		end
		status.Text = if note ~= "" then note else ShopText.denied(current.status)
		timer.Text = ShopText.timer(endsAt - os.clock())
	end

	setOpen = function(value: boolean)
		if modal.isOpen() == value then
			return
		end
		if value then
			modal.open()
			dot.Visible = false
			ProgressClient.ensureStarted()
			Net.send("ShopSeenRequest")
			draw()
		else
			modal.close()
		end
	end

	Net.on("ShopState", function(incoming: Types.ShopState)
		state = incoming
		endsAt = os.clock() + incoming.secondsLeft
		asked = false
		note = ShopText.denied(incoming.denied)
		local bought = incoming.bought
		if bought ~= nil and bought ~= lastBoughtShown then
			lastBoughtShown = bought
			for _, o in incoming.offers do
				if o.id == bought then
					showToast(`NEW LOOK! {o.name}`)
				end
			end
		end
		dot.Visible = incoming.isNew and not modal.isOpen()
		draw()
	end)

	ProgressClient.ensureStarted()
	ProgressClient.Changed:connect(function()
		if modal.isOpen() then
			draw()
		end
	end)

	Net.on("MatchState", function(m: any)
		if m.matchId < matchId then
			return
		end
		matchId = m.matchId
		if m.phase ~= MatchPhase.Waiting then
			setOpen(false)
		end
	end)

	-- The timer, and a fresh shop when the day turns (asks once, then waits for the answer).
	task.spawn(function()
		while toastGui.Parent ~= nil do
			if state ~= nil then
				local left = endsAt - os.clock()
				timer.Text = ShopText.timer(left)
				if left <= 0 and not asked then
					asked = true
					Net.send("ShopRequest")
				end
			end
			task.wait(1)
		end
	end)

	Net.send("ShopRequest")
end

return ShopUiSystem
