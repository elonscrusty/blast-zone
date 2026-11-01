--!strict
-- The thumb buttons (bottom right): SWEEP (hold), SELL (appears near a sell pad or when full), and
-- the AUTO chip. Hold-to-sweep works for touch and mouse; releasing anywhere, losing window focus
-- or opening a panel lets go.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local StoreLogic = require(Shared.Client.StoreLogic)
local UiMath = require(Shared.Ui.UiMath)
local Bridge = require(script.Parent.Parent.Ui.Bridge)
local Components = require(script.Parent.Parent.Ui.Components)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Context = require(script.Parent.Context)

local Actions = {}

export type ActionsWidget = {
	sweep: GuiObject,
	sell: GuiObject,
	auto: GuiObject,
	releaseSweep: () -> (),
	setEnabled: (on: boolean) -> (),
	destroy: () -> (),
}

local SELL_PAD_TAG = "VSSellPad"
local SELL_VALUE_H = 18
local AUTO_SETTLE = 1.5 -- seconds after a tap before the store's value wins again (snap back)

local function isPress(input: InputObject): boolean
	local t = input.UserInputType
	return (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch)
		and input.UserInputState == Enum.UserInputState.Begin
end

local function padPoints(): { { x: number, z: number } }
	local points: { { x: number, z: number } } = {}
	for _, inst in CollectionService:GetTagged(SELL_PAD_TAG) do
		if inst:IsA("BasePart") then
			table.insert(points, { x = inst.Position.X, z = inst.Position.Z })
		elseif inst:IsA("Model") then
			local p = inst:GetPivot().Position
			table.insert(points, { x = p.X, z = p.Z })
		end
	end
	return points
end

function Actions.new(parent: Instance, ctx: Context.Context): ActionsWidget
	local K = UiMath.K
	local destroyed = false

	-- ===== SWEEP =====
	local sweepRoot = Instance.new("Frame")
	sweepRoot.Name = "SweepButton"
	sweepRoot.BackgroundTransparency = 1
	sweepRoot.BorderSizePixel = 0
	sweepRoot.Size = UDim2.fromOffset(K.sweepSize, K.sweepSize)
	sweepRoot.Parent = parent

	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(1.34, 1.34)
	glow.BackgroundColor3 = Theme.color.gold
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.Active = false
	glow.Parent = sweepRoot
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = Theme.radius.full
	glowCorner.Parent = glow

	local sweepBtn = Components.Button({
		parent = sweepRoot,
		name = "Sweep",
		size = UDim2.fromScale(1, 1),
		variant = "primary",
		round = true,
		icon = "🧹",
		text = "SWEEP",
		textSize = Theme.text.label,
		stack = true,
		silent = true,
	})
	local holdScale = Instance.new("UIScale")
	holdScale.Name = "Hold"
	holdScale.Parent = sweepBtn.root

	local held = false
	local heldInput: InputObject? = nil
	local heldType: Enum.UserInputType? = nil
	local glowPulse: Tween? = nil
	local externalHeld = false -- keyboard / gamepad hold seen through Controls.sweepHeld()

	local function paintHeld(on: boolean)
		if on then
			Components.tween(glow, { BackgroundTransparency = 0.5 }, Theme.ease.fast)
			Components.tween(holdScale, { Scale = 0.95 }, Theme.ease.fast)
			if glowPulse == nil then
				local t = TweenService:Create(
					glow,
					TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Size = UDim2.fromScale(1.46, 1.46) }
				)
				glowPulse = t
				t:Play()
			end
		else
			if glowPulse ~= nil then
				glowPulse:Cancel()
				glowPulse = nil
			end
			Components.tween(
				glow,
				{ BackgroundTransparency = 1, Size = UDim2.fromScale(1.34, 1.34) },
				Theme.ease.normal
			)
			Components.tween(holdScale, { Scale = 1 }, Theme.ease.normal)
		end
	end

	local function setHeld(on: boolean)
		if held == on then
			return
		end
		held = on
		local controls = Bridge.controls()
		if controls ~= nil and type(controls.setSweepHeld) == "function" then
			local ok, err = pcall(controls.setSweepHeld, on)
			if not ok then
				warn(`[Hud] setSweepHeld failed: {err}`)
			end
		end
		paintHeld(on or externalHeld)
	end

	local function release()
		heldInput = nil
		heldType = nil
		setHeld(false)
	end

	ctx.connect(sweepBtn.hit.InputBegan:Connect(function(input: InputObject)
		if destroyed or heldInput ~= nil or not isPress(input) then
			return
		end
		heldInput = input
		heldType = input.UserInputType
		setHeld(true)
	end))
	ctx.connect(UserInputService.InputEnded:Connect(function(input: InputObject)
		if heldInput == nil then
			return
		end
		-- a touch is tracked by identity; the mouse button by type
		if
			input == heldInput
			or (heldType == Enum.UserInputType.MouseButton1 and input.UserInputType == heldType)
		then
			release()
		end
	end))
	ctx.connect(UserInputService.WindowFocusReleased:Connect(release))
	ctx.onCleanup(release)

	-- keyboard / gamepad sweeping is done by Controls; mirror it with the glow
	ctx.every(0.1, function()
		local controls = Bridge.controls()
		local now = false
		if controls ~= nil and type(controls.sweepHeld) == "function" then
			local ok, value = pcall(controls.sweepHeld)
			now = ok and value == true
		end
		if now ~= externalHeld then
			externalHeld = now
			if not held then
				paintHeld(now)
			end
		end
	end)

	-- ===== AUTO chip =====
	local autoBtn = Components.Button({
		parent = parent,
		name = "AutoButton",
		size = UDim2.fromOffset(K.sweepSize, K.autoH),
		variant = "dark",
		text = "AUTO OFF",
		textSize = Theme.text.small,
	})
	local autoOn = false
	local autoTappedAt = -10
	local function paintAuto()
		autoBtn.setVariant(if autoOn then "good" else "dark")
		autoBtn.setText(if autoOn then "AUTO ON" else "AUTO OFF")
	end
	autoBtn.onClick(function()
		autoOn = not autoOn -- shows at once; the server's State confirms it
		autoTappedAt = os.clock()
		paintAuto()
		Bridge.send("SetSetting", "autoSweep", autoOn)
	end)

	-- ===== SELL =====
	local sellRoot = Instance.new("Frame")
	sellRoot.Name = "SellButton"
	sellRoot.BackgroundTransparency = 1
	sellRoot.BorderSizePixel = 0
	sellRoot.Size = UDim2.fromOffset(K.sellSize, K.sellSize)
	sellRoot.Visible = false
	sellRoot.Parent = parent
	local sellScale = Instance.new("UIScale")
	sellScale.Name = "Show"
	sellScale.Scale = 0
	sellScale.Parent = sellRoot

	local valuePill = Components.Pill({
		parent = sellRoot,
		name = "Value",
		size = UDim2.new(1, 0, 0, SELL_VALUE_H),
		icon = "@coin",
		text = "0",
		fill = Theme.color.ink,
		fillTransparency = 0.25,
		textColor = Theme.color.goldLight,
		textSize = Theme.text.tiny + 1,
		align = Enum.TextXAlignment.Left,
	})
	local valueIcon = valuePill.icon
	if valueIcon then
		valueIcon.Size = UDim2.fromOffset(14, 14)
		valueIcon.Position = UDim2.new(0, 5, 0.5, 0)
	end
	valuePill.label.Position = UDim2.fromOffset(22, 0)
	valuePill.label.Size = UDim2.new(1, -26, 1, 0)
	local sellCircle = K.sellSize - SELL_VALUE_H
	local sellBtn = Components.Button({
		parent = sellRoot,
		name = "Sell",
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, SELL_VALUE_H),
		size = UDim2.fromOffset(sellCircle, sellCircle),
		variant = "good",
		round = true,
		icon = "💰",
		text = "SELL",
		textSize = Theme.text.label,
		stack = true,
	})
	sellBtn.onClick(function()
		local controls = Bridge.controls()
		if controls ~= nil and type(controls.requestSell) == "function" then
			local ok, err = pcall(controls.requestSell)
			if not ok then
				warn(`[Hud] requestSell failed: {err}`)
			end
		end
	end)

	local sellShown = false
	local nearPad = false
	local fullPulse: Tween? = nil
	local sellGlow = Instance.new("Frame")
	sellGlow.Name = "FullGlow"
	sellGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	sellGlow.Position = UDim2.new(0.5, 0, 0, SELL_VALUE_H + sellCircle / 2)
	sellGlow.Size = UDim2.fromOffset(sellCircle + 14, sellCircle + 14)
	sellGlow.BackgroundColor3 = Theme.color.green
	sellGlow.BackgroundTransparency = 1
	sellGlow.BorderSizePixel = 0
	sellGlow.ZIndex = 0
	sellGlow.Active = false
	sellGlow.Parent = sellRoot
	local sellGlowCorner = Instance.new("UICorner")
	sellGlowCorner.CornerRadius = Theme.radius.full
	sellGlowCorner.Parent = sellGlow

	local function setSellShown(on: boolean)
		if on == sellShown then
			return
		end
		sellShown = on
		if on then
			sellRoot.Visible = true
			Components.tween(sellScale, { Scale = 1 }, Theme.ease.pop)
		else
			local t = Components.tween(sellScale, { Scale = 0 }, Theme.ease.fast)
			t.Completed:Connect(function()
				if not sellShown then
					sellRoot.Visible = false
				end
			end)
		end
	end

	local function setFullPulse(on: boolean)
		if on and fullPulse == nil then
			sellGlow.BackgroundTransparency = 0.5
			local t = TweenService:Create(
				sellGlow,
				TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundTransparency = 0.85 }
			)
			fullPulse = t
			t:Play()
		elseif not on and fullPulse ~= nil then
			fullPulse:Cancel()
			fullPulse = nil
			sellGlow.BackgroundTransparency = 1
		end
	end

	local function refreshSell()
		local view = ctx.view()
		local carried = if type(view.carried) == "number" then view.carried else 0
		local derived = view.derived
		local capacity = if type(derived) == "table" and type(derived.capacity) == "number"
			then derived.capacity
			else 0
		local mult = if type(derived) == "table" and type(derived.sellMult) == "number"
			then derived.sellMult
			else 1
		local value = if type(view.carriedValue) == "number" then view.carriedValue else 0
		local isFull = carried > 0 and capacity > 0 and carried >= capacity - 1e-6
		valuePill.setText(Theme.fmt(math.floor(value * mult)))
		setSellShown(carried > 0 and (nearPad or isFull))
		setFullPulse(isFull)
	end

	local function pollPads()
		local player = Players.LocalPlayer
		local char = if player then player.Character else nil
		local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
		local near = false
		if hrp ~= nil and hrp:IsA("BasePart") then
			near =
				UiMath.nearAny(padPoints(), hrp.Position.X, hrp.Position.Z, Config.World.sellRange)
		end
		if near ~= nearPad then
			nearPad = near
			refreshSell()
		end
	end

	-- ===== settings (AUTO) =====
	-- The store (the server's word) wins, except right after a tap while the answer is on its way.
	-- If the server never agreed (a dropped or rate-limited request), the chip snaps back.
	local function refreshAuto()
		if os.clock() - autoTappedAt < AUTO_SETTLE then
			return
		end
		-- missing = ON, the same default as Controls, Tutorial and the Settings panel (DESIGN)
		local view = ctx.view()
		if type(view.settings) ~= "table" then
			return -- nothing from the server yet
		end
		local on = StoreLogic.setting(view, "autoSweep", true)
		if on ~= autoOn then
			autoOn = on
			paintAuto()
		end
	end

	paintAuto()
	ctx.every(0.25, pollPads)
	ctx.watch({ "carried", "carriedValue", "derived" }, refreshSell)
	ctx.watch({ "settings" }, refreshAuto)
	ctx.every(0.5, refreshAuto)

	return {
		sweep = sweepRoot,
		sell = sellRoot,
		auto = autoBtn.root,
		releaseSweep = release,
		setEnabled = function(on: boolean)
			sweepRoot.Visible = on
			autoBtn.root.Visible = on
			if not on then
				release()
			end
		end,
		destroy = function()
			destroyed = true
			release()
			setFullPulse(false)
			if glowPulse then
				glowPulse:Cancel()
				glowPulse = nil
			end
			sweepRoot:Destroy()
			autoBtn.destroy()
			sellRoot:Destroy()
		end,
	}
end

return Actions
