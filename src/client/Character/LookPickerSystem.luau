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
local LobbyMenu = require(script.Parent.Parent.Ui.LobbyMenu)

local LookPickerSystem = {}

local localPlayer = Players.LocalPlayer
-- The looks slot is 152 design points tall: three 48 point buttons and two 4 point gaps (LobbyLayout).
local BUTTON_SHARE = 48 / 152
local GAP_SHARE = 4 / 152
local NAVY = Color3.fromHex(Config.Palette.Navy)
local CYAN = Color3.fromHex(Config.Palette.Cyan)
local WHITE = Color3.fromRGB(243, 241, 234)

-- Phases where a body is not in a fight: the buttons show only here.
local CALM = {
	[MatchPhase.Waiting] = true,
	[MatchPhase.Countdown] = true,
	[MatchPhase.Results] = true,
	[MatchPhase.Resetting] = true,
}

function LookPickerSystem.start()
	-- Lives in the lobby layout's "looks" slot (Ui/LobbyLayout): three buttons stacked, 48 points each.
	local row = Instance.new("Frame")
	row.Name = "LookPicker"
	row.BackgroundTransparency = 1
	row.Visible = true
	LobbyMenu.dock(row, "looks")
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(GAP_SHARE, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
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
		button.Size = UDim2.fromScale(1, BUTTON_SHARE)
		button.Text = name
		button.Font = Enum.Font.GothamBlack
		button.AutoButtonColor = true
		button.BorderSizePixel = 0
		button.Parent = row
		LobbyMenu.fitText(button, 22)
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
			row.Visible = CALM[state.phase] == true
		end
	end)
end

return LookPickerSystem
