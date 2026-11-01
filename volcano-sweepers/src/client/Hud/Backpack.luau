--!strict
-- Backpack bar (under the coins): fills as you carry ash, turns lava-red and pulses when full.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Ui.Format)
local UiMath = require(Shared.Ui.UiMath)
local Components = require(script.Parent.Parent.Ui.Components)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Context = require(script.Parent.Context)
local Widget = require(script.Parent.Widget)

local Backpack = {}

export type BackpackWidget = Widget.Widget & {
	isFull: () -> boolean,
}

function Backpack.new(parent: Instance, ctx: Context.Context): BackpackWidget
	local root = Instance.new("Frame")
	root.Name = "Backpack"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(UiMath.K.coinsW, UiMath.K.packH)
	root.Parent = parent

	local icon = Components.Label({
		parent = root,
		name = "Icon",
		text = "🎒",
		textSize = 20,
		position = UDim2.fromOffset(0, 0),
		size = UDim2.fromOffset(24, UiMath.K.packH),
	})
	icon.ZIndex = 2

	local bar = Components.Bar({
		parent = root,
		name = "PackBar",
		position = UDim2.fromOffset(26, 0),
		size = UDim2.new(1, -26, 1, 0),
		fill = Theme.color.teal,
		text = "0/30",
		textSize = Theme.text.small,
	})
	local pulseScale = Instance.new("UIScale")
	pulseScale.Name = "Pulse"
	pulseScale.Parent = bar.root

	local full = false
	local pulse: Tween? = nil
	local lastText = ""
	local tone = ""

	local function setTone(name: string, color: Color3)
		if tone ~= name then
			tone = name
			bar.setColor(color)
		end
	end

	local function setPulse(on: boolean)
		if on then
			if pulse == nil then
				local t = TweenService:Create(
					pulseScale,
					TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Scale = 1.07 }
				)
				pulse = t
				t:Play()
			end
		elseif pulse ~= nil then
			pulse:Cancel()
			pulse = nil
			Components.tween(pulseScale, { Scale = 1 }, Theme.ease.fast)
		end
	end

	local function refresh()
		local view = ctx.view()
		local carried = view.carried
		local derived = view.derived
		local capacity = if type(derived) == "table" and type(derived.capacity) == "number"
			then derived.capacity
			else 0
		if type(carried) ~= "number" then
			carried = 0
		end
		capacity = math.max(1, capacity)
		local fraction = UiMath.barFill(carried / capacity)
		local nowFull = carried >= capacity - 1e-6 and carried > 0
		local text = if nowFull
			then "FULL — SELL!"
			else Format.pair(math.floor(carried), math.floor(capacity))
		if text ~= lastText then
			lastText = text
			bar.setText(text)
		end
		bar.set(fraction)
		if nowFull ~= full then
			full = nowFull
			setPulse(nowFull)
			if nowFull then
				bar.flash()
				Components.punch(icon, 0.25)
			end
		end
		if nowFull then
			setTone("full", Theme.color.red)
		elseif fraction >= 0.75 then
			setTone("high", Theme.color.gold)
		else
			setTone("normal", Theme.color.teal)
		end
	end
	ctx.watch({ "carried", "derived" }, refresh)
	refresh()

	return {
		root = root,
		isFull = function()
			return full
		end,
		destroy = function()
			setPulse(false)
			root:Destroy()
		end,
	}
end

return Backpack
