--!strict
-- Goals panel (id "goals"): one card per goal with a progress bar, the reward, and a big CLAIM
-- button once the target is reached. Goals you can claim come first, finished goals shrink to
-- one line at the bottom. All words and numbers come from shared/Ui/GoalsModel; the server pays.
--
-- Registers itself with PanelHost when required. The red dot on the menu button is kept up to date
-- all the time (also while the panel is closed) through Hud.setBadge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GoalsModel = require(Shared.Ui.GoalsModel)
local Bridge = require(script.Parent.Parent.Ui.Bridge)
local Components = require(script.Parent.Parent.Ui.Components)
local PanelHost = require(script.Parent.Parent.Ui.PanelHost)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Context = require(script.Parent.Parent.Hud.Context)

local ID = "goals"

-- layout numbers (virtual px)
local BODY_SIDE = 12 -- PanelHost pads the body by this much left and right
local SCROLL_SIDE = 14 -- ScrollList padding left 4 + right 4 + 6 for the scroll bar
local HEADER_H = 46
local WIDE_FROM = 480 -- cards are one row of columns from this width up, stacked below it
local CLAIM_W = 104
local WIDE_RIGHT_W = 140
local NARROW_REWARD_W = 100
local BAR_H = 18
local COMPACT_H = 34
local SECTION_H = 22
local CLAIM_LATCH = 1.5 -- seconds a CLAIM button stays grey after a tap (the server answers meanwhile)

type CardRefs = {
	card: Frame,
	stroke: UIStroke?,
	icon: TextLabel,
	name: TextLabel,
	desc: TextLabel,
	bar: Components.Bar,
	reward: TextLabel,
	claim: Components.Button,
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
local badgeDirty = true
local badgeTicks = 0
badgeLive.watch({ "stats", "goalsClaimed" }, function()
	badgeDirty = true -- stats change while sweeping: the 4 Hz tick below does the work
end)
badgeLive.every(0.25, function()
	badgeTicks += 1
	-- every 8th tick (2 s) say it again even if nothing changed: the HUD may be built later
	if badgeDirty or badgeTicks % 8 == 0 then
		badgeDirty = false
		setHudBadge(GoalsModel.badge(Bridge.view()))
	end
end)

-- ===== the panel =====
local function build(parent: Frame, _ctx: PanelHost.Ctx): (() -> ())?
	local live = Context.new()
	local conns: { RBXScriptConnection } = {}
	local root = panelRoot(parent)

	local view: GoalsModel.View = GoalsModel.build(Bridge.view())
	local dirty = true
	local latch: { [string]: number } = {} -- goal id -> os.clock() of the last CLAIM tap
	local firstPaint = true

	-- ---- header ----
	local header = make("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, HEADER_H),
		Parent = parent,
	})
	local headLabel = Components.Label({
		parent = header,
		name = "Head",
		text = view.headerText,
		textSize = Theme.text.big,
		font = Theme.font.title,
		color = Theme.color.charcoal,
		align = Enum.TextXAlignment.Left,
		size = UDim2.new(1, 0, 0, 26),
	})
	local headBar = Components.Bar({
		parent = header,
		name = "HeadBar",
		position = UDim2.fromOffset(0, 30),
		size = UDim2.new(1, 0, 0, 14),
		fill = Theme.color.teal,
	})

	local list = Components.ScrollList({
		parent = parent,
		name = "Goals",
		position = UDim2.fromOffset(0, HEADER_H + Theme.size.gap),
		size = UDim2.new(1, 0, 1, -(HEADER_H + Theme.size.gap)),
	})
	local scroll = list.root

	local doneLabel = Components.Label({
		parent = scroll,
		name = "DoneTitle",
		text = "Finished goals",
		textSize = Theme.text.body,
		font = Theme.font.bold,
		color = Theme.color.charcoalSoft,
		align = Enum.TextXAlignment.Left,
		size = UDim2.new(1, 0, 0, SECTION_H),
		layoutOrder = 0,
	})
	doneLabel.Visible = false

	-- ---- one card per goal (built once, restyled on every change) ----
	local cards: { [string]: CardRefs } = {}
	for _, data in view.cards do
		local card = Components.Card({
			parent = scroll,
			name = "Goal_" .. data.id,
			size = UDim2.new(1, 0, 0, 80),
		})
		local icon = Components.Label({
			parent = card,
			name = "Icon",
			text = data.icon,
			textSize = Theme.text.huge,
		})
		local nameLabel = Components.Label({
			parent = card,
			name = "GoalName",
			text = data.name,
			textSize = Theme.text.big,
			font = Theme.font.title,
			color = Theme.color.charcoal,
			align = Enum.TextXAlignment.Left,
		})
		local descLabel = Components.Label({
			parent = card,
			name = "Desc",
			text = data.desc,
			textSize = Theme.text.small,
			font = Theme.font.body,
			color = Theme.color.charcoalSoft,
			align = Enum.TextXAlignment.Left,
		})
		local bar = Components.Bar({
			parent = card,
			name = "Progress",
			fill = Theme.color.teal,
			text = data.progressText,
		})
		local rewardLabel = Components.Label({
			parent = card,
			name = "Reward",
			text = data.rewardText,
			textSize = Theme.text.body,
			font = Theme.font.title,
			color = Theme.color.goldDark,
			align = Enum.TextXAlignment.Right,
			anchor = Vector2.new(1, 0),
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
		local goalId = data.id
		claim.onClick(function()
			latch[goalId] = os.clock()
			Bridge.send("ClaimGoal", goalId)
			Bridge.play("coin")
			dirty = true
		end)
		cards[data.id] = {
			card = card,
			stroke = card:FindFirstChild("UIStroke") :: UIStroke?,
			icon = icon,
			name = nameLabel,
			desc = descLabel,
			bar = bar,
			reward = rewardLabel,
			claim = claim,
		}
	end

	-- Style and place one card for its current state and the current width.
	local function place(refs: CardRefs, data: GoalsModel.Card, wide: boolean, waiting: boolean)
		local pad = Theme.size.pad
		local gap = Theme.size.gap
		local ready = data.status == "ready"
		local claimed = data.status == "claimed"

		refs.name.Text = data.name
		refs.desc.Text = data.desc
		refs.icon.Text = data.icon
		refs.reward.Text = if claimed then "✔ Got it!" else data.rewardText
		refs.reward.TextColor3 = if claimed then Theme.color.greenDark else Theme.color.goldDark
		refs.bar.setText(data.progressText)
		refs.bar.set(data.fraction, not firstPaint)
		refs.bar.setColor(if ready then Theme.color.green else Theme.color.teal)
		refs.claim.root.Visible = ready
		refs.claim.setEnabled(ready and not waiting)

		refs.card.BackgroundColor3 = if ready
			then Theme.color.goldLight:Lerp(Theme.color.creamLight, 0.5)
			elseif claimed then Theme.color.creamDark
			else Theme.color.creamLight
		refs.name.TextColor3 = if claimed then Theme.color.charcoalSoft else Theme.color.charcoal
		local stroke = refs.stroke
		if stroke then
			stroke.Color = if ready then Theme.color.lava else Theme.color.parchmentLine
			stroke.Thickness = if ready then Theme.size.strokeThick else Theme.size.stroke
		end

		refs.desc.Visible = not claimed
		refs.bar.root.Visible = not claimed

		if claimed then
			refs.card.Size = UDim2.new(1, 0, 0, COMPACT_H)
			refs.icon.Position = UDim2.fromOffset(pad, 3)
			refs.icon.Size = UDim2.fromOffset(28, 28)
			refs.name.Position = UDim2.fromOffset(40, 0)
			refs.name.Size = UDim2.new(1, -(40 + pad + NARROW_REWARD_W + gap), 1, 0)
			refs.reward.Position = UDim2.new(1, -pad, 0, 0)
			refs.reward.Size = UDim2.fromOffset(NARROW_REWARD_W, COMPACT_H)
		elseif wide then
			refs.card.Size = UDim2.new(1, 0, 0, if ready then 80 else 72)
			refs.icon.Position = UDim2.fromOffset(pad, 0)
			refs.icon.Size = UDim2.new(0, 44, 1, 0)
			local textW = UDim2.new(1, -(58 + pad + WIDE_RIGHT_W), 0, 22)
			refs.name.Position = UDim2.fromOffset(58, 6)
			refs.name.Size = textW
			refs.desc.Position = UDim2.fromOffset(58, 28)
			refs.desc.Size = UDim2.new(1, -(58 + pad + WIDE_RIGHT_W), 0, 16)
			refs.bar.root.Position = UDim2.fromOffset(58, 48)
			refs.bar.root.Size = UDim2.new(1, -(58 + pad + WIDE_RIGHT_W), 0, BAR_H)
			refs.reward.Position = UDim2.new(1, -pad, 0, 6)
			refs.reward.Size = UDim2.fromOffset(WIDE_RIGHT_W - pad, 22)
			refs.claim.root.Position = UDim2.new(1, -pad, 0, 30)
		else
			refs.card.Size = UDim2.new(1, 0, 0, if ready then 106 else 84)
			refs.icon.Position = UDim2.fromOffset(pad, 6)
			refs.icon.Size = UDim2.fromOffset(28, 28)
			refs.name.Position = UDim2.fromOffset(40, 6)
			refs.name.Size = UDim2.new(1, -(40 + pad + NARROW_REWARD_W + gap), 0, 24)
			refs.reward.Position = UDim2.new(1, -pad, 0, 6)
			refs.reward.Size = UDim2.fromOffset(NARROW_REWARD_W, 24)
			refs.desc.Position = UDim2.fromOffset(pad, 34)
			refs.desc.Size = UDim2.new(1, -2 * pad, 0, 16)
			refs.bar.root.Position = UDim2.fromOffset(pad, if ready then 67 else 58)
			refs.bar.root.Size =
				UDim2.new(1, -(2 * pad + (if ready then CLAIM_W + gap else 0)), 0, BAR_H)
			refs.claim.root.Position = UDim2.new(1, -pad, 0, 54)
		end
	end

	local function render()
		dirty = false
		view = GoalsModel.build(Bridge.view())
		local wide = bodyWidth(root) - SCROLL_SIDE >= WIDE_FROM
		local now = os.clock()

		headLabel.Text = view.headerText
		headLabel.TextColor3 = if view.readyCount > 0
			then Theme.color.lavaDark
			else Theme.color.charcoal
		headBar.set(view.claimedCount / math.max(1, view.total), not firstPaint)

		local firstClaimed = 0
		for index, data in view.cards do
			local refs = cards[data.id]
			if refs then
				local tappedAt = latch[data.id]
				local waiting = tappedAt ~= nil and now - tappedAt < CLAIM_LATCH
				place(refs, data, wide, waiting)
				refs.card.LayoutOrder = index * 10
				if data.status == "claimed" and firstClaimed == 0 then
					firstClaimed = index
				end
			end
		end
		doneLabel.Visible = firstClaimed > 0
		if firstClaimed > 0 then
			doneLabel.LayoutOrder = firstClaimed * 10 - 5
		end
		firstPaint = false
	end

	render()
	live.watch({ "stats", "goalsClaimed" }, function()
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
				dirty = true
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
	title = "Goals",
	icon = "🎯",
	order = 60,
	build = build,
}
PanelHost.register(def)

return def
