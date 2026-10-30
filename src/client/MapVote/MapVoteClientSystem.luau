--!strict
-- PLACEHOLDER map vote buttons (piece 33). Claude Design makes the real look; this is only enough to test the logic.
-- One big button per map, each with its vote count. Tapping asks the server; the server decides and sends back the truth.
-- Phone first: every button is at least Config.Settings.minTouchTarget tall and works by tap or click.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local VoteFlow = require(Shared.MapVote.VoteFlow)

local Net = require(script.Parent.Parent:WaitForChild("Core"):WaitForChild("Net"))
local UiLayers = require(script.Parent.Parent.Ui.UiLayers)

local MapVoteClientSystem = {}
MapVoteClientSystem.order = 200

local MIN_TOUCH = Config.Settings.minTouchTarget

function MapVoteClientSystem.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MapVote"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = UiLayers.MatchFlowExtra
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.fromScale(0.5, 0.18)
	row.Size = UDim2.fromScale(0.9, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = row

	local function render(state: VoteFlow.State)
		gui.Enabled = state.open and #state.maps > 1
		for _, child in row:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		for _, entry in state.maps do
			local button = Instance.new("TextButton")
			button.Name = entry.id
			button.Size = UDim2.new(0, math.max(MIN_TOUCH * 2.2, 120), 0, MIN_TOUCH)
			button.Font = Enum.Font.FredokaOne
			button.TextScaled = true
			button.Text = `{entry.name}  {entry.votes}`
				.. (if state.yourVote == entry.id then "  ✓" else "")
			button.Parent = row
			button.Activated:Connect(function()
				Net.send("MapVoteRequest", entry.id)
			end)
		end
	end

	Net.on("MapVoteState", render)
	Net.send("MapVoteStateRequest")
end

return MapVoteClientSystem
