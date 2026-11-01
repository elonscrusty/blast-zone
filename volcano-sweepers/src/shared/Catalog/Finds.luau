--!strict
-- The Finds Book: 30 hidden finds. 5 per zone (zones 1-5) + 5 rainbow finds (zone 0, can turn up in
-- any zone with tiny odds). Rarity weights give the odds the Book shows. Each find pays `coins`
-- (zone base x rarity multiplier). Completing a set gives a permanent sell bonus (fraction).

export type Rarity = {
	id: string,
	weight: number,
	coinMult: number,
	colorHex: string,
	label: string,
}

export type Find = {
	id: string,
	name: string,
	rarity: string,
	zone: number, -- 0 = rainbow (any zone)
	set: string,
	coins: number,
}

export type FindSet = {
	id: string,
	name: string,
	zone: number,
	reward: number, -- permanent sell bonus, 0.03 = +3% coins
}

local Finds = {}

Finds.rarities = {
	{ id = "common", weight = 62, coinMult = 1, colorHex = "#B8C4CC", label = "Common" },
	{ id = "uncommon", weight = 25, coinMult = 2.5, colorHex = "#5BD66F", label = "Uncommon" },
	{ id = "rare", weight = 11, coinMult = 7, colorHex = "#4DA3FF", label = "Rare" },
	{ id = "legendary", weight = 2, coinMult = 15, colorHex = "#FFC83D", label = "Legendary" },
} :: { Rarity }

Finds.rarityById = {} :: { [string]: Rarity }
for _, r in Finds.rarities do
	Finds.rarityById[r.id] = r
end

Finds.sets = {
	{ id = "beach", name = "Beach Treasures", zone = 1, reward = 0.02 },
	{ id = "forest", name = "Forest Treasures", zone = 2, reward = 0.03 },
	{ id = "springs", name = "Hot Springs Treasures", zone = 3, reward = 0.04 },
	{ id = "rim", name = "Crater Rim Treasures", zone = 4, reward = 0.05 },
	{ id = "heart", name = "Lava Heart Treasures", zone = 5, reward = 0.06 },
	{ id = "rainbow", name = "Rainbow Wonders", zone = 0, reward = 0.1 },
} :: { FindSet }

Finds.setById = {} :: { [string]: FindSet }
for _, s in Finds.sets do
	Finds.setById[s.id] = s
end

-- Base coins for a common find in each zone (index = zone id; [0] = rainbow): 12-30 ash units of
-- that zone, so a find is a happy bonus and the sets are the real prize, never the main income
-- (tests/pacing.test.luau checks the share stays between 3% and 20%). Early zones are kept low so
-- one lucky find never skips a whole step of the opening.
local zoneBase: { [number]: number } =
	{ [0] = 500, [1] = 12, [2] = 40, [3] = 240, [4] = 660, [5] = 1800 }
local setOfZone: { [number]: string } =
	{ [0] = "rainbow", [1] = "beach", [2] = "forest", [3] = "springs", [4] = "rim", [5] = "heart" }

local raw: { { string | number } } = {
	-- id, name, rarity, zone
	{ "shiny_shell", "Shiny Shell", "common", 1 },
	{ "starfish_sam", "Starfish Sam", "common", 1 },
	{ "bottle_note", "Bottle With a Note", "uncommon", 1 },
	{ "pearl_pebble", "Pearl Pebble", "rare", 1 },
	{ "golden_sand_dollar", "Golden Sand Dollar", "legendary", 1 },

	{ "fuzzy_acorn", "Fuzzy Acorn", "common", 2 },
	{ "rainbow_feather", "Rainbow Feather", "common", 2 },
	{ "glow_mushroom", "Glow Mushroom", "uncommon", 2 },
	{ "frog_crown", "Tiny Frog Crown", "rare", 2 },
	{ "fern_star", "Ancient Fern Star", "legendary", 2 },

	{ "warm_pebble", "Warm Pebble", "common", 3 },
	{ "bubble_gem", "Bubble Gem", "common", 3 },
	{ "steam_whistle", "Steam Whistle", "uncommon", 3 },
	{ "pink_crystal", "Pink Crystal Cluster", "rare", 3 },
	{ "spring_spirit", "Sleepy Spring Spirit", "legendary", 3 },

	{ "ember_chip", "Ember Chip", "common", 4 },
	{ "bone_whistle", "Bone-White Whistle", "common", 4 },
	{ "fire_opal", "Fire Opal", "uncommon", 4 },
	{ "ruby_spire", "Ruby Spire", "rare", 4 },
	{ "dragon_scale", "Friendly Dragon Scale", "legendary", 4 },

	{ "glass_marble", "Black Glass Marble", "common", 5 },
	{ "lava_bead", "Lava Bead", "common", 5 },
	{ "glowing_geode", "Glowing Geode", "uncommon", 5 },
	{ "magma_pearl", "Magma Pearl", "rare", 5 },
	{ "volcano_heart", "Volcano Heart", "legendary", 5 },

	{ "sprinkle_stone", "Sprinkle Stone", "rare", 0 },
	{ "cloud_cookie", "Cloud Cookie", "rare", 0 },
	{ "giggle_gem", "Giggle Gem", "legendary", 0 },
	{ "sunshine_star", "Sunshine Star", "legendary", 0 },
	{ "unicorn_egg", "Unicorn Egg", "legendary", 0 },
}

Finds.list = {} :: { Find }
Finds.byId = {} :: { [string]: Find }
Finds.order = {} :: { string }
for _, r in raw do
	local zone = r[4] :: number
	local rarity = r[3] :: string
	local find: Find = {
		id = r[1] :: string,
		name = r[2] :: string,
		rarity = rarity,
		zone = zone,
		set = setOfZone[zone],
		coins = math.floor(zoneBase[zone] * Finds.rarityById[rarity].coinMult + 0.5),
	}
	table.insert(Finds.list, find)
	Finds.byId[find.id] = find
	table.insert(Finds.order, find.id)
end

-- "12%" for the share of finds of this rarity, from the weights. "" for an unknown rarity.
function Finds.oddsText(rarity: string): string
	local r = Finds.rarityById[rarity]
	if not r then
		return ""
	end
	local total = 0
	for _, other in Finds.rarities do
		total += other.weight
	end
	return `{math.floor(r.weight / total * 100 + 0.5)}%`
end

-- Finds that belong to a set, in catalog order.
function Finds.inSet(setId: string): { Find }
	local out = {}
	for _, f in Finds.list do
		if f.set == setId then
			table.insert(out, f)
		end
	end
	return out
end

return Finds
