--!strict
-- Helpers panel: your robot friends. Six slots show the bots you own, a coin estimate says what
-- they earn ("about 120 coins a minute"), and two big buttons buy another bot or level them all up.
-- The client only asks (Buy "helper" / Buy "helperUp"); the server checks and sends the new State,
-- then the new bot pops into its slot. Texts come from HelpersModel (unit tested).
--
-- Note: the Buy remote always wants an id string, so these two send an empty one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HelpersModel = require(Shared.Ui.HelpersModel)
local Bridge = require(script.Parent.Parent.Ui.Bridge)
local Components = require(script.Parent.Parent.Ui.Components)
local PanelHost = require(script.Parent.Parent.Ui.PanelHost)
local Theme = require(script.Parent.Parent.Ui.Theme)
local PanelKit = require(script.Parent.Shared.PanelKit)
local StoreBinding = require(script.Parent.Shared.StoreBinding)

local L = {
	botsH = 100,
	botsHTall = 128,
	botsTitleH = 22,
	botsPad = 8,
	actionH = 140,
	icon = 36,
	pad = 8,
	textX = 52,
	buttonH = 44,
	wobble = 5,
}

-- every bot gets its own colour ring
local BOT_COLORS: { Color3 } = {
	Theme.color.lava,
	Theme.color.teal,
	Theme.color.gold,
	Theme.color.sky,
	Theme.color.green,
	Theme.color.red,
}

type BotSlot = {
	root: Frame,
	outline: UIStroke,
	glyph: TextLabel,
	level: TextLabel,
	stopWobble: (() -> ())?,
	filled: boolean,
}

type ActionCard = {
	slot: Frame,
	card: Frame,
	sub: TextLabel,
	line1: TextLabel,
	line2: TextLabel,
	cost: Components.CostButton,
	pips: Components.Pips?,
}

local function circleIcon(card: Frame, glyph: string)
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.BackgroundColor3 = Theme.color.creamDark
	icon.BorderSizePixel = 0
	icon.Position = UDim2.fromOffset(L.pad, L.pad)
	icon.Size = UDim2.fromOffset(L.icon, L.icon)
	icon.Parent = card
	local round = Instance.new("UICorner")
	round.CornerRadius = Theme.radius.full
	round.Parent = icon
	local ring = Instance.new("UIStroke")
	ring.Color = Theme.color.parchmentLine
	ring.Thickness = Theme.size.stroke
	ring.Parent = icon
	Components.Label({ parent = icon, name = "Glyph", text = glyph, textSize = Theme.text.big })
end

local function makeActionCard(
	parent: Instance,
	order: number,
	glyph: string,
	title: string,
	withPips: boolean
): ActionCard
	local slot, card = PanelKit.slot(parent, order)
	circleIcon(card, glyph)
	Components.Label({
		parent = card,
		name = "Title",
		text = title,
		textSize = Theme.text.body,
		font = Theme.font.title,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(L.textX, L.pad - 2),
		size = UDim2.new(1, -(L.textX + L.pad), 0, 22),
	})
	local sub = Components.Label({
		parent = card,
		name = "Sub",
		textSize = Theme.text.small,
		font = Theme.font.bold,
		color = Theme.color.charcoalSoft,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(L.textX, 28),
		size = UDim2.fromOffset(88, 16),
	})
	local pips: Components.Pips? = nil
	if withPips then
		pips = Components.Pips({
			parent = card,
			name = "Pips",
			total = 15,
			filled = 0,
			color = Theme.color.lava,
			position = UDim2.new(0, L.textX + 92, 0, 32),
			size = UDim2.new(1, -(L.textX + 92 + L.pad), 0, 8),
		})
	end
	local line1 = Components.Label({
		parent = card,
		name = "Line1",
		textSize = Theme.text.small,
		font = Theme.font.title,
		color = Theme.color.tealDark,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(L.pad, 50),
		size = UDim2.new(1, -2 * L.pad, 0, 18),
	})
	local line2 = Components.Label({
		parent = card,
		name = "Line2",
		textSize = Theme.text.small,
		font = Theme.font.bold,
		color = Theme.color.redDark,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(L.pad, 68),
		size = UDim2.new(1, -2 * L.pad, 0, 18),
	})
	local cost = Components.CostButton({
		parent = card,
		name = "Buy",
		anchor = Vector2.new(0, 1),
		position = UDim2.new(0, L.pad, 1, -L.pad),
		size = UDim2.new(1, -2 * L.pad, 0, L.buttonH),
		textSize = Theme.text.big,
	})
	return {
		slot = slot,
		card = card,
		sub = sub,
		line1 = line1,
		line2 = line2,
		cost = cost,
		pips = pips,
	}
end

local function build(parent: Frame, ctx: PanelHost.Ctx): () -> ()
	local header = PanelKit.header(parent)
	local list = PanelKit.scroll(parent, PanelKit.HEADER_H + Theme.size.gap)

	-- ===== the six robot slots =====
	local botsSlot, botsCard = PanelKit.slot(list.root, 1)
	botsSlot.Name = "BotsSlot"
	local botsTitle = Components.Label({
		parent = botsCard,
		name = "Title",
		text = "My robot friends",
		textSize = Theme.text.body,
		font = Theme.font.title,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(L.botsPad, 6),
		size = UDim2.new(0.5, -L.botsPad, 0, L.botsTitleH),
	})
	local incomeIcon = Components.CoinIcon({
		parent = botsCard,
		name = "IncomeCoin",
		size = UDim2.fromOffset(18, 18),
	})
	local income = Components.Label({
		parent = botsCard,
		name = "Income",
		textSize = Theme.text.small,
		font = Theme.font.title,
		color = Theme.color.tealDark,
		align = Enum.TextXAlignment.Right,
	})
	local botsRow = Instance.new("Frame")
	botsRow.Name = "Bots"
	botsRow.BackgroundTransparency = 1
	botsRow.BorderSizePixel = 0
	botsRow.Parent = botsCard
	local botsGrid = PanelKit.newGrid(botsRow)
	botsGrid.FillDirectionMaxCells = 6
	botsGrid.CellSize = UDim2.new(1 / 6, -5, 1, 0)

	local bots: { BotSlot } = {}
	for i = 1, 6 do
		local frame = Instance.new("Frame")
		frame.Name = "Bot" .. i
		frame.LayoutOrder = i
		frame.BackgroundColor3 = Theme.color.creamDark
		frame.BorderSizePixel = 0
		frame.Parent = botsRow
		local round = Instance.new("UICorner")
		round.CornerRadius = Theme.radius.md
		round.Parent = frame
		local outline = Instance.new("UIStroke")
		outline.Color = Theme.color.parchmentLine
		outline.Thickness = Theme.size.stroke
		outline.Parent = frame
		local glyph = Components.Label({
			parent = frame,
			name = "Glyph",
			text = "+",
			textSize = Theme.text.title,
			color = Theme.color.greyDark,
			anchor = Vector2.new(0.5, 0),
			position = UDim2.fromScale(0.5, 0.06),
			size = UDim2.fromScale(0.8, 0.58),
		})
		local level = Components.Label({
			parent = frame,
			name = "Level",
			textSize = Theme.text.tiny,
			font = Theme.font.title,
			color = Theme.color.charcoalSoft,
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -3),
			size = UDim2.new(1, -4, 0.28, 0),
		})
		bots[i] = {
			root = frame,
			outline = outline,
			glyph = glyph,
			level = level,
			stopWobble = nil,
			filled = false,
		}
	end

	-- ===== the two buttons =====
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.BackgroundTransparency = 1
	actions.BorderSizePixel = 0
	actions.LayoutOrder = 2
	actions.Parent = list.root
	local actionGrid = PanelKit.newGrid(actions)
	local buyCard = makeActionCard(actions, 1, "🤖", "Buy a robot", false)
	local upCard = makeActionCard(actions, 2, "⚡", "Robot level", true)

	-- ===== state =====
	local current: HelpersModel.Model = HelpersModel.build(Bridge.view())
	local lastCount: number? = nil
	local lastLevel: number? = nil
	local destroyed = false

	buyCard.cost.onBuy(function()
		Bridge.send("Buy", "helper", "")
	end)
	buyCard.cost.onBlocked(function()
		local m = current
		if m.buy.price == nil then
			ctx.toast("You have all six robots. Wow!", "gold")
		else
			ctx.toast(m.buy.needText or "Collect a few more coins!", "warn")
		end
	end)
	upCard.cost.onBuy(function()
		Bridge.send("Buy", "helperUp", "")
	end)
	upCard.cost.onBlocked(function()
		local m = current
		if m.count < 1 then
			ctx.toast("Get a robot first!", "warn")
		elseif m.up.price == nil then
			ctx.toast("Your robots are at the top level!", "gold")
		else
			ctx.toast(m.up.needText or "Collect a few more coins!", "warn")
		end
	end)

	local function paintBots(m: HelpersModel.Model)
		for i, bot in bots do
			local filled = m.slots[i] ~= nil and m.slots[i].filled
			if filled then
				bot.glyph.Text = "🤖"
				bot.glyph.TextColor3 = Theme.color.charcoal
				bot.root.BackgroundColor3 = Theme.color.creamLight
				bot.outline.Color = BOT_COLORS[(i - 1) % #BOT_COLORS + 1]
				bot.outline.Thickness = Theme.size.strokeThick
				bot.level.Text = `Lv {m.level}`
				if bot.stopWobble == nil then
					local sign = if i % 2 == 0 then -1 else 1
					bot.stopWobble = PanelKit.wobble(bot.glyph, L.wobble * sign)
				end
			else
				bot.glyph.Text = "+"
				bot.glyph.TextColor3 = Theme.color.greyDark
				bot.glyph.Rotation = 0
				bot.root.BackgroundColor3 = Theme.color.creamDark
				bot.outline.Color = Theme.color.parchmentLine
				bot.outline.Thickness = Theme.size.stroke
				bot.level.Text = ""
				local stop = bot.stopWobble
				if stop ~= nil then
					stop()
					bot.stopWobble = nil
				end
			end
			bot.filled = filled
		end
	end

	local function repaint()
		if destroyed then
			return
		end
		local view = Bridge.view()
		local m = HelpersModel.build(view)
		current = m
		header.setCoins(m.coins)
		header.setHint(m.hint)

		botsTitle.Text = `My robot friends: {m.count} of {m.max}`
		income.Text = m.incomeText
		incomeIcon.Visible = m.count > 0
		paintBots(m)

		-- buy a robot
		buyCard.sub.Text = `{m.count} of {m.max}`
		buyCard.line1.Text = m.buy.gainText
			or (if m.buy.price == nil then "You have all of them!" else "A robot sweeps for you!")
		buyCard.line2.Text = m.buy.needText or ""
		buyCard.cost.set(m.buy.price, m.buy.affordable, m.buy.label)

		-- level up
		upCard.sub.Text = `Level {m.level}`
		local upPips = upCard.pips
		if upPips ~= nil then
			upPips.set(m.level, m.maxLevel)
		end
		upCard.line1.Text = m.up.effectLine
		upCard.line2.Text = if m.up.price ~= nil and m.up.gainText ~= nil
			then (if m.up.needText ~= nil then m.up.needText else m.up.gainText)
			else ""
		upCard.line2.TextColor3 = if m.up.needText ~= nil
			then Theme.color.redDark
			else Theme.color.tealDark
		upCard.cost.set(m.up.price, m.up.affordable, m.up.label)

		-- pop what the SERVER just changed (never before the store is real)
		if Bridge.storeReady() then
			local oldCount = lastCount
			if oldCount ~= nil and m.count > oldCount then
				local bot = bots[m.count]
				if bot then
					PanelKit.celebrate(bot.root, nil)
				end
				PanelKit.celebrate(buyCard.card, "New robot!")
				Bridge.play("unlock")
				Bridge.tap(0.6)
			end
			local oldLevel = lastLevel
			if oldLevel ~= nil and m.level > oldLevel then
				PanelKit.celebrate(upCard.card, `Level {m.level}!`)
				for _, bot in bots do
					if bot.filled then
						Components.punch(bot.root, 0.1)
					end
				end
				Bridge.play("upgrade")
				Bridge.tap(0.5)
			end
			lastCount = m.count
			lastLevel = m.level
		end
	end

	local stopSize = PanelKit.watchSize(parent, function(size: Vector2)
		local wide = size.X >= PanelKit.WIDE_FROM
		-- bots card: title (and income) on one row in landscape, two rows in portrait
		local cardH = if wide then L.botsH else L.botsHTall
		botsSlot.Size = UDim2.new(1, 0, 0, cardH + 6)
		botsTitle.Size = UDim2.new(0.5, -L.botsPad, 0, L.botsTitleH)
		local rowTop: number
		if wide then
			incomeIcon.AnchorPoint = Vector2.new(1, 0)
			incomeIcon.Position = UDim2.new(1, -L.botsPad, 0, 8)
			income.AnchorPoint = Vector2.new(1, 0)
			income.Position = UDim2.new(1, -(L.botsPad + 22), 0, 6)
			income.Size = UDim2.new(0.5, -(L.botsPad + 22), 0, L.botsTitleH)
			income.TextXAlignment = Enum.TextXAlignment.Right
			rowTop = 32
		else
			botsTitle.Size = UDim2.new(1, -2 * L.botsPad, 0, L.botsTitleH)
			incomeIcon.AnchorPoint = Vector2.zero
			incomeIcon.Position = UDim2.fromOffset(L.botsPad, 30)
			income.AnchorPoint = Vector2.zero
			income.Position = UDim2.fromOffset(L.botsPad + 22, 28)
			income.Size = UDim2.new(1, -(2 * L.botsPad + 22), 0, L.botsTitleH)
			income.TextXAlignment = Enum.TextXAlignment.Left
			rowTop = 56
		end
		botsRow.Position = UDim2.fromOffset(L.botsPad, rowTop)
		botsRow.Size = UDim2.new(1, -2 * L.botsPad, 1, -(rowTop + L.botsPad))

		local cols = if wide then 2 else 1
		PanelKit.setGrid(actionGrid, cols, L.actionH)
		local rows = math.ceil(2 / cols)
		actions.Size = UDim2.new(1, 0, 0, rows * L.actionH + (rows - 1) * Theme.size.gap)
	end)

	local binding =
		StoreBinding.new({ "coins", "helpers", "helperLevel", "zones", "derived" }, repaint)

	return function()
		destroyed = true
		binding.destroy()
		stopSize()
		for _, bot in bots do
			local stop = bot.stopWobble
			if stop ~= nil then
				stop()
				bot.stopWobble = nil
			end
		end
		buyCard.cost.button.destroy()
		upCard.cost.button.destroy()
	end
end

local def: PanelHost.Def = {
	id = "helpers",
	title = "Helpers",
	icon = "🤖",
	order = 30,
	build = build,
}

PanelHost.register(def)

return def
