--!strict
-- Every weekly mission and achievement the game can pick (piece 48). Ids are saved: never rename or reuse one,
-- only add. A mission or achievement counts the same things as a daily challenge (see Daily/DailyDefs.kinds):
--   elims, crates, orbs, matches, top3, wins.
-- Weekly missions: each week picks one per tier, all different kinds, new every Monday. Pay is in
-- Config.Missions.weeklyRewards. Achievements never expire: they count your whole life in the game from the day
-- this shipped, and each pays its own reward once.

local MissionDefs = {}

export type Weekly = {
	id: string,
	tier: string, -- "easy" | "medium" | "hard"
	kind: string,
	goal: number,
}

export type Award = {
	id: string,
	kind: string,
	goal: number,
	reward: number, -- Scrap, once
}

MissionDefs.tiers = { "easy", "medium", "hard" } :: { string }

MissionDefs.weekly = {
	{ id = "w_elims_12", tier = "easy", kind = "elims", goal = 12 },
	{ id = "w_crates_10", tier = "easy", kind = "crates", goal = 10 },
	{ id = "w_orbs_40", tier = "easy", kind = "orbs", goal = 40 },
	{ id = "w_matches_5", tier = "easy", kind = "matches", goal = 5 },

	{ id = "w_elims_25", tier = "medium", kind = "elims", goal = 25 },
	{ id = "w_crates_20", tier = "medium", kind = "crates", goal = 20 },
	{ id = "w_orbs_90", tier = "medium", kind = "orbs", goal = 90 },
	{ id = "w_matches_10", tier = "medium", kind = "matches", goal = 10 },
	{ id = "w_top3_4", tier = "medium", kind = "top3", goal = 4 },

	{ id = "w_elims_50", tier = "hard", kind = "elims", goal = 50 },
	{ id = "w_crates_40", tier = "hard", kind = "crates", goal = 40 },
	{ id = "w_top3_8", tier = "hard", kind = "top3", goal = 8 },
	{ id = "w_wins_2", tier = "hard", kind = "wins", goal = 2 },
} :: { Weekly }

-- Lists go from small to large inside one kind, so a screen can show them in this order.
MissionDefs.awards = {
	{ id = "a_elims_10", kind = "elims", goal = 10, reward = 20 },
	{ id = "a_elims_50", kind = "elims", goal = 50, reward = 40 },
	{ id = "a_elims_250", kind = "elims", goal = 250, reward = 80 },
	{ id = "a_elims_1000", kind = "elims", goal = 1000, reward = 150 },

	{ id = "a_wins_1", kind = "wins", goal = 1, reward = 30 },
	{ id = "a_wins_5", kind = "wins", goal = 5, reward = 50 },
	{ id = "a_wins_25", kind = "wins", goal = 25, reward = 100 },
	{ id = "a_wins_100", kind = "wins", goal = 100, reward = 150 },

	{ id = "a_matches_5", kind = "matches", goal = 5, reward = 20 },
	{ id = "a_matches_25", kind = "matches", goal = 25, reward = 40 },
	{ id = "a_matches_100", kind = "matches", goal = 100, reward = 80 },
	{ id = "a_matches_500", kind = "matches", goal = 500, reward = 150 },

	{ id = "a_top3_10", kind = "top3", goal = 10, reward = 30 },
	{ id = "a_top3_50", kind = "top3", goal = 50, reward = 80 },

	{ id = "a_crates_25", kind = "crates", goal = 25, reward = 20 },
	{ id = "a_crates_150", kind = "crates", goal = 150, reward = 60 },
	{ id = "a_crates_750", kind = "crates", goal = 750, reward = 120 },

	{ id = "a_orbs_100", kind = "orbs", goal = 100, reward = 20 },
	{ id = "a_orbs_500", kind = "orbs", goal = 500, reward = 60 },
} :: { Award }

local weeklyById: { [string]: Weekly } = {}
for _, def in MissionDefs.weekly do
	weeklyById[def.id] = def
end

local awardById: { [string]: Award } = {}
for _, def in MissionDefs.awards do
	awardById[def.id] = def
end

function MissionDefs.getWeekly(id: string): Weekly?
	return weeklyById[id]
end

function MissionDefs.getAward(id: string): Award?
	return awardById[id]
end

function MissionDefs.weeklyOfTier(tier: string): { Weekly }
	local out: { Weekly } = {}
	for _, def in MissionDefs.weekly do
		if def.tier == tier then
			table.insert(out, def)
		end
	end
	return out
end

return MissionDefs
