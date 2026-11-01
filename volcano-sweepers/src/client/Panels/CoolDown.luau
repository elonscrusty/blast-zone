--!strict
-- Cool Down panel (id "cooldown"): two tabs.
--   Cool Down   what it is, what you keep and what starts over, the Sparks you would get, a bar to
--               the first allowed Cool Down, and one big lava button that needs TWO taps (the second
--               one after a 1 second wait) before the server is ever asked.
--               The button never scrolls: it lives in a pinned footer (a right-hand column on a
--               landscape phone, the bottom on portrait) with one line of text above it that
--               explains it. Arming shows "Not now" in a slot ABOVE the button, so the button
--               itself never moves between the first and the second tap.
--   Spark Shop  spend Sparks on forever perks (Buy "sparkPerk"), see your Sparks and your coin bonus.
-- All words and numbers come from shared/Ui/CoolDownModel. The server checks every rule again.
-- The menu's red dot (Cool Down possible) comes from the HUD.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoolDownModel = require(Shared.Ui.CoolDownModel)
local Bridge = require(script.Parent.Parent.Ui.Bridge)
local Components = require(script.Parent.Parent.Ui.Components)
local PanelHost = require(script.Parent.Parent.Ui.PanelHost)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Context = require(script.Parent.Parent.Hud.Context)
local PanelKit = require(script.Parent.Shared.PanelKit)

local ID = "cooldown"

-- layout numbers (virtual px)
local SCROLL_SIDE = 14 -- ScrollList padding left 4 + right 4 + 6 for the scroll bar
local WIDE_FROM = 480 -- two columns from this width up
local TABS_H = Theme.size.touch
local ROW_H = 22 -- one line in a keep/reset list
local LIST_TITLE_H = 24
local LIST_CARD_H = 8 + LIST_TITLE_H + 5 * ROW_H + 8 -- room for the longer list (5 rows)
local BIG_H = 56 -- the big lava button
local INFO_H = 52 -- the one line above it (portrait)
local FOOT_W = 210 -- landscape: width of the pinned action column
local NOT_NOW_H = Theme.size.button
local PERK_H = 92
local PERK_BUTTON_W = Theme.size.claimW
local DONE_SHOW_SECONDS = 8
local SENT_LATCH = 3 -- seconds the big button stays grey after the CoolDown message went out
local BUY_LATCH = 1 -- seconds a perk button stays grey after a tap
local SOFT = 0.8 -- how much white goes into a colour for a quiet card background

type PerkRefs = {
	card: Frame,
	name: TextLabel,
	desc: TextLabel,
	effect: TextLabel,
	pips: Components.Pips,
	buy: Components.CostButton,
}

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

-- A card with a title and one line per item ("keep" and "start over" lists).
local function itemCard(
	parent: Instance,
	name: string,
	title: string,
	titleColor: Color3,
	fill: Color3,
	items: { CoolDownModel.Item }
): Frame
	local card = Components.Card({ parent = parent, name = name, color = fill })
	Components.Label({
		parent = card,
		name = "Title",
		text = title,
		textSize = Theme.text.big,
		font = Theme.font.title,
		color = titleColor,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(Theme.size.pad, Theme.size.pad),
		size = UDim2.new(1, -2 * Theme.size.pad, 0, LIST_TITLE_H),
	})
	for i, item in items do
		Components.Label({
			parent = card,
			name = "Item" .. i,
			text = `{item.icon}  {item.text}`,
			textSize = Theme.text.body,
			font = Theme.font.bold,
			color = Theme.color.charcoal,
			align = Enum.TextXAlignment.Left,
			position = UDim2.fromOffset(
				Theme.size.pad,
				Theme.size.pad + LIST_TITLE_H + (i - 1) * ROW_H
			),
			size = UDim2.new(1, -2 * Theme.size.pad, 0, ROW_H),
		})
	end
	return card
end

local function build(parent: Frame, ctx: PanelHost.Ctx): (() -> ())?
	local live = Context.new()
	local conns: { RBXScriptConnection } = {}

	local view: CoolDownModel.View = CoolDownModel.build(Bridge.view())
	local confirm = CoolDownModel.newConfirm()
	local dirty = true
	local sentAt: number? = nil
	local doneUntil = 0
	local buyLatch: { [string]: number } = {}
	local page = "cool"

	-- ---- tabs ----
	local tabs: Components.Tabs
	local pageTop = TABS_H + Theme.size.gap
	local coolList = Components.ScrollList({
		parent = parent,
		name = "CoolPage",
		position = UDim2.fromOffset(0, pageTop),
		size = UDim2.new(1, 0, 1, -pageTop),
	})
	local shopList = Components.ScrollList({
		parent = parent,
		name = "ShopPage",
		position = UDim2.fromOffset(0, pageTop),
		size = UDim2.new(1, 0, 1, -pageTop),
	})
	shopList.root.Visible = false

	local footerRef: Frame? = nil
	local function showPage(id: string)
		page = id
		coolList.root.Visible = id == "cool"
		shopList.root.Visible = id == "shop"
		if footerRef then
			footerRef.Visible = id == "cool"
		end
	end
	tabs = Components.Tabs({
		parent = parent,
		name = "Tabs",
		tabs = {
			{ id = "cool", text = "Cool Down", icon = "❄️" },
			{ id = "shop", text = "Spark Shop", icon = "✨" },
		},
		selected = page,
		onSelect = showPage,
	})

	-- ================= page 1: Cool Down =================
	local cool = coolList.root

	local doneCard = Components.Card({
		parent = cool,
		name = "Done",
		color = Theme.color.green:Lerp(Theme.color.white, SOFT),
		layoutOrder = 1,
		size = UDim2.new(1, 0, 0, 44),
	})
	local doneLabel = Components.Label({
		parent = doneCard,
		name = "DoneText",
		text = "",
		textSize = Theme.text.body,
		font = Theme.font.title,
		color = Theme.color.greenDeep,
		wrap = true,
		position = UDim2.fromOffset(Theme.size.pad, 2),
		size = UDim2.new(1, -2 * Theme.size.pad, 1, -4),
	})
	doneCard.Visible = false

	-- what it is
	local hero = Components.Card({
		parent = cool,
		name = "Hero",
		color = Theme.color.lava:Lerp(Theme.color.white, SOFT),
		layoutOrder = 2,
		size = UDim2.new(1, 0, 0, 100),
	})
	Components.Label({
		parent = hero,
		name = "Snow",
		text = "❄️",
		textSize = Theme.text.huge,
		position = UDim2.fromOffset(Theme.size.pad, Theme.size.pad),
		size = UDim2.fromOffset(44, 44),
	})
	Components.Label({
		parent = hero,
		name = "HeroTitle",
		text = view.title,
		textSize = Theme.text.title - 4,
		font = Theme.font.title,
		color = Theme.color.lavaDark,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(60, Theme.size.pad),
		size = UDim2.new(1, -(60 + Theme.size.pad), 0, 28),
	})
	local heroText = Components.Label({
		parent = hero,
		name = "HeroText",
		text = view.explain,
		textSize = Theme.text.body,
		font = Theme.font.bold,
		color = Theme.color.charcoal,
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		wrap = true,
		position = UDim2.fromOffset(60, Theme.size.pad + 30),
		size = UDim2.new(1, -(60 + Theme.size.pad), 0, 56),
	})

	-- Sparks you would get + progress
	local status = Components.Card({
		parent = cool,
		name = "Status",
		layoutOrder = 3,
		size = UDim2.new(1, 0, 0, 92),
	})
	local sparksLabel = Components.Label({
		parent = status,
		name = "Sparks",
		text = view.sparksText,
		textSize = Theme.text.title - 4,
		font = Theme.font.title,
		color = Theme.color.charcoal,
		position = UDim2.fromOffset(Theme.size.pad, Theme.size.pad),
		size = UDim2.new(1, -2 * Theme.size.pad, 0, 28),
	})
	local progress = Components.Bar({
		parent = status,
		name = "Progress",
		fill = Theme.color.lava,
		text = view.progressText,
		position = UDim2.fromOffset(Theme.size.pad, Theme.size.pad + 34),
		size = UDim2.new(1, -2 * Theme.size.pad, 0, 20),
	})
	local noteLabel = Components.Label({
		parent = status,
		name = "Note",
		text = view.note,
		textSize = Theme.text.body,
		font = Theme.font.bold,
		color = Theme.color.charcoalSoft,
		wrap = true,
		position = UDim2.fromOffset(Theme.size.pad, Theme.size.pad + 60),
		size = UDim2.new(1, -2 * Theme.size.pad, 0, 20),
	})

	-- keep / start over
	local listsFrame = make("Frame", {
		Name = "Lists",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, LIST_CARD_H),
		LayoutOrder = 4,
		Parent = cool,
	})
	local listsLayout = make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Theme.size.gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = listsFrame,
	})
	local keepCard = itemCard(
		listsFrame,
		"Keep",
		"You keep ✔",
		Theme.color.greenDark,
		Theme.color.green:Lerp(Theme.color.white, SOFT),
		view.keep
	)
	keepCard.LayoutOrder = 1
	local resetCard = itemCard(
		listsFrame,
		"Reset",
		"Starts over ↺",
		Theme.color.lavaDark,
		Theme.color.lava:Lerp(Theme.color.white, SOFT),
		view.reset
	)
	resetCard.LayoutOrder = 2

	-- the pinned footer: one line that explains the button, the "Not now" slot, the big button
	local footer = make("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = parent,
	})
	local infoCard = Components.Card({
		parent = footer,
		name = "Info",
		color = Theme.color.goldLight:Lerp(Theme.color.white, 0.4),
	})
	local warnLabel = Components.Label({
		parent = infoCard,
		name = "InfoText",
		text = "",
		textSize = Theme.text.body,
		font = Theme.font.bold,
		color = Theme.color.charcoal,
		wrap = true,
		position = UDim2.fromOffset(Theme.size.pad, 2),
		size = UDim2.new(1, -2 * Theme.size.pad, 1, -4),
	})
	local main = Components.Button({
		parent = footer,
		name = "CoolDownButton",
		text = "COOL DOWN",
		variant = "primary",
		textSize = Theme.text.title,
	})
	local cancel = Components.Button({
		parent = footer,
		name = "NotNow",
		text = "Not now",
		variant = "neutral",
		textSize = Theme.text.big,
	})
	cancel.root.Visible = false

	-- ================= page 2: Spark Shop =================
	local shop = shopList.root
	local bank = Components.Card({
		parent = shop,
		name = "Bank",
		color = Theme.color.goldLight:Lerp(Theme.color.white, 0.5),
		layoutOrder = 1,
		size = UDim2.new(1, 0, 0, 68),
	})
	local bankLabel = Components.Label({
		parent = bank,
		name = "BankSparks",
		text = view.sparksBalanceText,
		textSize = Theme.text.title - 4,
		font = Theme.font.title,
		color = Theme.color.charcoal,
		position = UDim2.fromOffset(Theme.size.pad, Theme.size.pad),
		size = UDim2.new(1, -2 * Theme.size.pad, 0, 28),
	})
	local bonusLabel = Components.Label({
		parent = bank,
		name = "Bonus",
		text = view.bonusText,
		textSize = Theme.text.body,
		font = Theme.font.bold,
		color = Theme.color.tealDark,
		position = UDim2.fromOffset(Theme.size.pad, Theme.size.pad + 32),
		size = UDim2.new(1, -2 * Theme.size.pad, 0, 20),
	})

	local perkRefs: { [string]: PerkRefs } = {}
	for index, perk in view.perks do
		local card = Components.Card({
			parent = shop,
			name = "Perk_" .. perk.id,
			layoutOrder = 10 + index,
			size = UDim2.new(1, 0, 0, PERK_H),
		})
		local textW = UDim2.new(1, -(3 * Theme.size.pad + PERK_BUTTON_W), 0, 22)
		local nameLabel = Components.Label({
			parent = card,
			name = "PerkName",
			text = perk.name,
			textSize = Theme.text.big,
			font = Theme.font.title,
			color = Theme.color.charcoal,
			align = Enum.TextXAlignment.Left,
			position = UDim2.fromOffset(Theme.size.pad, 5),
			size = textW,
		})
		local descLabel = Components.Label({
			parent = card,
			name = "PerkDesc",
			text = perk.desc,
			textSize = Theme.text.small,
			font = Theme.font.body,
			color = Theme.color.charcoalSoft,
			align = Enum.TextXAlignment.Left,
			valign = Enum.TextYAlignment.Top,
			wrap = true,
			position = UDim2.fromOffset(Theme.size.pad, 28),
			size = UDim2.new(1, -(3 * Theme.size.pad + PERK_BUTTON_W), 0, 28),
		})
		local effectLabel = Components.Label({
			parent = card,
			name = "PerkEffect",
			text = "",
			textSize = Theme.text.small,
			font = Theme.font.bold,
			color = Theme.color.tealDark,
			align = Enum.TextXAlignment.Left,
			valign = Enum.TextYAlignment.Top,
			wrap = true,
			position = UDim2.fromOffset(Theme.size.pad, 58),
			size = UDim2.new(1, -(3 * Theme.size.pad + PERK_BUTTON_W), 0, 30),
		})
		local pips = Components.Pips({
			parent = card,
			name = "Level",
			total = perk.maxLevel,
			filled = perk.level,
			color = Theme.color.gold,
			anchor = Vector2.new(1, 0),
			position = UDim2.new(1, -Theme.size.pad, 0, 62),
			size = UDim2.fromOffset(PERK_BUTTON_W, 10),
		})
		local buy = Components.CostButton({
			parent = card,
			name = "Buy",
			currency = "sparks",
			price = perk.cost,
			affordable = perk.affordable,
			label = "MAXED",
			anchor = Vector2.new(1, 0),
			position = UDim2.new(1, -Theme.size.pad, 0, Theme.size.pad),
			size = UDim2.fromOffset(PERK_BUTTON_W, Theme.size.touch),
		})
		local perkId = perk.id
		buy.onBuy(function()
			buyLatch[perkId] = os.clock()
			Bridge.send("Buy", "sparkPerk", perkId)
			Bridge.play("upgrade")
			dirty = true
		end)
		buy.onBlocked(function()
			for _, p in view.perks do
				if p.id == perkId then
					if p.maxed then
						ctx.toast("Maxed out!", "info")
					elseif p.cost ~= nil then
						ctx.toast(`Need {math.max(1, p.cost - view.sparks)} more Sparks`, "warn")
					end
				end
			end
		end)
		perkRefs[perk.id] = {
			card = card,
			name = nameLabel,
			desc = descLabel,
			effect = effectLabel,
			pips = pips,
			buy = buy,
		}
	end

	-- ================= layout and drawing =================
	footerRef = footer
	local bodySize = Vector2.new(312, 400)
	local armedShown = false

	-- The big button sits at the very bottom of the footer and never moves. Above it: the
	-- "Not now" slot (only while armed), and the info line takes whatever is left.
	local function placeFooter()
		local gap = Theme.size.gap
		local w, h = bodySize.X, bodySize.Y - pageTop
		local side = w >= PanelKit.WIDE_FROM
		local footH: number
		local footW: number
		if side then
			footW = FOOT_W
			footH = h
			footer.Position = UDim2.new(1, -FOOT_W, 0, pageTop)
			coolList.root.Size = UDim2.new(1, -(FOOT_W + gap), 1, -pageTop)
		else
			footW = w
			footH = INFO_H + gap + BIG_H + (if armedShown then NOT_NOW_H + gap else 0)
			footer.Position = UDim2.new(0, 0, 1, -footH)
			coolList.root.Size = UDim2.new(1, 0, 1, -(pageTop + footH + gap))
		end
		footer.Size = UDim2.fromOffset(footW, footH)
		main.root.Position = UDim2.new(0, 0, 1, -BIG_H)
		main.root.Size = UDim2.new(1, 0, 0, BIG_H)
		local slotY = footH - BIG_H - gap - NOT_NOW_H
		cancel.root.Position = UDim2.fromOffset(0, slotY)
		cancel.root.Size = UDim2.new(1, 0, 0, NOT_NOW_H)
		local infoBottom = if armedShown then slotY - gap else footH - BIG_H - gap
		infoCard.Position = UDim2.new()
		infoCard.Size = UDim2.new(1, 0, 0, math.max(Theme.size.touch, infoBottom))
	end

	local function layout()
		local wide = bodySize.X
				- (if bodySize.X >= PanelKit.WIDE_FROM then FOOT_W else 0)
				- SCROLL_SIDE
			>= WIDE_FROM
		hero.Size = UDim2.new(1, 0, 0, if wide then 84 else 106)
		heroText.Size = UDim2.new(1, -(60 + Theme.size.pad), 0, if wide then 40 else 62)
		if wide then
			listsLayout.FillDirection = Enum.FillDirection.Horizontal
			listsFrame.Size = UDim2.new(1, 0, 0, LIST_CARD_H)
			keepCard.Size = UDim2.new(0.5, -Theme.size.gap / 2, 0, LIST_CARD_H)
			resetCard.Size = UDim2.new(0.5, -Theme.size.gap / 2, 0, LIST_CARD_H)
		else
			listsLayout.FillDirection = Enum.FillDirection.Vertical
			listsFrame.Size = UDim2.new(1, 0, 0, 2 * LIST_CARD_H + Theme.size.gap)
			keepCard.Size = UDim2.new(1, 0, 0, LIST_CARD_H)
			resetCard.Size = UDim2.new(1, 0, 0, LIST_CARD_H)
		end
		placeFooter()
	end

	local function render()
		dirty = false
		view = CoolDownModel.build(Bridge.view())
		local now = os.clock()

		-- Cool Down page
		sparksLabel.Text = view.sparksText
		noteLabel.Text = view.note
		noteLabel.TextColor3 = if view.canCoolDown
			then Theme.color.tealDark
			else Theme.color.charcoalSoft
		progress.root.Visible = not view.canCoolDown
		progress.set(view.fraction)
		progress.setText(view.progressText)

		local cv = CoolDownModel.confirmView(confirm, now, view.canCoolDown)
		local cooling = sentAt ~= nil and now - sentAt < SENT_LATCH
		cancel.root.Visible = cv.warn
		if armedShown ~= cv.warn then
			armedShown = cv.warn
			placeFooter()
		end
		if cooling then
			main.setText("Cooling down...")
			main.setEnabled(false)
		else
			main.setText(cv.text)
			main.setVariant(if cv.armed then "danger" else "primary")
			main.setEnabled(cv.enabled)
		end
		warnLabel.Text = CoolDownModel.footerText(view, cv.warn)

		-- Spark Shop page
		bankLabel.Text = view.sparksBalanceText
		bonusLabel.Text = `Your Sparks give you {view.bonusText}`
		for _, perk in view.perks do
			local refs = perkRefs[perk.id]
			if refs then
				refs.effect.Text = if perk.nextText ~= ""
					then `{perk.nowText}\n{perk.nextText}`
					else perk.nowText
				refs.pips.set(perk.level, perk.maxLevel)
				local tapped = buyLatch[perk.id]
				local waiting = tapped ~= nil and now - tapped < BUY_LATCH
				refs.buy.set(perk.cost, perk.affordable and not waiting, "MAXED")
			end
		end
		tabs.setBadge("shop", view.perkAffordable)

		if doneUntil > 0 and now > doneUntil then
			doneUntil = 0
			doneCard.Visible = false
		end
	end

	main.onClick(function()
		local act = CoolDownModel.tap(confirm, os.clock(), view.canCoolDown)
		if act == "send" then
			sentAt = os.clock()
			Bridge.send("CoolDown")
		end
		dirty = true
	end)
	main.onBlocked(function()
		-- grey button: tell kids why (during the 1 second wait it just wiggles)
		if not view.canCoolDown and view.remainingText ~= "" then
			ctx.toast(view.remainingText, "info")
		end
	end)
	cancel.onClick(function()
		CoolDownModel.cancel(confirm)
		dirty = true
	end)

	local stopSize = PanelKit.watchSize(parent, function(size: Vector2)
		bodySize = size
		layout()
	end)
	render()
	live.watch({ "runCoins", "sparks", "coolDowns", "sparkPerks" }, function()
		dirty = true
	end)
	live.listen("CoolDownDone", function(payload: any)
		local gained = 0
		if type(payload) == "table" and type((payload :: any).sparksGained) == "number" then
			gained = (payload :: any).sparksGained
		end
		doneLabel.Text = CoolDownModel.doneText(gained)
		doneCard.Visible = true
		doneUntil = os.clock() + DONE_SHOW_SECONDS
		CoolDownModel.cancel(confirm)
		Components.punch(doneCard, 0.04)
		dirty = true
	end)
	live.every(0.1, function()
		-- while the confirm step is armed the button changes with time, not with the store
		if dirty or confirm.armedAt ~= nil or sentAt ~= nil or doneUntil > 0 then
			render()
			if sentAt ~= nil and os.clock() - sentAt >= SENT_LATCH then
				sentAt = nil
			end
		end
	end)

	return function()
		stopSize()
		live.destroy()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
	end
end

local def: PanelHost.Def = {
	id = ID,
	title = "Cool Down",
	icon = "❄️",
	order = 80,
	build = build,
}
PanelHost.register(def)

return def
