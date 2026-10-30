--!strict
-- Every daily challenge the game can pick (piece 25). Ids are saved: never rename or reuse one, only add.
-- Each day picks one from each tier. Rewards per tier are in Config.Daily.rewards.
-- kind = what counts:
--   elims    eliminations you score          crates   supply crates you break
--   orbs     XP orbs you grab                matches  matches you finish (any place)
--   top3     matches you end in the top 3    wins     matches you win

local DailyDefs = {}

export type Tier = string -- "easy" | "medium" | "hard"
export type Kind = string -- one of DailyDefs.kinds

export type Def = {
	id: string,
	tier: Tier,
	kind: Kind,
	goal: number,
}

DailyDefs.tiers = { "easy", "medium", "hard" } :: { Tier }

DailyDefs.kinds = { "elims", "crates", "orbs", "matches", "top3", "wins" } :: { Kind }

DailyDefs.list = {
	{ id = "elims_2", tier = "easy", kind = "elims", goal = 2 },
	{ id = "crates_3", tier = "easy", kind = "crates", goal = 3 },
	{ id = "orbs_10", tier = "easy", kind = "orbs", goal = 10 },
	{ id = "matches_2", tier = "easy", kind = "matches", goal = 2 },

	{ id = "elims_5", tier = "medium", kind = "elims", goal = 5 },
	{ id = "crates_6", tier = "medium", kind = "crates", goal = 6 },
	{ id = "orbs_25", tier = "medium", kind = "orbs", goal = 25 },
	{ id = "top3_1", tier = "medium", kind = "top3", goal = 1 },

	{ id = "elims_10", tier = "hard", kind = "elims", goal = 10 },
	{ id = "crates_12", tier = "hard", kind = "crates", goal = 12 },
	{ id = "top3_3", tier = "hard", kind = "top3", goal = 3 },
	{ id = "wins_1", tier = "hard", kind = "wins", goal = 1 },
} :: { Def }

local byId: { [string]: Def } = {}
for _, def in DailyDefs.list do
	byId[def.id] = def
end

function DailyDefs.get(id: string): Def?
	return byId[id]
end

function DailyDefs.ofTier(tier: Tier): { Def }
	local out: { Def } = {}
	for _, def in DailyDefs.list do
		if def.tier == tier then
			table.insert(out, def)
		end
	end
	return out
end

-- What the RunXp award reasons count toward.
DailyDefs.kindForXpReason = {
	elimination = "elims",
	containerBreak = "crates",
	orbPickup = "orbs",
} :: { [string]: Kind }

return DailyDefs
