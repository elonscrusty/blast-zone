--!strict
-- The three looks for the daily board (piece 25). Config.Daily.look picks one; the others stay as skins.
--   A Sticker Stack  DAILY button in the lobby opens three sticker cards, one above the other (phone: big rows).
--   B Ticket Row     DAILY button opens three tall tickets side by side.
--   C Big Board      the board is always open on the left of the lobby, no tap needed.
-- Colors are hex text; the tier colors follow the crate tiers (blue, violet, magenta).

local DailyLooks = {}

export type Look = {
	name: string,
	layout: string, -- "stack" | "row" | "board"
	tierColors: { [string]: string },
	cardColor: string,
	doneColor: string,
}

DailyLooks.looks = {
	A = {
		name = "Sticker Stack",
		layout = "stack",
		tierColors = { easy = "#3FA9FF", medium = "#9B5CFF", hard = "#FF3FA4" },
		cardColor = "#FFF4D6",
		doneColor = "#7CE38B",
	},
	B = {
		name = "Ticket Row",
		layout = "row",
		tierColors = { easy = "#3FA9FF", medium = "#9B5CFF", hard = "#FF3FA4" },
		cardColor = "#FFF4D6",
		doneColor = "#7CE38B",
	},
	C = {
		name = "Big Board",
		layout = "board",
		tierColors = { easy = "#3FA9FF", medium = "#9B5CFF", hard = "#FF3FA4" },
		cardColor = "#1E2A4A",
		doneColor = "#7CE38B",
	},
} :: { [string]: Look }

function DailyLooks.get(key: string): Look
	return DailyLooks.looks[key] or DailyLooks.looks.A
end

return DailyLooks
