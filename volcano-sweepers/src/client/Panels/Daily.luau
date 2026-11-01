--!strict
-- Daily Gift panel (id "daily"): seven gift tiles (day 7 is the big prize), today's tile glows,
-- finished days get a tick, and one big CLAIM button that only works when a gift is waiting.
-- The server decides the day and pays; the client only previews with the same rules
-- (shared/Player/DailyRules through shared/Ui/DailyModel). The menu's red dot comes from the HUD.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DailyModel = require(Shared.Ui.DailyModel)
local Bridge = require(script.Parent.Parent.Ui.Bridge)
local Components = require(script.Parent.Parent.Ui.Components)
local PanelHost = require(script.Parent.Parent.Ui.PanelHost)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Context = require(script.Parent.Parent.Hud.Context)

local ID = "daily"

-- layout numbers (virtual px)
local BODY_SIDE = 12 -- PanelHost pads the body by this much left and right
local SCROLL_SIDE = 14 -- ScrollList padding left 4 + right 4 + 6 for the scroll bar
local CLAIM_H = 48
local CLAIM_MAX_W = 360
local COUNTDOWN_H = 18
local TIGHT = 4 -- gaps in this panel are tight: it has to fit a phone held sideways
local BOTTOM_H = CLAIM_H + TIGHT + COUNTDOWN_H
local STREAK_H = 26
local INFO_H = 20
local INFO_TALL_H = 36 -- room for two lines when the panel is narrow
local NARROW = 420
local CLAIM_LATCH = 1.5 -- seconds the button stays grey after a tap (the server answers meanwhile)
local SOFT = 0.72 -- how much white goes into a colour for a quiet tile background

type TileRefs = {
	root: Frame,
	stroke: UIStroke,
	day: TextLabel,
	icon: TextLabel,
	reward: TextLabel,
	state: TextLabel,
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

-- Unix seconds. The server's clock when we can have it (a phone's own clock can be wrong).
local function nowUnix(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" and t > 1e9 then
		return t
	end
	return os.time()
end

local function build(parent: Frame, ctx: PanelHost.Ctx): (() -> ())?
	local live = Context.new()
	local conns: { RBXScriptConnection } = {}
	local root = panelRoot(parent)

	local view: DailyModel.View = DailyModel.build(Bridge.view().daily, nowUnix())
	local dirty = true
	local tappedAt: number? = nil
	local glowing: { [number]: boolean } = {}
	local previous: DailyModel.View? = nil

	-- ---- the claim button and the countdown stay at the bottom ----
	local bottom = make("Frame", {
		Name = "Bottom",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, BOTTOM_H),
		Parent = parent,
	})
	local claim = Components.Button({
		parent = bottom,
		name = "Claim",
		text = view.buttonText,
		variant = "gold",
		textSize = Theme.text.title,
		anchor = Vector2.new(0.5, 0),
		position = UDim2.fromScale(0.5, 0),
		size = UDim2.new(1, 0, 0, CLAIM_H),
	})
	make("UISizeConstraint", {
		MaxSize = Vector2.new(CLAIM_MAX_W, CLAIM_H),
		Parent = claim.root,
	})
	local countdown = Components.Label({
		parent = bottom,
		name = "Countdown",
		text = view.countdownText,
		textSize = Theme.text.body,
		font = Theme.font.bold,
		color = Theme.color.charcoalSoft,
		position = UDim2.fromOffset(0, CLAIM_H + TIGHT),
		size = UDim2.new(1, 0, 0, COUNTDOWN_H),
	})

	local list = Components.ScrollList({
		parent = parent,
		name = "Days",
		gap = TIGHT,
		padding = 2,
		size = UDim2.new(1, 0, 1, -(BOTTOM_H + TIGHT)),
	})
	local scroll = list.root

	local streakLabel = Components.Label({
		parent = scroll,
		name = "Streak",
		text = view.streakText,
		textSize = Theme.text.big,
		font = Theme.font.title,
		color = Theme.color.lavaDark,
		size = UDim2.new(1, 0, 0, STREAK_H),
		layoutOrder = 1,
	})
	local infoLabel = Components.Label({
		parent = scroll,
		name = "Info",
		text = view.giftText,
		textSize = Theme.text.body,
		font = Theme.font.bold,
		color = Theme.color.charcoal,
		wrap = true,
		size = UDim2.new(1, 0, 0, INFO_H),
		layoutOrder = 2,
	})
	local tilesFrame = make("Frame", {
		Name = "Tiles",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 86),
		LayoutOrder = 3,
		Parent = scroll,
	})

	-- ---- seven tiles ----
	local tiles: { TileRefs } = {}
	for _, tile in view.tiles do
		local frame = make("Frame", {
			Name = "Day" .. tile.day,
			BackgroundColor3 = Theme.color.creamLight,
			BorderSizePixel = 0,
			Parent = tilesFrame,
		})
		make("UICorner", { CornerRadius = Theme.radius.md, Parent = frame })
		local stroke = make("UIStroke", {
			Color = Theme.color.parchmentLine,
			Thickness = Theme.size.stroke,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			LineJoinMode = Enum.LineJoinMode.Round,
			Parent = frame,
		})
		local dayLabel = Components.Label({
			parent = frame,
			name = "Day",
			text = tile.label,
			textSize = Theme.text.small,
			font = Theme.font.title,
			color = Theme.color.charcoal,
			position = UDim2.fromOffset(2, 3),
			size = UDim2.new(1, -4, 0, 15),
		})
		local iconLabel = Components.Label({
			parent = frame,
			name = "Icon",
			text = tile.icon,
			textSize = Theme.text.huge,
			position = UDim2.fromOffset(2, 18),
			size = UDim2.new(1, -4, 0, 30),
		})
		local rewardLabel = Components.Label({
			parent = frame,
			name = "Reward",
			text = tile.rewardText,
			textSize = Theme.text.body,
			font = Theme.font.title,
			color = Theme.color.charcoal,
			position = UDim2.fromOffset(2, 49),
			size = UDim2.new(1, -4, 0, 18),
		})
		local stateLabel = Components.Label({
			parent = frame,
			name = "State",
			text = "",
			textSize = Theme.text.small,
			font = Theme.font.title,
			color = Theme.color.charcoalSoft,
			position = UDim2.fromOffset(2, 68),
			size = UDim2.new(1, -4, 0, 15),
		})
		tiles[tile.day] = {
			root = frame,
			stroke = stroke,
			day = dayLabel,
			icon = iconLabel,
			reward = rewardLabel,
			state = stateLabel,
		}
	end

	local function layout()
		local width = bodyWidth(root) - SCROLL_SIDE
		local plan = DailyModel.tileRects(width)
		tilesFrame.Size = UDim2.new(1, 0, 0, plan.height)
		infoLabel.Size = UDim2.new(1, 0, 0, if width < NARROW then INFO_TALL_H else INFO_H)
		for day, rect in plan.rects do
			local refs = tiles[day]
			if refs then
				refs.root.Position = UDim2.fromOffset(math.floor(rect.x), math.floor(rect.y))
				refs.root.Size = UDim2.fromOffset(math.floor(rect.w), math.floor(rect.h))
			end
		end
	end

	-- Today's tile breathes: its outline grows and shrinks until it is claimed.
	local function setGlow(day: number, on: boolean)
		local refs = tiles[day]
		if refs == nil or (glowing[day] == true) == on then
			return
		end
		glowing[day] = on
		if on then
			Components.tween(
				refs.stroke,
				{ Thickness = Theme.size.strokeThick + 3 },
				TweenInfo.new(
					Theme.duration.slow * 2,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut,
					-1,
					true
				)
			)
		else
			Components.tween(refs.stroke, { Thickness = Theme.size.stroke }, Theme.ease.fast)
		end
	end

	local function render()
		dirty = false
		local daily = Bridge.view().daily
		-- before the first State arrives we know nothing: do not offer a gift we cannot see
		local loaded = type(daily) == "table"
		view = DailyModel.build(daily, nowUnix())

		streakLabel.Text = view.streakText
		infoLabel.Text = if view.noteText ~= "" then view.noteText else view.giftText
		countdown.Text = if type(daily) == "table" then view.countdownText else ""
		countdown.TextColor3 = if view.canClaim
			then Theme.color.lavaDark
			else Theme.color.charcoalSoft

		for _, tile in view.tiles do
			local refs = tiles[tile.day]
			if refs then
				refs.reward.Text = if tile.sparksText ~= ""
					then `{tile.rewardText} {tile.sparksText}`
					else tile.rewardText
				refs.state.Text = tile.stateText
				refs.icon.Text = if tile.state == "claimed" then "✔" else tile.icon
				local special = tile.special
				if tile.state == "today" then
					refs.root.BackgroundColor3 = Theme.color.goldLight
					refs.stroke.Color = Theme.color.gold
					refs.state.TextColor3 = Theme.color.lavaDark
					refs.icon.TextColor3 = Theme.color.charcoal
				elseif tile.state == "claimed" then
					refs.root.BackgroundColor3 = Theme.color.green:Lerp(Theme.color.white, SOFT)
					refs.stroke.Color = Theme.color.greenDark
					refs.state.TextColor3 = Theme.color.greenDark
					refs.icon.TextColor3 = Theme.color.greenDark
				else
					refs.root.BackgroundColor3 = if special
						then Theme.color.goldLight:Lerp(Theme.color.creamLight, 0.5)
						else Theme.color.creamLight
					refs.stroke.Color = if tile.state == "next"
						then Theme.color.teal
						elseif special then Theme.color.goldDark
						else Theme.color.parchmentLine
					refs.state.TextColor3 = if tile.state == "next"
						then Theme.color.tealDark
						else Theme.color.charcoalSoft
					refs.icon.TextColor3 = Theme.color.charcoal
				end
				setGlow(tile.day, tile.state == "today")
			end
		end

		-- the button: gold and tappable only while a gift is waiting
		local waiting = tappedAt ~= nil and os.clock() - tappedAt < CLAIM_LATCH
		claim.setText(if loaded then view.buttonText else "Loading...")
		if loaded and view.canClaim and not waiting then
			claim.setVariant("gold")
			claim.setEnabled(true)
		else
			claim.setEnabled(false)
		end

		-- a gift just got claimed: pop the tile that turned into a tick
		local before = previous
		if before ~= nil and before.canClaim and not view.canClaim and before.todayDay then
			local refs = tiles[before.todayDay]
			if refs then
				Components.punch(refs.root, 0.12)
			end
		end
		previous = view
	end

	claim.onClick(function()
		tappedAt = os.clock()
		Bridge.send("ClaimDaily")
		Bridge.play("coin")
		dirty = true
	end)
	claim.onBlocked(function()
		local why = if view.reason ~= "" then view.reason else "Come back tomorrow!"
		ctx.toast(why, "info")
	end)

	layout()
	render()
	live.watch({ "daily" }, function()
		dirty = true
	end)
	-- the countdown ticks every second (and midnight flips the button with no store change)
	live.every(1, function()
		dirty = true
	end)
	live.every(0.1, function()
		if dirty then
			render()
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
		for day in glowing do
			setGlow(day, false)
		end
	end
end

local def: PanelHost.Def = {
	id = ID,
	title = "Daily Gift",
	icon = "🎁",
	order = 70,
	build = build,
}
PanelHost.register(def)

return def
