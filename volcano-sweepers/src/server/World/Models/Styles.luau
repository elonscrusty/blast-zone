--!strict
-- The three looks every model comes in. Pure data (hex strings). A model asks for a style by id.
--   toy    "Toy Pop"     rounded, bright, cream and coral: matches the existing island toys
--   tiki   "Tiki Wood"   bamboo, thatch, planks, torch flames
--   basalt "Basalt Glow" dark volcanic stone with glowing orange and cyan trim

local Styles = {}

export type Palette = {
	wall: string,
	wallDark: string,
	roof: string,
	roofAlt: string,
	trim: string,
	wood: string,
	woodLight: string,
	woodDark: string,
	stone: string,
	stoneDark: string,
	cloth: string,
	clothAlt: string,
	leaf: string,
	leafAlt: string,
	glow: string, -- main neon
	glowAlt: string, -- second neon
	gold: string,
	dark: string,
	white: string,
}

Styles.ids = { "toy", "tiki", "basalt" }

Styles.names = {
	toy = "Toy Pop",
	tiki = "Tiki Wood",
	basalt = "Basalt Glow",
} :: { [string]: string }

Styles.pal = {
	toy = {
		wall = "#FFF1CC",
		wallDark = "#F2D9A0",
		roof = "#FF7A59",
		roofAlt = "#2EB6C9",
		trim = "#FFD23F",
		wood = "#C98A4B",
		woodLight = "#F6C27A",
		woodDark = "#8A5A3C",
		stone = "#E9E2D0",
		stoneDark = "#C9BFA8",
		cloth = "#FF4D4D",
		clothAlt = "#FFFFFF",
		leaf = "#4FD06A",
		leafAlt = "#2FB35A",
		glow = "#FFE27A",
		glowAlt = "#7DF0FF",
		gold = "#FFD84D",
		dark = "#2B2230",
		white = "#FFFFFF",
	},
	tiki = {
		wall = "#C9A15B",
		wallDark = "#A67C3E",
		roof = "#C99A3C",
		roofAlt = "#A9782C",
		trim = "#8A5A3C",
		wood = "#9C6B3F",
		woodLight = "#D9B27A",
		woodDark = "#5E3B22",
		stone = "#B9AE9A",
		stoneDark = "#8E8472",
		cloth = "#D9423B",
		clothAlt = "#F2C14E",
		leaf = "#3FA64A",
		leafAlt = "#2C8A3C",
		glow = "#FF9A2E",
		glowAlt = "#FFD23F",
		gold = "#F2C14E",
		dark = "#2B2018",
		white = "#FFF4DC",
	},
	basalt = {
		wall = "#65546C",
		wallDark = "#483B50",
		roof = "#37293F",
		roofAlt = "#51435C",
		trim = "#FF7A2F",
		wood = "#5A4A52",
		woodLight = "#7A6A72",
		woodDark = "#2B2230",
		stone = "#85768F",
		stoneDark = "#4A3E55",
		cloth = "#FF7A2F",
		clothAlt = "#7DF0FF",
		leaf = "#2FD6C8",
		leafAlt = "#1AA39B",
		glow = "#FF7A2F",
		glowAlt = "#7DF0FF",
		gold = "#FFC24D",
		dark = "#1A1420",
		white = "#F3E9D2",
	},
} :: { [string]: Palette }

function Styles.get(id: string?): string
	if id ~= nil and Styles.pal[id] ~= nil then
		return id
	end
	return "toy"
end

return Styles
