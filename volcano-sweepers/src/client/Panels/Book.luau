--!strict
-- Finds Book panel (id "book"): 30 finds in six sets. A find you have not found is a dark "?" tile;
-- a found one has a rarity-coloured frame, a picture, its name and how many you found. Tap a tile
-- for details. A finished set shows a big CLAIM button (the server pays the reward and decides).
-- All words and numbers come from shared/Ui/BookModel; this file only draws them.
--
-- Registers itself with PanelHost when required. The red dot on the menu button is kept up to date
-- all the time (also while the panel is closed) through Hud.setBadge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BookModel = require(Shared.Ui.BookModel)
local Bridge = require(script.Parent.Parent.Ui.Bridge)
local Components = require(script.Parent.Parent.Ui.Components)
local PanelHost = require(script.Parent.Parent.Ui.PanelHost)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Context = require(script.Parent.Parent.Hud.Context)

local ID = "book"

-- layout numbers (virtual px)
local BODY_SIDE = 12 -- PanelHost pads the body by this much left and right
local SCROLL_SIDE = 14 -- ScrollList padding left 4 + right 4 + 6 for the scroll bar
local HEADER_H = 46
local ROW_H = 24
local REWARD_H = 20
local CLAIM_W = Theme.size.claimW
local PILL_W = 54
local TILE_H = 98
local TILE_MIN_W = 84
local LEGEND_CHIP_H = 38
local LEGEND_TIP_H = 18 -- one line (wide panel)
local LEGEND_TIP_TALL_H = 32 -- two lines (narrow panel)
local WIDE_FROM = 480
local DETAIL_W = 300
local DETAIL_H = 196
local CLAIM_LATCH = 1.5 -- seconds a CLAIM button stays grey after a tap (the server answers meanwhile)
local PASTEL = 0.7 -- how much white goes into a rarity colour for a tile background

type TileRefs = {
	button: TextButton,
	stroke: UIStroke,
	icon: TextLabel,
	name: TextLabel,
	count: TextLabel,
}

type SetRefs = {
	card: Frame,
	name: TextLabel,
	pill: Components.Pill,
	reward: TextLabel,
	claim: Components.Button,
	grid: Frame,
	order: { string },
	tiles: { [string]: TileRefs },
}

type ChipRefs = { odds: TextLabel }

local function make(className: string, props: { [string]: any }): any
	local inst: any = Instance.new(className)
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	if parent ~= nil then
		inst.Parent = parent
	end
	return inst
end

local function rounded(inst: Instance, radius: UDim)
	make("UICorner", { CornerRadius = radius, Parent = inst })
end

local function outline(inst: Instance, color: Color3, thickness: number): UIStroke
	return make("UIStroke", {
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = inst,
	})
end

-- The panel root (named Panel_<id> by PanelHost) is sized in virtual px; that is the width we lay out in.
local function panelRoot(body: Instance): GuiObject?
	local node: Instance? = body
	while node ~= nil do
		if string.sub(node.Name, 1, 6) == "Panel_" and node:IsA("GuiObject") then
			return node :: GuiObject
		end
		node = node.Parent
	end
	return nil
end

local function bodyWidth(root: GuiObject?): number
	if root ~= nil then
		local w = root.Size.X.Offset
		if w > 2 * BODY_SIDE then
			return w - 2 * BODY_SIDE
		end
	end
	return 312
end

-- ===== the red dot, kept right even while the panel is closed =====
local hudModule: any = nil

local function setHudBadge(on: boolean)
	if hudModule == nil then
		local clientRoot = script.Parent.Parent
		local folder = clientRoot:FindFirstChild("Hud")
		local mod = if folder then folder:FindFirstChild("Hud") else nil
		if mod == nil or not mod:IsA("ModuleScript") then
			return
		end
		local ok, result = pcall(require, mod)
		if not ok then
			return
		end
		hudModule = result
	end
	local fn = hudModule.setBadge
	if type(fn) == "function" then
		pcall(fn, ID, on)
	end
end

local badgeLive = Context.new() -- lives as long as the client does
local function pushBadge()
	setHudBadge(BookModel.badge(Bridge.view()))
end
badgeLive.watch({ "finds", "setsClaimed" }, pushBadge)
-- the HUD may be built after the first change, so say it again now and then
badgeLive.every(2, pushBadge)

-- ===== the panel =====
local function build(parent: Frame, _ctx: PanelHost.Ctx): (() -> ())?
	local live = Context.new()
	local conns: { RBXScriptConnection } = {}
	local root = panelRoot(parent)

	local view: BookModel.View = BookModel.build(Bridge.view(), 1)
	local dirty = true
	local latch: { [string]: number } = {} -- set id -> os.clock() of the last CLAIM tap

	-- ---- header: "Found 12 / 30" and a bar ----
	local header = make("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, HEADER_H),
		Parent = parent,
	})
	local foundLabel = Components.Label({
		parent = header,
		name = "Found",
		text = view.headerText,
		textSize = Theme.text.big,
		font = Theme.font.title,
		color = Theme.color.charcoal,
		align = Enum.TextXAlignment.Left,
		size = UDim2.new(1, 0, 0, ROW_H + 2),
	})
	local foundBar = Components.Bar({
		parent = header,
		name = "FoundBar",
		position = UDim2.fromOffset(0, ROW_H + 6),
		size = UDim2.new(1, 0, 0, 16),
		fill = Theme.color.teal,
	})
	foundBar.set(view.fraction, false)

	local list = Components.ScrollList({
		parent = parent,
		name = "Sets",
		position = UDim2.fromOffset(0, HEADER_H + Theme.size.gap),
		size = UDim2.new(1, 0, 1, -(HEADER_H + Theme.size.gap)),
	})
	local scroll = list.root

	-- ---- rarity legend ----
	local legendCard = Components.Card({
		parent = scroll,
		name = "Legend",
		layoutOrder = 1,
		size = UDim2.new(
			1,
			0,
			0,
			Theme.size.pad + LEGEND_CHIP_H + Theme.size.gap + LEGEND_TIP_H + Theme.size.pad
		),
	})
	local chipRow = make("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(Theme.size.pad, Theme.size.pad),
		Size = UDim2.new(1, -2 * Theme.size.pad, 0, LEGEND_CHIP_H),
		Parent = legendCard,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Theme.size.gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chipRow,
	})
	local chips: { [string]: ChipRefs } = {}
	local legendCount = math.max(1, #view.legend)
	for i, entry in view.legend do
		local chip = make("Frame", {
			Name = "Chip_" .. entry.id,
			LayoutOrder = i,
			Size = UDim2.new(
				1 / legendCount,
				-Theme.size.gap * (legendCount - 1) / legendCount,
				1,
				0
			),
			BackgroundColor3 = Color3.fromHex(entry.colorHex),
			BorderSizePixel = 0,
			Parent = chipRow,
		})
		rounded(chip, Theme.radius.sm)
		outline(chip, Theme.color.charcoal, 1)
		Components.Label({
			parent = chip,
			text = entry.label,
			textSize = Theme.text.small,
			font = Theme.font.bold,
			color = Theme.color.charcoal,
			position = UDim2.fromOffset(2, 1),
			size = UDim2.new(1, -4, 0.45, 0),
		})
		local odds = Components.Label({
			parent = chip,
			name = "Odds",
			text = entry.oddsText,
			textSize = Theme.text.body,
			font = Theme.font.title,
			color = Theme.color.charcoal,
			position = UDim2.new(0, 2, 0.45, 0),
			size = UDim2.new(1, -4, 0.5, 0),
		})
		chips[entry.id] = { odds = odds }
	end
	local tipLabel = Components.Label({
		parent = legendCard,
		name = "Tip",
		text = view.tipText,
		textSize = Theme.text.small,
		font = Theme.font.body,
		color = Theme.color.charcoalSoft,
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		wrap = true,
		position = UDim2.fromOffset(
			Theme.size.pad,
			Theme.size.pad + LEGEND_CHIP_H + Theme.size.gap
		),
		size = UDim2.new(1, -2 * Theme.size.pad, 0, LEGEND_TIP_H),
	})

	-- ---- detail pop-up (built once, filled when a tile is tapped) ----
	local detail = make("Frame", {
		Name = "Detail",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 10,
		Parent = parent,
	})
	local dim = make("TextButton", {
		Name = "Dim",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.color.ink,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = detail,
	})
	local sheet = make("Frame", {
		Name = "Sheet",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		-- never taller than the panel body (short landscape phones): the constraint caps it at DETAIL_H
		Size = UDim2.new(1, -2 * Theme.size.pad, 1, -8),
		BackgroundColor3 = Theme.color.creamLight,
		BorderSizePixel = 0,
		Active = true, -- taps on the sheet never reach the dim behind it
		ZIndex = 2,
		Parent = detail,
	})
	rounded(sheet, Theme.radius.lg)
	local sheetStroke = outline(sheet, Theme.color.charcoal, Theme.size.strokeThick)
	make("UISizeConstraint", { MaxSize = Vector2.new(DETAIL_W, DETAIL_H), Parent = sheet })
	local textX = 84
	local dIcon = Components.Label({
		parent = sheet,
		name = "Icon",
		text = "?",
		textSize = Theme.text.huge,
		position = UDim2.fromOffset(10, 10),
		size = UDim2.fromOffset(64, 64),
	})
	local dName = Components.Label({
		parent = sheet,
		name = "Name",
		text = "",
		textSize = Theme.text.big,
		font = Theme.font.title,
		color = Theme.color.charcoal,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(textX, 10),
		size = UDim2.new(1, -(textX + 10), 0, 28),
	})
	local dRarity = make("Frame", {
		Name = "Rarity",
		Position = UDim2.fromOffset(textX, 42),
		Size = UDim2.new(1, -(textX + 10), 0, 24),
		BackgroundColor3 = Theme.color.grey,
		BorderSizePixel = 0,
		Parent = sheet,
	})
	rounded(dRarity, Theme.radius.full)
	local dRarityText = Components.Label({
		parent = dRarity,
		text = "",
		textSize = Theme.text.small,
		font = Theme.font.title,
		color = Theme.color.charcoal,
		size = UDim2.new(1, -8, 1, 0),
		position = UDim2.fromOffset(4, 0),
	})
	local dHint = Components.Label({
		parent = sheet,
		name = "Hint",
		text = "",
		textSize = Theme.text.small,
		font = Theme.font.bold,
		color = Theme.color.charcoalSoft,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(textX, 70),
		size = UDim2.new(1, -(textX + 10), 0, 18),
	})
	local lines: { TextLabel } = {}
	for i = 1, 3 do
		lines[i] = Components.Label({
			parent = sheet,
			name = "Line" .. i,
			text = "",
			textSize = Theme.text.body,
			font = Theme.font.bold,
			color = Theme.color.charcoal,
			align = Enum.TextXAlignment.Left,
			position = UDim2.fromOffset(14, 86 + (i - 1) * 20),
			size = UDim2.new(1, -28, 0, 20),
		})
	end
	local okButton = Components.Button({
		parent = sheet,
		name = "Ok",
		text = "OK",
		variant = "secondary",
		textSize = Theme.text.big,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -10),
		size = UDim2.fromOffset(140, Theme.size.touch),
	})

	local function hideDetail()
		detail.Visible = false
	end
	dim.Activated:Connect(hideDetail)
	okButton.onClick(hideDetail)

	local function showDetail(entry: BookModel.Entry)
		local color = Color3.fromHex(entry.colorHex)
		sheetStroke.Color = color
		dIcon.Text = if entry.found then entry.icon else "?"
		dIcon.TextColor3 = Theme.color.charcoalSoft
		dName.Text = if entry.found then entry.name else "Mystery find"
		dRarity.BackgroundColor3 = color
		dRarityText.Text = entry.oddsLine
		dHint.Text = entry.hint
		lines[1].Text = entry.zoneText
		lines[2].Text = entry.coinsText
		lines[3].Text = if entry.found
			then (if entry.count == 1
				then "You found it 1 time!"
				else `You found it {entry.count} times!`)
			else "Keep sweeping to find it!"
		detail.Visible = true
		Components.punch(sheet, 0.04)
	end

	-- ---- one card per set ----
	local sets: { [string]: SetRefs } = {}
	local setIds: { string } = {}
	local entriesById: { [string]: BookModel.Entry } = {}
	for _, setView in view.sets do
		for _, entry in setView.entries do
			entriesById[entry.id] = entry
		end
	end

	for index, setView in view.sets do
		local card = Components.Card({
			parent = scroll,
			name = "Set_" .. setView.id,
			layoutOrder = 10 + index,
			size = UDim2.new(1, 0, 0, 160),
		})
		local nameLabel = Components.Label({
			parent = card,
			name = "SetName",
			text = setView.name,
			textSize = Theme.text.body + 2,
			font = Theme.font.title,
			color = Theme.color.charcoal,
			align = Enum.TextXAlignment.Left,
		})
		local pill = Components.Pill({
			parent = card,
			name = "Progress",
			text = setView.progressText,
			fill = Theme.color.teal,
			textColor = Theme.color.white,
			textSize = Theme.text.body,
			bordered = false,
			size = UDim2.fromOffset(PILL_W, ROW_H - 2),
			anchor = Vector2.new(1, 0),
		})
		local rewardLabel = Components.Label({
			parent = card,
			name = "Reward",
			text = setView.rewardLine,
			textSize = Theme.text.body,
			font = Theme.font.bold,
			color = Theme.color.charcoalSoft,
			align = Enum.TextXAlignment.Left,
			wrap = true,
		})
		local claim = Components.Button({
			parent = card,
			name = "Claim",
			text = "CLAIM!",
			variant = "good",
			textSize = Theme.text.big,
			anchor = Vector2.new(1, 0),
			size = UDim2.fromOffset(CLAIM_W, Theme.size.touch),
		})
		local grid = make("Frame", {
			Name = "Grid",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = card,
		})

		local refs: SetRefs = {
			card = card,
			name = nameLabel,
			pill = pill,
			reward = rewardLabel,
			claim = claim,
			grid = grid,
			order = {},
			tiles = {},
		}
		for _, entry in setView.entries do
			local button = make("TextButton", {
				Name = "Tile_" .. entry.id,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = Theme.color.charcoal,
				BorderSizePixel = 0,
				Parent = grid,
			})
			rounded(button, Theme.radius.md)
			local stroke = outline(button, Theme.color.charcoalSoft, 2)
			local icon = Components.Label({
				parent = button,
				name = "Icon",
				text = "?",
				textSize = Theme.text.huge,
				position = UDim2.fromOffset(4, 4),
				size = UDim2.new(1, -8, 0, 42),
			})
			local nameText = Components.Label({
				parent = button,
				name = "Name",
				text = "???",
				textSize = Theme.text.small,
				font = Theme.font.bold,
				color = Theme.color.greyDark,
				wrap = true,
				position = UDim2.fromOffset(4, 48),
				size = UDim2.new(1, -8, 0, 30),
			})
			local countText = Components.Label({
				parent = button,
				name = "Count",
				text = "",
				textSize = Theme.text.small,
				font = Theme.font.title,
				color = Theme.color.charcoal,
				position = UDim2.new(0, 4, 1, -20),
				size = UDim2.new(1, -8, 0, 16),
			})
			table.insert(refs.order, entry.id)
			refs.tiles[entry.id] = {
				button = button,
				stroke = stroke,
				icon = icon,
				name = nameText,
				count = countText,
			}
			local entryId = entry.id
			button.Activated:Connect(function()
				Bridge.play("click")
				Components.punch(button, 0.05)
				local entry = entriesById[entryId]
				if entry then
					showDetail(entry)
				end
			end)
		end

		claim.onClick(function()
			latch[setView.id] = os.clock()
			Bridge.send("ClaimSet", setView.id)
			Bridge.play("coin")
			dirty = true
		end)
		sets[setView.id] = refs
		table.insert(setIds, setView.id)
	end

	-- Sizes and positions of everything that depends on the width or on a set being claimable.
	local function layout()
		local width = bodyWidth(root) - SCROLL_SIDE
		local pad = Theme.size.pad
		local gap = Theme.size.gap
		local gridW = width - 2 * pad
		local tipH = if width >= WIDE_FROM then LEGEND_TIP_H else LEGEND_TIP_TALL_H
		tipLabel.Size = UDim2.new(1, -2 * pad, 0, tipH)
		legendCard.Size = UDim2.new(1, 0, 0, pad + LEGEND_CHIP_H + gap + tipH + pad)
		for index, setId in setIds do
			local refs = sets[setId]
			local setView = view.sets[index]
			local count = #refs.order
			local cols = BookModel.columns(gridW, count, TILE_MIN_W, gap)
			local cell = math.floor((gridW - (cols - 1) * gap) / cols)
			local rows = math.ceil(count / cols)
			local gridH = rows * TILE_H + (rows - 1) * gap
			local rowTwo = if setView.claimable then Theme.size.touch else REWARD_H

			refs.name.Position = UDim2.fromOffset(pad, pad)
			refs.name.Size = UDim2.new(1, -(2 * pad + PILL_W + gap), 0, ROW_H)
			refs.pill.root.Position = UDim2.new(1, -pad, 0, pad)
			local rewardY = pad + ROW_H + gap
			refs.reward.Position = UDim2.fromOffset(pad, rewardY)
			refs.reward.Size = if setView.claimable
				then UDim2.new(1, -(2 * pad + CLAIM_W + gap), 0, rowTwo)
				else UDim2.new(1, -2 * pad, 0, rowTwo)
			refs.claim.root.Position = UDim2.new(1, -pad, 0, rewardY)
			refs.claim.root.Visible = setView.claimable
			local gridY = rewardY + rowTwo + gap
			refs.grid.Position = UDim2.fromOffset(pad, gridY)
			refs.grid.Size = UDim2.new(1, -2 * pad, 0, gridH)
			refs.card.Size = UDim2.new(1, 0, 0, gridY + gridH + pad)

			local used = cols * cell + (cols - 1) * gap
			local left = math.max(0, math.floor((gridW - used) / 2))
			for i, entryId in refs.order do
				local tile = refs.tiles[entryId]
				local col = (i - 1) % cols
				local row = (i - 1) // cols
				tile.button.Position =
					UDim2.fromOffset(left + col * (cell + gap), row * (TILE_H + gap))
				tile.button.Size = UDim2.fromOffset(cell, TILE_H)
			end
		end
	end

	local layoutKey = ""

	local function render()
		dirty = false
		local source = Bridge.view()
		local derived = source.derived
		local luck = if type(derived) == "table" then (derived :: any).luck else 1
		view = BookModel.build(source, luck)

		foundLabel.Text = view.headerText
		foundBar.set(view.fraction)
		tipLabel.Text = view.tipText
		for _, setView in view.sets do
			for _, entry in setView.entries do
				entriesById[entry.id] = entry
			end
		end
		for _, entry in view.legend do
			local chip = chips[entry.id]
			if chip then
				chip.odds.Text = if entry.yourOddsText
					then `{entry.oddsText} ({entry.yourOddsText})`
					else entry.oddsText
			end
		end

		local now = os.clock()
		local keyParts: { string } = {}
		for _, setView in view.sets do
			local refs = sets[setView.id]
			if refs then
				refs.name.Text = setView.name
				refs.pill.setText(setView.progressText)
				refs.pill.setFill(
					if setView.complete then Theme.color.green else Theme.color.teal,
					0
				)
				refs.reward.Text = if setView.claimed
					then `✔ {setView.rewardText}`
					else setView.rewardLine
				refs.reward.TextColor3 = if setView.claimed
					then Theme.color.greenDark
					elseif setView.claimable then Theme.color.lavaDark
					else Theme.color.charcoalSoft
				local tappedAt = latch[setView.id]
				local waiting = tappedAt ~= nil and now - tappedAt < CLAIM_LATCH
				refs.claim.setEnabled(setView.claimable and not waiting)
				table.insert(keyParts, if setView.claimable then "1" else "0")

				for _, entry in setView.entries do
					local tile = refs.tiles[entry.id]
					if tile then
						local color = Color3.fromHex(entry.colorHex)
						if entry.found then
							tile.button.BackgroundColor3 = color:Lerp(Theme.color.white, PASTEL)
							tile.stroke.Color = color
							tile.stroke.Thickness = Theme.size.strokeThick
							tile.icon.Text = entry.icon
							tile.icon.TextColor3 = Theme.color.charcoal
							tile.name.Text = entry.shownName
							tile.name.TextColor3 = Theme.color.charcoal
							tile.count.Text = entry.countText
						else
							tile.button.BackgroundColor3 = Theme.color.charcoal
							tile.stroke.Color = Theme.color.charcoalSoft
							tile.stroke.Thickness = Theme.size.stroke
							tile.icon.Text = "?"
							tile.icon.TextColor3 = Theme.color.charcoalSoft
							tile.name.Text = "???"
							tile.name.TextColor3 = Theme.color.greyDark
							tile.count.Text = ""
						end
					end
				end
			end
		end
		local key = table.concat(keyParts, "")
		if key ~= layoutKey then
			layoutKey = key
			layout()
		end
	end

	-- first paint now; later changes arrive through the store
	render()
	live.watch({ "finds", "setsClaimed", "derived" }, function()
		dirty = true
	end)
	live.every(0.1, function()
		if dirty then
			render()
		end
	end)
	-- a CLAIM that never got answered turns green again after the latch
	live.every(CLAIM_LATCH, function()
		if next(latch) ~= nil then
			dirty = true
		end
	end)

	if root ~= nil then
		table.insert(
			conns,
			root:GetPropertyChangedSignal("Size"):Connect(function()
				layout()
			end)
		)
	end

	return function()
		live.destroy()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
	end
end

local def: PanelHost.Def = {
	id = ID,
	title = "Finds Book",
	icon = "📖",
	order = 50,
	build = build,
}
PanelHost.register(def)

return def
