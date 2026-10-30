--!strict
-- Look B "Street Sticker", picked by carter: cream panels, thick navy outlines, hard drop shadows.
-- Hex strings only (no Roblox types) so Lune can test; UI code turns them into Color3.fromHex.
-- Looks A (Neon Grid) and C (Clean Glass) from the preview are meant to become skins later.

export type Look = {
	id: string,
	name: string,
	panel: string, -- cream panel fill
	ink: string, -- text on panels
	outline: string, -- thick outline and hard shadow
	accent: string, -- gold: slide, level, ready states
	good: string,
	danger: string, -- coral: health, fire, outside-zone
	info: string, -- xp bar
	dim: string,
	strokeScale: number, -- outline thickness as a share of the screen height
	cornerScale: number, -- corner radius as a share of the element height
	shadowOffset: number, -- hard shadow depth as a share of the screen height
}

local Tokens = require("../Ui/Tokens")

local Theme = {}

-- The numbers now come from the shared skin (src/client/Ui/Tokens.luau), so a new skin from
-- Claude Design restyles the HUD too. This file stays so older code that reads Theme keeps working.
local function fromSkin(id: string, skin: Tokens.Skin): Look
	local c = skin.colors
	return {
		id = id,
		name = skin.name,
		panel = c.panel,
		ink = c.ink,
		outline = c.outline,
		accent = c.accent,
		good = c.good,
		danger = c.danger,
		info = c.info,
		dim = c.dim,
		strokeScale = skin.shape.strokeScale,
		cornerScale = skin.shape.cornerScale,
		shadowOffset = skin.shape.shadowOffset,
	}
end

Theme.looks = {
	B = fromSkin("B", Tokens.get("street_sticker")),
}

Theme.defaultLook = "B"

-- The chunky display face. Roblox has no Lilita One, FredokaOne is the closest built-in.
Theme.fontName = Tokens.get(nil).fonts.display

-- With no id, follows the skin picked in Tokens (so a new skin restyles every old caller).
function Theme.get(id: string?): Look
	if id == nil then
		return fromSkin(Tokens.currentId(), Tokens.get(nil))
	end
	return Theme.looks[id] or Theme.looks[Theme.defaultLook]
end

return Theme
