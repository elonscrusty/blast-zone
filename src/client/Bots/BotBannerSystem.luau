--!strict
-- "Alone? Bots join in 10s" banner with an "Add bots now" button. The server counts the seconds and
-- decides everything (BotFillState shows it, AddBotsRequest asks); this only draws and asks.
-- Phone first: the button is a big touch target and works with a mouse or a controller too.
-- Look: Street Sticker+ "BotsBanner" (cream panel, gold button). Built from Ui/Components.

local Net = require(script.Parent.Parent.Core.Net)
local Components = require(script.Parent.Parent.Ui.Components)

local BotBannerSystem = {}

local TAP_LOCK_SECONDS = 2

-- Top band, under the status chips (design phone 780 x 360). The lobby menu starts under it.
local RECT = { x = 215, y = 48, w = 350, h = 64 }

function BotBannerSystem.start()
	local gui, root = Components.screen("BotBanner", "Popups")
	gui.Enabled = false

	local piece = Components.piece(root, "Piece", RECT)
	local panel = Components.panel(piece, root, "Panel", "panel")
	panel.Size = UDim2.fromScale(1, 1)

	local text = Components.text(panel, root, "Text", "body", {
		text = "Alone? Bots join soon",
		align = Enum.TextXAlignment.Left,
		size = UDim2.fromScale(0.5, 0.7),
		position = UDim2.fromScale(0.05, 0.15),
	})

	local button =
		Components.button(panel, root, "AddBots", { text = "Add bots now", style = "primary" })
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.fromScale(0.97, 0.5)
	button.Size = UDim2.fromScale(0.4, 0.78)

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
end

return BotBannerSystem
