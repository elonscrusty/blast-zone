--!strict
-- Map vote buttons (piece 33). One big button per map, each with its vote count. Tapping asks the server;
-- the server decides and sends back the truth. Phone first: the row sits in its own band under the bots
-- banner (Ui/ScreenMap.mapVote) and the buttons share its width, so any number of maps fits and nothing
-- covers the banner or the lobby menu. Built from Ui/Components.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VoteFlow = require(Shared.MapVote.VoteFlow)

local Net = require(script.Parent.Parent:WaitForChild("Core"):WaitForChild("Net"))
local Components = require(script.Parent.Parent.Ui.Components)
local Layout = require(script.Parent.Parent.Hud.Layout)
local ScreenMap = require(script.Parent.Parent.Ui.ScreenMap)

local MapVoteClientSystem = {}
MapVoteClientSystem.order = 200

local GAP = 6 -- points between buttons

function MapVoteClientSystem.start()
	local gui, root = Components.screen("MapVote", "MatchFlowExtra")
	gui.Enabled = false

	local row = Components.piece(root, "Row", ScreenMap.mapVote, nil, Layout.LOBBY_MIN_ASPECT)

	local function render(state: VoteFlow.State)
		gui.Enabled = state.open and #state.maps > 1
		row:ClearAllChildren()
		local count = math.max(1, #state.maps)
		for i, entry in state.maps do
			local voted = state.yourVote == entry.id
			local button = Components.button(row, root, entry.id, {
				text = `{entry.name}  {entry.votes}` .. (if voted then "  ✓" else ""),
				style = if voted then "good" else "secondary",
				onPress = function()
					Net.send("MapVoteRequest", entry.id)
				end,
			})
			-- placed by hand (no list layout): each button brings a shadow frame that must not take a slot
			button.Position = UDim2.new((i - 1) / count, 0, 0, 0)
			button.Size = UDim2.new(1 / count, -GAP, 1, 0)
		end
	end

	Net.on("MapVoteState", render)
	Net.send("MapVoteStateRequest")
end

return MapVoteClientSystem
