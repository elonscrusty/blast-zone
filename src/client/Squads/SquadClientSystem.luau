--!strict
-- PLACEHOLDER squad buttons and squad list (video 3 gap 11). Claude Design makes the real look; this is only
-- enough to test the logic. Vote: one button per mode with its count. List: your teammates and who is out.
-- Looks come from Ui/Components and Ui/Tokens roles only. Phone first: buttons keep the minimum touch size.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Net = require(script.Parent.Parent:WaitForChild("Core"):WaitForChild("Net"))
local Components = require(script.Parent.Parent.Ui.Components)
local SquadModel = require(script.Parent.SquadModel)

local SquadClientSystem = {}
SquadClientSystem.order = 200

type VoteMode = { id: string, name: string, size: number, votes: number }
type VoteState = { open: boolean, modes: { VoteMode }, yourVote: string?, chosen: string? }

function SquadClientSystem.start()
	if not Config.Squads.enabled or Players.LocalPlayer == nil then
		return
	end

	-- ===== vote buttons (lobby) =====
	local voteGui, voteRoot = Components.screen("SquadVote", "MatchFlowExtra")
	voteGui.Enabled = false
	local buttons: { Instance } = {}

	local function renderVote(state: VoteState)
		voteGui.Enabled = state.open and #state.modes > 1
		for _, old in buttons do
			old:Destroy()
		end
		buttons = {}
		for i, mode in state.modes do
			local button = Components.button(voteRoot, voteRoot, mode.id, {
				text = mode.name
					.. (if mode.votes > 0 then `  {mode.votes}` else "")
					.. (if state.yourVote == mode.id then "  ✓" else ""),
				style = if state.yourVote == mode.id then "primary" else "quiet",
				onPress = function()
					Net.send("SquadVoteRequest", mode.id)
				end,
			})
			button.AnchorPoint = Vector2.new(0, 0)
			button.Position = UDim2.fromScale(0.04 + (i - 1) * 0.32, 0.3)
			button.Size = UDim2.fromScale(0.28, 0.1)
			table.insert(buttons, button)
			local shadow = voteRoot:FindFirstChild(button.Name .. "Shadow")
			if shadow then
				table.insert(buttons, shadow)
			end
		end
	end

	-- ===== squad list (in a match) =====
	local listGui, listRoot = Components.screen("SquadList", "Hud")
	listGui.Enabled = false
	local panel = Components.panel(listRoot, listRoot, "Panel")
	panel.Position = UDim2.fromScale(0.01, 0.32)
	panel.Size = UDim2.fromScale(0.16, 0.18)
	local label = Components.text(panel, listRoot, "List", "caption", {
		align = Enum.TextXAlignment.Left,
		size = UDim2.fromScale(0.9, 0.9),
		position = UDim2.fromScale(0.05, 0.05),
	})

	local function renderList()
		local state = SquadModel.get()
		listGui.Enabled = state.size > 1 and state.team ~= nil
		local lines = { `SQUAD {state.team or ""}` }
		for _, mate in state.mates do
			table.insert(lines, if mate.alive then mate.name else `{mate.name} (out)`)
		end
		label.Text = table.concat(lines, "\n")
	end

	SquadModel.Changed:connect(renderList)
	Net.on("SquadVoteState", renderVote)
	Net.on("SquadState", function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		SquadModel.set({
			size = payload.size,
			team = payload.team,
			mates = payload.mates or {},
		})
	end)
	Net.send("SquadVoteStateRequest")
end

return SquadClientSystem
