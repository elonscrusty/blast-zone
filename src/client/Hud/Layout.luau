--!strict
-- Where everything on the combat screen sits. Pure numbers so Lune can check them.
-- Design space is a 780 x 360 landscape phone (19.5:9). The UI scales by screen HEIGHT and each
-- piece hugs its nearest screen edge, so tall or wide phones do not stretch or move anything.
--
-- Reserved areas other pieces rely on:
--   CardsBand (piece 08, upgrade cards): bottom centre, between the thumbs.
--   Player: the character stays at screen centre, so that box stays clear.

export type Rect = { x: number, y: number, w: number, h: number }

local Layout = {}

Layout.WIDTH = 780
Layout.HEIGHT = 360
Layout.MIN_TOUCH = 48 -- points, from Config.Settings.minTouchTarget

-- Piece 08 asked for x 26%-74%, y 76%-96% of the screen.
Layout.CardsBand = { x = 202.8, y = 273.6, w = 374.4, h = 72 } :: Rect
-- Where the controlled character is drawn (screen centre). Nothing on the HUD goes here.
Layout.PlayerBox = { x = 330, y = 120, w = 120, h = 120 } :: Rect

-- Read-only display pieces
Layout.regions = {
	vitals = { x = 16, y = 16, w = 136, h = 48 } :: Rect, -- health bar and run level
	status = { x = 311, y = 16, w = 158, h = 28 } :: Rect, -- players left and zone timer
	warning = { x = 285, y = 52, w = 210, h = 24 } :: Rect, -- one warning at a time
	minimap = { x = 676, y = 16, w = 88, h = 88 } :: Rect,
	weapon = { x = 590, y = 140, w = 100, h = 56 } :: Rect, -- also the weapon-swap button
	-- Touch controls
	moveStick = { x = 24, y = 210, w = 126, h = 126 } :: Rect,
	fireStick = { x = 630, y = 210, w = 126, h = 126 } :: Rect,
	slide = { x = 690, y = 138, w = 60, h = 60 } :: Rect,
	reload = { x = 578, y = 208, w = 50, h = 50 } :: Rect,
	settings = { x = 16, y = 82, w = 36, h = 36 } :: Rect, -- small gear; the one allowed under 48
}

-- Circles keep their shape on any screen; everything else scales by height too.
Layout.circles = { minimap = true, moveStick = true, fireStick = true, slide = true, reload = true }

-- What counts as a thumb target (must be 48 points or more, and clear of the cards band).
Layout.touchTargets = { "moveStick", "fireStick", "slide", "reload", "weapon" }

function Layout.mirror(r: Rect): Rect
	return { x = Layout.WIDTH - r.x - r.w, y = r.y, w = r.w, h = r.h }
end

function Layout.overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function Layout.inside(r: Rect): boolean
	return r.x >= 0 and r.y >= 0 and r.x + r.w <= Layout.WIDTH and r.y + r.h <= Layout.HEIGHT
end

export type Placement = {
	anchorX: number, -- 0 left edge, 0.5 centre, 1 right edge
	anchorY: number,
	posX: number, -- scale 0..1
	posY: number,
	sizeY: number, -- scale of screen height
	aspect: number, -- width / height
}

-- Which screen edge a piece hugs, and how big it is relative to screen height.
function Layout.place(r: Rect, leftHanded: boolean?): Placement
	local rect = if leftHanded then Layout.mirror(r) else r
	local cx = (rect.x + rect.w / 2) / Layout.WIDTH
	local cy = (rect.y + rect.h / 2) / Layout.HEIGHT
	local anchorX = if cx < 0.4 then 0 elseif cx > 0.6 then 1 else 0.5
	local anchorY = if cy < 0.5 then 0 else 1
	local posX = if anchorX == 0
		then rect.x / Layout.WIDTH
		elseif anchorX == 1 then (rect.x + rect.w) / Layout.WIDTH
		else cx
	local posY = if anchorY == 0 then rect.y / Layout.HEIGHT else (rect.y + rect.h) / Layout.HEIGHT
	return {
		anchorX = anchorX,
		anchorY = anchorY,
		posX = posX,
		posY = posY,
		sizeY = rect.h / Layout.HEIGHT,
		aspect = rect.w / rect.h,
	}
end

return Layout
