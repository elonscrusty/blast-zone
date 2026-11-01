--!strict
-- The five island rings, outside in. Names and ids match Config.World.zones.
-- value = coins (before multipliers) per ash unit swept here. Zone 1 is free and owned from the start.

local Config = require("../Config")

export type Zone = {
	id: number,
	name: string,
	value: number,
	unlockPrice: number,
	ground: string, -- ground colour once swept clean
	ash: string, -- ash tint
	blurb: string,
}

local Zones = {}

local data: { { value: number, price: number, ground: string, ash: string, blurb: string } } = {
	{
		value = 1,
		price = 0,
		ground = "#F2D9A0",
		ash = "#B8B2AA",
		blurb = "Sandy and sunny. A great place to start!",
	},
	{
		value = 3,
		price = 550,
		ground = "#6FBF5A",
		ash = "#A9AEA2",
		blurb = "Giant ferns and glowing mushrooms. Richer ash!",
	},
	{
		value = 8,
		price = 9000,
		ground = "#7FD6E8",
		ash = "#C2AEB6",
		blurb = "Warm bubbly pools and pink rocks.",
	},
	{
		value = 22,
		price = 70000,
		ground = "#C4503C",
		ash = "#8C7B78",
		blurb = "Red rock and tall white spires. Hot hot hot!",
	},
	{
		value = 60,
		price = 600000,
		ground = "#2B2230",
		ash = "#6E5A66",
		blurb = "The glowing heart of the volcano. The best ash of all!",
	},
}

Zones.list = {} :: { Zone }
Zones.byId = {} :: { [number]: Zone }
for i, zone in Config.World.zones do
	local d = data[i]
	local entry: Zone = {
		id = zone.id,
		name = zone.name,
		value = d.value,
		unlockPrice = d.price,
		ground = d.ground,
		ash = d.ash,
		blurb = d.blurb,
	}
	table.insert(Zones.list, entry)
	Zones.byId[entry.id] = entry
end

-- Coins (before multipliers) per ash unit in this zone; 0 for an unknown zone.
function Zones.valueOf(id: number): number
	local zone = Zones.byId[id]
	return if zone then zone.value else 0
end

-- Coins to open the zone's gate (0 for zone 1); nil for an unknown zone.
function Zones.price(id: number): number?
	local zone = Zones.byId[id]
	return if zone then zone.unlockPrice else nil
end

return Zones
