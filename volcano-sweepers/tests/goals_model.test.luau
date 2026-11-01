--!strict
-- Goals view-model: ready first, claimed last, progress, reward text, same answers as GoalRules.
local Harness = require("./harness")
local Goals = require("../src/shared/Catalog/Goals")
local GoalRules = require("../src/shared/Player/GoalRules")
local Economy = require("../src/shared/Rules/Economy")
local GoalsModel = require("../src/shared/Ui/GoalsModel")

local function blank(): any
	return Economy.blankProfile()
end

local function cardOf(view: GoalsModel.View, id: string): GoalsModel.Card
	for _, c in view.cards do
		if c.id == id then
			return c
		end
	end
	error("no card " .. id)
end

local function indexOf(view: GoalsModel.View, id: string): number
	for i, c in view.cards do
		if c.id == id then
			return i
		end
	end
	return -1
end

Harness.test("goals: a new player has 14 locked goals", function()
	local v = GoalsModel.build(blank())
	Harness.eq(#v.cards, 14)
	Harness.eq(v.total, 14)
	Harness.eq(v.readyCount, 0)
	Harness.eq(v.claimedCount, 0)
	Harness.eq(v.badge, false)
	Harness.eq(v.allDone, false)
	Harness.eq(v.headerText, "Goals done: 0 / 14")
	for _, c in v.cards do
		Harness.eq(c.status, "locked", c.id)
		Harness.eq(c.fraction, 0)
		Harness.truthy(c.icon ~= "")
	end
end)

Harness.test("goals: reaching a target makes it ready and puts it first", function()
	local p = blank()
	p.stats.ashSwept = 200
	p.stats.sellCount = 2
	local v = GoalsModel.build(p)
	Harness.eq(v.readyCount, 1)
	Harness.eq(v.badge, true)
	Harness.eq(v.cards[1].id, "first_sweeps")
	Harness.eq(v.cards[1].status, "ready")
	Harness.eq(v.cards[1].progressText, "200/200")
	Harness.eq(v.headerText, "1 reward is ready!")
	-- sellCount 2 of 5 = 0.4 beats everything else still at ~0 (ashSwept 200 of 2500 = 0.08)
	Harness.eq(v.cards[2].id, "first_sales")
	Harness.eq(v.cards[2].progressText, "2/5")
end)

Harness.test("goals: two ready goals and the plural header", function()
	local p = blank()
	p.stats.ashSwept = 2500
	local v = GoalsModel.build(p)
	Harness.eq(v.readyCount, 2) -- first_sweeps + tidy_beach
	Harness.eq(v.headerText, "2 rewards are ready!")
	Harness.eq(v.cards[1].id, "first_sweeps") -- catalog order among ready
	Harness.eq(v.cards[2].id, "tidy_beach")
end)

Harness.test("goals: claimed goals sink to the bottom", function()
	local p = blank()
	p.stats.ashSwept = 2500
	p.goalsClaimed.first_sweeps = true
	local v = GoalsModel.build(p)
	Harness.eq(v.claimedCount, 1)
	Harness.eq(v.readyCount, 1)
	Harness.eq(v.cards[1].id, "tidy_beach")
	Harness.eq(v.cards[#v.cards].id, "first_sweeps")
	Harness.eq(v.cards[#v.cards].status, "claimed")
	Harness.eq(v.headerText, "1 reward is ready!")
	-- nothing ready any more: the header counts what is done
	p.goalsClaimed.tidy_beach = true
	local v2 = GoalsModel.build(p)
	Harness.eq(v2.badge, false)
	Harness.eq(v2.headerText, "Goals done: 2 / 14")
	Harness.eq(v2.cards[13].status, "claimed")
	Harness.eq(v2.cards[14].status, "claimed")
end)

Harness.test("goals: a claimed goal stays claimed even if the stat is low", function()
	local p = blank()
	p.goalsClaimed.long_play = true
	local v = GoalsModel.build(p)
	Harness.eq(cardOf(v, "long_play").status, "claimed")
	Harness.eq(v.cards[14].id, "long_play")
end)

Harness.test("goals: everything claimed", function()
	local p = blank()
	for _, g in Goals.list do
		p.goalsClaimed[g.id] = true
	end
	local v = GoalsModel.build(p)
	Harness.eq(v.allDone, true)
	Harness.eq(v.headerText, "All goals done! Wow!")
	Harness.eq(v.badge, false)
end)

Harness.test("goals: locked goals are sorted closest-to-done first, ties by catalog", function()
	local p = blank()
	p.stats.ashSwept = 1000 -- 0.4 of tidy_beach(2500); 0.025 of ash_buster
	p.stats.findsTotal = 1 -- 1/3 of treasure_peek
	local v = GoalsModel.build(p)
	local lockedIds: { string } = {}
	for _, c in v.cards do
		if c.status == "locked" then
			table.insert(lockedIds, c.id)
		end
	end
	Harness.eq(lockedIds[1], "tidy_beach")
	Harness.eq(lockedIds[2], "treasure_peek")
	-- all-zero goals keep catalog order
	local zero = {}
	for _, c in v.cards do
		if c.fraction == 0 then
			table.insert(zero, c.id)
		end
	end
	local last = 0
	for _, id in zero do
		local pos = table.find(Goals.order, id) :: number
		Harness.truthy(pos > last, "catalog order for ties")
		last = pos
	end
end)

Harness.test("goals: progress never goes past the target", function()
	local p = blank()
	p.stats.ashSwept = 9e9
	local c = cardOf(GoalsModel.build(p), "first_sweeps")
	Harness.eq(c.progress, 200)
	Harness.eq(c.fraction, 1)
	Harness.eq(c.progressText, "200/200")
end)

Harness.test("goals: reward text has coins and Sparks", function()
	local v = GoalsModel.build(blank())
	local small = cardOf(v, "first_sweeps")
	Harness.eq(small.rewardText, "💰 40")
	Harness.eq(small.rewardShort, "40 coins")
	local big = cardOf(v, "ash_legend")
	Harness.eq(big.rewardText, "💰 250K  ✨ 2")
	Harness.eq(big.rewardShort, "250K coins, 2 Sparks")
	local one = cardOf(v, "trade_titan")
	Harness.eq(one.rewardShort, "25K coins, 1 Spark")
end)

Harness.test("goals: descriptions are short kid words for every stat", function()
	local v = GoalsModel.build(blank())
	Harness.eq(cardOf(v, "first_sweeps").desc, "Sweep 200 ash")
	Harness.eq(cardOf(v, "first_sales").desc, "Sell 5 times")
	Harness.eq(cardOf(v, "treasure_peek").desc, "Find 3 treasures")
	Harness.eq(cardOf(v, "spotless").desc, "Sweep 300 spots down to bare ground")
	Harness.eq(cardOf(v, "bounce_buddy").desc, "Get bounced by lava 3 times")
	Harness.eq(cardOf(v, "dodge_dancer").desc, "Dodge 10 volcano burps")
	Harness.eq(cardOf(v, "long_play").desc, "Play for 1 hour")
	Harness.eq(cardOf(v, "ash_legend").desc, "Sweep 1M ash")
	for _, c in v.cards do
		Harness.truthy(#c.desc > 0 and #c.desc < 60, c.id)
	end
end)

Harness.test("goals: play time shows minutes", function()
	local p = blank()
	p.stats.playSeconds = 725
	local c = cardOf(GoalsModel.build(p), "long_play")
	Harness.eq(c.progressText, "12/60 min")
end)

Harness.test("goals: model agrees with GoalRules for many profiles", function()
	local stats = { 0, 5, 200, 3000, 50000, 2e6 }
	for _, s in stats do
		local p = blank()
		p.stats.ashSwept = s
		p.stats.sellCount = s / 100
		p.stats.findsTotal = s / 1000
		p.stats.playSeconds = s
		p.stats.burpHits = s / 1000
		p.stats.burpDodged = s / 100
		p.stats.cleared = s
		if s == 3000 then
			p.goalsClaimed.first_sweeps = true
		end
		local v = GoalsModel.build(p)
		for _, goal in Goals.list do
			Harness.eq(cardOf(v, goal.id).status, GoalRules.status(goal, p), `{goal.id} at {s}`)
		end
		Harness.eq(v.readyCount, GoalRules.readyCount(p))
		Harness.eq(GoalsModel.badge(p), GoalRules.readyCount(p) > 0)
	end
end)

Harness.test("goals: junk input never throws", function()
	local junk: any = { stats = "x", goalsClaimed = 4 }
	Harness.eq(GoalsModel.build(junk).readyCount, 0)
	Harness.eq(GoalsModel.build({}).readyCount, 0)
	local odd: any = { stats = { ashSwept = 0 / 0, sellCount = -4 } }
	Harness.eq(GoalsModel.build(odd).readyCount, 0)
end)
