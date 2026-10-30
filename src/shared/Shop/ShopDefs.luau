--!strict
-- What the Scrap Shop can sell: looks only (slide trails and shot tracers). Nothing here changes damage, speed,
-- health, ammo or cooldowns. Ids are saved with the player, so never rename or reuse one (lowercase a-z 0-9 _).
-- A look's price comes from its rarity (Config.Shop.prices). `always` looks are on sale every day; the rest are
-- the pool the daily slots draw from (ShopRules.stockFor).

local Config = require("../Config")

local ShopDefs = {}

export type Rarity = "common" | "rare" | "epic"

export type Offer = {
	id: string,
	slot: string, -- "trail" | "tracer" (the same slots as TrackDefs)
	name: string,
	color: string, -- hex
	rarity: Rarity,
	price: number,
	always: boolean,
}

local function offer(
	id: string,
	slot: string,
	name: string,
	color: string,
	rarity: Rarity,
	always: boolean
): Offer
	return {
		id = id,
		slot = slot,
		name = name,
		color = color,
		rarity = rarity,
		price = Config.Shop.prices[rarity],
		always = always,
	}
end

-- All of them, in a fixed order (the order is part of the daily pick, so adding to the END keeps old days).
ShopDefs.list = {
	offer("trail_mint", "trail", "Mint Dash", "#5CE6B0", "common", true),
	offer("tracer_mint", "tracer", "Mint Shot", "#5CE6B0", "common", true),
	offer("trail_sunset", "trail", "Sunset Skid", "#FF9A3D", "common", false),
	offer("tracer_sunset", "tracer", "Sunset Shot", "#FF9A3D", "common", false),
	offer("trail_deepblue", "trail", "Deep Blue Wake", "#3F7BFF", "common", false),
	offer("tracer_deepblue", "tracer", "Deep Blue Shot", "#3F7BFF", "common", false),
	offer("trail_magenta", "trail", "Magenta Rush", "#E23FD0", "rare", false),
	offer("tracer_lime", "tracer", "Lime Zap", "#B6F23A", "rare", false),
	offer("trail_lagoon", "trail", "Lagoon Slip", "#12B8A6", "rare", false),
	offer("trail_ember", "trail", "Ember Trail", "#FF4A1C", "epic", false),
	offer("tracer_plasma", "tracer", "Plasma Shot", "#7A5CFF", "epic", false),
	offer("tracer_ember", "tracer", "Ember Shot", "#FF4A1C", "epic", false),
} :: { Offer }

local byId: { [string]: Offer } = {}
for _, o in ShopDefs.list do
	byId[o.id] = o
end

function ShopDefs.get(id: string): Offer?
	return byId[id]
end

function ShopDefs.always(): { Offer }
	local out: { Offer } = {}
	for _, o in ShopDefs.list do
		if o.always then
			table.insert(out, o)
		end
	end
	return out
end

-- The pool for the daily slots of one rarity.
function ShopDefs.pool(rarity: string): { Offer }
	local out: { Offer } = {}
	for _, o in ShopDefs.list do
		if not o.always and o.rarity == rarity then
			table.insert(out, o)
		end
	end
	return out
end

return ShopDefs
