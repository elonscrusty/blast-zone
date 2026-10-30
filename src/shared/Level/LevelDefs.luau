--!strict
-- The account level's free gifts. A gift is Scrap or a look from TrackDefs.gifts; nothing here changes damage,
-- speed, health, ammo or cooldowns, and nothing costs Robux. Levels are saved as strings in claimedLevels, so
-- never move a gift to another level once the game is live (an unclaimed one would still arrive later).

local LevelDefs = {}

export type Gift = {
	level: number,
	kind: "scrap" | "item",
	amount: number?, -- scrap
	itemId: string?, -- item (an id in TrackDefs.gifts)
}

-- In level order.
LevelDefs.gifts = {
	{ level = 3, kind = "scrap", amount = 30 },
	{ level = 5, kind = "item", itemId = "trail_violet" },
	{ level = 8, kind = "scrap", amount = 50 },
	{ level = 10, kind = "item", itemId = "tracer_violet" },
	{ level = 15, kind = "scrap", amount = 80 },
	{ level = 20, kind = "item", itemId = "trail_ice" },
	{ level = 30, kind = "scrap", amount = 120 },
	{ level = 40, kind = "item", itemId = "tracer_pink" },
	{ level = 50, kind = "scrap", amount = 200 },
} :: { Gift }

-- The next gift above `level`, or nil when none is left.
function LevelDefs.nextGift(level: number): Gift?
	for _, g in LevelDefs.gifts do
		if g.level > level then
			return g
		end
	end
	return nil
end

return LevelDefs
