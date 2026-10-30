--!strict
-- The unlock track: looks only (slide trail colors, shot tracer colors). Nothing here changes damage, speed,
-- health, ammo or cooldowns, so every fighter starts equal. Ids are saved, so never rename or reuse one.
-- Order matters: tiers are unlocked in order, each for its own coin price.

local TrackDefs = {}

export type Slot = "trail" | "tracer"

export type Item = {
	id: string, -- lowercase a-z 0-9 _
	slot: Slot,
	name: string,
	color: string, -- hex
	cost: number, -- 0 = everyone owns it
}

local function item(id: string, slot: Slot, name: string, color: string, cost: number): Item
	return { id = id, slot = slot, name = name, color = color, cost = cost }
end

-- Owned by everyone, equipped by default. These match what the game looked like before the track.
TrackDefs.defaults = {
	item("trail_cyan", "trail", "Cyan Streak", "#36D9E8", 0),
	item("tracer_cyan", "tracer", "Cyan Shot", "#36D9E8", 0),
}

TrackDefs.slots = { "trail", "tracer" } :: { Slot }

-- Bought in this order.
TrackDefs.tiers = {
	item("trail_coral", "trail", "Coral Spark", "#F15B64", 100),
	item("tracer_gold", "tracer", "Gold Shot", "#FFC44D", 160),
	item("trail_gold", "trail", "Gold Comet", "#FFC44D", 240),
	item("tracer_coral", "tracer", "Coral Shot", "#F15B64", 330),
	item("trail_green", "trail", "Park Leaf", "#8DB36B", 430),
	item("tracer_white", "tracer", "White Shot", "#EAF2FA", 540),
}

local byId: { [string]: Item } = {}
for _, it in TrackDefs.defaults do
	byId[it.id] = it
end
for _, it in TrackDefs.tiers do
	byId[it.id] = it
end

function TrackDefs.get(id: string): Item?
	return byId[id]
end

function TrackDefs.defaultFor(slot: Slot): Item
	for _, it in TrackDefs.defaults do
		if it.slot == slot then
			return it
		end
	end
	error("no default for slot " .. slot)
end

return TrackDefs
