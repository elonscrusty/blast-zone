--!strict
-- The coin's name and drawing, in three looks (carter picks one with Config.Progression.look; the other two are
-- skins for later). All are round coins: a raised rim, a reeded (ridged) edge and a raised mark on both faces.
-- Colors are hex. Drawn with plain shapes only, so no art assets are needed.

local CoinLooks = {}

export type Look = {
	name: string, -- plural, used in the banner ("+48 Volts")
	face: string,
	rim: string,
	edge: string, -- the ridges on the side
	ink: string, -- the raised mark
	glyph: "bolt" | "gear" | "diamond",
}

CoinLooks.looks = {
	A = {
		name = "Volts",
		face = "#FFC44D",
		rim = "#E0A02E",
		edge = "#B27A14",
		ink = "#14243A",
		glyph = "bolt",
	},
	B = {
		name = "Scrap",
		face = "#C8A675",
		rim = "#A9834F",
		edge = "#7A5B30",
		ink = "#14243A",
		glyph = "gear",
	},
	C = {
		name = "Tokens",
		face = "#9FC3D6",
		rim = "#36D9E8",
		edge = "#1E8FA0",
		ink = "#14243A",
		glyph = "diamond",
	},
} :: { [string]: Look }

function CoinLooks.get(key: string): Look
	return CoinLooks.looks[key] or CoinLooks.looks.A
end

return CoinLooks
