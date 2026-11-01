--!strict
-- Coins counter (top left): drawn gold coin + a number that counts up smoothly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiMath = require(Shared.Ui.UiMath)
local Components = require(script.Parent.Parent.Ui.Components)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Context = require(script.Parent.Context)
local Widget = require(script.Parent.Widget)

local Coins = {}

export type CoinsWidget = Widget.Widget & {
	targetPosition: () -> UDim2?,
}

local COUNT_RATE = 6

function Coins.new(parent: Instance, ctx: Context.Context): CoinsWidget
	local pill = Components.Pill({
		parent = parent,
		name = "Coins",
		size = UDim2.fromOffset(UiMath.K.coinsW, UiMath.K.coinsH),
		text = "0",
		icon = "@coin",
		textSize = Theme.text.big,
		align = Enum.TextXAlignment.Left,
	})
	local icon = pill.icon
	if icon then
		-- a bigger coin than the default pill icon, centred vertically
		icon.Size = UDim2.fromOffset(26, 26)
		icon.Position = UDim2.new(0, 5, 0.5, 0)
	end
	pill.label.Position = UDim2.fromOffset(36, 0)
	pill.label.Size = UDim2.new(1, -44, 1, 0)
	pill.label.TextColor3 = Theme.color.goldLight

	local shown = 0
	local target = 0
	local first = true

	local function render()
		pill.setText(Theme.fmt(math.floor(shown + 0.5)))
	end

	local function refresh()
		local coins = ctx.view().coins
		if type(coins) ~= "number" or coins ~= coins then
			return
		end
		local old = target
		target = math.max(0, coins)
		if first then
			first = false
			shown = target -- no count-up on the very first value
			render()
			return
		end
		if target > old then
			Components.punch(pill.root, 0.05)
		end
	end

	ctx.every(0, function(dt: number)
		if shown ~= target then
			shown = UiMath.approach(shown, target, dt, COUNT_RATE)
			render()
		end
	end)
	ctx.watch({ "coins" }, refresh)

	return {
		root = pill.root,
		destroy = function()
			pill.root:Destroy()
		end,
		-- centre of the coin icon in screen pixels (for Vfx.coinBurst); nil until it has a size
		targetPosition = function(): UDim2?
			if icon == nil then
				return nil
			end
			local size = icon.AbsoluteSize
			if size.X <= 0 then
				return nil
			end
			local p = icon.AbsolutePosition
			return UDim2.fromOffset(p.X + size.X / 2, p.Y + size.Y / 2)
		end,
	}
end

return Coins
