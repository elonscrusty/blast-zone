--!strict
-- Whole matches, end to end (piece 41): lobby, bot fill, spawns, crates, guns, zone, winner, rewards,
-- reset, and the next match. Every pure piece is real and wired like the game wires it (match_sim.luau).
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local MatchRules = require("../src/server/Match/MatchRules")
local MatchSim = require("./match_sim")

local SEEDS = { 1, 2, 3, 4, 5, 6, 7, 8 }
local MATCH_LIMIT = 30 + Config.Match.maxActiveSeconds + 30 -- lobby + longest fight + results

local function patched(section: string, values: { [string]: any }): any
	local cfg: any = table.clone(Config :: any)
	local copy: any = table.clone((Config :: any)[section])
	for k, v in values do
		copy[k] = v
	end
	cfg[section] = copy
	return cfg
end

local function noErrors(sim: any)
	if #sim.errors > 0 then
		error("errors inside the pieces:\n  " .. table.concat(sim.errors, "\n  "), 2)
	end
end

local function untilResults(sim: any, matchId: number): boolean
	return sim.runUntil(function()
		return sim.ctx:getMatchId() == matchId and sim.ctx:getPhase() == "Results"
	end, MATCH_LIMIT)
end

local function untilWaiting(sim: any): boolean
	return sim.untilPhase(
		"Waiting",
		Config.Match.resultsSeconds + Config.Match.resettingSeconds + 5
	)
end

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Everything one finished match must agree on, across every piece that saw it.
local function checkFinished(sim: any, matchId: number)
	local res = sim.controller.getResult()
	Harness.truthy(res, "a result exists")
	Harness.eq(res.matchId, matchId, "result is for this match")
	local rows = res.rows
	local started = 0
	for _ in sim.registry:list() do
		started += 1
	end
	-- Everyone who started has a row; places run 1..n with ties sharing a number.
	local seen: { [string]: boolean } = {}
	for i, row in rows do
		Harness.truthy(not seen[row.participantId], "one row each")
		seen[row.participantId] = true
		Harness.truthy(row.placement >= 1 and row.placement <= i, "placement is in range")
		if i > 1 then
			Harness.truthy(row.placement >= rows[i - 1].placement, "best first")
		end
	end
	-- Kill counts on the results screen = eliminations the feed showed for that killer.
	local feedKills: { [string]: number } = {}
	for _, e in sim.eliminations do
		if e.matchId == matchId and e.killerId then
			feedKills[e.killerId] = (feedKills[e.killerId] or 0) + 1
		end
	end
	for _, row in rows do
		Harness.eq(
			row.eliminations,
			feedKills[row.participantId] or 0,
			`kills of {row.participantId}`
		)
	end
	-- Win means one alive at the end and nobody else on place 1.
	local alive = sim.registry:aliveList()
	if res.outcome == "win" then
		Harness.truthy(res.winnerId ~= nil, "a win names the winner")
		Harness.eq(rows[1].participantId, res.winnerId, "winner is first")
		Harness.truthy(#rows < 2 or rows[2].placement == 2, "only one first place")
		Harness.truthy(#alive <= 1, "at most one alive after a win")
	end
	-- Every human got a results screen with their own row and the reward they will be paid.
	for id, _ in sim.humans do
		local list = sim.results[id]
		Harness.truthy(list and #list >= 1, `{id} got results`)
		local mine = list[#list]
		Harness.eq(mine.matchId, matchId)
		Harness.eq(mine.outcome, res.outcome)
		if mine.you then
			local myRow
			for _, row in rows do
				if row.participantId == id then
					myRow = row
				end
			end
			Harness.eq(mine.you.placement, myRow.placement)
			Harness.eq(
				mine.you.reward,
				MatchRules.rewardFor(myRow.placement, myRow.eliminations, Config.Rewards),
				`{id} reward shown`
			)
		end
	end
	-- Nobody acts after the end: no live zone, weapons locked, no new damage.
	Harness.eq(sim.zone:isRunning(), false, "zone stopped at the end")
	for id, f in sim.fighters do
		Harness.truthy(f.weapons.locked, `{id} weapons locked`)
	end
	local before = sim.book:get(rows[1].participantId)
	local r = sim.router:apply({
		matchId = matchId,
		targetId = rows[1].participantId,
		amount = 10,
		cause = "bullet",
		sourceId = rows[#rows].participantId,
	})
	Harness.eq(r.applied, false, "late hit refused")
	Harness.eq(sim.book:get(rows[1].participantId), before, "late hit changed nothing")
end

-- After Resetting: nothing from the old match is left anywhere.
local function checkClean(sim: any)
	Harness.eq(#sim.registry:list(), 0, "roster empty")
	Harness.eq(count(sim.fighters), 0, "no combat records")
	Harness.eq(count(sim.book.entries), 0, "no health records")
	Harness.eq(count(sim.runXp._state), 0, "no run XP")
	Harness.eq(count(sim.runUpgrades._entries), 0, "no upgrades")
	Harness.eq(count(sim.crates), 0, "no crates")
	Harness.eq(count(sim.orbs), 0, "no orbs")
	Harness.eq(count(sim.shields._until or {}), 0, "no shields")
	Harness.eq(sim.runner:count(), 0, "no bots thinking")
	Harness.eq(sim.zone:isRunning(), false, "zone off")
	for id in sim.bodies do
		error(`a body is left in the arena: {id}`)
	end
end

-- Coins: each human is paid once per match, exactly what the results screen said (daily bonuses aside).
local function paidOnce(sim: any, matchId: number)
	local paid: { [string]: number } = {}
	for _, r in sim.rewards do
		if r.matchId == matchId then
			Harness.truthy(paid[r.id] == nil, `{r.id} paid twice for match {matchId}`)
			paid[r.id] = r.amount
			Harness.truthy(string.sub(r.id, 1, 1) == "p", "bots are never paid")
		end
	end
	return paid
end

Harness.test("full match: a lone player gets bots, plays a whole match, is paid once", function()
	for _, seed in SEEDS do
		local sim = MatchSim.new({ seed = seed })
		local me = sim.join(101, "Carter")
		sim.press(me)
		-- Alone: the match waits for bots, then auto-fill asks after the short count.
		sim.runUntil(function()
			return sim.ctx:getPhase() ~= "Waiting"
		end, 20)
		Harness.eq(sim.ctx:getPhase(), "Countdown", `seed {seed}: bots filled the lobby`)
		Harness.eq(sim.botFillAsks[1], Config.Match.targetParticipants - 1, "filled to the target")
		Harness.truthy(untilResults(sim, 1), `seed {seed}: match 1 reached results`)
		noErrors(sim)
		checkFinished(sim, 1)
		-- Crates were there and the fight happened.
		Harness.truthy(sim.shots > 0 and sim.hits > 0, "shots landed")
		local paid = paidOnce(sim, 1)
		Harness.truthy(paid[me] ~= nil, `seed {seed}: the player was paid on claim`)
		local res = sim.controller.getResult()
		local myRow
		for _, row in res.rows do
			if row.participantId == me then
				myRow = row
			end
		end
		Harness.eq(
			paid[me],
			MatchRules.rewardFor(myRow.placement, myRow.eliminations, Config.Rewards)
		)
		Harness.truthy(sim.coins(me) >= paid[me], "coins landed in the save")
		Harness.truthy(untilWaiting(sim), "back to the lobby")
		checkClean(sim)
		noErrors(sim)
	end
end)

Harness.test("full match: phases run in order and the zone ends long fights", function()
	for _, seed in SEEDS do
		local sim = MatchSim.new({ seed = seed })
		sim.press(sim.join(101))
		untilResults(sim, 1)
		local want = { "Countdown", "Spawning", "Active" }
		for i, phase in want do
			Harness.eq(sim.phases[i], phase, `seed {seed} phase {i}`)
		end
		local res = sim.controller.getResult()
		Harness.truthy(
			res.reason ~= "timeout",
			`seed {seed}: no draw by the safety timer ({res.activeSeconds}s)`
		)
		Harness.truthy(
			res.activeSeconds
				< Config.Zone.suddenDeath.startsAt + Config.Zone.suddenDeath.closeSeconds + 15
		)
	end
end)

Harness.test("full match: crates break, orbs pay XP, XP buys upgrades", function()
	local broke, orbs, upgrades = 0, 0, 0
	for _, seed in SEEDS do
		local sim = MatchSim.new({ seed = seed })
		sim.press(sim.join(101))
		untilResults(sim, 1)
		noErrors(sim)
		broke += sim.cratesBroken
		orbs += sim.orbsTaken
		upgrades += sim.upgradesTaken
	end
	Harness.truthy(broke > 0, "some crates broke")
	Harness.truthy(orbs > 0, "some orbs were taken")
	Harness.truthy(upgrades > 0, "some upgrades were picked")
end)

Harness.test("full match: two matches in a row, the second starts clean", function()
	local sim = MatchSim.new({ seed = 11 })
	local me = sim.join(101)
	sim.replay[me] = true
	sim.press(me)
	Harness.truthy(untilResults(sim, 1), "match 1 done")
	local coinsAfter1 = sim.coins(me)
	Harness.truthy(untilWaiting(sim), "reset")
	checkClean(sim)
	Harness.eq(sim.controller.isReady(me), true, "Play again keeps the player queued")
	Harness.truthy(untilResults(sim, 2), "match 2 done")
	noErrors(sim)
	checkFinished(sim, 2)
	local paid = paidOnce(sim, 2)
	Harness.truthy(paid[me] ~= nil, "paid for match 2 as well")
	Harness.truthy(
		sim.coins(me) >= coinsAfter1 + paid[me],
		"match 2 coins were added, not refused as a repeat"
	)
end)

Harness.test("full match: two people, no bots, one of them wins", function()
	for _, seed in { 1, 2, 3, 4 } do
		local sim = MatchSim.new({ seed = seed })
		local a, b = sim.join(101), sim.join(102)
		sim.press(a)
		sim.press(b)
		Harness.truthy(untilResults(sim, 1), `seed {seed}: done`)
		noErrors(sim)
		checkFinished(sim, 1)
		Harness.eq(#sim.controller.getResult().rows, 2, "no bots joined two people")
		local paid = paidOnce(sim, 1)
		Harness.truthy(paid[a] and paid[b], "both paid")
	end
end)

Harness.test("full match: a full lobby of eight people", function()
	local sim = MatchSim.new({ seed = 5 })
	for i = 1, Config.Match.maxParticipants do
		sim.press(sim.join(100 + i))
	end
	Harness.truthy(untilResults(sim, 1), "done")
	noErrors(sim)
	checkFinished(sim, 1)
	Harness.eq(#sim.controller.getResult().rows, Config.Match.maxParticipants)
	local paid = paidOnce(sim, 1)
	Harness.eq(count(paid), Config.Match.maxParticipants, "everyone paid once")
end)

Harness.test("full match: the only person leaves mid-fight, the bots match is dropped", function()
	local sim = MatchSim.new({ seed = 3 })
	local me = sim.join(101)
	sim.press(me)
	sim.untilPhase("Active", 40)
	sim.runUntil(function()
		return false
	end, 5)
	sim.leave(me)
	sim.step()
	Harness.eq(sim.ctx:getPhase(), "Resetting", "nobody to show results to")
	Harness.truthy(untilWaiting(sim))
	checkClean(sim)
	Harness.eq(#sim.rewards, 0, "nobody paid")
	noErrors(sim)
end)

Harness.test("full match: someone leaves mid-fight, the others finish and get paid", function()
	local sim = MatchSim.new({ seed = 4 })
	local a, b, c = sim.join(101), sim.join(102), sim.join(103)
	for _, id in { a, b, c } do
		sim.press(id)
	end
	sim.untilPhase("Active", 40)
	sim.runUntil(function()
		return false
	end, 4)
	sim.leave(c)
	Harness.truthy(untilResults(sim, 1), "the match still ends")
	noErrors(sim)
	local res = sim.controller.getResult()
	Harness.eq(#res.rows, 3, "the leaver keeps a row")
	local paid = paidOnce(sim, 1)
	Harness.eq(paid[c], nil, "a leaver is not paid")
	Harness.truthy(paid[a] and paid[b], "the others are")
end)

Harness.test(
	"full match: leaving on the results screen is not a forfeit and keeps the reward",
	function()
		local sim = MatchSim.new({ seed = 2 })
		local a, b = sim.join(101), sim.join(102)
		sim.press(a)
		sim.press(b)
		Harness.truthy(
			sim.runUntil(function()
				return sim.ctx:getPhase() == "Finished"
			end, MATCH_LIMIT),
			"finished"
		)
		local winner = sim.controller.getResult().rows[1].participantId
		local feed = #sim.announcements
		sim.leave(winner)
		for i = feed + 1, #sim.announcements do
			Harness.truthy(
				not string.find(sim.announcements[i], "left the match", 1, true),
				"no 'left the match' line after the match is over"
			)
		end
		Harness.truthy(untilWaiting(sim))
		local paid = paidOnce(sim, 1)
		Harness.truthy(
			paid[winner] ~= nil,
			"the winner who left on the results screen was still paid"
		)
		Harness.truthy(sim.coins(winner) >= paid[winner], "and the coins reached their save")
		noErrors(sim)
	end
)

Harness.test("full match: a draw is not a win on the stats board or the daily list", function()
	-- Nobody can finish anyone in 6 seconds of spawn shields: the safety timer ends it as a draw.
	local cfg = patched("Match", { maxActiveSeconds = 2, finalPressureAtSeconds = 1 })
	local sim = MatchSim.new({ seed = 1, config = cfg })
	local a, b = sim.join(101), sim.join(102)
	sim.press(a)
	sim.press(b)
	Harness.truthy(untilResults(sim, 1), "done")
	local res = sim.controller.getResult()
	Harness.eq(res.outcome, "draw")
	Harness.eq(res.reason, "timeout")
	for _, id in { a, b } do
		local userId = tonumber(string.sub(id, 2)) :: number
		local saved = sim.savedStats[userId]
		Harness.truthy(saved ~= nil, "the match was saved")
		Harness.eq(saved.matches, 1)
		Harness.eq(saved.wins, 0, `{id}: a draw is not a win`)
		local d = sim.daily(id)
		Harness.eq(d and d.progress and d.progress.wins or 0, 0, `{id}: daily wins did not tick`)
	end
	noErrors(sim)
end)

Harness.test(
	"full match: a friend idling in the lobby does not keep a queued player waiting",
	function()
		local sim = MatchSim.new({ seed = 3 })
		local me = sim.join(101)
		sim.join(102) -- in the server, never presses Play
		sim.press(me)
		Harness.truthy(
			sim.runUntil(function()
				return sim.ctx:getPhase() ~= "Waiting"
			end, 30),
			"bots came and the match started"
		)
		Harness.truthy(untilResults(sim, 1), "the match finished")
		Harness.truthy(#sim.controller.getResult().rows > 1, "with bots in it")
		noErrors(sim)
	end
)

Harness.test("full match: two people start in Active, not Final pressure", function()
	local sim = MatchSim.new({ seed = 3 })
	local a, b = sim.join(101), sim.join(102)
	sim.press(a)
	sim.press(b)
	sim.untilPhase("Active", 60)
	sim.runUntil(function()
		return false
	end, 3)
	Harness.eq(sim.ctx:getPhase(), "Active", "two alive out of two is the start, not the end game")
	noErrors(sim)
end)

Harness.test("full match: every map plays to a winner", function()
	for _, layoutId in { "A", "B", "C" } do
		local sim = MatchSim.new({ seed = 7, layout = layoutId })
		sim.press(sim.join(101))
		Harness.truthy(untilResults(sim, 1), `map {layoutId} reached results`)
		noErrors(sim)
		checkFinished(sim, 1)
	end
end)

return {}
