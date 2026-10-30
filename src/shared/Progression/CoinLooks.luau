--!strict
-- The coin's name and drawing, in three looks (carter picks one with Config.Progression.look; the other two are
-- skins for later). Colors are hex. Drawn with plain shapes only, so no art assets are needed.
--   disc   = a round coin; octagon = two squares turned 45 degrees; hole = a dark circle in the middle.

local CoinLooks = {}

export type Look = {
	name: string, -- plural, used in the banner ("+48 Volts")
	shape: "disc" | "octagon",
	face: string,
	rim: string,
	ink: string,
	glyph: string?, -- one big letter in the middle
	hole: boolean,
	dot: string?, -- a round center mark
}

CoinLooks.looks = {
	A = {
		name = "Volts",
		shape = "disc",
		face = "#FFC44D",
		rim = "#14243A",
		ink = "#14243A",
		glyph = "V",
		hole = false,
		dot = nil,
	},
	B = {
		name = "Scrap",
		shape = "octagon",
		face = "#C8A675",
		rim = "#14243A",
		ink = "#14243A",
		glyph = nil,
		hole = false,
		dot = "#F15B64",
	},
	C = {
		name = "Tokens",
		shape = "disc",
		face = "#718D57",
		rim = "#36D9E8",
		ink = "#14243A",
		glyph = nil,
		hole = true,
		dot = nil,
	},
} :: { [string]: Look }

function CoinLooks.get(key: string): Look
	return CoinLooks.looks[key] or CoinLooks.looks.A
end

return CoinLooks
