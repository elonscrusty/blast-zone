--!strict
-- The look of the big moments (piece 44): name plates, the ring under your feet, the banner and the
-- level-up burst. Three tries (A, B, C) so carter can pick; the ones not picked stay as skins.
-- Colours are ROLES from Ui/Tokens, never hex, so a new skin from Claude Design restyles them too.
-- Pure data so Lune can test it. Config.Moments.style says which one is drawn.

export type PlateStyle = {
	fill: string, -- colour role of the plate behind the name
	fillAlpha: number, -- 0 solid .. 1 clear
	outline: string,
	outlineThickness: number, -- pixels; 0 = none
	corner: number, -- 0 square .. 0.5 pill
	ink: string, -- the name
	barFill: string,
	barLow: string,
	barTrack: string,
	badgeFill: string,
	badgeInk: string,
	badgeCorner: number, -- 0.5 = circle, 0.2 = rounded square, 0 = square
	badgeSide: "left" | "top",
}

export type RingStyle = {
	mine: string, -- colour role of your ring
	other: string, -- colour role of an enemy ring (if Config.Plates.enemyRing)
	transparency: number,
	pulse: boolean, -- breathes slowly
}

export type BannerStyle = {
	fill: string,
	ink: string,
	outline: string,
	corner: number,
	emblemFill: boolean, -- true: the emblem sits in a filled badge of the banner's tone
	toneStripe: boolean, -- true: a thin stripe of the tone along the bottom
	subtitleInk: string,
}

export type BurstStyle = {
	colors: { string }, -- colour roles the sparks pick from
	ring: string, -- colour role of the ring that opens on the floor
	arrowInk: string,
	arrowOutline: string,
	sparkSize: number, -- studs
}

export type Style = {
	id: string,
	name: string,
	plate: PlateStyle,
	ring: RingStyle,
	banner: BannerStyle,
	burst: BurstStyle,
}

local MomentStyles = {}

MomentStyles.list = {
	-- A "Sticker Tag": cream plate, thick navy edge, round gold badge (matches the HUD look).
	A = {
		id = "A",
		name = "Sticker Tag",
		plate = {
			fill = "panel",
			fillAlpha = 0,
			outline = "outline",
			outlineThickness = 2,
			corner = 0.4,
			ink = "ink",
			barFill = "danger",
			barLow = "danger",
			barTrack = "dim",
			badgeFill = "accent",
			badgeInk = "inkOnAccent",
			badgeCorner = 0.5,
			badgeSide = "left",
		},
		ring = { mine = "good", other = "danger", transparency = 0.25, pulse = false },
		banner = {
			fill = "panel",
			ink = "ink",
			outline = "outline",
			corner = 0.32,
			emblemFill = true,
			toneStripe = false,
			subtitleInk = "ink",
		},
		burst = {
			colors = { "accent", "inkOnDark", "info" },
			ring = "accent",
			arrowInk = "accent",
			arrowOutline = "outline",
			sparkSize = 0.7,
		},
	},
	-- B "Neon Tag": dark glass plate, thin bright edge, square badge, bright ring that breathes.
	B = {
		id = "B",
		name = "Neon Tag",
		plate = {
			fill = "backdrop",
			fillAlpha = 0.25,
			outline = "info",
			outlineThickness = 1,
			corner = 0.15,
			ink = "inkOnDark",
			barFill = "info",
			barLow = "danger",
			barTrack = "panelAlt",
			badgeFill = "info",
			badgeInk = "outline",
			badgeCorner = 0.2,
			badgeSide = "left",
		},
		ring = { mine = "info", other = "danger", transparency = 0.15, pulse = true },
		banner = {
			fill = "backdrop",
			ink = "inkOnDark",
			outline = "info",
			corner = 0.1,
			emblemFill = false,
			toneStripe = true,
			subtitleInk = "info",
		},
		burst = {
			colors = { "info", "inkOnDark", "good" },
			ring = "info",
			arrowInk = "info",
			arrowOutline = "backdrop",
			sparkSize = 0.5,
		},
	},
	-- C "Arcade Medal": no box, bold outlined name, level as a round medal on top, big confetti burst.
	C = {
		id = "C",
		name = "Arcade Medal",
		plate = {
			fill = "backdrop",
			fillAlpha = 1,
			outline = "outline",
			outlineThickness = 0,
			corner = 0.5,
			ink = "inkOnDark",
			barFill = "good",
			barLow = "danger",
			barTrack = "backdrop",
			badgeFill = "accent",
			badgeInk = "inkOnAccent",
			badgeCorner = 0.5,
			badgeSide = "top",
		},
		ring = { mine = "good", other = "danger", transparency = 0.4, pulse = true },
		banner = {
			fill = "accent",
			ink = "inkOnAccent",
			outline = "outline",
			corner = 0.5,
			emblemFill = true,
			toneStripe = false,
			subtitleInk = "inkOnAccent",
		},
		burst = {
			colors = { "accent", "danger", "info", "good" },
			ring = "good",
			arrowInk = "good",
			arrowOutline = "outline",
			sparkSize = 0.9,
		},
	},
} :: { [string]: Style }

MomentStyles.ids = { "A", "B", "C" }

function MomentStyles.get(id: string?): Style
	return MomentStyles.list[id or "A"] or MomentStyles.list.A
end

return MomentStyles
