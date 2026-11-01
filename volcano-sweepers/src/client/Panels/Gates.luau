--!strict
-- Gates panel: the five zones as a map-like stack, with a little ring picture of the island.
--   * open zones say OPEN   * only the NEXT zone can be bought (price button, glowing outline)
--   * far zones say LOCKED and tell you which gate to open first
--   * every zone brags how many times more coins its ash is worth
-- The client only asks (Buy "zone", "2"); the server checks everything and sends the new State.
-- Texts and states come from GatesModel (unit tested), which uses the same Pricing as the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GatesModel = require(Shared.Ui.GatesModel)
local Bridge = require(script.Parent.Parent.Ui.Bridge)
local Components = require(script.Parent.Parent.Ui.Components)
local PanelHost = require(script.Parent.Parent.Ui.PanelHost)
local Theme = require(script.Parent.Parent.Ui.Theme)
local PanelKit = require(script.Parent.Shared.PanelKit)
local StoreBinding = require(script.Parent.Shared.StoreBinding)

local L = {
	disc = 150, -- the ring picture is a square this big
	diagramW = 166, -- landscape: width of the column the picture sits in
	scrollPad = 14, -- the scroll area's own padding and scroll bar
	cardWideFrom = 400, -- cards at least this wide put the price button beside the text
	cardH = 100,
	cardHTall = 152,
	node = 40,
	pad = 8,
	textX = 58,
	tagW = 92,
	tagH = 18,
	buttonW = 104,
	buttonH = 44,
	buttonHTall = 42,
	pillW = 190,
	pillH = 18,
}

type Card = {
	id: number,
	slot: Frame,
	card: Frame,
	cardStroke: UIStroke?,
	node: Frame,
	nodeLabel: TextLabel,
	name: TextLabel,
	blurb: TextLabel,
	value: TextLabel,
	compare: Components.Pill,
	compareStroke: UIStroke,
	tag: Components.Pill,
	cost: Components.CostButton,
	openPill: Components.Pill,
	row: GatesModel.Row?,
}

type RingArt = {
	circle: Frame,
	outline: UIStroke,
	label: TextLabel,
}

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function makeCard(list: Components.ScrollList, row: GatesModel.Row, ctx: PanelHost.Ctx): Card
	local slot, card = PanelKit.slot(list.root, row.id)

	local node = Instance.new("Frame")
	node.Name = "Node"
	node.BackgroundColor3 = Color3.fromHex(row.groundHex)
	node.BorderSizePixel = 0
	node.Position = UDim2.fromOffset(L.pad, L.pad)
	node.Size = UDim2.fromOffset(L.node, L.node)
	node.Parent = card
	corner(node, Theme.radius.full)
	local nodeStroke = Instance.new("UIStroke")
	nodeStroke.Color = Theme.color.charcoal
	nodeStroke.Thickness = Theme.size.stroke
	nodeStroke.Parent = node
	local nodeLabel = Components.Label({
		parent = node,
		name = "Number",
		text = tostring(row.id),
		textSize = Theme.text.big,
		font = Theme.font.title,
		color = Theme.color.white,
		outline = Theme.color.ink,
	})

	local name = Components.Label({
		parent = card,
		name = "Name",
		text = row.name,
		textSize = Theme.text.body,
		font = Theme.font.title,
		align = Enum.TextXAlignment.Left,
	})
	local blurb = Components.Label({
		parent = card,
		name = "Blurb",
		text = row.blurb,
		textSize = Theme.text.small,
		font = Theme.font.body,
		color = Theme.color.charcoalSoft,
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		wrap = true,
	})
	local value = Components.Label({
		parent = card,
		name = "Value",
		text = `💰 {row.valueText}`,
		textSize = Theme.text.small,
		font = Theme.font.title,
		color = Theme.color.tealDark,
		align = Enum.TextXAlignment.Left,
	})

	local compare = Components.Pill({
		parent = card,
		name = "Compare",
		text = row.compareText or "",
		fill = Theme.color.gold,
		textColor = Theme.color.charcoal,
		textSize = Theme.text.small,
		bordered = false,
		size = UDim2.fromOffset(L.pillW, L.pillH),
	})
	compare.root.Visible = row.compareText ~= nil
	local compareStroke = Instance.new("UIStroke")
	compareStroke.Color = Theme.color.goldLight
	compareStroke.Thickness = Theme.size.strokeThick
	compareStroke.Parent = compare.root

	local tag = Components.Pill({
		parent = card,
		name = "BestTag",
		text = "⭐ Your best",
		fill = Theme.color.green,
		textColor = Theme.color.white,
		textSize = Theme.text.tiny,
		bordered = false,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -L.pad, 0, L.pad),
		size = UDim2.fromOffset(L.tagW, L.tagH),
	})
	tag.root.Visible = false

	local cost = Components.CostButton({
		parent = card,
		name = "Buy",
		anchor = Vector2.new(1, 1),
		position = UDim2.new(1, -L.pad, 1, -L.pad),
		size = UDim2.fromOffset(L.buttonW, L.buttonH),
		textSize = Theme.text.body,
	})
	local openPill = Components.Pill({
		parent = card,
		name = "Open",
		text = "✓ OPEN",
		fill = Theme.color.green,
		textColor = Theme.color.white,
		textSize = Theme.text.body,
		bordered = false,
		anchor = Vector2.new(1, 1),
		position = UDim2.new(1, -L.pad, 1, -L.pad),
		size = UDim2.fromOffset(L.buttonW, L.buttonH),
	})
	openPill.root.Visible = false

	local self: Card = {
		id = row.id,
		slot = slot,
		card = card,
		cardStroke = PanelKit.stroke(card),
		node = node,
		nodeLabel = nodeLabel,
		name = name,
		blurb = blurb,
		value = value,
		compare = compare,
		compareStroke = compareStroke,
		tag = tag,
		cost = cost,
		openPill = openPill,
		row = nil,
	}

	cost.onBuy(function()
		-- the Buy remote carries ids as text; the server turns "2" into zone 2 and checks it again
		Bridge.send("Buy", "zone", tostring(row.id))
	end)
	cost.onBlocked(function()
		local r = self.row
		local why = if r ~= nil then r.reasonText else nil
		ctx.toast(why or "Not yet!", "warn")
	end)
	return self
end

local function applyMode(c: Card, wide: boolean)
	c.slot.Size = UDim2.new(1, 0, 0, (if wide then L.cardH else L.cardHTall) + 6)
	local tagRoom = L.tagW + L.pad + 6
	c.name.Position = UDim2.fromOffset(L.textX, 6)
	c.name.Size = UDim2.new(1, -(L.textX + tagRoom), 0, 22)
	if wide then
		c.blurb.Position = UDim2.fromOffset(L.textX, 28)
		c.blurb.Size = UDim2.new(1, -(L.textX + L.buttonW + L.pad + 8), 0, 30)
		c.value.Position = UDim2.fromOffset(L.textX, 60)
		c.value.Size = UDim2.new(1, -(L.textX + L.buttonW + L.pad + 8), 0, 16)
		c.compare.root.Position = UDim2.fromOffset(L.textX, 78)
		c.compare.root.Size = UDim2.fromOffset(L.pillW, L.pillH)
		c.cost.root.AnchorPoint = Vector2.new(1, 1)
		c.cost.root.Position = UDim2.new(1, -L.pad, 1, -L.pad)
		c.cost.root.Size = UDim2.fromOffset(L.buttonW, L.buttonH)
		c.openPill.root.AnchorPoint = Vector2.new(1, 1)
		c.openPill.root.Position = UDim2.new(1, -L.pad, 1, -L.pad)
		c.openPill.root.Size = UDim2.fromOffset(L.buttonW, L.buttonH)
	else
		c.blurb.Position = UDim2.fromOffset(L.textX, 28)
		c.blurb.Size = UDim2.new(1, -(L.textX + L.pad), 0, 30)
		c.value.Position = UDim2.fromOffset(L.textX, 60)
		c.value.Size = UDim2.new(1, -(L.textX + L.pad), 0, 16)
		c.compare.root.Position = UDim2.fromOffset(L.textX, 80)
		c.compare.root.Size = UDim2.new(1, -(L.textX + L.pad), 0, L.pillH)
		for _, button in { c.cost.root, c.openPill.root } do
			button.AnchorPoint = Vector2.new(0.5, 1)
			button.Position = UDim2.new(0.5, 0, 1, -L.pad)
			button.Size = UDim2.new(1, -2 * L.pad, 0, L.buttonHTall)
		end
	end
end

local function paintCard(c: Card, row: GatesModel.Row)
	c.row = row
	local open = row.state == "open"
	local locked = row.state == "locked"
	c.node.BackgroundColor3 = if locked then Theme.color.grey else Color3.fromHex(row.groundHex)
	c.nodeLabel.Text = if locked then "🔒" else tostring(row.id)
	c.value.Text = `💰 {row.valueText}`
	c.tag.root.Visible = row.best
	c.cost.root.Visible = not open
	c.openPill.root.Visible = open
	if not open then
		if locked then
			c.cost.set(nil, false, "🔒 LOCKED")
		else
			c.cost.set(row.price, row.affordable, nil)
		end
	end
	-- the x-times brag: gold while it is still to be won, quiet once it is yours
	c.compare.root.Visible = row.compareText ~= nil
	c.compare.setText(row.compareText or "")
	c.compare.setFill(if open then Theme.color.creamDark else Theme.color.gold, nil)
	c.compare.setTextColor(if open then Theme.color.charcoalSoft else Theme.color.charcoal)
	c.compareStroke.Enabled = not open
	c.card.BackgroundColor3 = if locked then Theme.color.creamDark else Theme.color.creamLight
	if c.cardStroke then
		c.cardStroke.Color = if row.state == "next"
			then Theme.color.goldDark
			else Theme.color.parchmentLine
		c.cardStroke.Thickness = if row.state == "next"
			then Theme.size.strokeThick
			else Theme.size.stroke
	end
end

local function build(parent: Frame, ctx: PanelHost.Ctx): () -> ()
	local header = PanelKit.header(parent)
	local top = PanelKit.HEADER_H + Theme.size.gap
	local list = PanelKit.scroll(parent, top)
	local first = GatesModel.build(Bridge.view())

	-- ===== the ring picture =====
	local holder = Instance.new("Frame")
	holder.Name = "Diagram"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.LayoutOrder = 0
	holder.Parent = list.root
	local disc = Instance.new("Frame")
	disc.Name = "Island"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromOffset(L.disc, L.disc)
	disc.BackgroundTransparency = 1
	disc.BorderSizePixel = 0
	disc.Parent = holder

	local rings: { [number]: RingArt } = {}
	for i, ring in first.rings do
		local circle = Instance.new("Frame")
		circle.Name = "Ring" .. ring.id
		circle.AnchorPoint = Vector2.new(0.5, 0.5)
		circle.Position = UDim2.fromScale(0.5, 0.5)
		circle.Size = UDim2.fromScale(ring.radiusFrac, ring.radiusFrac)
		circle.BackgroundColor3 = Color3.fromHex(ring.colorHex)
		circle.BorderSizePixel = 0
		circle.ZIndex = ring.id
		circle.Parent = disc
		corner(circle, Theme.radius.full)
		local outline = Instance.new("UIStroke")
		outline.Color = Theme.color.charcoal
		outline.Thickness = Theme.size.stroke
		outline.Parent = circle

		-- the number sits in the middle of this ring's band
		local inner = if first.rings[i + 1] then first.rings[i + 1].radiusFrac else first.coreFrac
		local mid = (ring.radiusFrac + inner) / 2
		local label = Components.Label({
			parent = disc,
			name = "RingLabel" .. ring.id,
			text = tostring(ring.id),
			textSize = Theme.text.big,
			font = Theme.font.title,
			color = Theme.color.white,
			outline = Theme.color.ink,
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(0.5, 0.5 - mid * 0.5),
			size = UDim2.fromScale(0.2, 0.16),
			zIndex = 20,
		})
		rings[ring.id] = { circle = circle, outline = outline, label = label }
	end
	local core = Instance.new("Frame")
	core.Name = "Volcano"
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromScale(first.coreFrac, first.coreFrac)
	core.BackgroundColor3 = Theme.color.lavaDeep
	core.BorderSizePixel = 0
	core.ZIndex = 10
	core.Parent = disc
	corner(core, Theme.radius.full)
	Components.Label({ parent = core, name = "Glyph", text = "🌋", textSize = Theme.text.body })

	-- ===== the zone cards =====
	local cards: { [number]: Card } = {}
	for _, row in first.rows do
		cards[row.id] = makeCard(list, row, ctx)
	end

	-- ===== state =====
	local glowRing: (() -> ())? = nil
	local glowPill: (() -> ())? = nil
	local glowFor: number? = nil
	local lastOpen: { [number]: boolean }? = nil
	local destroyed = false
	local wideMode = true

	local function setGlow(nextId: number?)
		if glowFor == nextId then
			return
		end
		local old = if glowFor then rings[glowFor] else nil
		if glowRing then
			glowRing()
			glowRing = nil
		end
		if glowPill then
			glowPill()
			glowPill = nil
		end
		if glowFor then
			if old then
				old.outline.Transparency = 0
			end
			local oldCard = cards[glowFor]
			if oldCard then
				oldCard.compareStroke.Transparency = 0
			end
		end
		glowFor = nextId
		if nextId ~= nil then
			local art = rings[nextId]
			if art then
				glowRing = PanelKit.glow(art.outline)
			end
			local card = cards[nextId]
			if card then
				glowPill = PanelKit.glow(card.compareStroke)
			end
		end
	end

	local function repaint()
		if destroyed then
			return
		end
		local model = GatesModel.build(Bridge.view())
		header.setCoins(model.coins)
		header.setHint(model.hint)

		local openNow: { [number]: boolean } = {}
		for _, row in model.rows do
			openNow[row.id] = row.state == "open"
			local c = cards[row.id]
			if c then
				paintCard(c, row)
			end
		end
		for _, ring in model.rings do
			local art = rings[ring.id]
			if art then
				local locked = ring.state == "locked"
				art.circle.BackgroundColor3 = if locked
					then Theme.color.grey
					else Color3.fromHex(ring.colorHex)
				art.label.Text = if locked then "🔒" else tostring(ring.id)
				local isNext = ring.state == "next"
				art.outline.Color = if isNext then Theme.color.gold else Theme.color.charcoal
				art.outline.Thickness = if isNext then Theme.size.strokeThick else Theme.size.stroke
			end
		end
		setGlow(model.nextId)

		-- a gate the SERVER just opened: pop it (never before the store is real)
		if Bridge.storeReady() then
			local before = lastOpen
			if before ~= nil then
				for _, row in model.rows do
					if openNow[row.id] and not before[row.id] then
						local c = cards[row.id]
						if c then
							PanelKit.celebrate(c.card, "Gate open!")
						end
						Components.punch(disc, 0.08)
						Bridge.play("unlock")
						Bridge.tap(0.7)
					end
				end
			end
			lastOpen = openNow
		end
	end

	local stopSize = PanelKit.watchSize(parent, function(size: Vector2)
		wideMode = size.X >= PanelKit.WIDE_FROM
		if wideMode then
			-- landscape: picture on the left, scrolling zones on the right
			holder.Parent = parent
			holder.Position = UDim2.fromOffset(0, top)
			holder.Size = UDim2.new(0, L.diagramW, 1, -top)
			list.root.Position = UDim2.fromOffset(L.diagramW + Theme.size.pad, top)
			list.root.Size = UDim2.new(1, -(L.diagramW + Theme.size.pad), 1, -top)
		else
			-- portrait: the picture is the first thing in the one scrolling column
			holder.Parent = list.root
			holder.Position = UDim2.new()
			holder.Size = UDim2.new(1, 0, 0, L.disc + 12)
			list.root.Position = UDim2.fromOffset(0, top)
			list.root.Size = UDim2.new(1, 0, 1, -top)
		end
		-- a card needs room for its price button beside the text: judge by the card's own width
		local cardWidth = size.X
			- (if wideMode then L.diagramW + Theme.size.pad else 0)
			- L.scrollPad
		for _, c in cards do
			applyMode(c, cardWidth >= L.cardWideFrom)
		end
	end)

	local binding = StoreBinding.new({ "coins", "zones" }, repaint)

	return function()
		destroyed = true
		binding.destroy()
		stopSize()
		if glowRing then
			glowRing()
		end
		if glowPill then
			glowPill()
		end
		for _, c in cards do
			c.cost.button.destroy()
		end
	end
end

local def: PanelHost.Def = {
	id = "gates",
	title = "Gates",
	icon = "🚪",
	order = 40,
	build = build,
}

PanelHost.register(def)

return def
