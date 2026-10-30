--!strict
-- The counter bar (piece G17, video 3 gap 17): Scrap, Sparks, and any counter the server lists. PLACEHOLDER LOOK:
-- plain panels and text through Ui/Components (roles, never colours). Claude Design restyles it by changing the skin
-- or this drawing; the data flow stays. The server owns every number (WalletState); this screen only shows it.
--   * top right, on UiLayers.Calm, shown between fights only (WalletBarModel.visible).
--   * a counter that goes up pops once (not on the first state after joining).
--   * a small note under the bar says when the numbers are not being saved.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local WalletBarModel = require(Shared.Wallet.WalletBarModel)
local Net = require(script.Parent.Parent.Core.Net)
local Components = require(script.Parent.Parent.Ui.Components)
local Tokens = require(script.Parent.Parent.Ui.Tokens)

local WalletBarSystem = {}
WalletBarSystem.order = 230

type Chip = { holder: Frame, scale: UIScale, label: TextLabel, value: TextLabel }

local MAX_CHIPS = 4 -- the bar is sized for this many; more counters need a bigger bar

function WalletBarSystem.start()
	local _, root = Components.screen("WalletBar", "Calm")

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(1, 0)
	bar.Position = UDim2.new(1, -12, 0, 12)
	bar.Size = UDim2.fromScale(0.36, 0.1)
	bar.BackgroundTransparency = 1
	bar.Active = false
	bar.Parent = root
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(190, 44)
	limit.MaxSize = Vector2.new(420, 84)
	limit.Parent = bar
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.Padding = UDim.new(0.02, 0)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = bar

	local note = Components.text(root, root, "Note", "caption", {
		text = "",
		color = "inkOnDark",
		align = Enum.TextXAlignment.Right,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -12, 0.1, 18),
		size = UDim2.fromScale(0.36, 0.05),
	})

	local chips: { [string]: Chip } = {}

	local function chipFor(id: string, order: number): Chip
		local chip = chips[id]
		if chip == nil then
			local holder = Instance.new("Frame")
			holder.Name = id
			holder.BackgroundTransparency = 1
			holder.Active = false
			holder.Size = UDim2.fromScale(1 / MAX_CHIPS - 0.02, 1)
			holder.Parent = bar
			local scale = Instance.new("UIScale")
			scale.Parent = holder
			local panel = Components.panel(holder, root, "Panel", "panel")
			panel.Size = UDim2.fromScale(1, 1)
			local label = Components.text(panel, root, "Label", "caption", {
				color = "ink",
				size = UDim2.fromScale(0.86, 0.34),
				position = UDim2.fromScale(0.07, 0.06),
			})
			local value = Components.text(panel, root, "Value", "title", {
				size = UDim2.fromScale(0.86, 0.5),
				position = UDim2.fromScale(0.07, 0.42),
			})
			chip = { holder = holder, scale = scale, label = label, value = value }
			chips[id] = chip
		end
		chip.holder.LayoutOrder = order
		return chip :: Chip
	end

	local function pop(chip: Chip)
		chip.scale.Scale = 1.18
		TweenService:Create(
			chip.scale,
			TweenInfo.new(
				Tokens.get(nil).motion.pop,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			),
			{ Scale = 1 }
		):Play()
	end

	local current: Types.WalletState? = nil
	local phase: string? = nil

	local function refresh()
		bar.Visible = WalletBarModel.visible(phase)
		note.Visible = bar.Visible
		note.Text = WalletBarModel.note(current)
		local shown: { [string]: boolean } = {}
		for i, row in WalletBarModel.rows(current) do
			if i <= MAX_CHIPS then
				local chip = chipFor(row.id, i)
				chip.label.Text = row.label
				chip.value.Text = row.text
				chip.holder.Visible = true
				shown[row.id] = true
			end
		end
		for id, chip in chips do
			if not shown[id] then
				chip.holder.Visible = false
			end
		end
	end

	Net.on("WalletState", function(state: Types.WalletState)
		local old = current
		current = state
		refresh()
		for _, rise in WalletBarModel.rises(old, state) do
			local chip = chips[rise.id]
			if chip ~= nil then
				pop(chip)
			end
		end
	end)
	Net.on("MatchState", function(state: any)
		if type(state) == "table" and type(state.phase) == "string" then
			phase = state.phase
			refresh()
		end
	end)

	refresh()
	-- The server pushes on join, but this script may not have been listening yet: ask once.
	task.delay(1, function()
		if current == nil then
			Net.send("WalletRequest")
		end
	end)
end

return WalletBarSystem
