--!strict
-- First-load splash: "VOLCANO SWEEPERS" over a warm gradient, hiding the world until the store has
-- its first state (or 4 seconds, whichever comes first), then a 0.8 s fade.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Bridge = require(script.Parent.Parent.Ui.Bridge)
local Components = require(script.Parent.Parent.Ui.Components)
local Theme = require(script.Parent.Parent.Ui.Theme)

local Splash = {}

export type SplashHandle = {
	dismiss: () -> (),
	destroy: () -> (),
}

local MIN_SHOW = 1.0 -- never flash by faster than this

function Splash.new(): SplashHandle
	local screen = Components.screen("VSSplash", Theme.DisplayOrder.overlay, { fullBleed = true })
	-- the splash covers the REAL screen: use the gui itself, not the scaled root, for the backdrop
	local group = Instance.new("CanvasGroup")
	group.Name = "Splash"
	group.Size = UDim2.fromScale(1, 1)
	-- white base: a UIGradient MULTIPLIES the colour under it, so gold -> lava shows true only on white
	group.BackgroundColor3 = Theme.color.white
	group.BorderSizePixel = 0
	group.Active = true -- swallow taps while loading
	group.Parent = screen.gui
	-- the gradient lives on its own backdrop frame: on a CanvasGroup it could tint the whole group,
	-- white title included
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.color.white
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 0
	backdrop.Parent = group
	local bg = Instance.new("UIGradient")
	bg.Color = ColorSequence.new(Theme.color.gold, Theme.color.lava)
	bg.Rotation = 90
	bg.Parent = backdrop

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(360, 200)
	content.BackgroundTransparency = 1
	content.Parent = group
	local contentScale = Instance.new("UIScale")
	contentScale.Parent = content
	local function fit()
		contentScale.Scale = Theme.scaleFor(screen.gui.AbsoluteSize.X, screen.gui.AbsoluteSize.Y)
	end
	fit()
	local sizeConn = screen.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	local broom = Components.Label({
		parent = content,
		text = "🧹",
		textSize = Theme.text.logo,
		position = UDim2.fromOffset(0, 0),
		size = UDim2.new(1, 0, 0, 80),
	})
	Components.Label({
		parent = content,
		text = string.upper(Config.Game.Name),
		textSize = Theme.text.huge,
		font = Theme.font.title,
		color = Theme.color.white,
		outline = Theme.color.lavaDeep,
		position = UDim2.fromOffset(0, 84),
		size = UDim2.new(1, 0, 0, 52),
	})
	local sub = Components.Label({
		parent = content,
		text = "Sweeping...",
		textSize = Theme.text.body,
		font = Theme.font.bold,
		color = Theme.color.cream,
		position = UDim2.fromOffset(0, 146),
		size = UDim2.new(1, 0, 0, 24),
	})

	-- the broom swings gently while we wait
	local sway = TweenService:Create(
		broom,
		TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Rotation = 14 }
	)
	broom.Rotation = -14
	sway:Play()

	local startedAt = os.clock()
	local finished = false
	local beat: RBXScriptConnection? = nil
	local dots = 0
	local lastDot = 0

	local function destroy()
		finished = true
		sway:Cancel()
		sizeConn:Disconnect()
		if beat then
			beat:Disconnect()
			beat = nil
		end
		screen.destroy()
	end

	local fading = false
	local function dismiss()
		if fading then
			return
		end
		fading = true
		sway:Cancel()
		local t = TweenService:Create(
			group,
			TweenInfo.new(Theme.duration.splash, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ GroupTransparency = 1 }
		)
		t.Completed:Connect(function()
			if not finished then
				destroy()
			end
		end)
		t:Play()
		group.Active = false
	end

	beat = RunService.Heartbeat:Connect(function()
		if finished or fading then
			return
		end
		local elapsed = os.clock() - startedAt
		if elapsed - lastDot > 0.4 then
			lastDot = elapsed
			dots = (dots + 1) % 4
			sub.Text = "Sweeping" .. string.rep(".", dots)
		end
		if elapsed >= Theme.duration.splashMax or (elapsed >= MIN_SHOW and Bridge.storeReady()) then
			dismiss()
		end
	end)

	return { dismiss = dismiss, destroy = destroy }
end

return Splash
