--!strict
-- Volcano banner (under the clean bar): driven by the `Burp` remote. A colour per event, a big
-- countdown during the rumble and a timer bar that shrinks. Hidden when the volcano is calm.

local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiMath = require(Shared.Ui.UiMath)
local Components = require(script.Parent.Parent.Ui.Components)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Context = require(script.Parent.Context)
local Widget = require(script.Parent.Widget)

local BurpBanner = {}

local STALE_AFTER = 12 -- hide if the server never said "calm" this long after the phase should have ended

type Info = { phase: string, kind: string?, startsAt: number, endsAt: number }

local function readInfo(payload: any): Info?
	if type(payload) ~= "table" then
		return nil
	end
	local phase = payload.phase
	local startsAt = payload.startsAt
	local endsAt = payload.endsAt
	if type(phase) ~= "string" or type(startsAt) ~= "number" or type(endsAt) ~= "number" then
		return nil
	end
	local kind = payload.kind
	return {
		phase = phase,
		kind = if type(kind) == "string" then kind else nil,
		startsAt = startsAt,
		endsAt = endsAt,
	}
end

function BurpBanner.new(parent: Instance, ctx: Context.Context): Widget.Widget
	local holder = Instance.new("Frame")
	holder.Name = "BurpBanner"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(300, UiMath.K.bannerH)
	holder.Visible = false
	holder.Parent = parent

	local card = Instance.new("CanvasGroup")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.Position = UDim2.fromOffset(0, -12)
	card.BackgroundColor3 = Theme.tone.rumble.fill
	card.BorderSizePixel = 0
	card.GroupTransparency = 1
	card.Parent = holder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.radius.md
	corner.Parent = card
	local rim = Instance.new("UIStroke")
	rim.Color = Theme.color.white
	rim.Transparency = 0.35
	rim.Thickness = 2
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = card
	local pulseScale = Instance.new("UIScale")
	pulseScale.Name = "Pulse"
	pulseScale.Parent = card

	local text = Components.Label({
		parent = card,
		name = "Text",
		text = "",
		textSize = 20,
		font = Theme.font.title,
		color = Theme.tone.rumble.text,
		outline = Theme.color.ink,
		position = UDim2.fromOffset(8, 2),
		size = UDim2.new(1, -16, 1, -12),
	})
	local count = Components.Label({
		parent = card,
		name = "Count",
		text = "",
		textSize = 30,
		font = Theme.font.title,
		color = Theme.color.white,
		outline = Theme.color.ink,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -10, 0, 1),
		size = UDim2.new(0, 46, 1, -11),
	})
	local timerTrack = Instance.new("Frame")
	timerTrack.Name = "TimerTrack"
	timerTrack.AnchorPoint = Vector2.new(0.5, 1)
	timerTrack.Position = UDim2.new(0.5, 0, 1, -4)
	timerTrack.Size = UDim2.new(1, -20, 0, 5)
	timerTrack.BackgroundColor3 = Theme.color.ink
	timerTrack.BackgroundTransparency = 0.55
	timerTrack.BorderSizePixel = 0
	timerTrack.Parent = card
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = Theme.radius.full
	trackCorner.Parent = timerTrack
	local timerFill = Instance.new("Frame")
	timerFill.Name = "Fill"
	timerFill.Size = UDim2.fromScale(1, 1)
	timerFill.BackgroundColor3 = Theme.color.white
	timerFill.BorderSizePixel = 0
	timerFill.Parent = timerTrack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = Theme.radius.full
	fillCorner.Parent = timerFill

	local info: Info? = nil
	local shown = false
	local tone = ""
	local shownText = ""
	local pulse: Tween? = nil

	local function setPulse(on: boolean)
		if on and pulse == nil then
			local t = TweenService:Create(
				pulseScale,
				TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = 1.04 }
			)
			pulse = t
			t:Play()
		elseif not on and pulse ~= nil then
			pulse:Cancel()
			pulse = nil
			pulseScale.Scale = 1
		end
	end

	local function show()
		if shown then
			return
		end
		shown = true
		holder.Visible = true
		card.Position = UDim2.fromOffset(0, -12)
		card.GroupTransparency = 1
		Components.tween(
			card,
			{ GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) },
			Theme.ease.pop
		)
	end

	local function hide()
		if not shown then
			return
		end
		shown = false
		tone = ""
		shownText = ""
		setPulse(false)
		local t = Components.tween(
			card,
			{ GroupTransparency = 1, Position = UDim2.fromOffset(0, -12) },
			Theme.ease.normal
		)
		t.Completed:Connect(function()
			if not shown then
				holder.Visible = false
			end
		end)
	end

	local function apply()
		local current = info
		if current == nil then
			hide()
			return
		end
		local now = ctx.serverNow()
		if now > current.endsAt + STALE_AFTER then
			info = nil
			hide()
			return
		end
		local spec = UiMath.banner(current, now)
		if spec == nil then
			hide()
			return
		end
		local look = Theme.tone[spec.tone] or Theme.tone.rumble
		if tone ~= spec.tone then
			tone = spec.tone
			Components.tween(card, { BackgroundColor3 = look.fill }, Theme.ease.normal)
			text.TextColor3 = look.text
			count.TextColor3 = look.text
			if spec.tone == "rumble" or spec.tone == "pops" then
				setPulse(true)
			else
				setPulse(false)
			end
			Components.punch(holder, 0.04)
		end
		if shownText ~= spec.text then
			shownText = spec.text
			text.Text = spec.text
		end
		count.Visible = spec.showCount
		text.Size = if spec.showCount then UDim2.new(1, -66, 1, -12) else UDim2.new(1, -16, 1, -12)
		text.TextXAlignment = if spec.showCount
			then Enum.TextXAlignment.Left
			else Enum.TextXAlignment.Center
		if spec.showCount then
			count.Text = tostring(spec.secondsLeft)
		end
		Components.tween(
			timerFill,
			{ Size = UDim2.fromScale(spec.fraction, 1) },
			TweenInfo.new(0.12, Enum.EasingStyle.Linear)
		)
		show()
	end

	ctx.listen("Burp", function(payload: any)
		info = readInfo(payload)
		apply()
	end)
	ctx.every(0.1, function()
		if info ~= nil then
			apply()
		end
	end)

	return {
		root = holder,
		destroy = function()
			setPulse(false)
			holder:Destroy()
		end,
	}
end

return BurpBanner
