--!strict
-- Tools panel: a row of eight tool tiles on top, and a big detail card under it for the tool you
-- tapped: picture, name, what makes it special, five stat bars and one big button.
--   * owned tool        -> EQUIP  (sends EquipTool)        * your tool -> EQUIPPED
--   * not owned         -> price button (sends Buy "tool")  * the next tool up glows and says NEXT
-- The client only asks. The server checks and sends the new State; the panel then follows it.
-- The pictures are an emoji on a coloured disc (no asset ids). Texts come from ToolsModel (tested).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ToolsModel = require(Shared.Ui.ToolsModel)
local Bridge = require(script.Parent.Parent.Ui.Bridge)
local Components = require(script.Parent.Parent.Ui.Components)
local PanelHost = require(script.Parent.Parent.Ui.PanelHost)
local Theme = require(script.Parent.Parent.Ui.Theme)
local PanelKit = require(script.Parent.Shared.PanelKit)
local StoreBinding = require(script.Parent.Shared.StoreBinding)

local L = {
	tileH = 64,
	tileHTall = 72,
	art = 34,
	nextW = 38,
	traitW = 160,
	nextH = 14,
	-- landscape detail
	wideH = 160,
	wideTextX = 122,
	wideRightW = 150,
	wideRowY = 62,
	wideRowStep = 18,
	wideBarH = 16,
	-- portrait detail
	tallH = 340,
	tallTextX = 110,
	tallRowY = 116,
	tallRowStep = 26,
	tallBarH = 20,
	labelW = 56,
	pad = 10,
	buttonH = 50,
	buttonHTall = 52,
}

type Tile = {
	id: string,
	button: TextButton,
	stroke: UIStroke,
	art: Frame,
	glyph: TextLabel,
	state: TextLabel,
	next: Frame,
}

type StatRow = {
	root: Frame,
	label: TextLabel,
	bar: Components.Bar,
}

local STATE_TEXT: { [string]: string } = {
	equipped = "USING",
	owned = "OWNED",
	buy = "BUY!",
	locked = "🔒",
}

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function makeTile(strip: Frame, row: ToolsModel.Row): Tile
	local button = Instance.new("TextButton")
	button.Name = "Tile_" .. row.id
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = Theme.color.creamLight
	button.LayoutOrder = row.tier
	button.Parent = strip
	corner(button, Theme.radius.md)
	local outline = stroke(button, Theme.color.parchmentLine, Theme.size.stroke)

	local art = Instance.new("Frame")
	art.Name = "Art"
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.Position = UDim2.new(0.5, 0, 0, 6)
	art.Size = UDim2.fromOffset(L.art, L.art)
	art.BackgroundColor3 = Color3.fromHex(row.colorHex)
	art.BorderSizePixel = 0
	art.Active = false
	art.Parent = button
	corner(art, Theme.radius.full)
	local glyph = Components.Label({
		parent = art,
		name = "Glyph",
		text = row.glyph,
		textSize = Theme.text.big,
	})

	local state = Components.Label({
		parent = button,
		name = "State",
		textSize = Theme.text.tiny,
		font = Theme.font.title,
		color = Theme.color.charcoalSoft,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -4),
		size = UDim2.new(1, -6, 0, 16),
	})

	local nextTag = Instance.new("Frame")
	nextTag.Name = "NextTag"
	nextTag.AnchorPoint = Vector2.new(1, 0)
	nextTag.Position = UDim2.new(1, -2, 0, 2)
	nextTag.Size = UDim2.fromOffset(L.nextW, L.nextH)
	nextTag.BackgroundColor3 = Theme.color.gold
	nextTag.BorderSizePixel = 0
	nextTag.ZIndex = 5
	nextTag.Visible = false
	nextTag.Parent = button
	corner(nextTag, Theme.radius.full)
	Components.Label({
		parent = nextTag,
		name = "Text",
		text = "NEXT",
		textSize = Theme.text.tiny,
		font = Theme.font.title,
		color = Theme.color.charcoal,
		zIndex = 6,
	})

	return {
		id = row.id,
		button = button,
		stroke = outline,
		art = art,
		glyph = glyph,
		state = state,
		next = nextTag,
	}
end

local function build(parent: Frame, ctx: PanelHost.Ctx): () -> ()
	local header = PanelKit.header(parent)
	local list = PanelKit.scroll(parent, PanelKit.HEADER_H + Theme.size.gap)
	local conns: { RBXScriptConnection } = {}
	local stops: { () -> () } = {}

	-- ===== the tile strip =====
	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.LayoutOrder = 1
	strip.Size = UDim2.new(1, 0, 0, L.tileH)
	strip.Parent = list.root
	local stripGrid = PanelKit.newGrid(strip)

	local first = ToolsModel.build(Bridge.view())
	local tiles: { [string]: Tile } = {}
	local tileOrder: { string } = {}
	for _, row in first.rows do
		local tile = makeTile(strip, row)
		tiles[row.id] = tile
		table.insert(tileOrder, row.id)
	end

	-- ===== the detail card =====
	local slot, card = PanelKit.slot(list.root, 2)
	slot.Name = "DetailSlot"

	local preview = Instance.new("Frame")
	preview.Name = "Preview"
	preview.BorderSizePixel = 0
	preview.BackgroundColor3 = Theme.color.creamDark
	preview.Parent = card
	corner(preview, Theme.radius.full)
	local previewStroke = stroke(preview, Theme.color.charcoal, Theme.size.strokeThick)
	local previewGlyph = Components.Label({
		parent = preview,
		name = "Glyph",
		text = "🧹",
		textSize = Theme.text.huge,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromScale(0.7, 0.7),
	})
	table.insert(stops, PanelKit.wobble(previewGlyph, 6))

	local nameLabel = Components.Label({
		parent = card,
		name = "Name",
		textSize = Theme.text.big,
		font = Theme.font.title,
		align = Enum.TextXAlignment.Left,
	})
	local trait = Components.Pill({
		parent = card,
		name = "Trait",
		text = "",
		fill = Theme.color.teal,
		textColor = Theme.color.white,
		textSize = Theme.text.small,
		bordered = false,
		size = UDim2.fromOffset(L.traitW, 20),
	})
	local blurb = Components.Label({
		parent = card,
		name = "Blurb",
		textSize = Theme.text.small,
		font = Theme.font.body,
		color = Theme.color.charcoalSoft,
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		wrap = true,
	})

	local statKeys = { "Reach", "Width", "Power", "Speed", "Bag" }
	local statRows: { StatRow } = {}
	for i, label in statKeys do
		local rowFrame = Instance.new("Frame")
		rowFrame.Name = "Stat_" .. label
		rowFrame.BackgroundTransparency = 1
		rowFrame.BorderSizePixel = 0
		rowFrame.Parent = card
		local statLabel = Components.Label({
			parent = rowFrame,
			text = label,
			textSize = Theme.text.small,
			font = Theme.font.bold,
			color = Theme.color.charcoal,
			align = Enum.TextXAlignment.Left,
			size = UDim2.new(0, L.labelW, 1, 0),
		})
		local bar = Components.Bar({
			parent = rowFrame,
			position = UDim2.fromOffset(L.labelW, 0),
			size = UDim2.new(1, -L.labelW, 1, 0),
			fill = Theme.color.teal,
			text = " ",
			textSize = Theme.text.small,
		})
		statRows[i] = { root = rowFrame, label = statLabel, bar = bar }
	end

	local actionHolder = Instance.new("Frame")
	actionHolder.Name = "Action"
	actionHolder.BackgroundTransparency = 1
	actionHolder.BorderSizePixel = 0
	actionHolder.Parent = card
	local costButton = Components.CostButton({
		parent = actionHolder,
		name = "Buy",
		size = UDim2.fromScale(1, 1),
		textSize = Theme.text.big,
	})
	local equipButton = Components.Button({
		parent = actionHolder,
		name = "Equip",
		text = "EQUIP",
		variant = "primary",
		textSize = Theme.text.big,
		size = UDim2.fromScale(1, 1),
	})
	local equippedPill = Components.Pill({
		parent = actionHolder,
		name = "Equipped",
		text = "✓ EQUIPPED",
		fill = Theme.color.green,
		textColor = Theme.color.white,
		textSize = Theme.text.big,
		bordered = false,
		size = UDim2.fromScale(1, 1),
	})
	local needLabel = Components.Label({
		parent = card,
		name = "Need",
		textSize = Theme.text.small,
		font = Theme.font.bold,
		color = Theme.color.redDark,
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		wrap = true,
	})

	-- ===== state =====
	local selectedId = first.equippedId
	local current: ToolsModel.Model = first
	local lastEquipped: string? = nil
	local lastOwned = -1
	local wide = true
	local glowFor: string? = nil
	local glowStop: (() -> ())? = nil
	local destroyed = false

	local function selectedRow(): ToolsModel.Row
		for _, row in current.rows do
			if row.id == selectedId then
				return row
			end
		end
		return current.rows[1]
	end

	local function layout()
		local textX = if wide then L.wideTextX else L.tallTextX
		local rightW = if wide then L.wideRightW else 0
		local detailH = if wide then L.wideH else L.tallH
		slot.Size = UDim2.new(1, 0, 0, detailH + 6)

		local previewPx = if wide then 104 else 92
		preview.Position = UDim2.fromOffset(L.pad, L.pad)
		preview.Size = UDim2.fromOffset(previewPx, previewPx)

		local textW = -(textX + L.pad + rightW + (if wide then L.pad else 0))
		nameLabel.Position = UDim2.fromOffset(textX, 8)
		nameLabel.Size = UDim2.new(1, textW, 0, 26)
		trait.root.Position = UDim2.fromOffset(textX, 36)

		local rowY = if wide then L.wideRowY else L.tallRowY
		local step = if wide then L.wideRowStep else L.tallRowStep
		local barH = if wide then L.wideBarH else L.tallBarH
		for i, r in statRows do
			r.root.Position = UDim2.fromOffset(textX, rowY + (i - 1) * step)
			r.root.Size = UDim2.new(1, textW, 0, barH)
		end

		if wide then
			actionHolder.AnchorPoint = Vector2.new(1, 0)
			actionHolder.Position = UDim2.new(1, -L.pad, 0, L.pad)
			actionHolder.Size = UDim2.fromOffset(L.wideRightW, L.buttonH)
			blurb.AnchorPoint = Vector2.new(1, 0)
			blurb.Position = UDim2.new(1, -L.pad, 0, L.pad + L.buttonH + 6)
			blurb.Size = UDim2.fromOffset(L.wideRightW, 46)
			needLabel.AnchorPoint = Vector2.new(1, 0)
			needLabel.Position = UDim2.new(1, -L.pad, 0, L.pad + L.buttonH + 56)
			needLabel.Size = UDim2.fromOffset(L.wideRightW, 34)
		else
			actionHolder.AnchorPoint = Vector2.zero
			actionHolder.Position = UDim2.fromOffset(L.pad, 252)
			actionHolder.Size = UDim2.new(1, -2 * L.pad, 0, L.buttonHTall)
			blurb.AnchorPoint = Vector2.zero
			blurb.Position = UDim2.fromOffset(textX, 64)
			blurb.Size = UDim2.new(1, -(textX + L.pad), 0, 44)
			needLabel.AnchorPoint = Vector2.zero
			needLabel.Position = UDim2.fromOffset(L.pad, 252 + L.buttonHTall + 6)
			needLabel.Size = UDim2.new(1, -2 * L.pad, 0, 26)
		end

		local cols = if wide then 8 else 4
		local tileH = if wide then L.tileH else L.tileHTall
		PanelKit.setGrid(stripGrid, cols, tileH)
		local rows = math.ceil(#tileOrder / cols)
		strip.Size = UDim2.new(1, 0, 0, rows * tileH + (rows - 1) * Theme.size.gap)
	end

	local function paintTiles()
		for _, row in current.rows do
			local tile = tiles[row.id]
			if tile then
				local picked = row.id == selectedId
				tile.stroke.Color = if picked
					then Theme.color.lava
					elseif row.isNext then Theme.color.goldDark
					else Theme.color.parchmentLine
				tile.stroke.Thickness = if picked or row.isNext
					then Theme.size.strokeThick
					else Theme.size.stroke
				tile.button.BackgroundColor3 = if picked
					then Theme.color.white
					else Theme.color.cream
				tile.next.Visible = row.isNext
				local dim = row.status == "locked"
				tile.art.BackgroundTransparency = if dim then 0.55 else 0
				tile.glyph.TextTransparency = if dim then 0.5 else 0
				local text = STATE_TEXT[row.status] or Theme.fmt(row.price)
				tile.state.Text = text
				tile.state.TextColor3 = if row.status == "equipped"
					then Theme.color.greenDark
					elseif row.status == "buy" then Theme.color.lavaDark
					elseif row.status == "owned" then Theme.color.charcoal
					else Theme.color.greyDeep
			end
		end
		-- the glowing outline follows the NEXT tool
		if glowFor ~= current.nextId then
			if glowStop then
				glowStop()
				glowStop = nil
				local old = if glowFor then tiles[glowFor] else nil
				if old then
					old.stroke.Transparency = 0
				end
			end
			glowFor = current.nextId
			local nextTile = if current.nextId then tiles[current.nextId] else nil
			if nextTile then
				glowStop = PanelKit.glow(nextTile.stroke)
			end
		end
	end

	local function paintDetail()
		local row = selectedRow()
		preview.BackgroundColor3 = Color3.fromHex(row.colorHex)
		previewStroke.Color = Theme.color.charcoal
		previewGlyph.Text = row.glyph
		nameLabel.Text = row.name
		trait.setText(row.trait)
		blurb.Text = row.blurb
		for i, stat in row.stats do
			local r = statRows[i]
			if r then
				r.label.Text = stat.label
				r.bar.set(stat.fraction)
				r.bar.setText(stat.text)
				-- green = better than the tool in your hands, orange = weaker
				local mine = stat.equippedFraction
				r.bar.setColor(
					if stat.fraction > mine + 0.001
						then Theme.color.green
						elseif stat.fraction < mine - 0.001 then Theme.color.lava
						else Theme.color.teal
				)
			end
		end
		costButton.root.Visible = row.status == "buy"
			or row.status == "short"
			or row.status == "locked"
		equipButton.root.Visible = row.status == "owned"
		equippedPill.root.Visible = row.status == "equipped"
		if costButton.root.Visible then
			costButton.set(row.price, row.affordable, nil)
		end
		needLabel.Text = if row.status == "short" or row.status == "locked"
			then (row.needText or "")
			else ""
	end

	local function repaint()
		if destroyed then
			return
		end
		local view = Bridge.view()
		local model = ToolsModel.build(view)
		current = model
		header.setCoins(model.coins)
		header.setHint(model.hint)

		local owned = 0
		for _, row in model.rows do
			if row.owned then
				owned += 1
			end
		end
		-- your tool changed (you bought or equipped one): show it
		if lastEquipped ~= model.equippedId then
			selectedId = model.equippedId
		end
		paintTiles()
		paintDetail()
		if Bridge.storeReady() then
			if lastEquipped ~= nil and lastEquipped ~= model.equippedId then
				PanelKit.celebrate(card, if owned > lastOwned then "New tool!" else "Equipped!")
				Bridge.play("upgrade")
				Bridge.tap(0.5)
			end
			lastEquipped = model.equippedId
			lastOwned = owned
		end
	end

	-- ===== taps (intent only; the server decides) =====
	for _, id in tileOrder do
		local tile = tiles[id]
		table.insert(
			conns,
			tile.button.Activated:Connect(function()
				if selectedId == id then
					return
				end
				selectedId = id
				Bridge.play("click")
				paintTiles()
				paintDetail()
				Components.punch(preview, 0.1)
			end)
		)
	end
	costButton.onBuy(function()
		Bridge.send("Buy", "tool", selectedId)
	end)
	costButton.onBlocked(function()
		local need = selectedRow().needText
		ctx.toast(need or "Save up a few more coins!", "warn")
	end)
	equipButton.onClick(function()
		Bridge.send("EquipTool", selectedId)
	end)

	local stopSize = PanelKit.watchSize(parent, function(size: Vector2)
		wide = size.X >= PanelKit.WIDE_FROM
		layout()
	end)
	local binding = StoreBinding.new({ "coins", "tool", "toolsOwned" }, repaint)

	return function()
		destroyed = true
		binding.destroy()
		stopSize()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		if glowStop then
			glowStop()
		end
		for _, stop in stops do
			stop()
		end
		costButton.button.destroy()
		equipButton.destroy()
	end
end

local def: PanelHost.Def = {
	id = "tools",
	title = "Tools",
	icon = "🧹",
	order = 20,
	build = build,
}

PanelHost.register(def)

return def
