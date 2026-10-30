--!strict
-- Skin "Street Sticker" (HUD look B, carter's pick): cream panels, thick navy outlines, hard drop
-- shadows, gold and coral pops. This is the default skin until Claude Design sends a new one.
-- A skin is ONLY looks. Every key below is listed in Tokens.luau and checked by tests/ui_tokens.test.luau.
-- New skins can be written by hand or made with `lune run tools/import-design <file.json>`.

return {
	id = "street_sticker",
	name = "Street Sticker",
	colors = {
		panel = "#FFF4D6", -- cream panel fill
		panelAlt = "#F3E3B8", -- second panel shade (rows, inner boxes)
		ink = "#14243A", -- text on panels
		inkOnAccent = "#14243A", -- text on gold / coral / cyan buttons
		inkOnDark = "#FFF4D6", -- text on the dim backdrop and dark banners
		outline = "#14243A", -- thick outline
		shadow = "#14243A", -- hard drop shadow
		accent = "#FFC44D", -- gold: main button, level, ready, slide
		good = "#7BD88F",
		danger = "#F15B64", -- coral: health, low ammo, outside zone
		info = "#36D9E8", -- cyan: xp bar, zone, win
		dim = "#B9AE92", -- disabled, empty bar track
		backdrop = "#0B1626", -- the dim behind a full panel
		coin = "#C9D3DC", -- Scrap coin colour
		winTop = "#36D9E8",
		winBottom = "#1E8FA0",
		loseTop = "#F15B64",
		loseBottom = "#A23A42",
		drawTop = "#C8A675",
		drawBottom = "#8A6D45",
	},
	fonts = {
		display = "FredokaOne", -- big titles, numbers, buttons
		body = "GothamBold", -- small words
	},
	-- Text sizes in points of the 780 x 360 design phone (the UI scales with screen height).
	text = {
		display = 44,
		title = 24,
		body = 14,
		caption = 10,
	},
	shape = {
		strokeScale = 0.0085, -- outline thickness, share of screen height
		cornerScale = 0.32, -- corner radius, share of the element height
		shadowOffset = 0.011, -- hard shadow depth, share of screen height
		backdropAlpha = 0.45, -- how see-through the dim behind a panel is (0 solid, 1 clear)
	},
	motion = {
		pop = 0.18, -- press / new-thing bounce, seconds
		slide = 0.25, -- panels and banners sliding in
		fade = 0.2,
	},
}
