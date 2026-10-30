--!strict
-- Three big touch buttons (Runner, Courier, Spark) along the bottom while no fight is on, so you can try
-- each fighter. The server decides (SetLookRequest); this only draws the buttons and asks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Looks = require(Shared.Character.Looks)
local MatchPhase = require(Shared.MatchPhase)
local Net = require(script.Parent.Parent.Core.Net)
local UiLayers = require(script.Parent.Parent.Ui.UiLayers)

local LookPickerSystem = {}

local localPlayer = Players.LocalPlayer
local NAVY = Color3.fromHex(Config.Palette.Navy)
local CYAN = Color3.fromHex(Config.Palette.Cyan)
local WHITE = Color3.fromRGB(243, 241, 234)
local BUTTON = Vector2.new(104, 48) -- points: above the 48 point touch minimum

-- Phases where a body is not in a fight: the buttons show only here.
local CALM = {
	[MatchPhase.Waiting] = true,
	[MatchPhase.Countdown] = true,
	[MatchPhase.Results] = true,
	[MatchPhase.Resetting] = true,
}

function LookPickerSystem.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "LookPicker"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = UiLayers.Calm
	gui.Enabled = true

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -12)
	row.Size = UDim2.new(0, BUTTON.X * 3 + 16, 0, BUTTON.Y)
	row.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = row

	local buttons: { [string]: TextButton } = {}
	local function paint()
		local worn = localPlayer:GetAttribute(Config.Character.lookAttribute)
		if type(worn) ~= "string" then
			worn = Config.Character.defaultLook
		end
		for name, button in buttons do
			local on = name == worn
			button.BackgroundColor3 = if on then CYAN else NAVY
			button.TextColor3 = if on then NAVY else WHITE
		end
	end

	for i, name in Looks.NAMES do
		local button = Instance.new("TextButton")
		button.Name = name
		button.LayoutOrder = i
		button.Size = UDim2.fromOffset(BUTTON.X, BUTTON.Y)
		button.Text = name
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 16
		button.AutoButtonColor = true
		button.BorderSizePixel = 0
		button.Parent = row
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = button
		local stroke = Instance.new("UIStroke")
		stroke.Color = WHITE
		stroke.Thickness = 2
		stroke.Parent = button
		button.Activated:Connect(function()
			Net.send("SetLookRequest", name)
		end)
		buttons[name] = button
	end

	localPlayer:GetAttributeChangedSignal(Config.Character.lookAttribute):Connect(paint)
	paint()

	Net.on("MatchState", function(state: any)
		if type(state) == "table" then
			gui.Enabled = CALM[state.phase] == true
		end
	end)
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

return LookPickerSystem
