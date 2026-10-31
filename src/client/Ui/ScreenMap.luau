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
ScreenMap.botsBanner = { x = 240, y = 44, w = 260, h = 52 } :: Rect
ScreenMap.mapVote = { x = 160, y = 102, w = 340, h = 48 } :: Rect -- 1 row; buttons share the width
-- A column left of the PLAY menu, beside the look picker (LobbyLayout.groups.side is x 56-160).
ScreenMap.modeVote = { x = 168, y = 160, w = 104, h = 152 } :: Rect
-- Above BENCH and MISSIONS in the "more" column of LobbyLayout.
ScreenMap.invite = { x = 508, y = 152, w = 104, h = 48 } :: Rect

-- The round EMOTE button, bottom right (16 point gutter, 72 points wide). It never shrinks with the lobby.
ScreenMap.emote = { x = 692, y = 272, w = 72, h = 72 } :: Rect

-- ===== spectating (out of the fight) =====
ScreenMap.spectate = { x = 240, y = 288, w = 300, h = 56 } :: Rect

-- ===== in a fight =====
-- Top-left, one short line between the settings gear row (ends y 124) and the heal and sprint buttons (start y 148).
ScreenMap.airdropHint = { x = 64, y = 124, w = 140, h = 22 } :: Rect

-- Pieces that can be on screen together in the lobby (the test checks these against each other and
-- against LobbyLayout.groups).
ScreenMap.lobbyPieces = { "botsBanner", "mapVote", "modeVote", "invite", "emote" }

return ScreenMap
