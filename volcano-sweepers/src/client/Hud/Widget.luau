--!strict
-- The tiny shape every HUD widget returns. Hud places `root` from the layout rectangles and calls
-- `layout` (if there is one) so a widget can react to its new size.

local UiMath = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Ui.UiMath)

export type Widget = {
	root: GuiObject,
	destroy: () -> (),
	layout: ((rect: UiMath.Rect, all: UiMath.Layout) -> ())?,
}

return {}
