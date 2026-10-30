--!strict
-- The season pass rows: 20 tiers, each with a free reward and a paid reward. A reward is Scrap or a look from
-- TrackDefs.passItems. Nothing here changes damage, speed, health, ammo or cooldowns. Tier numbers and item ids
-- are saved (claim marks), so never reorder or rename once the game is live.
-- Everyone who earns the XP can open the free row. The paid row opens through SeasonSystem.unlockPaid.

local SeasonDefs = {}

export type Reward = {
	kind: "scrap" | "item",
	amount: number?, -- scrap
	itemId: string?, -- item (an id in TrackDefs.passItems)
}

export type Tier = { free: Reward, paid: Reward }

local function scrap(amount: number): Reward
	return { kind = "scrap", amount = amount }
end

local function look(itemId: string): Reward
	return { kind = "item", itemId = itemId }
end

local function tier(free: Reward, paid: Reward): Tier
	return { free = free, paid = paid }
end

-- Tier 1 first. Climb with season XP (Config.Season.xpPerTier each).
SeasonDefs.tiers = {
	tier(scrap(10), scrap(20)),
	tier(scrap(10), scrap(20)),
	tier(scrap(15), look("trail_dusk")),
	tier(scrap(15), scrap(25)),
	tier(look("tracer_sky"), scrap(30)),
	tier(scrap(15), look("tracer_dusk")),
	tier(scrap(20), scrap(30)),
	tier(scrap(20), scrap(35)),
	tier(scrap(20), look("trail_orchid")),
	tier(look("trail_aqua"), scrap(40)),
	tier(scrap(25), scrap(40)),
	tier(scrap(25), look("tracer_citrus")),
	tier(scrap(25), scrap(45)),
	tier(scrap(30), scrap(45)),
	tier(scrap(30), look("trail_royal")),
	tier(scrap(30), scrap(50)),
	tier(scrap(35), scrap(50)),
	tier(scrap(35), look("tracer_royal")),
	tier(scrap(40), scrap(60)),
	tier(scrap(50), scrap(80)),
} :: { Tier }

SeasonDefs.rows = { "free", "paid" }

function SeasonDefs.count(): number
	return #SeasonDefs.tiers
end

function SeasonDefs.reward(tierNumber: number, row: string): Reward?
	local t = SeasonDefs.tiers[tierNumber]
	if t == nil then
		return nil
	end
	if row == "free" then
		return t.free
	elseif row == "paid" then
		return t.paid
	end
	return nil
end

return SeasonDefs
