--!strict
-- The "your data did not load" strip (carter's pick A, Top Strip): a coral band across the top with
-- one short sentence and, when it helps, a TRY AGAIN button. It never blocks play: the player can
-- still press PLAY underneath. A slow load uses the gold version with no button.

local Players = game:GetService("Players")

local UiKit = require(script.Parent.Parent.Hud.UiKit)
local UiLayers = require(script.Parent.Parent.Ui.UiLayers)
local DataNotice = require(script.Parent.DataNotice)

local DeviceZones = require(script.Parent.Parent.Ui.DeviceZones)
local ScreenMap = require(script.Parent.Parent.Ui.ScreenMap)

local StatusStripView = {}

-- dp from the screen's left edge: past the widest notch (64) and Roblox's menu + chat buttons.
local TEXT_LEFT = DeviceZones.NOTCH_MAX + DeviceZones.LEFT_CLUSTER_WIDTH
local STRIP_HEIGHT = ScreenMap.saveStripHeight -- share of the screen height
local RETRY_RIGHT = DeviceZones.NOTCH_MAX + 8 -- dp from the right edge

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
	strip.Size = UDim2.fromScale(1, STRIP_HEIGHT)
	strip.BorderSizePixel = 0
	strip.BackgroundColor3 = UiKit.color(look.danger)
	strip.Parent = g
	local stripMax = Instance.new("UISizeConstraint") -- on a tablet it stops growing
	stripMax.MaxSize = Vector2.new(math.huge, ScreenMap.saveStripMax)
	stripMax.Parent = strip

	local edge = Instance.new("Frame") -- thick navy bottom line, like the other stickers
	edge.Name = "Edge"
	edge.AnchorPoint = Vector2.new(0, 1)
	edge.Position = UDim2.fromScale(0, 1)
	edge.Size = UDim2.new(1, 0, 0, 4)
	edge.BackgroundColor3 = UiKit.color(look.outline)
	edge.BorderSizePixel = 0
	edge.Active = false
	edge.Parent = strip

	-- The text starts right of Roblox's own menu and chat buttons (top left, drawn over this strip) and the
	-- notch; TRY AGAIN keeps clear of the notch on the right. See Ui/DeviceZones and tests/phone_audit.
	message = UiKit.label(strip, "Message", {
		size = UDim2.new(0.78, -(TEXT_LEFT + RETRY_RIGHT + 8), 0.8, 0),
		position = UDim2.new(0, TEXT_LEFT, 0.1, 0),
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
	retry.Position = UDim2.new(1, -RETRY_RIGHT, 0.48, 0)
	retry.Size = UDim2.fromScale(0.22, 0.9)
	local retryMin = Instance.new("UISizeConstraint") -- never under a thumb's size, whatever the strip height works out to
	retryMin.MinSize = Vector2.new(0, DeviceZones.MIN_TAP)
	retryMin.Parent = retry
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
		then UDim2.new(0.78, -(TEXT_LEFT + RETRY_RIGHT + 8), 0.8, 0)
		else UDim2.new(1, -(TEXT_LEFT + RETRY_RIGHT), 0.8, 0)
	g.Enabled = true
end

return StatusStripView
