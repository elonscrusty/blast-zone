--!strict
-- PLACEHOLDER map vote buttons (piece 33). Claude Design makes the real look; this is only enough to test the logic.
-- One big button per map, each with its vote count. Tapping asks the server; the server decides and sends back the truth.
-- Phone first: the vote slot is 48 points tall (LobbyLayout checks it), and buttons work by tap or click.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VoteFlow = require(Shared.MapVote.VoteFlow)

local Net = require(script.Parent.Parent:WaitForChild("Core"):WaitForChild("Net"))
local LobbyMenu = require(script.Parent.Parent.Ui.LobbyMenu)

local MapVoteClientSystem = {}
MapVoteClientSystem.order = 200

function MapVoteClientSystem.start()
	-- Lives in the lobby layout's "vote" slot (Ui/LobbyLayout): one row, the buttons share its width.
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Visible = false
	LobbyMenu.dock(row, "vote")

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row

	local function render(state: VoteFlow.State)
		row.Visible = state.open and #state.maps > 1
		for _, child in row:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		local count = math.max(1, #state.maps)
		for _, entry in state.maps do
			local button = Instance.new("TextButton")
			button.Name = entry.id
			-- Equal shares of the row (less the gaps), full slot height: 48 points or more.
			button.Size = UDim2.new(1 / count, -6, 1, 0)
			button.Font = Enum.Font.FredokaOne
			button.Text = `{entry.name}  {entry.votes}`
				.. (if state.yourVote == entry.id then "  ✓" else "")
			button.Parent = row
			LobbyMenu.fitText(button, 24)
			button.Activated:Connect(function()
				Net.send("MapVoteRequest", entry.id)
			end)
		end
	end

	Net.on("MapVoteState", render)
	Net.send("MapVoteStateRequest")
end

return MapVoteClientSystem
