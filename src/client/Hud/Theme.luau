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

local Theme = {}

Theme.looks = {
	B = {
		id = "B",
		name = "Street Sticker",
		panel = "#FFF4D6",
		ink = "#14243A",
		outline = "#14243A",
		accent = "#FFC44D",
		good = "#7BD88F",
		danger = "#F15B64",
		info = "#36D9E8",
		dim = "#B9AE92",
		strokeScale = 0.0085,
		cornerScale = 0.32,
		shadowOffset = 0.011,
	} :: Look,
}

Theme.defaultLook = "B"

-- The chunky display face. Roblox has no Lilita One, FredokaOne is the closest built-in.
Theme.fontName = "FredokaOne"

function Theme.get(id: string?): Look
	local look = Theme.looks[id or Theme.defaultLook]
	return look or Theme.looks[Theme.defaultLook]
end

return Theme
