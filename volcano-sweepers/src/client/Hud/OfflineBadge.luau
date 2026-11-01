--!strict
-- Tiny, friendly note when this session cannot save. The server sends State keys `offline` (the save
-- is not loaded) and `offlineRetrying` (it is still trying in the background):
--   offline + retrying   "⏳ Loading your save..."   (kind words: it usually comes back by itself)
--   offline only         "👤 Guest mode — not saving"
-- Without `offline` the badge never shows. Format.offlineBadge (pure, tested) picks the words.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Ui.Format)
local UiMath = require(Shared.Ui.UiMath)
local Components = require(script.Parent.Parent.Ui.Components)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Context = require(script.Parent.Context)
local Widget = require(script.Parent.Widget)

local OfflineBadge = {}

function OfflineBadge.new(parent: Instance, ctx: Context.Context): Widget.Widget
	local pill = Components.Pill({
		parent = parent,
		name = "OfflineBadge",
		size = UDim2.fromOffset(UiMath.K.offlineW, UiMath.K.offlineH),
		icon = "👤",
		text = "",
		textSize = Theme.text.tiny,
		align = Enum.TextXAlignment.Left,
	})
	pill.root.Visible = false

	local shownText = ""
	local function refresh()
		local view = ctx.view()
		local note = Format.offlineBadge(view.offline, view.offlineRetrying)
		if note ~= nil and note.text ~= shownText then
			shownText = note.text
			pill.setText(note.text)
			local icon = pill.icon
			if icon ~= nil and icon:IsA("TextLabel") then
				icon.Text = note.icon
			end
		end
		local on = note ~= nil
		if on == pill.root.Visible then
			return
		end
		pill.root.Visible = on
		if on then
			Components.punch(pill.root, 0.1)
		end
	end
	ctx.watch({ "offline", "offlineRetrying" }, refresh)

	return {
		root = pill.root,
		destroy = function()
			pill.root:Destroy()
		end,
	}
end

return OfflineBadge
