--!strict
-- The "your data did not load" strip (carter's pick A, Top Strip): a coral band across the top with
-- one short sentence and, when it helps, a TRY AGAIN button. It never blocks play: the player can
-- still press PLAY underneath. A slow load uses the gold version with no button.

local Players = game:GetService("Players")

local UiKit = require(script.Parent.Parent.Hud.UiKit)
local UiLayers = require(script.Parent.Parent.Ui.UiLayers)
local DataNotice = require(script.Parent.DataNotice)

local StatusStripView = {}

local gui: ScreenGui? = nil
local strip: Frame
local message: TextLabel
local retry: TextButton
local onRetry: (() -> ())? = nil

local function build()
	local look = UiKit.look()
	local g = Instance.new("ScreenGui")
	g.Name = "SaveStatus"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.ScreenInsets = Enum.ScreenInsets.None
	g.DisplayOrder = UiLayers.Toast -- above the lobby buttons and panels so the message is seen
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Enabled = false

	strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.Size = UDim2.fromScale(1, 0.16)
	strip.BorderSizePixel = 0
	strip.BackgroundColor3 = UiKit.color(look.danger)
	strip.Parent = g

	local edge = Instance.new("Frame") -- thick navy bottom line, like the other stickers
	edge.Name = "Edge"
	edge.AnchorPoint = Vector2.new(0, 1)
	edge.Position = UDim2.fromScale(0, 1)
	edge.Size = UDim2.new(1, 0, 0, 4)
	edge.BackgroundColor3 = UiKit.color(look.outline)
	edge.BorderSizePixel = 0
	edge.Active = false
	edge.Parent = strip

	message = UiKit.label(strip, "Message", {
		size = UDim2.fromScale(0.62, 0.8),
		position = UDim2.fromScale(0.05, 0.1),
		align = Enum.TextXAlignment.Left,
		maxTextSize = 24,
	})
	message.RichText = true
	message.TextWrapped = true

	retry = Instance.new("TextButton")
	retry.Name = "Retry"
	retry.Font = UiKit.FONT
	retry.TextScaled = true
	retry.TextColor3 = UiKit.color(look.ink)
	retry.BackgroundColor3 = UiKit.color(look.accent)
	retry.BorderSizePixel = 0
	retry.AnchorPoint = Vector2.new(1, 0.5)
	retry.Position = UDim2.fromScale(0.95, 0.48)
	retry.Size = UDim2.fromScale(0.22, 0.8) -- 0.8 of 16% of the height is 48 points on a 390 point screen
	UiKit.round(retry, 0.3)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiKit.color(look.outline)
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = retry
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 24
	cap.MinTextSize = 8
	cap.Parent = retry
	retry.Parent = strip
	retry.Activated:Connect(function()
		if onRetry then
			onRetry()
		end
	end)

	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = g
end

-- notice nil hides the strip. visible=false hides it without forgetting the notice (during a match
-- the HUD owns the top of the screen).
function StatusStripView.set(notice: DataNotice.Notice?, visible: boolean, retryHandler: () -> ())
	if gui == nil then
		if notice == nil then
			return
		end
		build()
	end
	local g = gui :: ScreenGui
	onRetry = retryHandler
	if notice == nil or not visible then
		g.Enabled = false
		return
	end
	local look = UiKit.look()
	strip.BackgroundColor3 = UiKit.color(if notice.kind == "bad" then look.danger else look.accent)
	message.Text = `<b>{notice.headline}</b> {notice.body}`
	retry.Visible = notice.button ~= nil
	retry.Text = notice.button or ""
	message.Size = if notice.button ~= nil
		then UDim2.fromScale(0.62, 0.8)
		else UDim2.fromScale(0.9, 0.8)
	g.Enabled = true
end

return StatusStripView
