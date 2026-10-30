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
local Layout = require(script.Parent.Parent.Hud.Layout)
local ScreenMap = require(script.Parent.Parent.Ui.ScreenMap)

local ModeClientSystem = {}
ModeClientSystem.order = 200

local GAP = 4 -- points between the stacked buttons

-- The words on one button. Pure, so the lock text is the same everywhere.
local function labelFor(entry: ModeRules.Choice, yourVote: string?): string
	if entry.locked then
		return `{entry.name}  Lv {entry.unlockLevel}` -- locked: dim button, no emoji (design rule)
	end
	return `{entry.name}  {entry.votes}` .. (if yourVote == entry.id then "  ✓" else "")
end

function ModeClientSystem.start()
	local gui, root = Components.screen("ModeVote", "MatchFlowExtra")
	gui.Enabled = false

	-- A column in its own spot (Ui/ScreenMap.modeVote), beside the look picker and left of the PLAY menu.
	local row = Components.piece(root, "Row", ScreenMap.modeVote, nil, Layout.LOBBY_MIN_ASPECT)

	local function render(state: ModeRules.State)
		gui.Enabled = state.open and #state.modes > 1
		row:ClearAllChildren()
		local count = #state.modes
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
			-- placed by hand (no list layout): each button brings a shadow frame that must not take a slot
			button.AnchorPoint = Vector2.new(0, 0)
			local total = ScreenMap.modeVote.h
			local each = (total - GAP * (count - 1)) / count
			button.Size = UDim2.fromScale(1, each / total)
			button.Position = UDim2.fromScale(0, (i - 1) * (each + GAP) / total)
		end
	end

	Net.on("ModeState", render)
	Net.send("ModeStateRequest")
end

return ModeClientSystem
