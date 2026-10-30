--!strict
-- Squads (video 3 gap 11): seating, friendly fire, squad placement, whole squad matches.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local RemoteDefs = require("../src/shared/RemoteDefs")
local SquadBook = require("../src/shared/Squads/SquadBook")
local BotBrain = require("../src/server/Bots/BotBrain")
local BotTuning = require("../src/server/Bots/BotTuning")
local MatchRules = require("../src/server/Match/MatchRules")
local TeamRank = require("../src/server/Match/TeamRank")
local MC = require("./match_controller.test")

local test, eq, truthy = Harness.test, Harness.eq, Harness.truthy

local function people(n: number): { SquadBook.Member }
	local out = {}
	for i = 1, n do
		table.insert(out, { id = `p{i}`, isBot = false })
	end
	return out
end

local function bots(from: number, n: number): { SquadBook.Member }
	local out = {}
	for i = from, from + n - 1 do
		table.insert(out, { id = `b{i}`, isBot = true })
	end
	return out
end

local function concat(a: { SquadBook.Member }, b: { SquadBook.Member }): { SquadBook.Member }
	local out = table.clone(a)
	for _, m in b do
		table.insert(out, m)
	end
	return out
end

local function teamsOf(book: any): { string }
	local out = {}
	for t = 1, book:teamCount() do
		table.insert(out, table.concat(book:membersOf(t), "+"))
	end
	return out
end

-- ===== seating =====

test("squads: solo seats nobody", function()
	local book = SquadBook.new()
	eq(book:assign(people(4), 2), 1)
	eq(book:active(), false)
	eq(book:teamOf("p1"), nil)
	eq(book:sameTeam("p1", "p2"), false)
end)

test("squads: duo pairs people in order and tells listeners", function()
	local book = SquadBook.new()
	local fired = 0
	book.Assigned:connect(function()
		fired += 1
	end)
	book:setWanted(2)
	eq(book:assign(people(4), 2), 2)
	eq(book:active(), true)
	eq(table.concat(teamsOf(book), " "), "p1+p2 p3+p4")
	eq(book:teamOf("p3"), 2)
	eq(fired, 1)
end)

test("squads: a party stays together and loose players fill the open seats", function()
	local book = SquadBook.new()
	book:setWanted(3)
	book:setParties({ { "p1", "p5" } })
	book:assign(people(6), 2)
	eq(table.concat(teamsOf(book), " "), "p1+p5+p2 p3+p4+p6")
end)

test("squads: a party bigger than the squad is cut into chunks", function()
	local book = SquadBook.new()
	book:setWanted(2)
	book:setParties({ { "p1", "p2", "p3", "p4" } })
	book:assign(people(4), 2)
	eq(table.concat(teamsOf(book), " "), "p1+p2 p3+p4")
end)

test("squads: people before bots, bots fill the gaps then team up", function()
	local book = SquadBook.new()
	book:setWanted(2)
	-- bots listed first on purpose: they still sit after the people
	book:assign(concat(bots(1, 3), people(3)), 2)
	eq(table.concat(teamsOf(book), " "), "p1+p2 p3+b1 b2+b3")
end)

test("squads: a party id that is not in the match, or is a bot, is ignored", function()
	local book = SquadBook.new()
	book:setWanted(2)
	book:setParties({ { "p9", "b1", "p1" } })
	book:assign(concat(people(2), bots(1, 2)), 2)
	eq(book:sameTeam("p1", "p2"), true)
	eq(book:sameTeam("b1", "b2"), true)
end)

test("squads: never fewer than two teams (small matches shrink the squad)", function()
	eq(SquadBook.effectiveSize(2, 3, 2), 1)
	eq(SquadBook.effectiveSize(3, 4, 2), 2)
	eq(SquadBook.effectiveSize(3, 6, 2), 3)
	eq(SquadBook.effectiveSize(3, 100, 2), 3)
	eq(SquadBook.effectiveSize(0, 8, 2), 1)
	local book = SquadBook.new()
	book:setWanted(2)
	eq(book:assign(people(3), 2), 1, "three fighters cannot make two duos")
	eq(book:active(), false)
	book:setWanted(3)
	eq(book:assign(people(4), 2), 2, "a trio of four becomes duos")
	eq(book:teamCount(), 2)
end)

test("squads: odd counts leave one short squad", function()
	local book = SquadBook.new()
	book:setWanted(3)
	book:assign(people(8), 2)
	eq(table.concat(teamsOf(book), " "), "p1+p2+p3 p4+p5+p6 p7+p8")
end)

test("squads: bad wanted sizes mean solo", function()
	local book = SquadBook.new()
	for _, bad in { 0, -2, 0 / 0 } do
		book:setWanted(bad)
		eq(book:assign(people(6), 2), 1)
	end
	book:setWanted(2.9)
	eq(book:assign(people(6), 2), 2, "fractions round down")
end)

test("squads: clear forgets the teams and a new seating starts fresh", function()
	local book = SquadBook.new()
	book:setWanted(2)
	book:assign(people(4), 2)
	book:clear()
	eq(book:active(), false)
	eq(book:teamCount(), 0)
	eq(book:teamOf("p1"), nil)
	book:assign(concat(bots(1, 2), people(2)), 2)
	eq(book:sameTeam("p1", "b1"), false)
	eq(book:sameTeam("p1", "p2"), true)
end)

-- ===== reading the teams =====

test("squads: mates, same team, self is not a mate", function()
	local book = SquadBook.new()
	book:setWanted(3)
	book:assign(people(6), 2)
	eq(table.concat(book:matesOf("p2"), ","), "p1,p3")
	eq(book:sameTeam("p1", "p3"), true)
	eq(book:sameTeam("p1", "p1"), false)
	eq(book:sameTeam("p1", "p4"), false)
	eq(book:sameTeam("p1", "zzz"), false)
	eq(#book:matesOf("zzz"), 0)
end)

test("squads: friendly fire stops at teammates only", function()
	local book = SquadBook.new()
	book:setWanted(2)
	book:assign(people(4), 2)
	eq(book:blocksDamage("p1", "p2", false), true, "teammate")
	eq(book:blocksDamage("p1", "p3", false), false, "enemy")
	eq(book:blocksDamage("p1", "p1", false), false, "your own blast still hurts you")
	eq(book:blocksDamage(nil, "p1", false), false, "the zone has no source")
	eq(book:blocksDamage("p1", "p2", true), false, "friendly fire switched on")
end)

test("squads: a squad is alive while any member is", function()
	local book = SquadBook.new()
	book:setWanted(2)
	book:assign(people(4), 2)
	local out: { [string]: boolean } = {}
	local function alive(id: string): boolean
		return not out[id]
	end
	eq(book:aliveTeamCount(alive), 2)
	out.p1 = true
	eq(book:aliveTeamCount(alive), 2)
	out.p2 = true
	eq(book:aliveTeamCount(alive), 1)
	eq(book:teamAlive(1, alive), false)
	eq(book:teamAlive(2, alive), true)
	eq(book:teamAlive(9, alive), false)
end)

test("squads: modes come from config and unknown ids fall back", function()
	local modes = Config.Squads.modes
	eq(#SquadBook.pool(modes), 3)
	eq(SquadBook.sizeOf(modes, "duo", "solo"), 2)
	eq(SquadBook.sizeOf(modes, "trio", "solo"), 3)
	eq(SquadBook.sizeOf(modes, nil, "solo"), 1)
	eq(SquadBook.sizeOf(modes, "mega", "duo"), 2)
	eq(SquadBook.sizeOf(modes, "mega", "nope"), 1)
	eq(Config.Squads.modes[1].size, 1, "solo is first and always there")
	truthy(Config.Squads.defaultMode == "solo")
end)

test("squads: remotes exist with a limit on the mode id", function()
	local ask = RemoteDefs.byName.SquadVoteRequest
	truthy(ask ~= nil and ask.direction == "toServer")
	truthy(RemoteDefs.byName.SquadState ~= nil and RemoteDefs.byName.SquadVoteState ~= nil)
	for _, mode in Config.Squads.modes do
		truthy(#mode.id <= Config.Squads.maxModeIdLength, mode.id .. " fits the remote")
	end
end)

-- ===== squad placement =====

local function entry(id: string, alive: boolean, out: number?, left: boolean?): MatchRules.RankEntry
	return { id = id, alive = alive, left = left == true, eliminatedAt = out }
end

test("team rank: the squad with a survivor wins, the rest go by their last fall", function()
	local teams = { { "p1", "p2" }, { "p3", "p4" }, { "p5", "p6" } }
	local r = TeamRank.rank({
		entry("p1", false, 10),
		entry("p2", false, 30),
		entry("p3", true),
		entry("p4", false, 5),
		entry("p5", false, 20),
		entry("p6", false, 25),
	}, teams, 40, 0.1)
	eq(r.winnerTeam, 2)
	eq(r.rank.outcome, "win")
	eq(table.concat(r.order :: any, ","), "2,1,3")
	eq(r.placeOf[1], 2, "a squad lasts until its LAST member falls (30 beats 25)")
	eq(r.placeOf[3], 3)
end)

test("team rank: squads that fall together share first place (a draw)", function()
	local r = TeamRank.rank(
		{ entry("p1", false, 10), entry("p2", false, 10.05), entry("p3", false, 10.02) },
		{ { "p1", "p2" }, { "p3" } },
		11,
		0.1
	)
	eq(r.rank.outcome, "draw")
	eq(r.winnerTeam, nil)
	eq(r.placeOf[1], 1)
	eq(r.placeOf[2], 1)
end)

test("team rank: a best squad that all left is abandoned, not a win", function()
	local r = TeamRank.rank(
		{ entry("p1", false, 10, true), entry("p2", false, 12, true), entry("p3", false, 5) },
		{ { "p1", "p2" }, { "p3" } },
		20,
		0.1
	)
	eq(r.rank.outcome, "abandoned")
	eq(r.winnerTeam, nil)
end)

-- ===== whole squad matches =====

local function squadRig(count: number, size: number, overrides: { [string]: any }?)
	local book = SquadBook.new()
	book:setWanted(size)
	local rig, ids = MC.humans(count, overrides, book)
	rig.router:addGuard(function(req: any): string?
		if book:blocksDamage(req.sourceId, req.targetId, Config.Squads.friendlyFire) then
			return "teammate"
		end
		return nil
	end)
	rig.untilPhase("Active")
	return rig, ids, book
end

test("squad match: teammates cannot hurt each other, enemies and the zone can", function()
	local rig, ids, book = squadRig(4, 2)
	eq(book:active(), true)
	local a, b, c = ids[1], ids[2], ids[3]
	local friendly = rig.kill(b, a)
	eq(friendly.applied, false)
	eq(friendly.reason, "teammate")
	eq(rig.registry:isAlive(b), true)
	eq(rig.kill(a, a).applied, true, "your own blast still counts")
	eq(rig.kill(c, nil, "zone").applied, true, "the zone hurts everyone")
end)

test("squad match: it goes on until one squad is left, then everyone shares the place", function()
	local rig, ids, book = squadRig(4, 2)
	local a, b, c, d = ids[1], ids[2], ids[3], ids[4]
	eq(book:teamCount(), 2)
	eq(rig.kill(a, c).applied, true)
	rig.step(1)
	eq(
		rig.ctx:getPhase() == "Active" or rig.ctx:getPhase() == "FinalPressure",
		true,
		"b is still in"
	)
	eq(rig.eliminated[1].squadOut, false, "a's squad still stands")
	eq(rig.kill(b, d).applied, true)
	rig.untilPhase("Finished", 3)
	local res = rig.ctl.getResult() :: any
	eq(res.outcome, "win")
	eq(res.winnerTeam, 2)
	eq(res.squadSize, 2)
	truthy(
		res.winnerId == c or res.winnerId == d,
		"the banner names a winner from the winning squad"
	)
	eq(#res.rows, 4)
	for _, row in res.rows do
		local mine = row.participantId == c or row.participantId == d
		eq(row.placement, if mine then 1 else 2, row.participantId)
		eq(row.teamIndex, if mine then 2 else 1, row.participantId)
	end
	eq(
		res.rows[1].participantId,
		c,
		"kills order the members: c made one, d made one, c comes first"
	)
	eq(rig.eliminated[2].squadOut, true)
	eq(rig.eliminated[2].placement, 2)
	rig.untilPhase("Results")
	rig.step(1)
	eq(rig.results[d].you.placement, 1, "the quiet teammate shares the win")
	eq(rig.results[d].you.teamIndex, 2)
	eq(rig.results[d].winnerTeam, 2)
	eq(rig.results[a].you.placement, 2)
	local winnerPay = MatchRules.rewardFor(1, rig.results[d].you.eliminations, Config.Rewards)
	eq(rig.results[d].you.reward, winnerPay)
end)

test("squad match: Final pressure counts squads, not people", function()
	local rig, ids = squadRig(6, 2) -- three duos
	eq(rig.ctx:getPhase(), "Active")
	rig.kill(ids[1], ids[3])
	rig.kill(ids[2], ids[3])
	rig.step(0.5)
	eq(rig.ctx:getPhase(), "FinalPressure", "two squads left of three")
	eq(rig.registry:aliveCount(), 4)
end)

test("squad match: a fallen fighter watches a living teammate before their killer", function()
	local rig, ids = squadRig(4, 2)
	rig.kill(ids[1], ids[3])
	rig.step(0.5)
	eq(rig.spectate[ids[1]], ids[2])
	rig.kill(ids[2], ids[3])
	rig.step(0.5)
	truthy(rig.spectate[ids[1]] ~= ids[2], "no mate left: the whole match is open")
end)

test("squad match: a squad that is two people leaving still ends cleanly", function()
	local rig, ids = squadRig(4, 2)
	rig.ctl.removeHuman(ids[1])
	rig.step(0.5)
	eq(
		rig.ctx:getPhase() == "Active" or rig.ctx:getPhase() == "FinalPressure",
		true,
		"partner carries on"
	)
	rig.ctl.removeHuman(ids[2])
	rig.untilPhase("Finished", 3)
	local res = rig.ctl.getResult() :: any
	eq(res.winnerTeam, 2)
end)

test("squad match: two people cannot be two duos, so it plays solo", function()
	local rig, ids, book = squadRig(2, 2)
	eq(book:active(), false)
	rig.kill(ids[1], ids[2])
	rig.untilPhase("Finished", 3)
	local res = rig.ctl.getResult() :: any
	eq(res.winnerTeam, nil)
	eq(res.squadSize, 1)
	eq(res.winnerId, ids[2])
	eq(res.rows[1].teamIndex, nil)
end)

test("squad match: the teams are forgotten at reset and the next match can be solo", function()
	local rig, ids, book = squadRig(4, 2)
	rig.kill(ids[1], ids[3])
	rig.kill(ids[2], ids[3])
	rig.untilPhase("Resetting", 60)
	eq(book:active(), false)
	eq(book:teamCount(), 0)
	book:setWanted(1)
	for _, id in ids do
		rig.ready(id)
	end
	rig.untilPhase("Active", 60)
	eq(book:active(), false)
	rig.kill(ids[1], ids[2])
	eq(rig.registry:isAlive(ids[1]), false, "free for all again")
end)

test("squad match: bots fill the squads after the people", function()
	local book = SquadBook.new()
	book:setWanted(2)
	local rig = MC.newRig(nil, book)
	local a = rig.join(1, "Alice")
	rig.ready(a)
	rig.ctl.requestBots(3)
	rig.untilPhase("Active")
	eq(book:active(), true)
	eq(table.concat(book:matesOf(a), ","), "b1", "Alice has a bot partner")
	eq(book:sameTeam("b2", "b3"), true)
end)

-- ===== bots =====

local T = BotTuning.from(Config)

local function botView(others: { BotBrain.Body }, rand: () -> number): BotBrain.View
	return {
		now = 10,
		me = {
			id = "b1",
			pos = { x = 0, z = 0 },
			health = 100,
			maxHealth = 100,
			ammo = 12,
			magazine = 12,
			reloading = false,
			canFire = true,
			slideReady = true,
		},
		others = others,
		pickups = {},
		zone = nil,
		range = Config.Weapons.Firearm.range,
		canSee = function()
			return true
		end,
		rand = rand,
		tuning = T,
	}
end

test("bots: a teammate in plain sight is never a target", function()
	local state = BotBrain.newState()
	local v = botView({ { id = "p1", pos = { x = 0, z = 10 }, ally = true } }, function()
		return 0.5
	end)
	BotBrain.think(v, state)
	v.now += T.reactionTime + 0.01
	local intent = BotBrain.think(v, state)
	eq(state.targetId, nil)
	eq(intent.fire, false)
end)

test("bots: the same body as an enemy is a target", function()
	local state = BotBrain.newState()
	local v = botView({ { id = "p1", pos = { x = 0, z = 10 } } }, function()
		return 0.5
	end)
	BotBrain.think(v, state)
	eq(state.targetId, "p1")
end)

test("bots: a squad bot walks toward a teammate when it picks a new goal", function()
	local state = BotBrain.newState()
	-- rand 0.5 is under the 0.6 chance, so the goal is next to the teammate far to the east
	local v = botView({ { id = "p1", pos = { x = 200, z = 0 }, ally = true } }, function()
		return 0.5
	end)
	BotBrain.think(v, state)
	local goal = state.goal :: BotBrain.Vec2
	truthy(goal ~= nil and math.abs(goal.x - 200) <= 13, "goal near the teammate")
end)

return {}
