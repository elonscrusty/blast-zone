--!strict
local Harness = require("./harness")
local ResultsText = require("../src/client/Match/ResultsText")

local rows = {
	{
		participantId = "p1",
		displayName = "Alice",
		isBot = false,
		placement = 1,
		eliminations = 3,
		survivedSeconds = 161,
	},
	{
		participantId = "b1",
		displayName = "[BOT] Volt",
		isBot = true,
		placement = 2,
		eliminations = 1,
		survivedSeconds = 100,
	},
}

Harness.test("ordinal handles 1st 2nd 3rd 4th and the teens", function()
	Harness.eq(ResultsText.ordinal(1), "1st")
	Harness.eq(ResultsText.ordinal(2), "2nd")
	Harness.eq(ResultsText.ordinal(3), "3rd")
	Harness.eq(ResultsText.ordinal(4), "4th")
	Harness.eq(ResultsText.ordinal(11), "11th")
	Harness.eq(ResultsText.ordinal(12), "12th")
	Harness.eq(ResultsText.ordinal(13), "13th")
	Harness.eq(ResultsText.ordinal(21), "21st")
end)

Harness.test("winner sees YOU WIN with place, kills, time, reward", function()
	local w = ResultsText.describe({
		rows = rows,
		outcome = "win",
		winnerId = "p1",
		you = { placement = 1, eliminations = 3, survivedSeconds = 161, reward = 55 },
	})
	Harness.eq(w.title, "YOU WIN!")
	Harness.eq(w.tone, "win")
	Harness.eq(w.time, "2:41")
	Harness.eq(w.kills, 3)
	Harness.eq(w.reward, 55)
end)

Harness.test("loser is told who won and what place they got", function()
	local w = ResultsText.describe({
		rows = rows,
		outcome = "win",
		winnerId = "p1",
		you = { placement = 2, eliminations = 1, survivedSeconds = 100, reward = 25 },
	})
	Harness.eq(w.title, "NICE TRY!")
	Harness.eq(w.tone, "lose")
	Harness.eq(w.sub, "2nd place · Alice won")
end)

Harness.test("draw: sharing first says so; others just lose", function()
	local shared = ResultsText.describe({
		rows = rows,
		outcome = "draw",
		draw = true,
		you = { placement = 1, eliminations = 1, survivedSeconds = 50, reward = 40 },
	})
	Harness.eq(shared.title, "DRAW!")
	Harness.eq(shared.sub, "You share 1st place")
	local other = ResultsText.describe({
		rows = rows,
		outcome = "draw",
		draw = true,
		you = { placement = 3, eliminations = 0, survivedSeconds = 10, reward = 10 },
	})
	Harness.eq(other.title, "NICE TRY!")
end)

Harness.test("abandoned and watcher cases have honest words", function()
	local a = ResultsText.describe({
		rows = rows,
		outcome = "abandoned",
		you = { placement = 2, eliminations = 0, survivedSeconds = 30, reward = 18 },
	})
	Harness.eq(a.title, "NO WINNER")
	local watcher = ResultsText.describe({ rows = rows, outcome = "win", winnerId = "p1" })
	Harness.eq(watcher.title, "MATCH OVER")
	Harness.eq(watcher.sub, "Alice won")
	Harness.eq(watcher.place, nil)
end)

Harness.test("formatTime", function()
	Harness.eq(ResultsText.formatTime(125.4), "2:05")
	Harness.eq(ResultsText.formatTime(-4), "0:00")
end)

Harness.test("defeat line: who got you, or what, and your place; ignores other players", function()
	local byPlayer = {
		victimId = "p1",
		killerId = "b2",
		killerName = "[BOT] Volt",
		cause = "bullet",
		placement = 3,
	}
	Harness.eq(ResultsText.defeatLine(byPlayer, "p1"), "by [BOT] Volt · 3rd place")
	Harness.eq(ResultsText.defeatLine(byPlayer, "p9"), nil)
	Harness.eq(
		ResultsText.defeatLine({ victimId = "p1", cause = "zone", placement = 2 }, "p1"),
		"by the closing zone · 2nd place"
	)
	Harness.eq(
		ResultsText.defeatLine({ victimId = "p1", cause = "weird", placement = 5 }, "p1"),
		"by the arena · 5th place"
	)
end)
