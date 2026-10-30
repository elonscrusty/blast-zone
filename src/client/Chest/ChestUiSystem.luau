--!strict
-- The chest screen (gap 19). LOGIC ONLY: it is built from Ui/Components and colour roles from Ui/Tokens, so the real
-- look comes from the UI system (Claude Design thread) without touching this file. The server earns, rolls and
-- pays; this screen only shows ChestState and asks (ChestRequest, ChestOpenRequest).
--   * CHESTS button in the lobby slot "chests" (LobbyMenu), with a dot while a chest is waiting.
--   * Panel (Components.modal): the chests you own, the odds of the chosen one BEFORE you open it, OPEN.
--   * Reveal: the chest shakes, bursts, prizes come out, "TAP TO CONTINUE". The timing is ChestReveal (pure).
--   * A short strip (UiLayers.Toast) says when a chest was earned: "NEW CHEST! Street Chest".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChestDefs = require(Shared.Chest.ChestDefs)
local ChestReveal = require(Shared.Chest.ChestReveal)
local ChestText = require(Shared.Chest.ChestText)
local Config = require(Shared.Config)
local MatchPhase = require(Shared.MatchPhase)
local Types = require(Shared.Types)
local Net = require(script.Parent.Parent.Core.Net)
local Components = require(script.Parent.Parent.Ui.Components)
local LobbyMenu = require(script.Parent.Parent.Ui.LobbyMenu)
local Settings = require(script.Parent.Parent.Settings.Settings)
local Tokens = require(script.Parent.Parent.Ui.Tokens)

local ChestUiSystem = {}
ChestUiSystem.order = 230

-- Which colour role each rarity uses. Claude Design can re-map these.
local RARITY_ROLE: { [string]: string } = { common = "panelAlt", rare = "info", epic = "accent" }

local function color(role: string): Color3
	return Color3.fromHex(Tokens.color(role))
end

function ChestUiSystem.start()
	local coinName = Config.Rewards.currencyName

	-- ===== state =====
	local open = false
	local state: Types.ChestState? = nil
	local selected = ChestDefs.kinds[1]
	local toastToken = 0
	local lastRevealId = -1
	local model: ChestReveal.Model? = nil
	local revealPrizes: { Types.ChestPrize } = {}
	local beat: RBXScriptConnection? = nil
	local matchId = 0
	local draw: () -> () = function() end

	-- ===== the panel =====
	local modal = Components.modal("chests", "CHESTS", function()
		open = false
		if beat ~= nil then
			beat:Disconnect()
			beat = nil
		end
		model = nil
		draw()
	end)
	local root = modal.root
	local body = modal.body

	local meterLine = Components.text(body, root, "Meter", "caption", {
		color = "coin",
		align = Enum.TextXAlignment.Left,
		size = UDim2.fromScale(1, 0.1),
	})

	local kindButtons: { [string]: TextButton } = {}
	for i, kind in ChestDefs.kinds do
		local b = Components.button(body, root, "Kind_" .. kind, {
			text = ChestDefs.chests[kind].name,
			style = "secondary",
			onPress = function()
				selected = kind
				draw()
			end,
		})
		b.Position = UDim2.fromScale(0, 0.14 + (i - 1) * 0.26)
		b.Size = UDim2.fromScale(0.36, 0.22)
		kindButtons[kind] = b
	end

	local oddsTitle = Components.text(body, root, "OddsTitle", "caption", {
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromScale(0.4, 0.14),
		size = UDim2.fromScale(0.6, 0.1),
	})
	local odds = Components.text(body, root, "Odds", "caption", {
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromScale(0.4, 0.25),
		size = UDim2.fromScale(0.6, 0.5),
	})
	odds.TextYAlignment = Enum.TextYAlignment.Top

	local openChest = Components.button(body, root, "Open", {
		text = "OPEN",
		style = "primary",
		onPress = function()
			if model == nil then
				Net.send("ChestOpenRequest", selected)
			end
		end,
	})
	openChest.AnchorPoint = Vector2.new(0.5, 1)
	openChest.Position = UDim2.fromScale(0.7, 1)
	openChest.Size = UDim2.fromScale(0.4, 0.2)

	local status = Components.text(modal.panel, root, "Status", "caption", {
		color = "danger",
		anchor = Vector2.new(0.5, 1),
		position = UDim2.fromScale(0.5, 0.99),
		size = UDim2.fromScale(0.3, 0.05),
	})

	-- ===== lobby button =====
	local openButton = Components.button(LobbyMenu.slot("chests"), root, "Chests", {
		text = "CHESTS",
		style = "secondary",
		onPress = function()
			if open then
				modal.close()
			else
				open = true
				modal.open()
				Net.send("ChestRequest")
				draw()
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
	dot.Visible = false
	dot.Parent = openButton

	-- ===== reveal (above the panel) =====
	local revealGui, revealRoot = Components.screen("ChestReveal", "Modal")
	revealGui.DisplayOrder += 1
	revealGui.Enabled = false
	local revealBack = Instance.new("TextButton") -- a tap anywhere skips, then continues
	revealBack.Name = "Back"
	revealBack.Text = ""
	revealBack.AutoButtonColor = false
	revealBack.Selectable = false
	revealBack.Size = UDim2.fromScale(1, 1)
	revealBack.BackgroundColor3 = color("backdrop")
	revealBack.BackgroundTransparency = Tokens.get(nil).shape.backdropAlpha
	revealBack.BorderSizePixel = 0
	revealBack.Parent = revealRoot

	local chestBox = Components.panel(revealBack, revealRoot, "ChestBox", "panelAlt")
	chestBox.AnchorPoint = Vector2.new(0.5, 0.5)
	chestBox.Size = UDim2.fromScale(0.16, 0.22)
	local chestName = Components.text(chestBox, revealRoot, "Name", "title", {})

	local maxPrizes = 1
	for _, def in ChestDefs.chests do
		maxPrizes = math.max(maxPrizes, def.items)
	end
	local prizeCards: { Frame } = {}
	local prizeLabels: { TextLabel } = {}
	for i = 1, maxPrizes do
		local card = Components.panel(revealBack, revealRoot, "Prize" .. i, "panelAlt")
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Size = UDim2.fromScale(0.16, 0.28)
		card.Visible = false
		prizeCards[i] = card
		prizeLabels[i] = Components.text(card, revealRoot, "Text", "body", {})
	end
	local tapLine = Components.text(revealBack, revealRoot, "Tap", "title", {
		text = "TAP TO CONTINUE",
		anchor = Vector2.new(0.5, 1),
		position = UDim2.fromScale(0.5, 0.95),
		size = UDim2.fromScale(0.5, 0.08),
	})
	tapLine.Visible = false

	-- ===== "new chest" strip =====
	local toastGui, toastRoot = Components.screen("ChestToast", "Toast")
	local toast = Components.text(toastRoot, toastRoot, "Strip", "title", {
		color = "inkOnAccent",
		anchor = Vector2.new(0.5, 0),
		position = UDim2.fromScale(0.5, 0.1),
		size = UDim2.fromScale(0.5, 0.08),
	})
	toast.BackgroundTransparency = 0
	toast.BackgroundColor3 = color("accent")
	toast.Visible = false

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

	local function waiting(): number
		local s = state
		if s == nil then
			return 0
		end
		local n = 0
		for _, c in s.owned do
			n += c
		end
		return n
	end

	draw = function()
		local s = state
		for _, kind in ChestDefs.kinds do
			local b = kindButtons[kind]
			local n = if s ~= nil then s.owned[kind] or 0 else 0
			b.Text = `{ChestDefs.chests[kind].name} x{n}`
			Components.restyle(b, if kind == selected then "primary" else "secondary")
		end
		local chest = ChestDefs.chests[selected]
		oddsTitle.Text = `{chest.name}: {ChestText.contents(selected)}. Odds of each:`
		odds.Text = table.concat(ChestText.oddsLines(selected, coinName), "\n")
		local have = if s ~= nil then s.owned[selected] or 0 else 0
		openChest.Visible = have > 0 and model == nil
		meterLine.Text = if s ~= nil then ChestText.meter(s.meter, s.meterGoal) else ""
		local words: { [string]: string } = {
			temporary = "Test mode: not saved",
			loading = "Loading...",
			failed = "Progress not loaded",
			lost = "Progress not loaded",
		}
		if s ~= nil and s.denied ~= nil then
			status.Text = ChestText.deny(s.denied)
		else
			status.Text = if s ~= nil then words[s.status] or "" else ""
		end
		dot.Visible = not open and waiting() > 0
	end

	-- ===== reveal drawing =====
	local function stopReveal()
		if beat ~= nil then
			beat:Disconnect()
			beat = nil
		end
		model = nil
		revealGui.Enabled = false
		for _, f in prizeCards do
			f.Visible = false
		end
		draw()
	end

	local function drawReveal()
		local m = model
		if m == nil then
			return
		end
		local phaseNow = ChestReveal.phase(m)
		local count = ChestReveal.shown(m)
		if phaseNow == "shaking" then
			chestBox.Position = UDim2.fromScale(0.5 + math.sin(m.elapsed * 40) * 0.01, 0.3)
		else
			chestBox.Position = UDim2.fromScale(0.5, 0.3)
		end
		chestBox.Visible = m.elapsed < m.style.shake + m.style.burst
		local total = #m.order
		for i = 1, #prizeCards do
			local card = prizeCards[i]
			local prizeIndex = m.order[i]
			card.Visible = prizeIndex ~= nil and i <= count
			if prizeIndex ~= nil then
				local p = revealPrizes[prizeIndex]
				card.Position = UDim2.fromScale(0.5 + (i - (total + 1) / 2) * 0.2, 0.62)
				card.BackgroundColor3 = color(RARITY_ROLE[p.rarity] or RARITY_ROLE.common)
				prizeLabels[i].Text = ChestText.prize(p, coinName)
			end
		end
		tapLine.Visible = phaseNow == "done" and m.elapsed >= m.doneAt + ChestReveal.TAP_LOCK
	end

	local function startReveal(reveal: Types.ChestReveal)
		revealPrizes = reveal.prizes
		local styleId = if Settings.flag("reduceFlashes")
			then Config.Chest.reduceMotionStyle
			else Config.Chest.revealStyle
		model = ChestReveal.new(styleId, reveal.prizes :: any)
		chestName.Text = (ChestDefs.get(reveal.kind) or ChestDefs.chests.street).name
		revealGui.Enabled = true
		if beat ~= nil then
			beat:Disconnect()
		end
		beat = RunService.RenderStepped:Connect(function(dt: number)
			local m = model
			if m ~= nil then
				ChestReveal.tick(m, dt)
				drawReveal()
			end
		end)
		drawReveal()
		draw()
	end

	revealBack.Activated:Connect(function()
		local m = model
		if m == nil then
			return
		end
		if ChestReveal.tap(m) == "continue" then
			stopReveal()
		else
			drawReveal()
		end
	end)

	Net.on("ChestState", function(incoming: Types.ChestState)
		state = incoming
		local awarded = incoming.justAwarded
		if awarded ~= nil and #awarded > 0 then
			local first = ChestDefs.get(awarded[1])
			showToast(`NEW CHEST! {if first ~= nil then first.name else ""}`)
		end
		local reveal = incoming.reveal
		if reveal ~= nil and reveal.id ~= lastRevealId then
			lastRevealId = reveal.id
			if open then
				startReveal(reveal)
			end
		end
		draw()
	end)

	Net.on("MatchState", function(m: any)
		if m.matchId < matchId then
			return
		end
		matchId = m.matchId
		if m.phase ~= MatchPhase.Waiting then
			if beat ~= nil then
				stopReveal()
			end
			modal.close()
		end
	end)

	Net.send("ChestRequest")
	draw()
end

return ChestUiSystem
