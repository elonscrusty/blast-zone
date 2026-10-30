--!strict
-- Where everything on the combat screen sits. Pure numbers so Lune can check them.
-- Design space is a 780 x 360 landscape phone (19.5:9). The UI scales by screen HEIGHT and each
-- piece hugs its nearest screen edge, so tall or wide phones do not stretch or move anything.
--
-- Reserved areas other pieces rely on:
--   CardsBand (piece 08, upgrade cards): bottom centre, between the thumbs.
--   Player: the character stays at screen centre, so that box stays clear.
-- Upgrade picks: three chips (chip1..3) by the aim thumb; the move thumb never lifts.

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
	weapon = { x = 586, y = 72, w = 88, h = 48 } :: Rect, -- also the weapon-swap button
	-- Touch controls
	moveStick = { x = 24, y = 210, w = 126, h = 126 } :: Rect,
	fireStick = { x = 630, y = 210, w = 126, h = 126 } :: Rect,
	slide = { x = 690, y = 138, w = 60, h = 60 } :: Rect,
	reload = { x = 578, y = 208, w = 50, h = 50 } :: Rect,
	heal = { x = 24, y = 148, w = 52, h = 52 } :: Rect, -- piece 42: use a heal pack; above the move stick
	sprint = { x = 84, y = 148, w = 52, h = 52 } :: Rect, -- piece 45: toggle running; beside heal, above the move stick
	settings = { x = 16, y = 80, w = 44, h = 44 } :: Rect, -- gear; just under 48 so it stays out of the way
	-- Upgrade pick chips (only drawn while an offer is up): a row above the aim thumb that mirrors
	-- the three cards, so a pick never needs the move thumb. Over the open street, not the card band.
	chip1 = { x = 524, y = 132, w = 48, h = 48 } :: Rect,
	chip2 = { x = 580, y = 132, w = 48, h = 48 } :: Rect,
	chip3 = { x = 636, y = 132, w = 48, h = 48 } :: Rect,
}

-- Where a thumb may land and the stick appears under it (Settings "Floating sticks"). These sit
-- under the buttons on purpose, so a touch on a button is a button and anything else is the
-- stick. The two ends keep out of the card band and the gear.
Layout.zones = {
	moveZone = { x = 8, y = 150, w = 192, h = 196 } :: Rect,
	fireZone = { x = 580, y = 150, w = 192, h = 196 } :: Rect,
	-- The free side of the screen turns the camera when dragged (right-hand play; mirrored for
	-- left-hand play). It sits under the fire zone and every button, so only a touch that lands on
	-- neither one turns the view. It stops above the card band and starts right of the player.
	lookZone = { x = 452, y = 0, w = 328, h = 270 } :: Rect,
}

-- Circles keep their shape on any screen; everything else scales by height too.
Layout.circles = {
	minimap = true,
	moveStick = true,
	fireStick = true,
	slide = true,
	reload = true,
	heal = true,
	sprint = true,
	chip1 = true,
	chip2 = true,
	chip3 = true,
}

-- What counts as a thumb target (must be 48 points or more, and clear of the cards band).
Layout.touchTargets = {
	"moveStick",
	"fireStick",
	"slide",
	"reload",
	"heal",
	"sprint",
	"weapon",
	"chip1",
	"chip2",
	"chip3",
}

-- Which chip rect to place chip `index` with, so the numbers still read 1 2 3 from left to right
-- when the whole control set is mirrored for left-handed play.
function Layout.chipName(index: number, leftHanded: boolean?): string
	return "chip" .. (if leftHanded then 4 - index else index)
end

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

-- Narrowest screen the layout keeps its design sizes on (16:9). Narrower screens (tablets) get
-- the 16:9 layout shrunk evenly, so nothing slides into anything else.
Layout.MIN_ASPECT = 16 / 9

-- Which screen edge a piece hugs, and how big it is relative to screen height.
-- `screenAspect` (width / height of the real screen) keeps each piece's distance to its edge in
-- height units, so pieces near the same edge keep their spacing on any phone shape. Leave it out
-- to get the design screen.
function Layout.place(r: Rect, leftHanded: boolean?, screenAspect: number?): Placement
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
	local sizeY = rect.h / Layout.HEIGHT
	if screenAspect and screenAspect > 0 then
		local shrink = math.min(1, screenAspect / Layout.MIN_ASPECT)
		local k = (Layout.WIDTH / Layout.HEIGHT) / screenAspect * shrink
		posX = if anchorX == 0
			then posX * k
			elseif anchorX == 1 then 1 - (1 - posX) * k
			else 0.5 + (posX - 0.5) * k
		posY = if anchorY == 0 then posY * shrink else 1 - (1 - posY) * shrink
		sizeY *= shrink
	end
	return {
		anchorX = anchorX,
		anchorY = anchorY,
		posX = posX,
		posY = posY,
		sizeY = sizeY,
		aspect = rect.w / rect.h,
	}
end

-- Where a piece really lands on a screen `screenAspect` wide, in design-height units (the screen
-- is 360 tall and 360 * screenAspect wide). Used by tests to look for overlaps on real phones.
function Layout.onScreen(r: Rect, screenAspect: number, leftHanded: boolean?): Rect
	local p = Layout.place(r, leftHanded, screenAspect)
	local screenW = Layout.HEIGHT * screenAspect
	local h = p.sizeY * Layout.HEIGHT
	local w = h * p.aspect
	return {
		x = p.posX * screenW - p.anchorX * w,
		y = p.posY * Layout.HEIGHT - p.anchorY * h,
		w = w,
		h = h,
	}
end

return Layout
