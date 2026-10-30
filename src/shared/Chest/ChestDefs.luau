--!strict
-- The chests and what can come out of them (gap 19: chests with a reveal). A chest is Scrap or a look from
-- TrackDefs.gifts; nothing here changes damage, speed, health, ammo or cooldowns, and nothing costs Robux.
-- Chests are earned by playing, never bought. The odds are public: each row's weight is out of 100, and
-- ChestText prints them on the chest screen. Chest ids and row ids are saved or sent, so never rename one.

local ChestDefs = {}

export type Rarity = "common" | "rare" | "epic"

export type Row = {
	id: string,
	kind: "scrap" | "look",
	rarity: Rarity,
	weight: number, -- out of 100 for the whole chest (a test checks the total)
	amount: number?, -- scrap
	itemId: string?, -- look (an id in TrackDefs.gifts)
}

export type Chest = {
	id: string,
	name: string,
	items: number, -- how many prizes one chest gives
	rows: { Row },
}

local function scrap(id: string, rarity: Rarity, weight: number, amount: number): Row
	return { id = id, kind = "scrap", rarity = rarity, weight = weight, amount = amount }
end

local function look(id: string, rarity: Rarity, weight: number, itemId: string): Row
	return { id = id, kind = "look", rarity = rarity, weight = weight, itemId = itemId }
end

-- Lowest to highest. This is also the order the chests show on the screen.
ChestDefs.kinds = { "street", "neon" }

ChestDefs.chests = {
	street = {
		id = "street",
		name = "Street Chest",
		items = 2,
		rows = {
			scrap("s15", "common", 34, 15),
			scrap("s30", "common", 26, 30),
			scrap("s60", "rare", 16, 60),
			look("trail_acid", "rare", 8, "trail_acid"),
			look("tracer_acid", "rare", 8, "tracer_acid"),
			look("trail_blaze", "epic", 4, "trail_blaze"),
			look("tracer_blaze", "epic", 4, "tracer_blaze"),
		},
	},
	neon = {
		id = "neon",
		name = "Neon Chest",
		items = 3,
		rows = {
			scrap("s30", "common", 26, 30),
			scrap("s60", "rare", 22, 60),
			scrap("s120", "rare", 12, 120),
			scrap("s150", "epic", 4, 150),
			look("trail_acid", "rare", 9, "trail_acid"),
			look("tracer_acid", "rare", 9, "tracer_acid"),
			look("trail_blaze", "epic", 9, "trail_blaze"),
			look("tracer_blaze", "epic", 9, "tracer_blaze"),
		},
	},
} :: { [string]: Chest }

-- A look you already own turns into this much Scrap instead, so a roll is never wasted.
ChestDefs.dupeScrap = { common = 10, rare = 40, epic = 100 } :: { [Rarity]: number }

ChestDefs.rarityOrder = { "common", "rare", "epic" } :: { Rarity }

function ChestDefs.get(kind: any): Chest?
	if type(kind) ~= "string" then
		return nil
	end
	return ChestDefs.chests[kind]
end

function ChestDefs.rank(rarity: Rarity): number
	return table.find(ChestDefs.rarityOrder, rarity) or 1
end

return ChestDefs
