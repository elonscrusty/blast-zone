--!strict
-- Where lobby buttons go. Same design space as the HUD (780 x 360 landscape phone, see
-- Hud/Layout.luau). Buttons sit in groups; a group is placed as one block by height and hugs its
-- nearest screen edge, and each slot keeps its place inside its group, so buttons can never slide
-- into each other on a wider or narrower phone.
--
-- Pieces that add a lobby button use a slot here (LobbyMenu.slot(name)), never their own spot.
-- Need a new one? Add a slot below and the tests check it fits. Pure numbers for Lune.

export type Rect = { x: number, y: number, w: number, h: number }

local LobbyLayout = {}

LobbyLayout.WIDTH = 780
LobbyLayout.HEIGHT = 360
LobbyLayout.MIN_TOUCH = 48
LobbyLayout.GAP = 6 -- room for the hard shadow under a button

-- Top of the screen is kept for banners (bots banner, messages). Lobby buttons start below this.
LobbyLayout.bannerBottom = 178

LobbyLayout.groups = {
	menu = { x = 280, y = 180, w = 220, h = 132 } :: Rect, -- centre column
	side = { x = 56, y = 160, w = 104, h = 152 } :: Rect, -- left column, clear of the notch
	right = { x = 620, y = 62, w = 104, h = 272 } :: Rect, -- right column, clear of the notch and of the save-message strip (top 16%, y 0-58)
	more = { x = 508, y = 208, w = 104, h = 104 } :: Rect, -- between the centre and right columns (piece 48)
}

export type Slot = { group: string, rect: Rect, touch: boolean }

LobbyLayout.slots = {
	status = { group = "menu", rect = { x = 280, y = 180, w = 220, h = 22 }, touch = false } :: Slot,
	play = { group = "menu", rect = { x = 280, y = 208, w = 220, h = 50 }, touch = true } :: Slot,
	settings = { group = "menu", rect = { x = 280, y = 264, w = 106, h = 48 }, touch = true } :: Slot,
	track = { group = "menu", rect = { x = 394, y = 264, w = 106, h = 48 }, touch = true } :: Slot, -- piece 18
	looks = { group = "side", rect = { x = 56, y = 160, w = 104, h = 152 }, touch = true } :: Slot, -- fighter looks
	chests = { group = "right", rect = { x = 620, y = 62, w = 104, h = 48 }, touch = true } :: Slot, -- gap 19
	shop = { group = "right", rect = { x = 620, y = 174, w = 104, h = 48 }, touch = true } :: Slot, -- Scrap Shop
	bench = { group = "more", rect = { x = 508, y = 208, w = 104, h = 48 }, touch = true } :: Slot, -- video 3 gap 14
	loadout = { group = "right", rect = { x = 620, y = 230, w = 104, h = 48 }, touch = true } :: Slot, -- piece 19
	daily = { group = "right", rect = { x = 620, y = 286, w = 104, h = 48 }, touch = true } :: Slot, -- piece 25
	season = { group = "right", rect = { x = 620, y = 118, w = 104, h = 48 }, touch = true } :: Slot, -- video 3 gap 20
	missions = { group = "more", rect = { x = 508, y = 264, w = 104, h = 48 }, touch = true } :: Slot, -- piece 48
}

-- A slot's place inside its group, as scales of the group (for Position and Size).
function LobbyLayout.relative(name: string): (number, number, number, number)
	local slot = LobbyLayout.slots[name]
	assert(slot, "unknown lobby slot " .. name)
	local g = LobbyLayout.groups[slot.group]
	local r = slot.rect
	return (r.x - g.x) / g.w, (r.y - g.y) / g.h, r.w / g.w, r.h / g.h
end

return LobbyLayout
