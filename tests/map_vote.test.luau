--!strict
-- Map vote rules (piece 33): counting, ties, locking, who may vote, phases.
local Harness = require("./harness")
local MatchPhase = require("../src/shared/MatchPhase")
local RemoteDefs = require("../src/shared/RemoteDefs")
local VoteBook = require("../src/shared/MapVote/VoteBook")
local VoteFlow = require("../src/shared/MapVote/VoteFlow")

local test, eq, truthy = Harness.test, Harness.eq, Harness.truthy

local POOL: { VoteBook.MapInfo } = {
	{ id = "C", name = "Arcade Row" },
	{ id = "D", name = "Neon Plaza" },
	{ id = "E", name = "Market Hall" },
}

local function first(_: number): number
	return 1
end
local function last(n: number): number
	return n
end

test("vote book: a closed book takes no votes", function()
	local book = VoteBook.new(POOL)
	eq(book:cast("p1", "C"), false)
end)

test("vote book: a map outside the pool is refused", function()
	local book = VoteBook.new(POOL)
	book:setOpen(true)
	eq(book:cast("p1", "Z"), false)
	eq(book:cast("p1", ""), false)
	eq(book:cast("p1", "C"), true)
end)

test("vote book: one vote each, a new vote replaces the old", function()
	local book = VoteBook.new(POOL)
	book:setOpen(true)
	book:cast("p1", "C")
	book:cast("p1", "D")
	local counts = book:counts()
	eq(counts.C, 0)
	eq(counts.D, 1)
end)

test("vote book: most votes wins", function()
	local book = VoteBook.new(POOL)
	book:setOpen(true)
	book:cast("p1", "D")
	book:cast("p2", "D")
	book:cast("p3", "C")
	eq(book:winner(first, nil), "D")
end)

test("vote book: no votes means no winner", function()
	local book = VoteBook.new(POOL)
	book:setOpen(true)
	eq(book:winner(first, nil), nil)
end)

test("vote book: a tie uses the pick, in pool order", function()
	local book = VoteBook.new(POOL)
	book:setOpen(true)
	book:cast("p1", "C")
	book:cast("p2", "E")
	eq(book:winner(first, nil), "C")
	eq(book:winner(last, nil), "E")
end)

test("vote book: a tie does not repeat the map just played when there is a choice", function()
	local book = VoteBook.new(POOL)
	book:setOpen(true)
	book:cast("p1", "C")
	book:cast("p2", "D")
	eq(book:winner(first, "C"), "D")
end)

test("vote book: the map just played still wins on votes alone", function()
	local book = VoteBook.new(POOL)
	book:setOpen(true)
	book:cast("p1", "C")
	book:cast("p2", "C")
	book:cast("p3", "D")
	eq(book:winner(first, "C"), "C")
end)

test("vote book: a wild pick number cannot go out of range", function()
	local book = VoteBook.new(POOL)
	book:setOpen(true)
	book:cast("p1", "C")
	book:cast("p2", "D")
	eq(
		book:winner(function()
			return 99
		end, nil),
		"D"
	)
	eq(
		book:winner(function()
			return -4
		end, nil),
		"C"
	)
end)

test("vote book: the pool is copied, so later edits to it do not change the book", function()
	local pool: { VoteBook.MapInfo } = { { id = "C", name = "Arcade Row" } }
	local book = VoteBook.new(pool)
	pool[1].id = "Z"
	truthy(book:has("C"))
end)

test("vote flow: open in the lobby, locked at Spawning", function()
	local flow = VoteFlow.new(POOL, first)
	eq(flow:vote("p1", "D"), true)
	flow:onPhase(MatchPhase.Countdown)
	eq(flow:vote("p2", "D"), true)
	flow:onPhase(MatchPhase.Spawning)
	eq(flow:vote("p3", "C"), false)
	eq(flow:takeWinner(), "D")
	eq(flow:state("p1").open, false)
end)

test("vote flow: takeWinner locks the vote and repeats its answer", function()
	local flow = VoteFlow.new(POOL, first)
	flow:vote("p1", "E")
	eq(flow:takeWinner(), "E")
	eq(flow:vote("p2", "C"), false)
	eq(flow:takeWinner(), "E")
	eq(flow:state("p1").nextMapId, "E")
end)

test("vote flow: nobody voted gives nil, so the normal rotation runs", function()
	local flow = VoteFlow.new(POOL, first)
	flow:onPhase(MatchPhase.Spawning)
	eq(flow:takeWinner(), nil)
end)

test("vote flow: Results starts a clean window", function()
	local flow = VoteFlow.new(POOL, first)
	flow:vote("p1", "D")
	flow:onPhase(MatchPhase.Spawning)
	flow:onPhase(MatchPhase.Results)
	eq(flow:state("p1").open, true)
	eq(flow:state("p1").yourVote, nil)
	eq(flow:state("p1").nextMapId, nil)
	eq(flow:vote("p1", "C"), true)
end)

test("vote flow: an abort (Resetting without Results) reopens a clean window", function()
	local flow = VoteFlow.new(POOL, first)
	flow:vote("p1", "D")
	flow:onPhase(MatchPhase.Spawning)
	flow:onPhase(MatchPhase.Resetting)
	eq(flow:state("p1").open, true)
	eq(flow:state("p1").yourVote, nil)
end)

test("vote flow: Countdown falling back to Waiting keeps the votes", function()
	local flow = VoteFlow.new(POOL, first)
	flow:onPhase(MatchPhase.Results)
	flow:vote("p1", "D")
	flow:onPhase(MatchPhase.Resetting)
	flow:onPhase(MatchPhase.Waiting)
	flow:onPhase(MatchPhase.Countdown)
	flow:onPhase(MatchPhase.Waiting)
	eq(flow:state("p1").yourVote, "D")
end)

test("vote flow: the vote is shut during the fight", function()
	local flow = VoteFlow.new(POOL, first)
	for _, phase in
		{ MatchPhase.Spawning, MatchPhase.Active, MatchPhase.FinalPressure, MatchPhase.Finished }
	do
		flow:onPhase(phase)
		eq(flow:vote("p1", "C"), false, phase)
	end
end)

test("vote flow: a leaving player's vote is removed while open", function()
	local flow = VoteFlow.new(POOL, first)
	flow:vote("p1", "D")
	flow:leave("p1")
	eq(flow:state("p2").maps[2].votes, 0)
end)

test("vote flow: a leaving player cannot change a locked result", function()
	local flow = VoteFlow.new(POOL, first)
	flow:vote("p1", "D")
	flow:takeWinner()
	flow:leave("p1")
	eq(flow:state("p2").nextMapId, "D")
end)

test("vote flow: new pool keeps votes for maps that stay, drops the rest", function()
	local flow = VoteFlow.new(POOL, first)
	flow:vote("p1", "D")
	flow:vote("p2", "E")
	flow:setPool({ { id = "C", name = "Arcade Row" }, { id = "D", name = "Neon Plaza" } })
	eq(flow:state("p1").yourVote, "D")
	eq(flow:state("p2").yourVote, nil)
	eq(flow:state(nil).open, true)
end)

test("vote flow: ties avoid the map that was just played", function()
	local flow = VoteFlow.new(POOL, first)
	flow:setCurrentMap("C")
	flow:vote("p1", "C")
	flow:vote("p2", "E")
	eq(flow:takeWinner(), "E")
end)

test("map vote remotes: the vote asks are small and rate limited", function()
	local def = RemoteDefs.byName["MapVoteRequest"]
	truthy(def, "MapVoteRequest missing")
	eq(def.direction, "toServer")
	truthy(def.rate and def.rate.perSecond <= 3, "vote rate too high")
	truthy(def.schema and def.schema[1].kind == "id" and def.schema[1].maxLen ~= nil)
	eq(RemoteDefs.byName["MapVoteState"].direction, "toClient")
end)

Harness.test("vote buttons hide on the results screen but the vote stays open", function()
	Harness.eq(VoteFlow.buttonsShown("Results"), false)
	Harness.eq(VoteFlow.buttonsShown("Finished"), false)
	Harness.eq(VoteFlow.buttonsShown("Waiting"), true)
	Harness.eq(VoteFlow.buttonsShown("Countdown"), true)
	Harness.eq(VoteFlow.buttonsShown(nil), true)
end)
