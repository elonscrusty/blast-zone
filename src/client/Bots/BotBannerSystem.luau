--!strict
-- "Alone? Bots join in 10s" banner with an "Add bots now" button. The server counts the seconds and
-- decides everything (BotFillState shows it, AddBotsRequest asks); this only draws and asks.
-- Phone first: the button is a big touch target and works with a mouse or a controller too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Parent.Core.Net)
local LobbyMenu = require(script.Parent.Parent.Ui.LobbyMenu)

local BotBannerSystem = {}

local TAP_LOCK_SECONDS = 2

local function color(name: string): Color3
	return Color3.fromHex((Config.Palette :: any)[name])
end

function BotBannerSystem.start()
	-- Lives in the lobby layout's "banner" slot (Ui/LobbyLayout), so it can never sit on another piece.
	local panel = Instance.new("Frame")
	panel.Name = "BotBanner"
	panel.BackgroundColor3 = color("Navy")
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Visible = false
	LobbyMenu.dock(panel, "banner")
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = color("RewardGold")
	stroke.Thickness = 2
	stroke.Parent = panel

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromScale(0.04, 0.04)
	text.Size = UDim2.fromScale(0.92, 0.32)
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Text = "Alone? Bots join soon"
	text.Parent = panel
	LobbyMenu.fitText(text, 22)

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.fromScale(0.5, 0.95)
	button.Size = UDim2.fromScale(0.92, 0.58) -- 58% of the 84 point slot: over the 48 point touch minimum
	button.BackgroundColor3 = color("RewardGold")
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = color("Navy")
	button.Text = "Add bots now"
	button.AutoButtonColor = true
	button.Parent = panel
	LobbyMenu.fitText(button, 24)
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
			panel.Visible = true
		else
			panel.Visible = false
		end
	end)
end

return BotBannerSystem
