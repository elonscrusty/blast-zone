--!strict
-- Stability: whole matches over and over with the real roster, damage door and match flow, and the same
-- per-participant books the server systems keep (health, weapons, XP, slide cooldowns). After every reset
-- nothing may be left behind, nothing may fire twice, and nothing late may change a finished match.
-- This also stands in for the brief's edge cases (section 16, 23, 26), driven across systems.

local Harness = require("./harness")
local Config = require("../src/shared/Config")
local HealthBook = require("../src/server/Combat/HealthBook")
local WeaponState = require("../src/server/Combat/WeaponState")
local SlideBook = require("../src/shared/Movement/SlideBook")
local RunXp = require("../src/shared/RunXp")
local Matches = require("./match_controller.test")

type Rig = Matches.Rig

-- The books each server system keeps, hooked up the way the systems hook them (Enrolled / Removed / phase).
type Books = {
	health: any,
	weapons: { [string]: any },
	ledger: any,
	slides: any,
	slideOwners: { [string]: boolean },
	removedCount: number,
}

local function attach(rig: Rig): Books
	local books: Books = {
		health = HealthBook.new(Config.Health.max),
		weapons = {},
		ledger = RunXp.new(Config.Xp),
		slides = SlideBook.new(),
		slideOwners = {},
		removedCount = 0,
	}
	rig.registry.Enrolled:connect(function(p: any)
		books.health:add(p.id)
		books.weapons[p.id] = WeaponState.new({ 12, 3 }, Config.Combat.fireTolerance)
		books.ledger:reset(p.id)
	end)
	rig.registry.Removed:connect(function(p: any)
		books.removedCount += 1
		books.health:remove(p.id)
		books.weapons[p.id] = nil
		books.ledger:forget(p.id)
		books.slides:reset(p.id)
		books.slideOwners[p.id] = nil
	end)
	rig.ctx.MatchStarted:connect(function()
		rig.router:reset()
	end)
	rig.ctx.PhaseChanged:connect(function(phase: string)
		if phase == "Finished" or phase == "Results" or phase == "Resetting" then
			for _, w in books.weapons do
				w:lock()
			end
		end
	end)
	-- The same health maths the damage door uses in the game.
	rig.router:bind(function(req: any)
		local dealt, remaining, dead = books.health:apply(req.targetId, req.amount, req.sourceId)
		return {
			applied = dealt > 0,
			reason = if dealt > 0 then nil else "no-health",
			dealt = dealt,
			remaining = remaining,
			eliminated = dead,
		}
	end)
	return books
end

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function assertEmpty(rig: Rig, books: Books, label: string)
	Harness.eq(#rig.registry:list(), 0, label .. ": roster empty")
	Harness.eq(count(books.health.entries), 0, label .. ": health records")
	Harness.eq(count(books.weapons), 0, label .. ": weapon records")
	Harness.eq(count(books.ledger._state), 0, label .. ": xp records")
	Harness.eq(count(books.slides._entries), 0, label .. ": slide records")
end

local function shoot(rig: Rig, victim: string, killer: string, amount: number?): any
	return rig.router:apply({
		matchId = rig.ctx:getMatchId(),
		targetId = victim,
		amount = amount or Config.Weapons.Firearm.damage,
		cause = "bullet",
		sourceId = killer,
	})
end

Harness.test("registry clear tells everyone who left, once each, in order", function()
	local rig, ids = Matches.humans(3)
	rig.untilPhase("Active")
	local seen: { string } = {}
	rig.registry.Removed:connect(function(p: any)
		table.insert(seen, p.id)
	end)
	rig.registry:clear()
	Harness.eq(#seen, 3)
	Harness.eq(seen[1], ids[1])
	Harness.eq(#rig.registry:list(), 0)
	rig.registry:clear()
	Harness.eq(#seen, 3, "clearing an empty roster says nothing")
end)

Harness.test("run xp forgets a participant", function()
	local ledger = RunXp.new(Config.Xp)
	ledger:reset("p1")
	ledger:award("p1", "containerBreak")
	Harness.truthy(ledger:get("p1"))
	ledger:forget("p1")
	Harness.eq(ledger:get("p1"), nil)
	ledger:forget("p1") -- twice is fine
end)

Harness.test("40 matches in a row: every book is empty after each reset", function()
	local rig, ids = Matches.humans(4)
	local books = attach(rig)
	local listeners = rig.registry.Removed:listenerCount()
	for round = 1, 40 do
		rig.untilPhase("Active", 60)
		Harness.eq(count(books.health.entries), 4, "everyone has health")
		local victor = ids[(round % 4) + 1]
		for _, id in ids do
			if id ~= victor then
				shoot(rig, id, victor, 1000)
			end
		end
		rig.untilPhase("Results", 30)
		-- Every fifth match somebody walks out after it and comes straight back in.
		if round % 5 == 0 then
			local leaver = ids[1]
			rig.ctl.removeHuman(leaver)
			rig.ctl.addHuman({ UserId = 1 }, 1, "Player1")
		end
		for _, id in ids do
			rig.ctl.setReady(id, true)
		end
		rig.untilPhase("Waiting", 30)
		assertEmpty(rig, books, `round {round}`)
		Harness.eq(rig.registry.Removed:listenerCount(), listeners, "no listener piles up")
	end
end)

Harness.test("a late shot after the match ended changes nothing", function()
	local rig, ids = Matches.humans(2)
	local books = attach(rig)
	rig.untilPhase("Active")
	shoot(rig, ids[1], ids[2], 1000)
	rig.step(0.5)
	Harness.eq(rig.ctx:getPhase(), "Finished")
	local before = books.health:get(ids[2])
	local late = shoot(rig, ids[2], ids[1], 5)
	Harness.eq(late.applied, false)
	Harness.eq(books.health:get(ids[2]), before, "no health change after the end")
	-- A reload that was running when the match ended must not finish, and the gun stays shut.
	local w = books.weapons[ids[2]]
	Harness.eq(
		w:tryFire(rig.now(), { fireInterval = 0.1, magazine = 12, reloadSeconds = 1 }).ok,
		false
	)
	Harness.eq(
		w:startReload(rig.now(), { fireInterval = 0.1, magazine = 12, reloadSeconds = 1 }),
		false
	)
end)

Harness.test("match reset while effects are live: cooldowns, xp and weapons start clean", function()
	local rig, ids = Matches.humans(2)
	local books = attach(rig)
	rig.untilPhase("Active")
	books.slides:commit(ids[1], rig.now(), 0.25, 5)
	books.slideOwners[ids[1]] = true
	books.ledger:award(ids[1], "containerBreak")
	books.weapons[ids[1]]:startReload(
		rig.now(),
		{ fireInterval = 0.1, magazine = 12, reloadSeconds = 5 }
	)
	shoot(rig, ids[2], ids[1], 1000)
	rig.untilPhase("Waiting", 60)
	assertEmpty(rig, books, "after reset")
	-- Next match: a fresh start.
	rig.ctl.setReady(ids[1], true)
	rig.ctl.setReady(ids[2], true)
	rig.untilPhase("Active", 60)
	Harness.eq(books.slides:isReady(ids[1], rig.now()), true, "no old slide cooldown")
	Harness.eq(books.ledger:get(ids[1]).totalXp, 0, "no old xp")
	Harness.eq(books.weapons[ids[1]]:canFire(rig.now()), true, "fresh gun")
	Harness.eq(books.health:get(ids[1]), Config.Health.max)
end)

Harness.test("last two fall in the same moment: one draw, one reward each, no leftovers", function()
	local rig, ids = Matches.humans(2)
	local books = attach(rig)
	rig.untilPhase("Active")
	shoot(rig, ids[1], ids[2], 1000)
	shoot(rig, ids[2], ids[1], 1000)
	Harness.eq(rig.ctx:getPhase(), "Finished")
	local res = rig.ctl.getResult() :: any
	Harness.eq(res.outcome, "draw")
	rig.untilPhase("Waiting", 60)
	assertEmpty(rig, books, "draw")
	Harness.eq(#rig.rewards, 2, "paid once each")
end)

Harness.test("a player leaves during the countdown: no records, countdown can still run", function()
	local rig, ids = Matches.humans(3)
	local books = attach(rig)
	rig.untilPhase("Countdown", 30)
	rig.ctl.removeHuman(ids[3])
	rig.untilPhase("Active", 60)
	Harness.eq(count(books.health.entries), 2)
	Harness.eq(books.health:has(ids[3]), false)
	rig.untilPhase("Active")
end)

Harness.test(
	"the last player leaves during the countdown: back to waiting, nothing enrolled",
	function()
		local rig, ids = Matches.humans(1)
		local books = attach(rig)
		rig.ctl.requestBots(3)
		rig.untilPhase("Countdown", 30)
		rig.ctl.removeHuman(ids[1])
		rig.step(0.3)
		Harness.eq(rig.ctx:getPhase(), "Waiting")
		assertEmpty(rig, books, "aborted countdown")
	end
)

Harness.test("everyone leaves during spawn: clean reset, nothing left", function()
	local rig, ids = Matches.humans(2)
	local books = attach(rig)
	rig.ctl.requestBots(2)
	rig.untilPhase("Spawning", 30)
	for _, id in ids do
		rig.ctl.removeHuman(id)
	end
	rig.untilPhase("Waiting", 60)
	assertEmpty(rig, books, "spawn abort")
	Harness.eq(rig.ctx:getPhase(), "Waiting")
end)

Harness.test("the final human leaves mid-fight with bots still alive: reset, no records", function()
	local rig, ids = Matches.humans(1)
	local books = attach(rig)
	rig.ctl.requestBots(3)
	rig.untilPhase("Active", 60)
	Harness.eq(count(books.health.entries), 4)
	rig.ctl.removeHuman(ids[1])
	rig.step(0.2)
	rig.untilPhase("Waiting", 60)
	assertEmpty(rig, books, "last human left")
end)

Harness.test("asking for the reward again and again pays once", function()
	local rig, ids = Matches.humans(2)
	attach(rig)
	rig.untilPhase("Active")
	local matchId = rig.ctx:getMatchId()
	shoot(rig, ids[2], ids[1], 1000)
	rig.untilPhase("Results", 10)
	local paid = 0
	for _ = 1, 25 do
		if rig.ctl.claimResults(ids[1], matchId) then
			paid += 1
		end
	end
	Harness.eq(paid, 1)
	rig.untilPhase("Waiting", 60)
	local total = 0
	for _, r in rig.rewards do
		if r.id == ids[1] then
			total += 1
		end
	end
	Harness.eq(total, 1, "the reset does not pay it a second time")
	Harness.eq(rig.ctl.claimResults(ids[1], matchId), false, "late claim after reset")
end)

Harness.test("the damage door forgets eliminations from old matches", function()
	local rig, ids = Matches.humans(2)
	attach(rig)
	for _ = 1, 10 do
		rig.untilPhase("Active", 60)
		shoot(rig, ids[2], ids[1], 1000)
		rig.untilPhase("Results", 10)
		rig.ctl.setReady(ids[1], true)
		rig.ctl.setReady(ids[2], true)
		rig.untilPhase("Waiting", 30)
		Harness.truthy(
			count(rig.router._eliminated) <= 2,
			"at most this match's eliminations are kept"
		)
		rig.untilPhase("Countdown", 30)
	end
end)
