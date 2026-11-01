--!strict
-- Upgrades panel: all ten upgrade lines as cards. Each card: picture (level under it), name, one
-- sentence, level pips, "now -> next" effect and a 48 px price button. A "⭐ Cheapest" tag marks the
-- cheapest next step (the model says so honestly; it is not a "best value" promise).
--
-- The client NEVER spends anything: a tap only sends Buy("upgrade", id). The card pops when the
-- SERVER's State update says the level went up. No hold-to-buy (no accidental spending).
-- All texts and yes/no decisions come from Shared/Ui/UpgradesModel (unit tested).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UpgradeCatalog = require(Shared.Catalog.Upgrades)
local UpgradesModel = require(Shared.Ui.UpgradesModel)
local Bridge = require(script.Parent.Parent.Ui.Bridge)
local Components = require(script.Parent.Parent.Ui.Components)
local PanelHost = require(script.Parent.Parent.Ui.PanelHost)
local Theme = require(script.Parent.Parent.Ui.Theme)
local PanelKit = require(script.Parent.Shared.PanelKit)
local StoreBinding = require(script.Parent.Shared.StoreBinding)

-- layout numbers (virtual px), kept in one place
local L = {
	cellH = 124,
	cellHShort = 116, -- the 48 px BUY button needs this much under the 2-line text
	icon = 36,
	pad = 8,
	textX = 52,
	nameH = 22,
	tagW = 96,
	tagH = 18,
	pipsH = 8,
	levelY = 48, -- "3/16" sits under the round picture, clear of the BUY button
	levelH = 16,
	buttonW = Theme.size.claimW,
	buttonH = Theme.size.button,
	-- {normal, short}
	descY = { 30, 28 },
	descH = { 30, 26 },
	pipsY = { 64, 57 },
	effectY = { 78, 68 },
	effectH = { 30, 30 },
}

type Card = {
	id: string,
	slot: Frame,
	card: Frame,
	cardStroke: UIStroke?,
	desc: TextLabel,
	pips: Components.Pips,
	levelText: TextLabel,
	effect: TextLabel,
	tag: Frame,
	cost: Components.CostButton,
	row: UpgradesModel.Row?,
}

local function makeCard(
	list: Components.ScrollList,
	id: string,
	order: number,
	ctx: PanelHost.Ctx
): Card
	local slot, card = PanelKit.slot(list.root, order)

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.BackgroundColor3 = Theme.color.creamDark
	icon.BorderSizePixel = 0
	icon.Position = UDim2.fromOffset(L.pad, L.pad)
	icon.Size = UDim2.fromOffset(L.icon, L.icon)
	icon.Parent = card
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = Theme.radius.full
	iconCorner.Parent = icon
	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Theme.color.parchmentLine
	iconStroke.Thickness = Theme.size.stroke
	iconStroke.Parent = icon
	Components.Label({
		parent = icon,
		name = "Glyph",
		text = UpgradesModel.iconOf(id),
		textSize = Theme.text.big,
	})

	local name = Components.Label({
		parent = card,
		name = "Name",
		textSize = Theme.text.body,
		font = Theme.font.title,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(L.textX, L.pad - 2),
		size = UDim2.new(1, -(L.textX + L.tagW + L.pad + 6), 0, L.nameH),
	})

	local desc = Components.Label({
		parent = card,
		name = "Desc",
		textSize = Theme.text.small,
		font = Theme.font.body,
		color = Theme.color.charcoalSoft,
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		wrap = true,
		position = UDim2.fromOffset(L.textX, L.descY[1]),
		size = UDim2.new(1, -(L.textX + L.pad), 0, L.descH[1]),
	})

	-- pips stretch from the text column to just left of the BUY button
	local pips = Components.Pips({
		parent = card,
		name = "Pips",
		total = 10,
		filled = 0,
		color = Theme.color.lava,
		position = UDim2.fromOffset(L.textX, L.pipsY[1]),
		size = UDim2.new(1, -(L.textX + L.buttonW + L.pad + 8), 0, L.pipsH),
	})

	local levelText = Components.Label({
		parent = card,
		name = "LevelText",
		textSize = Theme.text.tiny,
		font = Theme.font.title,
		color = Theme.color.charcoalSoft,
		position = UDim2.fromOffset(L.pad - 4, L.levelY),
		size = UDim2.fromOffset(L.icon + 8, L.levelH),
	})

	local effect = Components.Label({
		parent = card,
		name = "Effect",
		textSize = Theme.text.small,
		font = Theme.font.title,
		color = Theme.color.tealDark,
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		wrap = true,
		position = UDim2.fromOffset(L.textX, L.effectY[1]),
		size = UDim2.new(1, -(L.textX + L.buttonW + L.pad + 8), 0, L.effectH[1]),
	})

	local tagPill = Components.Pill({
		parent = card,
		name = "BestTag",
		text = UpgradesModel.BEST_TAG,
		fill = Theme.color.gold,
		textColor = Theme.color.charcoal,
		textSize = Theme.text.tiny,
		bordered = false,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -L.pad, 0, L.pad),
		size = UDim2.fromOffset(L.tagW, L.tagH),
	})
	tagPill.root.Visible = false

	local cost = Components.CostButton({
		parent = card,
		name = "Buy",
		anchor = Vector2.new(1, 1),
		position = UDim2.new(1, -L.pad, 1, -L.pad),
		size = UDim2.fromOffset(L.buttonW, L.buttonH),
		textSize = Theme.text.body,
	})

	local line = UpgradeCatalog.byId[id]
	if line ~= nil then
		name.Text = line.name
		desc.Text = line.desc
	end

	local self: Card = {
		id = id,
		slot = slot,
		card = card,
		cardStroke = PanelKit.stroke(card),
		desc = desc,
		pips = pips,
		levelText = levelText,
		effect = effect,
		tag = tagPill.root,
		cost = cost,
		row = nil,
	}

	cost.onBuy(function()
		-- intent only: the server checks the price and the level, then sends the new State
		Bridge.send("Buy", "upgrade", id)
	end)
	cost.onBlocked(function()
		local row = self.row
		if row == nil then
			return
		end
		if row.maxed then
			ctx.toast("This one is maxed out. Great job!", "gold")
		else
			local need = row.needText
			if need ~= nil then
				ctx.toast(need, "warn")
			end
		end
	end)
	return self
end

local function paintCard(c: Card, row: UpgradesModel.Row)
	c.row = row
	c.pips.set(row.level, row.maxLevel)
	c.levelText.Text = `{row.level}/{row.maxLevel}`
	c.effect.Text = row.effectLine
	c.effect.TextColor3 = if row.maxed then Theme.color.greenDark else Theme.color.tealDark
	c.tag.Visible = row.best
	c.cost.set(row.price, row.affordable, row.buttonLabel)
	c.card.BackgroundColor3 = if row.maxed then Theme.color.creamDark else Theme.color.creamLight
	if c.cardStroke then
		c.cardStroke.Color = if row.best then Theme.color.goldDark else Theme.color.parchmentLine
		c.cardStroke.Thickness = if row.best then Theme.size.strokeThick else Theme.size.stroke
	end
end

local function applyShort(c: Card, short: boolean)
	local i = if short then 2 else 1
	c.desc.Position = UDim2.fromOffset(L.textX, L.descY[i])
	c.desc.Size = UDim2.new(1, -(L.textX + L.pad), 0, L.descH[i])
	c.pips.root.Position = UDim2.fromOffset(L.textX, L.pipsY[i])
	c.effect.Position = UDim2.fromOffset(L.textX, L.effectY[i])
	c.effect.Size = UDim2.new(1, -(L.textX + L.buttonW + L.pad + 8), 0, L.effectH[i])
end

local function build(parent: Frame, ctx: PanelHost.Ctx): () -> ()
	local header = PanelKit.header(parent)
	local list = PanelKit.scroll(parent, PanelKit.HEADER_H + Theme.size.gap)
	local grid = PanelKit.useGrid(list)

	local cards: { [string]: Card } = {}
	for i, row in UpgradesModel.build(Bridge.view()).rows do
		cards[row.id] = makeCard(list, row.id, i, ctx)
	end

	local lastLevels: { [string]: number }? = nil
	local destroyed = false

	local function repaint()
		if destroyed then
			return
		end
		local view = Bridge.view()
		local model = UpgradesModel.build(view)
		header.setCoins(model.coins)
		header.setHint(model.hint)
		for _, row in model.rows do
			local c = cards[row.id]
			if c then
				paintCard(c, row)
			end
		end
		-- pop the card of every line the SERVER just levelled up (never before the store is real)
		if Bridge.storeReady() then
			local before = lastLevels
			if before ~= nil then
				for _, id in UpgradesModel.levelUps(before, view) do
					local c = cards[id]
					if c and c.row then
						PanelKit.celebrate(c.card, `Level {c.row.level}!`)
						Bridge.play("upgrade")
						Bridge.tap(0.5)
					end
				end
			end
			lastLevels = UpgradesModel.levels(view)
		end
	end

	local stopSize = PanelKit.watchSize(parent, function(size: Vector2)
		local short = size.Y < PanelKit.SHORT_BELOW
		local cols = if size.X >= PanelKit.WIDE_FROM then 2 else 1
		PanelKit.setGrid(grid, cols, if short then L.cellHShort else L.cellH)
		for _, c in cards do
			applyShort(c, short)
		end
	end)

	local binding = StoreBinding.new({ "coins", "upgrades", "sparkPerks" }, repaint)

	return function()
		destroyed = true
		binding.destroy()
		stopSize()
		for _, c in cards do
			c.cost.button.destroy()
		end
	end
end

local def: PanelHost.Def = {
	id = "upgrades",
	title = "Upgrades",
	icon = "🛠",
	order = 10,
	build = build,
}

PanelHost.register(def)

return def
