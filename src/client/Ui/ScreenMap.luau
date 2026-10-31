--!strict
-- Where every full-width banner and floating button sits, in one list, on the 780 x 360 design phone
-- (same space as Hud/Layout and Ui/LobbyLayout). Screens place themselves from here instead of inventing
-- numbers, and tests/ui_layers.test.luau checks that nothing in the same phase overlaps on any phone
-- shape. Add a rect here when a screen adds a banner or a floating button; the test tells you what it hits.
--
-- Lobby phase, top to bottom: status chips (y 10-40, HUD) / bots banner / map vote / mode column + menu.

export type Rect = { x: number, y: number, w: number, h: number }

local ScreenMap = {}

-- ===== lobby (waiting, countdown, results) =====
ScreenMap.botsBanner = { x = 232, y = 60, w = 232, h = 44 } :: Rect -- under the save strip (top 16%, y 0-58)
-- 1 row; buttons share the width. Starts right of the WINS / ELIMS / GAMES card (statsCard ends x 222) and
-- stops left of the DAILY column (x 508), so it clears both on every phone.
ScreenMap.mapVote = { x = 230, y = 108, w = 270, h = 46 } :: Rect
-- The coral "saving is off" strip across the top of the full screen (Onboarding/StatusStripView), as a share of the
-- screen height. Lobby pieces start below it (the audit checks).
ScreenMap.saveStripHeight = 0.13
ScreenMap.saveStripMax = 64 -- dp: on a tablet the strip stops growing

-- WINS / ELIMS / GAMES, top left under Roblox's own menu and chat buttons (see DeviceZones.robloxTopLeft).
ScreenMap.statsCard = { x = 16, y = 72, w = 206, h = 56 } :: Rect
-- A column left of the PLAY menu, beside the look picker (ScreenMap.lookPicker is x 56-160).
ScreenMap.modeVote = { x = 168, y = 160, w = 104, h = 152 } :: Rect

-- The SCRAP / STARS bar, top right (Wallet/WalletBarSystem). It is placed in design points from the top right
-- corner of the safe area: inset, then a width and height that are shares of the screen between a floor and a ceiling.
ScreenMap.walletBar = {
	inset = 12,
	widthShare = 0.32,
	heightShare = 0.1,
	minW = 170,
	minH = 36,
	maxW = 420,
	maxH = 50,
	noteGap = 6, -- the "not saved" note sits this far to the LEFT of the bar, as wide as the bar
	noteHeightShare = 0.5, -- of the bar's height
}

-- The three fighter-look buttons, left column (LookPickerSystem). Same shrink rule as the rest of the lobby.
ScreenMap.lookPicker = { x = 56, y = 160, w = 104, h = 152 } :: Rect

-- The round EMOTE button, bottom right (16 point gutter, 72 points wide). It never shrinks with the lobby.
ScreenMap.emote = { x = 692, y = 272, w = 72, h = 72 } :: Rect

-- ===== spectating (out of the fight) =====
ScreenMap.spectate = { x = 240, y = 288, w = 300, h = 56 } :: Rect

-- ===== in a fight =====
-- Top-left, one short line between the settings gear row (ends y 124) and the heal and sprint buttons (start y 148).
ScreenMap.airdropHint = { x = 64, y = 124, w = 140, h = 22 } :: Rect

-- Pieces that can be on screen together in the lobby (the test checks these against each other and
-- against LobbyLayout.groups).
ScreenMap.lobbyPieces = { "botsBanner", "mapVote", "modeVote", "emote", "statsCard", "lookPicker" }

return ScreenMap
