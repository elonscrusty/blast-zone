--!strict
-- PLACEHOLDER game mode buttons (piece G24). Claude Design makes the real look; this is only enough to test the logic.
-- One big button per mode with its vote count; a mode the player has not unlocked shows a padlock and the level it
-- needs. Tapping asks the server; the server decides (level, window) and sends back the truth.
-- Phone first: Components.button keeps every button at least the minimum touch size; tap, click or gamepad A all work.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ModeRules = require(Shared.Modes.ModeRules)

local Net = require(script.Parent.Parent:WaitForChild("Core"):WaitForChild("Net"))
local Components = require(script.Parent.Parent.Ui.Components)

local ModeClientSystem = {}
ModeClientSystem.order = 200

local BUTTON_WIDTH = 0.2 -- of the screen
local BUTTON_GAP = 0.02
local BUTTON_HEIGHT = 0.1
local ROW_TOP = 0.3 -- under the map vote row (0.18)

-- The words on one button. Pure, so the lock text is the same everywhere.
local function labelFor(entry: ModeRules.Choice, yourVote: string?): string
	if entry.locked then
		return `🔒 {entry.name}  Lv {entry.unlockLevel}`
	end
	return `{entry.name}  {entry.votes}` .. (if yourVote == entry.id then "  ✓" else "")
end

function ModeClientSystem.start()
	local gui, root = Components.screen("ModeVote", "MatchFlowExtra")
	gui.Enabled = false

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = root

	local function render(state: ModeRules.State)
		gui.Enabled = state.open and #state.modes > 1
		row:ClearAllChildren()
		local count = #state.modes
		local total = count * BUTTON_WIDTH + (count - 1) * BUTTON_GAP
		for i, entry in state.modes do
			local style: Components.ButtonStyle = if entry.locked
				then "quiet"
				elseif state.yourVote == entry.id then "primary"
				else "secondary"
			local button = Components.button(row, root, entry.id, {
				text = labelFor(entry, state.yourVote),
				style = style,
				onPress = function()
					if not entry.locked then
						Net.send("ModeVoteRequest", entry.id)
					end
				end,
			})
			button.AnchorPoint = Vector2.new(0, 0)
			button.Position =
				UDim2.fromScale(0.5 - total / 2 + (i - 1) * (BUTTON_WIDTH + BUTTON_GAP), ROW_TOP)
			button.Size = UDim2.fromScale(BUTTON_WIDTH, BUTTON_HEIGHT)
		end
	end

	Net.on("ModeState", render)
	Net.send("ModeStateRequest")
end

return ModeClientSystem
