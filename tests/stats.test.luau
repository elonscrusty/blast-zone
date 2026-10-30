--!strict
-- Piece 24: lifetime stats and the top-wins board (pure parts).
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local RemoteDefs = require("../src/shared/RemoteDefs")
local StatsRules = require("../src/shared/Stats/StatsRules")
local StatsBook = require("../src/shared/Stats/StatsBook")
local BoardRules = require("../src/shared/Stats/BoardRules")

local test, eq, truthy = Harness.test, Harness.eq, Harness.truthy

-- ===== StatsRules =====

test("stats: read cleans junk and never errors", function()
	local s = StatsRules.read({ wins = 3.7, eliminations = -5, matches = 0 / 0 })
	eq(s.wins, 3)
	eq(s.eliminations, 0)
	eq(s.matches, 0)
	eq(StatsRules.read(nil).wins, 0)
	eq(StatsRules.read("x").matches, 0)
	eq(StatsRules.read({ wins = 1e20 }).wins, StatsRules.MAX)
end)

test("stats: 1st place is a win, every match counts once", function()
	local won = StatsRules.matchDelta(1)
	eq(won.wins, 1)
	eq(won.matches, 1)
	local lost = StatsRules.matchDelta(4)
	eq(lost.wins, 0)
	eq(lost.matches, 1)
	eq(StatsRules.matchDelta(nil).wins, 0)
end)

test("stats: a draw shares 1st place but is not a win", function()
	eq(StatsRules.matchDelta(1, false).wins, 0)
	eq(StatsRules.matchDelta(1, false).matches, 1)
	eq(StatsRules.matchDelta(1, true).wins, 1)
end)

test("stats: eliminations go to real players only", function()
	eq(StatsRules.eliminationCredit({ victimId = "p2", killerId = "p77", cause = "bullet" }), 77)
	eq(
		StatsRules.eliminationCredit({ victimId = "p2", killerId = "b3", cause = "bullet" }),
		nil,
		"bot"
	)
	eq(
		StatsRules.eliminationCredit({ victimId = "p2", killerId = "p2", cause = "explosion" }),
		nil,
		"self"
	)
	eq(StatsRules.eliminationCredit({ victimId = "p2", cause = "zone" }), nil, "zone")
	eq(
		StatsRules.eliminationCredit({ victimId = "p2", killerId = "p9", cause = "zone" }),
		nil,
		"zone with a source"
	)
	eq(StatsRules.eliminationCredit(nil), nil)
end)

test("stats: board hides only during a fight, card only in the lobby", function()
	for _, p in { "Spawning", "Active", "FinalPressure", "Finished" } do
		eq(StatsRules.boardVisible(p), false, p)
	end
	for _, p in { "Waiting", "Countdown", "Results", "Resetting" } do
		eq(StatsRules.boardVisible(p), true, p)
	end
	eq(StatsRules.boardVisible(nil), true)
	eq(StatsRules.cardVisible("Waiting"), true)
	eq(StatsRules.cardVisible("Countdown"), true)
	eq(StatsRules.cardVisible("Active"), false)
	eq(StatsRules.cardVisible(nil), false)
end)

test("stats: YOU row text", function()
	local line =
		StatsRules.youLine({ wins = 12, eliminations = 1500, matches = 46 }, BoardRules.short)
	truthy(string.find(line, "12 wins", 1, true), line)
	truthy(string.find(line, "1.5K elims", 1, true), line)
	truthy(string.find(line, "46 games", 1, true), line)
end)

-- ===== StatsBook (fake profile) =====

type Fake = {
	book: StatsBook.Book,
	data: { [number]: any }, -- userId -> profile data, nil = not loaded
	shown: { [number]: any },
	boardWins: { [number]: number },
	saves: number,
}

local function fake(): Fake
	local f = { data = {}, shown = {}, boardWins = {}, saves = 0 } :: any
	f.book = StatsBook.new({
		save = function(userId, delta)
			local data = f.data[userId]
			if data == nil then
				return nil -- like Profiles.update before load
			end
			f.saves += 1
			local total = StatsRules.add(StatsRules.read(data.stats), delta)
			data.stats =
				{ wins = total.wins, eliminations = total.eliminations, matches = total.matches }
			return total
		end,
		changed = function(userId, shown)
			f.shown[userId] = shown
		end,
		savedWins = function(userId, wins)
			f.boardWins[userId] = wins
		end,
	})
	return f
end

test("book: saved stats show after load and new ones add on top", function()
	local f = fake()
	f.data[1] =
		{ stats = { wins = 5, eliminations = 20, matches = 9 }, progression = { coins = 3 } }
	f.book:join(1)
	f.book:loaded(1)
	eq(f.shown[1].wins, 5)
	eq(f.shown[1].saved, true)
	eq(f.boardWins[1], 5, "saved wins go to the board once known")
	f.book:earn(1, StatsRules.matchDelta(1))
	f.book:earn(1, { wins = 0, eliminations = 1, matches = 0 })
	eq(f.data[1].stats.wins, 6)
	eq(f.data[1].stats.matches, 10)
	eq(f.data[1].stats.eliminations, 21)
	eq(f.data[1].progression.coins, 3, "other sections untouched")
	eq(f.shown[1].matches, 10)
	eq(f.boardWins[1], 6)
end)

test("book: stats earned before the profile loads are kept and written on load", function()
	local f = fake()
	f.book:join(2)
	f.book:earn(2, StatsRules.matchDelta(1))
	f.book:earn(2, { wins = 0, eliminations = 3, matches = 0 })
	eq(f.saves, 0, "nothing written before load")
	eq(f.shown[2].wins, 1)
	eq(f.shown[2].saved, false)
	f.data[2] = { stats = { wins = 10, eliminations = 0, matches = 10 } }
	f.book:loaded(2)
	eq(f.data[2].stats.wins, 11)
	eq(f.data[2].stats.eliminations, 3)
	eq(f.data[2].stats.matches, 11)
	eq(f.shown[2].saved, true)
	eq(f.boardWins[2], 11)
end)

test("book: a failed load never writes, and a later retry still saves", function()
	local f = fake()
	f.book:join(3)
	f.book:loaded(3) -- profile failed: save returns nil
	f.book:earn(3, StatsRules.matchDelta(2))
	eq(f.saves, 0)
	eq(f.shown[3].matches, 1, "still shown this session")
	eq(f.boardWins[3], nil, "unsaved wins never reach the board")
	f.data[3] = {} -- retry worked, brand new player
	f.book:loaded(3)
	eq(f.data[3].stats.matches, 1)
	eq(f.data[3].stats.wins, 0)
	eq(f.boardWins[3], nil, "zero wins are not put on the board")
end)

test("book: events for players not here are ignored", function()
	local f = fake()
	f.book:earn(99, StatsRules.matchDelta(1))
	eq(f.shown[99], nil)
	f.data[4] = {}
	f.book:join(4)
	f.book:loaded(4)
	f.book:leave(4)
	f.book:earn(4, StatsRules.matchDelta(1))
	eq(f.data[4].stats.wins, 0)
	eq(f.book:get(4), nil)
end)

test("book: a junk saved section is repaired, not crashed on", function()
	local f = fake()
	f.data[5] = { stats = "broken" }
	f.book:join(5)
	f.book:loaded(5)
	eq(f.data[5].stats.wins, 0)
	f.book:earn(5, StatsRules.matchDelta(1))
	eq(f.data[5].stats.wins, 1)
end)

-- ===== BoardRules =====

test("board: write never lowers the saved value", function()
	eq(BoardRules.merge(nil, 4), 4)
	eq(BoardRules.merge(10, 4), 10)
	eq(BoardRules.merge(10, 12), 12)
	eq(BoardRules.merge("x", 3), 3)
	eq(BoardRules.merge(5, -2), 5)
end)

test("board: rows are clean, sorted and capped", function()
	local entries = {
		{ key = "200", value = 7 },
		{ key = "100", value = 9 },
		{ key = "bad", value = 50 },
		{ key = "300", value = 0 },
		{ key = "400", value = 7 },
		{ key = "500", value = 0 / 0 },
		{ key = "600", value = 3 },
	}
	local rows = BoardRules.rows(entries, function(userId)
		return if userId == 200 then nil else `u{userId}`
	end, 3)
	eq(#rows, 3)
	eq(rows[1].userId, 100)
	eq(rows[1].rank, 1)
	eq(rows[2].userId, 200, "tie broken by userId")
	eq(rows[2].name, BoardRules.FALLBACK_NAME)
	eq(rows[3].userId, 400)
	eq(rows[3].rank, 3)
end)

test("board: short numbers", function()
	eq(BoardRules.short(0), "0")
	eq(BoardRules.short(999), "999")
	eq(BoardRules.short(1000), "1K")
	eq(BoardRules.short(1250), "1.2K")
	eq(BoardRules.short(34999), "34K")
	eq(BoardRules.short(1500000), "1.5M")
	eq(BoardRules.short(-4), "0")
end)

test("board: queue keeps the newest count per player and takes in batches", function()
	local q = BoardRules.newQueue()
	q:put(1, 3)
	q:put(2, 1)
	q:put(1, 5)
	q:put(1, 4) -- an older count arriving late never wins
	q:put(3, 0) -- zero is not worth a write
	eq(q:size(), 2)
	local first = q:take(1)
	eq(#first, 1)
	eq(first[1].userId, 1)
	eq(first[1].wins, 5)
	eq(q:size(), 1)
	eq(q:take(10)[1].userId, 2)
	eq(q:size(), 0)
end)

test("board: keys are plain user ids", function()
	eq(BoardRules.keyFor(123.0), "123")
	eq(BoardRules.userIdOf("123"), 123)
	eq(BoardRules.userIdOf("-1"), nil)
	eq(BoardRules.userIdOf(5), nil)
end)

-- ===== wiring =====

test("stats: remotes and config are in place", function()
	local req = RemoteDefs.byName.StatsRequest
	truthy(
		req and req.direction == "toServer" and req.rate ~= nil and req.schema ~= nil,
		"StatsRequest"
	)
	eq(#(req.schema :: any), 0, "StatsRequest takes no arguments")
	truthy(RemoteDefs.byName.StatsUpdate and RemoteDefs.byName.StatsUpdate.direction == "toClient")
	eq(Config.Stats.profileKey, "stats")
	truthy(Config.Stats.board.rows >= 3, "podium needs 3 rows")
	truthy(Config.Stats.board.writeSeconds >= 6, "OrderedDataStore writes are batched")
	eq(Config.Stats.board.look, "B", "carter picked B Neon Tower")
end)
