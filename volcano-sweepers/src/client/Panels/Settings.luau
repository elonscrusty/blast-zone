--!strict
-- Settings panel (id "settings"): five big switches (music, sounds, auto-sweep, screen shake,
-- controller buzz), a three-step "How to play", and the credits. A note shows when the game is
-- not being saved (guest mode). Every switch sends SetSetting; the server keeps the value and the
-- store sends it back. All words come from shared/Ui/SettingsModel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsModel = require(Shared.Ui.SettingsModel)
local Bridge = require(script.Parent.Parent.Ui.Bridge)
local Components = require(script.Parent.Parent.Ui.Components)
local PanelHost = require(script.Parent.Parent.Ui.PanelHost)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Context = require(script.Parent.Parent.Hud.Context)

local ID = "settings"

-- layout numbers (virtual px)
local ROW_H = 60
local ICON_W = 40
local TOGGLE_W = 66 -- room the switch itself takes on the right
local OFFLINE_H = 48
local STEP_H = 36
local GUIDE_TITLE_H = 26
local NUMBER_SIZE = 26
local SETTLE = 1.2 -- seconds after a tap during which the store may not overwrite the switch

local function build(parent: Frame, _ctx: PanelHost.Ctx): (() -> ())?
	local live = Context.new()
	local view: SettingsModel.View = SettingsModel.build(Bridge.view())
	local dirty = true
	local tappedAt: { [string]: number } = {} -- key -> os.clock() of the last tap

	local list = Components.ScrollList({ parent = parent, name = "Settings" })
	local scroll = list.root
	local pad = Theme.size.pad

	-- ---- guest mode note ----
	local offlineCard = Components.Card({
		parent = scroll,
		name = "Offline",
		color = Theme.kind.warn.fill,
		layoutOrder = 1,
		size = UDim2.new(1, 0, 0, OFFLINE_H),
	})
	local offlineLabel = Components.Label({
		parent = offlineCard,
		name = "OfflineText",
		text = `👤 {view.offlineText}`,
		textSize = Theme.text.body,
		font = Theme.font.bold,
		color = Theme.kind.warn.text,
		wrap = true,
		position = UDim2.fromOffset(pad, 2),
		size = UDim2.new(1, -2 * pad, 1, -4),
	})
	offlineCard.Visible = view.offline

	-- ---- switches ----
	local toggles: { [string]: Components.Toggle } = {}
	for index, row in view.rows do
		local card = Components.Card({
			parent = scroll,
			name = "Row_" .. row.key,
			layoutOrder = 10 + index,
			size = UDim2.new(1, 0, 0, ROW_H),
		})
		-- the switch covers the whole card, so the whole card is the touch target
		local key = row.key
		local toggle = Components.Toggle({
			parent = card,
			name = "Switch",
			value = row.value,
			position = UDim2.fromOffset(pad / 2, 0),
			size = UDim2.new(1, -pad, 1, 0),
		})
		toggle.onChanged(function(value: boolean)
			if not SettingsModel.isKey(key) then
				return
			end
			tappedAt[key] = os.clock()
			Bridge.send("SetSetting", key, value)
		end)
		toggles[key] = toggle
		Components.Label({
			parent = card,
			name = "Icon",
			text = row.icon,
			textSize = Theme.text.title,
			position = UDim2.fromOffset(pad, 0),
			size = UDim2.new(0, ICON_W, 1, 0),
			zIndex = 2,
		})
		Components.Label({
			parent = card,
			name = "RowName",
			text = row.label,
			textSize = Theme.text.big,
			font = Theme.font.title,
			color = Theme.color.charcoal,
			align = Enum.TextXAlignment.Left,
			position = UDim2.fromOffset(pad + ICON_W + 4, 6),
			size = UDim2.new(1, -(pad + ICON_W + 4 + TOGGLE_W + pad), 0, 26),
			zIndex = 2,
		})
		Components.Label({
			parent = card,
			name = "RowHint",
			text = row.hint,
			textSize = Theme.text.small,
			font = Theme.font.body,
			color = Theme.color.charcoalSoft,
			align = Enum.TextXAlignment.Left,
			position = UDim2.fromOffset(pad + ICON_W + 4, 33),
			size = UDim2.new(1, -(pad + ICON_W + 4 + TOGGLE_W + pad), 0, 20),
			zIndex = 2,
		})
	end

	-- ---- how to play ----
	local guide = Components.Card({
		parent = scroll,
		name = "HowToPlay",
		layoutOrder = 30,
		size = UDim2.new(1, 0, 0, pad + GUIDE_TITLE_H + #view.steps * STEP_H + pad),
	})
	Components.Label({
		parent = guide,
		name = "GuideTitle",
		text = "How to play",
		textSize = Theme.text.big,
		font = Theme.font.title,
		color = Theme.color.lavaDark,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(pad, pad),
		size = UDim2.new(1, -2 * pad, 0, GUIDE_TITLE_H),
	})
	for i, step in view.steps do
		local y = pad + GUIDE_TITLE_H + (i - 1) * STEP_H
		local badge = Instance.new("Frame")
		badge.Name = "Number" .. i
		badge.BackgroundColor3 = Theme.color.lava
		badge.BorderSizePixel = 0
		badge.Position = UDim2.fromOffset(pad, y + (STEP_H - NUMBER_SIZE) / 2)
		badge.Size = UDim2.fromOffset(NUMBER_SIZE, NUMBER_SIZE)
		badge.Parent = guide
		local round = Instance.new("UICorner")
		round.CornerRadius = Theme.radius.full
		round.Parent = badge
		Components.Label({
			parent = badge,
			text = tostring(i),
			textSize = Theme.text.body,
			font = Theme.font.title,
			color = Theme.color.white,
		})
		Components.Label({
			parent = guide,
			name = "StepIcon" .. i,
			text = step.icon,
			textSize = Theme.text.big,
			position = UDim2.fromOffset(pad + NUMBER_SIZE + 4, y),
			size = UDim2.fromOffset(32, STEP_H),
		})
		Components.Label({
			parent = guide,
			name = "StepText" .. i,
			text = step.text,
			textSize = Theme.text.body,
			font = Theme.font.bold,
			color = Theme.color.charcoal,
			align = Enum.TextXAlignment.Left,
			wrap = true,
			position = UDim2.fromOffset(pad + NUMBER_SIZE + 4 + 36, y),
			size = UDim2.new(1, -(pad + NUMBER_SIZE + 4 + 36 + pad), 0, STEP_H),
		})
	end

	-- ---- credits ----
	Components.Label({
		parent = scroll,
		name = "Credits",
		text = view.credits,
		textSize = Theme.text.small,
		font = Theme.font.bold,
		color = Theme.color.charcoalSoft,
		size = UDim2.new(1, 0, 0, 28),
		layoutOrder = 40,
	})

	local function render()
		dirty = false
		view = SettingsModel.build(Bridge.view())
		offlineCard.Visible = view.offline
		offlineLabel.Text = if view.offline then `👤 {view.offlineText}` else ""
		local now = os.clock()
		for _, row in view.rows do
			local toggle = toggles[row.key]
			local tapped = tappedAt[row.key]
			-- right after a tap the store still has the old value for a moment: let the switch be
			if toggle and (tapped == nil or now - tapped > SETTLE) then
				toggle.set(row.value, true)
			end
		end
	end

	render()
	live.watch({ "settings", "offline", "offlineRetrying" }, function()
		dirty = true
	end)
	-- also look again every half second: if the server said no, the switch snaps back
	live.every(0.5, function()
		dirty = true
	end)
	live.every(0.1, function()
		if dirty then
			render()
		end
	end)

	return function()
		live.destroy()
	end
end

local def: PanelHost.Def = {
	id = ID,
	title = "Settings",
	icon = "⚙️",
	order = 90,
	build = build,
}
PanelHost.register(def)

return def
