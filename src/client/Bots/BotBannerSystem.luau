--!strict
-- "Alone? Bots join in 10s" banner with an "Add bots now" button. The server counts the seconds and
-- decides everything (BotFillState shows it, AddBotsRequest asks); this only draws and asks.
-- Phone first: the button is a big touch target and works with a mouse or a controller too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Parent.Core.Net)
local UiLayers = require(script.Parent.Parent.Ui.UiLayers)

local BotBannerSystem = {}

local TAP_LOCK_SECONDS = 2

local function color(name: string): Color3
	return Color3.fromHex((Config.Palette :: any)[name])
end

function BotBannerSystem.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BotBanner"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = UiLayers.Popups
	gui.IgnoreGuiInset = false
	gui.Enabled = false

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 8) -- top band; the lobby menu starts under it (LobbyLayout.bannerBottom)
	panel.Size = UDim2.new(0.9, 0, 0, 108)
	panel.BackgroundColor3 = color("Navy")
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = color("RewardGold")
	stroke.Thickness = 2
	stroke.Parent = panel
	local fit = Instance.new("UISizeConstraint") -- 90% of a small phone, never wider than 300
	fit.MaxSize = Vector2.new(300, 108)
	fit.Parent = panel

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(8, 8)
	text.Size = UDim2.new(1, -16, 0, 34)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 20
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Text = "Alone? Bots join soon"
	text.Parent = panel

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -10)
	button.Size = UDim2.new(1, -24, 0, 48)
	button.BackgroundColor3 = color("RewardGold")
	button.Font = Enum.Font.GothamBold
	button.TextSize = 20
	button.TextColor3 = color("Navy")
	button.Text = "Add bots now"
	button.AutoButtonColor = true
	button.Parent = panel
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 10)
	buttonCorner.Parent = button

	local lockedUntil = 0
	button.Activated:Connect(function()
		if os.clock() < lockedUntil then
			return
		end
		lockedUntil = os.clock() + TAP_LOCK_SECONDS
		Net.send("AddBotsRequest")
	end)

	Net.on("BotFillState", function(state: any)
		local seconds = if type(state) == "table" then state.secondsLeft else nil
		if type(seconds) == "number" then
			text.Text = `Alone? Bots join in {math.max(0, math.floor(seconds))}s`
			gui.Enabled = true
		else
			gui.Enabled = false
		end
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return BotBannerSystem
