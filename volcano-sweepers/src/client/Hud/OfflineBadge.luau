--!strict
-- Tiny, friendly note when this session cannot save: "Guest mode — not saving". The server may
-- send State key `offline` (boolean); without it the badge simply never shows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
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
		text = "Guest mode — not saving",
		textSize = Theme.text.tiny,
		align = Enum.TextXAlignment.Left,
	})
	pill.root.Visible = false

	local function refresh()
		local offline = ctx.view().offline == true
		if offline == pill.root.Visible then
			return
		end
		pill.root.Visible = offline
		if offline then
			Components.punch(pill.root, 0.1)
		end
	end
	ctx.watch({ "offline" }, refresh)

	return {
		root = pill.root,
		destroy = function()
			pill.root:Destroy()
		end,
	}
end

return OfflineBadge
