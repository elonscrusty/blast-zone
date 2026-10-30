--!strict
-- Squad placement (video 3 gap 11). Pure. A squad is out when its last member is out, so it ranks like one
-- fighter: alive beats everyone, otherwise the later its last member fell the better, close finishes tie.
-- A squad whose members all left the match counts as "left" (the same abandoned rule as a lone leaver).

local MatchRules = require("./MatchRules")

local TeamRank = {}

export type Result = {
	rank: MatchRules.RankResult, -- over team ids "t1", "t2", ...
	order: { number }, -- team numbers, best first
	placeOf: { [number]: number }, -- team number -> place (ties share)
	winnerTeam: number?,
}

local function teamKey(team: number): string
	return "t" .. tostring(team)
end

-- `entries` are the per-fighter rank entries (living, out, and leavers). `teams[t]` lists a team's ids.
function TeamRank.rank(
	entries: { MatchRules.RankEntry },
	teams: { { string } },
	finishedAt: number,
	tieWindow: number
): Result
	local byId: { [string]: MatchRules.RankEntry } = {}
	for _, e in entries do
		byId[e.id] = e
	end
	local teamEntries: { MatchRules.RankEntry } = {}
	for t, ids in teams do
		local alive, allLeft = false, true
		local lastOut: number? = nil
		for _, id in ids do
			local e = byId[id]
			if e ~= nil then
				alive = alive or e.alive
				allLeft = allLeft and e.left
				if e.eliminatedAt ~= nil and (lastOut == nil or e.eliminatedAt > lastOut) then
					lastOut = e.eliminatedAt
				end
			end
		end
		table.insert(teamEntries, {
			id = teamKey(t),
			alive = alive,
			left = allLeft and not alive,
			eliminatedAt = lastOut,
		})
	end
	local ranked = MatchRules.rank(teamEntries, finishedAt, tieWindow)
	local order: { number } = {}
	local placeOf: { [number]: number } = {}
	for t = 1, #teams do
		placeOf[t] = ranked.place[teamKey(t)]
	end
	for _, key in ranked.order do
		table.insert(order, tonumber(string.sub(key, 2)) :: number)
	end
	local winnerTeam: number? = nil
	if ranked.winnerId ~= nil then
		winnerTeam = tonumber(string.sub(ranked.winnerId, 2))
	end
	return { rank = ranked, order = order, placeOf = placeOf, winnerTeam = winnerTeam }
end

return TeamRank
