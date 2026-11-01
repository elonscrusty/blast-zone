--!strict
-- Daily Reward view-model: UTC days, streak edges, countdown text, tile layout.
local Harness = require("./harness")
local Daily = require("../src/shared/Catalog/Daily")
local DailyRules = require("../src/shared/Player/DailyRules")
local Economy = require("../src/shared/Rules/Economy")
local DailyModel = require("../src/shared/Ui/DailyModel")

local DAY = 86400
local D0 = 20000

local function states(v: DailyModel.View): string
	local out: { string } = {}
	for _, t in v.tiles do
		table.insert(out, string.sub(t.state, 1, 1))
	end
	return table.concat(out)
end

Harness.test("daily: first visit, gift is ready on day 1", function()
	local v = DailyModel.build({ lastDay = 0, streak = 0 }, D0 * DAY + 3600)
	Harness.eq(v.canClaim, true)
	Harness.eq(v.badge, true)
	Harness.eq(v.todayDay, 1)
	Harness.eq(v.nextDay, nil)
	Harness.eq(states(v), "tllllll") -- today, then 6 later
	Harness.eq(v.streak, 0)
	Harness.eq(v.streakText, "Start your streak today!")
	Harness.eq(v.countdownText, "Your gift is ready!")
	Harness.eq(v.buttonText, "CLAIM GIFT!")
	Harness.eq(v.giftText, "Today's gift: 💰 100")
	Harness.eq(v.noteText, "")
	Harness.eq(v.reason, "")
	Harness.eq(#v.tiles, 7)
end)

Harness.test("daily: already claimed today shows a countdown", function()
	local now = D0 * DAY + 100
	local v = DailyModel.build({ lastDay = D0, streak = 1 }, now)
	Harness.eq(v.canClaim, false)
	Harness.eq(v.badge, false)
	Harness.eq(v.todayDay, nil)
	Harness.eq(v.nextDay, 2)
	Harness.eq(states(v), "cnlllll") -- claimed, next, later...
	Harness.eq(v.tiles[1].stateText, "✔")
	Harness.eq(v.tiles[2].stateText, "TOMORROW")
	Harness.eq(v.streakText, "🔥 1 day in a row")
	Harness.eq(v.countdownText, "Next gift in 23h 59m")
	Harness.eq(v.secondsToNext, DAY - 100)
	Harness.eq(v.buttonText, "Come back tomorrow")
	Harness.eq(v.giftText, "You got today's gift!")
	Harness.truthy(#v.reason > 0)
end)

Harness.test("daily: UTC midnight flips the gift to ready", function()
	local claimed = { lastDay = D0, streak = 1 }
	local last = DailyModel.build(claimed, (D0 + 1) * DAY - 1)
	Harness.eq(last.canClaim, false)
	Harness.eq(last.countdownText, "Next gift in 1s")
	Harness.eq(last.secondsToNext, 1)
	local first = DailyModel.build(claimed, (D0 + 1) * DAY)
	Harness.eq(first.canClaim, true)
	Harness.eq(first.today, D0 + 1)
	Harness.eq(first.todayDay, 2)
	Harness.eq(states(first), "ctlllll") -- day 1 ticked, day 2 glows
	Harness.eq(first.streakText, "🔥 1 day in a row")
	Harness.eq(first.giftText, "Today's gift: 💰 200")
	Harness.eq(first.secondsToNext, DAY)
end)

Harness.test("daily: a missed day starts again at day 1", function()
	local v = DailyModel.build({ lastDay = D0, streak = 3 }, (D0 + 2) * DAY + 5)
	Harness.eq(v.canClaim, true)
	Harness.eq(v.todayDay, 1)
	Harness.eq(states(v), "tllllll")
	Harness.eq(v.streak, 0)
	Harness.eq(v.streakText, "Start your streak today!")
	Harness.eq(v.noteText, "You missed a day, so we start again at Day 1.")
end)

Harness.test("daily: mid-week ladder", function()
	local v = DailyModel.build({ lastDay = D0 - 1, streak = 4 }, D0 * DAY)
	Harness.eq(v.canClaim, true)
	Harness.eq(v.todayDay, 5)
	Harness.eq(states(v), "cccctll")
	Harness.eq(v.streakText, "🔥 4 days in a row")
	Harness.eq(v.tiles[5].coins, 1000)
	local done = DailyModel.build({ lastDay = D0, streak = 5 }, D0 * DAY + 10)
	Harness.eq(done.canClaim, false)
	Harness.eq(states(done), "cccccnl")
end)

Harness.test("daily: day 7 is special and a full week wraps", function()
	local seven = DailyModel.build({ lastDay = D0 - 1, streak = 6 }, D0 * DAY)
	Harness.eq(seven.todayDay, 7)
	local t = seven.tiles[7]
	Harness.eq(t.special, true)
	Harness.eq(t.icon, "🎁")
	Harness.eq(t.rewardText, "3K")
	Harness.eq(t.sparksText, "+3 ✨")
	Harness.eq(seven.tiles[1].special, false)
	Harness.eq(seven.tiles[1].sparksText, "")
	Harness.eq(seven.giftText, "Today's gift: 💰 3K  ✨ 3")

	local week = DailyModel.build({ lastDay = D0, streak = 7 }, D0 * DAY + 1)
	Harness.eq(week.canClaim, false)
	Harness.eq(states(week), "ccccccc")
	Harness.eq(week.nextDay, 1)
	Harness.eq(week.noteText, "Wow, a whole week! A new week starts tomorrow.")

	-- next morning: day 1 again, none ticked, streak keeps counting
	local again = DailyModel.build({ lastDay = D0, streak = 7 }, (D0 + 1) * DAY)
	Harness.eq(again.canClaim, true)
	Harness.eq(again.todayDay, 1)
	Harness.eq(states(again), "tllllll")
	Harness.eq(again.streakText, "🔥 7 days in a row")
end)

Harness.test("daily: a long streak wraps its ladder day", function()
	local v = DailyModel.build({ lastDay = D0, streak = 9 }, D0 * DAY + 1)
	Harness.eq(v.canClaim, false)
	Harness.eq(states(v), "ccnllll") -- 9 -> day 2 of the week
	Harness.eq(v.streakText, "🔥 9 days in a row")
end)

Harness.test("daily: a clock that went backwards cannot claim", function()
	local v = DailyModel.build({ lastDay = D0 + 5, streak = 2 }, D0 * DAY)
	Harness.eq(v.canClaim, false)
	Harness.eq(v.countdownText, "Come back tomorrow!")
	Harness.eq(v.buttonText, "Come back tomorrow")
end)

Harness.test("daily: junk input is safe", function()
	local a = DailyModel.build(nil, D0 * DAY)
	Harness.eq(a.canClaim, true)
	local b = DailyModel.build({ lastDay = "x", streak = 0 / 0 }, D0 * DAY)
	Harness.eq(b.canClaim, true)
	Harness.eq(b.todayDay, 1)
	local c = DailyModel.build({ lastDay = 0, streak = 0 }, 0 / 0)
	Harness.eq(c.canClaim, false)
	Harness.eq(c.today, 0)
	Harness.truthy(#c.countdownText > 0)
	local d = DailyModel.build({ lastDay = 0, streak = 0 }, -50)
	Harness.eq(d.canClaim, false)
end)

Harness.test("daily: waitText", function()
	Harness.eq(DailyModel.waitText(0), "Next gift in 1s")
	Harness.eq(DailyModel.waitText(59), "Next gift in 59s")
	Harness.eq(DailyModel.waitText(60), "Next gift in 1m")
	Harness.eq(DailyModel.waitText(61), "Next gift in 2m")
	Harness.eq(DailyModel.waitText(3599), "Next gift in 1h 0m")
	Harness.eq(DailyModel.waitText(3481), "Next gift in 59m")
	Harness.eq(DailyModel.waitText(3600), "Next gift in 1h 0m")
	Harness.eq(DailyModel.waitText(18720), "Next gift in 5h 12m")
	Harness.eq(DailyModel.waitText(18721), "Next gift in 5h 13m")
	Harness.eq(DailyModel.waitText(86400), "Next gift in 24h 0m")
	Harness.eq(DailyModel.waitText(0 / 0), "Next gift in 1s")
	Harness.eq(DailyModel.waitText(-5), "Next gift in 1s")
end)

Harness.test("daily: tiles show the catalog rewards", function()
	local v = DailyModel.build({ lastDay = 0, streak = 0 }, D0 * DAY)
	for i, tile in v.tiles do
		local reward = Daily.rewardFor(i)
		Harness.eq(tile.day, i)
		Harness.eq(tile.label, `Day {i}`)
		Harness.eq(tile.coins, reward.coins)
		Harness.eq(tile.sparks, reward.sparks)
	end
	Harness.eq(v.tiles[2].rewardText, "200")
	Harness.eq(v.tiles[6].rewardText, "1.6K")
end)

Harness.test("daily: model follows DailyRules through a real week and a missed day", function()
	local p = Economy.blankProfile()
	local day = D0
	for step = 1, 9 do
		local before = DailyModel.build(p.daily, day * DAY + 40000)
		Harness.eq(before.canClaim, true, "ready on step " .. step)
		Harness.eq(before.canClaim, DailyRules.canClaim(p.daily, day))
		local paid = DailyRules.apply(p, day)
		Harness.truthy(paid ~= nil)
		local after = DailyModel.build(p.daily, day * DAY + 40001)
		Harness.eq(after.canClaim, false, "claimed on step " .. step)
		local tick = (step - 1) % 7 + 1
		local ticked = 0
		for _, t in after.tiles do
			if t.state == "claimed" then
				ticked += 1
			end
		end
		Harness.eq(ticked, tick, "ticks on step " .. step)
		Harness.eq(after.streak, step)
		day += 1
	end
	-- skip two days
	day += 2
	local back = DailyModel.build(p.daily, day * DAY)
	Harness.eq(back.canClaim, true)
	Harness.eq(back.todayDay, 1)
	Harness.eq(back.streak, 0)
end)

local function overlap(a: DailyModel.Rect, b: DailyModel.Rect): boolean
	return a.x < b.x + b.w - 0.001
		and b.x < a.x + a.w - 0.001
		and a.y < b.y + b.h - 0.001
		and b.y < a.y + a.h - 0.001
end

Harness.test("daily: tile layout fits every width without overlap", function()
	for width = 150, 700, 7 do
		local layout = DailyModel.tileRects(width)
		Harness.eq(#layout.rects, 7, "w" .. width)
		local bottom = 0
		for i, r in layout.rects do
			Harness.truthy(r.x >= -0.001, `w{width} tile{i} left`)
			Harness.truthy(r.x + r.w <= width + 0.001, `w{width} tile{i} right`)
			Harness.truthy(r.w >= 40, `w{width} tile{i} wide enough`)
			bottom = math.max(bottom, r.y + r.h)
			for j = i + 1, 7 do
				Harness.truthy(not overlap(r, layout.rects[j]), `w{width} {i}/{j}`)
			end
		end
		Harness.near(bottom, layout.height, 0.001, "height w" .. width)
	end
end)

Harness.test("daily: wide screens use one row, phones upright use two", function()
	Harness.eq(DailyModel.tileRects(642).height, 86)
	local tall = DailyModel.tileRects(298)
	Harness.eq(tall.height, 86 * 2 + 6)
	Harness.truthy(tall.rects[7].w > tall.rects[6].w * 1.9, "day 7 is double wide")
	Harness.eq(tall.rects[7].y, tall.rects[5].y)
	local tiny = DailyModel.tileRects(200)
	Harness.eq(tiny.height, 86 * 3 + 12)
	Harness.eq(DailyModel.tileRects(0 / 0).height > 0, true)
end)
