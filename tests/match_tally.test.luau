--!strict
-- Video 3 gap 29: the counts on the results card (things broken, crates opened, powers picked).
local fs = require("@lune/fs")
local Harness = require("./harness")
local MatchTally = require("../src/shared/Results/MatchTally")

local test, eq, truthy = Harness.test, Harness.eq, Harness.truthy

test("tally: counts per fighter and kind, and a quiet fighter reads zeros", function()
	local book = MatchTally.new()
	truthy(MatchTally.add(book, "p1", "broken"))
	truthy(MatchTally.add(book, "p1", "broken"))
	truthy(MatchTally.add(book, "p1", "crates"))
	truthy(MatchTally.add(book, "p2", "powers", 3))
	local one = MatchTally.get(book, "p1")
	eq(one.broken, 2)
	eq(one.crates, 1)
	eq(one.powers, 0)
	eq(MatchTally.get(book, "p2").powers, 3)
	local nobody = MatchTally.get(book, "p9")
	eq(nobody.broken + nobody.crates + nobody.powers, 0)
end)

test("tally: junk is refused and changes nothing", function()
	local book = MatchTally.new()
	eq(MatchTally.add(book, nil, "broken"), false)
	eq(MatchTally.add(book, "", "broken"), false)
	eq(MatchTally.add(book, "p1", "gold"), false)
	eq(MatchTally.add(book, "p1", "broken", 0), false)
	eq(MatchTally.add(book, "p1", "broken", -4), false)
	eq(MatchTally.add(book, "p1", "broken", 0 / 0), false)
	eq(MatchTally.add(book, "p1", "broken", 1e9), false)
	eq(next(book), nil)
end)

test("tally: a count stops at the cap", function()
	local book = MatchTally.new()
	for _ = 1, 3 do
		MatchTally.add(book, "p1", "broken", 500)
	end
	eq(MatchTally.get(book, "p1").broken, MatchTally.MAX)
end)

test("tally: get hands out a copy", function()
	local book = MatchTally.new()
	MatchTally.add(book, "p1", "crates")
	local copy = MatchTally.get(book, "p1")
	copy.crates = 50
	eq(MatchTally.get(book, "p1").crates, 1)
end)

test("tally: reset clears everyone (a new match starts from zero)", function()
	local book = MatchTally.new()
	MatchTally.add(book, "p1", "broken")
	MatchTally.reset(book)
	eq(MatchTally.get(book, "p1").broken, 0)
end)

test("tally: the card lists only what happened, in a fixed order", function()
	eq(#MatchTally.lines({ broken = 0, crates = 0, powers = 0 }), 0)
	local lines = MatchTally.lines({ broken = 12, crates = 0, powers = 2 })
	eq(#lines, 2)
	eq(lines[1].label, "Things broken")
	eq(lines[2].label, "Powers picked")
	eq(
		MatchTally.extrasLine({ broken = 12, crates = 3, powers = 2 }),
		"12 things broken · 3 crates opened · 2 powers picked"
	)
	eq(MatchTally.extrasLine({ broken = 0, crates = 0, powers = 0 }), nil)
end)

test("tally: what the client reads is cleaned", function()
	eq(MatchTally.extrasLine(nil), nil)
	eq(MatchTally.extrasLine("hi"), nil)
	eq(MatchTally.extrasLine({ broken = -3, crates = 0 / 0, powers = "7" }), nil)
	eq(MatchTally.read({ broken = 2.9 }).broken, 2)
	eq(MatchTally.read({ broken = 1e12 }).broken, MatchTally.MAX)
end)

-- The counting only happens if the systems really call it (the server decides, the client never counts).
local function has(path: string, needle: string): boolean
	return string.find(fs.readFile(path), needle, 1, true) ~= nil
end

test("tally: props, crates and power picks are counted on the server", function()
	truthy(has("src/server/Props/BreakSystem.luau", 'TallySystem.add(breakerId, "broken")'))
	truthy(has("src/server/Pickups/ContainerSystem.luau", 'TallySystem.add(breakerId, "crates")'))
	truthy(has("src/server/Upgrades/UpgradeSystem.luau", 'TallySystem.add(id, "powers")'))
end)

test("tally: results carry only the asking player's own counts", function()
	truthy(has("src/server/Match/MatchSystem.luau", "payload.you.tally = TallySystem.get(id)"))
	truthy(has("src/server/Results/TallySystem.luau", "MatchStarted"))
end)
