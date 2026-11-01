--!strict
-- Buff chips: Party x2 / Perfect +10% / Golden, each with the time left (server time).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Ui.Format)
local UiMath = require(Shared.Ui.UiMath)
local Components = require(script.Parent.Parent.Ui.Components)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Context = require(script.Parent.Context)
local Widget = require(script.Parent.Widget)

local BuffChips = {}

type Look = { icon: string, label: string, fill: Color3, text: Color3 }

local function multText(mult: number): string
	local r = math.floor(mult * 10 + 0.5) / 10
	return if r == math.floor(r) then `x{math.floor(r)}` else `x{r}`
end

local LOOKS: { [string]: Look } = {
	party = {
		icon = "🎉",
		label = multText(Config.Economy.partyMult),
		fill = Theme.color.lava,
		text = Theme.color.white,
	},
	perfect = {
		icon = "🎯",
		label = `+{math.floor((Config.Economy.perfectMult - 1) * 100 + 0.5)}%`,
		fill = Theme.color.teal,
		text = Theme.color.white,
	},
	golden = { icon = "⭐", label = "Gold", fill = Theme.color.gold, text = Theme.color.charcoal },
}
local FALLBACK: Look =
	{ icon = "✨", label = "Boost", fill = Theme.color.sky, text = Theme.color.white }
local ORDER = { "party", "perfect", "golden" }

local CHIP_MAX_W = 96
local CHIP_GAP = 4
local LOW_SECONDS = 10

function BuffChips.new(parent: Instance, ctx: Context.Context): Widget.Widget
	local root = Instance.new("Frame")
	root.Name = "BuffChips"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(300, UiMath.K.chipH)
	root.Parent = parent
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, CHIP_GAP)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = root

	local chips: { [string]: Components.Pill } = {}
	local totalW = 300

	local function ensureChip(id: string): Components.Pill
		local chip = chips[id]
		if chip then
			return chip
		end
		local look = LOOKS[id] or FALLBACK
		local index = table.find(ORDER, id) or 99
		local made = Components.Pill({
			parent = root,
			name = "Chip_" .. id,
			size = UDim2.fromOffset(CHIP_MAX_W, UiMath.K.chipH),
			layoutOrder = index,
			icon = look.icon,
			text = look.label,
			fill = look.fill,
			fillTransparency = 0.05,
			textColor = look.text,
			textSize = Theme.text.small,
			align = Enum.TextXAlignment.Left,
		})
		chips[id] = made
		Components.punch(made.root, 0.12)
		return made
	end

	local function refresh()
		local buffs = ctx.view().buffs
		local now = ctx.serverNow()
		local active: { string } = {}
		if type(buffs) == "table" then
			for id, endsAt in buffs do
				if type(id) == "string" and type(endsAt) == "number" and endsAt - now > 0 then
					table.insert(active, id)
				end
			end
		end
		local alive: { [string]: boolean } = {}
		for _, id in active do
			alive[id] = true
		end
		for id, chip in chips do
			if not alive[id] then
				chip.root:Destroy()
				chips[id] = nil
			end
		end
		local width = UiMath.chipWidth(totalW, #active, CHIP_MAX_W, CHIP_GAP)
		for _, id in active do
			local chip = ensureChip(id)
			local look = LOOKS[id] or FALLBACK
			local left = UiMath.secondsLeft((buffs :: any)[id], now)
			chip.root.Size = UDim2.fromOffset(width, UiMath.K.chipH)
			chip.setText(`{look.label} {Format.countdown(left)}`)
			-- last seconds: blink the chip a little so kids notice the boost running out
			chip.root.BackgroundTransparency = if left <= LOW_SECONDS
					and math.floor(left * 2) % 2 == 0
				then 0.45
				else 0.05
		end
	end

	ctx.every(0.5, refresh)
	ctx.watch({ "buffs" }, refresh)

	return {
		root = root,
		layout = function(rect: UiMath.Rect, _all: UiMath.Layout)
			totalW = rect.w
			refresh()
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return BuffChips
