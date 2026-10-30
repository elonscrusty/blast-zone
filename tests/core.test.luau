--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local Ids = require("../src/shared/Ids")
local Signal = require("../src/shared/Signal")
local MatchPhase = require("../src/shared/MatchPhase")
local MatchContext = require("../src/shared/MatchContext")
local ParticipantRegistry = require("../src/shared/ParticipantRegistry")
local DamageRouter = require("../src/shared/DamageRouter")
local RunXp = require("../src/shared/RunXp")
local StatBook = require("../src/shared/StatBook")
local Boot = require("../src/shared/Boot")

local t = 0
local function clock(): number
	return t
end

Harness.test("ids say what they are", function()
	Harness.eq(Ids.player(123), "p123")
	Harness.eq(Ids.bot(2), "b2")
	Harness.eq(Ids.isBot("b2"), true)
	Harness.eq(Ids.isBot("p2"), false)
	Harness.eq(Ids.userIdOf("p123"), 123)
	Harness.eq(Ids.userIdOf("b2"), nil)
	Harness.eq(Ids.isValid("x1"), false)
	Harness.eq(Ids.isValid(5), false)
end)

Harness.test("signal: disconnect works and a bad listener does not stop the rest", function()
	local s = Signal.new()
	local hits = 0
	local c = s:connect(function()
		hits += 1
	end)
	s:connect(function()
		error("boom")
	end)
	s:connect(function()
		hits += 10
	end)
	s:fire()
	Harness.eq(hits, 11)
	c:disconnect()
	s:fire()
	Harness.eq(hits, 21)
end)

Harness.test("phases: only legal moves; anything can abort to Resetting", function()
	Harness.eq(MatchPhase.canTransition("Waiting", "Countdown"), true)
	Harness.eq(MatchPhase.canTransition("Waiting", "Active"), false)
	Harness.eq(MatchPhase.canTransition("Countdown", "Waiting"), true)
	Harness.eq(MatchPhase.canTransition("Active", "Resetting"), true)
	Harness.eq(MatchPhase.canTransition("Results", "Active"), false)
	Harness.eq(MatchPhase.canTransition("Nope", "Waiting"), false)
	Harness.eq(MatchPhase.isCombat("FinalPressure"), true)
	Harness.eq(MatchPhase.allowsDamage("Spawning"), false)
	Harness.eq(MatchPhase.allowsDamage("Finished"), false)
	for _, p in MatchPhase.ORDER do
		Harness.eq(MatchPhase.isValid(p), true)
	end
end)

Harness.test("match context: matchId grows, illegal phase moves change nothing", function()
	local ctx = MatchContext.new(clock)
	local seen = {}
	ctx.PhaseChanged:connect(function(p: string, old: string, id: number)
		table.insert(seen, `{old}>{p}@{id}`)
	end)
	Harness.eq(ctx:setPhase("Active"), false)
	Harness.eq(ctx:getPhase(), "Waiting")
	local id = ctx:beginMatch()
	Harness.eq(id, 1)
	Harness.eq(ctx:setPhase("Countdown", 5), true)
	Harness.eq(ctx:getPhaseEndsAt(), t + 5)
	Harness.eq(seen[1], "Waiting>Countdown@1")
	Harness.eq(ctx:isCurrent(1), true)
	ctx:beginMatch()
	Harness.eq(ctx:isCurrent(1), false, "old match is stale")
end)

Harness.test("registry: enroll once, eliminate once, alive counts, clear", function()
	local reg = ParticipantRegistry.new(clock)
	Harness.truthy(reg:enrollPlayer(1, "playerA", 10, "A"))
	Harness.eq(reg:enrollPlayer(1, "playerA", 10, "A"), nil, "no double enroll")
	Harness.truthy(reg:enrollBot(1, 1, "[BOT] Volt"))
	Harness.eq(reg:aliveCount(), 2)
	Harness.eq(reg:ofPlayer("playerA").id, "p10")
	local elims = 0
	reg.Eliminated:connect(function()
		elims += 1
	end)
	Harness.eq(reg:markEliminated("b1"), true)
	Harness.eq(reg:markEliminated("b1"), false)
	Harness.eq(elims, 1)
	Harness.eq(reg:aliveCount(), 1)
	Harness.eq(reg:list()[1].id, "p10", "enrollment order kept")
	reg:remove("p10")
	Harness.eq(reg:get("p10"), nil)
	reg:clear()
	Harness.eq(#reg:list(), 0)
end)

local function newDamage()
	local ctx = MatchContext.new(clock)
	local reg = ParticipantRegistry.new(clock)
	local router = DamageRouter.new({
		getMatchId = function()
			return ctx:getMatchId()
		end,
		allowsDamage = function()
			return MatchPhase.allowsDamage(ctx:getPhase())
		end,
		isAlive = function(id: string)
			return reg:isAlive(id)
		end,
		markEliminated = function(id: string)
			return reg:markEliminated(id)
		end,
		clock = clock,
	})
	local hp: { [string]: number } = {}
	router:bind(function(req)
		local before = hp[req.targetId] or 100
		local after = math.max(0, before - req.amount)
		hp[req.targetId] = after
		return {
			applied = true,
			dealt = before - after,
			remaining = after,
			eliminated = after <= 0,
		}
	end)
	local id = ctx:beginMatch()
	reg:enrollBot(id, 1, "a")
	reg:enrollBot(id, 2, "b")
	return ctx, reg, router, id
end

local function toActive(ctx: any)
	ctx:setPhase("Countdown")
	ctx:setPhase("Spawning")
	ctx:setPhase("Active")
end

Harness.test("damage: refused before combat and for a stale match", function()
	local ctx, _, router, id = newDamage()
	local r = router:apply({ matchId = id, targetId = "b1", amount = 10, cause = "bullet" })
	Harness.eq(r.reason, "not-combat")
	toActive(ctx)
	Harness.eq(
		router:apply({ matchId = id - 1, targetId = "b1", amount = 10, cause = "bullet" }).reason,
		"stale-match"
	)
	Harness.eq(
		router:apply({ matchId = id, targetId = "b1", amount = 10, cause = "bullet" }).applied,
		true
	)
end)

Harness.test("damage: bad amounts and unknown targets are refused", function()
	local ctx, _, router, id = newDamage()
	toActive(ctx)
	for _, bad in { 0, -5, 0 / 0, math.huge } do
		Harness.eq(
			router:apply({ matchId = id, targetId = "b1", amount = bad, cause = "bullet" }).reason,
			"bad-amount"
		)
	end
	Harness.eq(
		router:apply({ matchId = id, targetId = "b9", amount = 5, cause = "bullet" }).reason,
		"no-target"
	)
end)

Harness.test("damage: one elimination event only, killer kept, late hits dropped", function()
	local ctx, reg, router, id = newDamage()
	toActive(ctx)
	local kills = {}
	router.Eliminated:connect(function(e)
		table.insert(kills, e)
	end)
	router:apply({
		matchId = id,
		targetId = "b1",
		amount = 60,
		cause = "bullet",
		sourceId = "b2",
		weaponId = "volt_pistol",
	})
	router:apply({ matchId = id, targetId = "b1", amount = 60, cause = "bullet", sourceId = "b2" })
	local second = router:apply({
		matchId = id,
		targetId = "b1",
		amount = 60,
		cause = "bullet",
		sourceId = "b2",
	})
	Harness.eq(second.reason, "no-target", "dead target takes no more damage")
	Harness.eq(#kills, 1)
	Harness.eq(kills[1].killerId, "b2")
	Harness.eq(kills[1].victimId, "b1")
	Harness.eq(reg:isAlive("b1"), false)
	ctx:setPhase("Finished")
	Harness.eq(
		router:apply({ matchId = id, targetId = "b2", amount = 5, cause = "zone" }).reason,
		"not-combat"
	)
end)

Harness.test("damage: no backend or a crashing backend is refused, not thrown", function()
	local ctx, _, router, id = newDamage()
	toActive(ctx)
	router:bind(function()
		error("bug")
	end)
	Harness.eq(
		router:apply({ matchId = id, targetId = "b1", amount = 5, cause = "zone" }).reason,
		"backend-error"
	)
end)

Harness.test("run xp: levels, carry-over, offers, cap, unknown reasons", function()
	local xp = RunXp.new(Config.Xp)
	Harness.eq(xp:award("b1", "orbPickup"), nil, "unknown id ignored")
	xp:reset("b1")
	local levels = 0
	xp.LevelUp:connect(function()
		levels += 1
	end)
	local st = xp:award("b1", "elimination") -- 30 xp: level 2 (cost 20), 10 left
	Harness.eq(st.level, 2)
	Harness.eq(st.xp, 10)
	Harness.eq(st.pendingOffers, 1)
	Harness.eq(st.xpToNext, Config.Xp.levelCosts[2])
	Harness.eq(levels, 1)
	Harness.eq(xp:takeOffer("b1"), true)
	Harness.eq(xp:takeOffer("b1"), false)
	Harness.eq(xp:costForLevel(4), Config.Xp.levelCosts[3] + Config.Xp.costStepAfter)
	Harness.truthy(not pcall(function()
		xp:award("b1", "free-money")
	end))
	for _ = 1, 200 do
		xp:award("b1", "elimination")
	end
	Harness.eq(xp:get("b1").offersGranted, Config.Xp.maxOffersPerMatch)
	xp:reset("b1")
	Harness.eq(xp:get("b1").level, 1)
end)

Harness.test(
	"stat book: base sheets are fresh copies; provider overrides; invalidate signals",
	function()
		local book = StatBook.new(Config)
		local a = book:get("b1")
		a.moveSpeed = 999
		Harness.eq(book:get("b1").moveSpeed, Config.Movement.walkSpeed)
		Harness.eq(book:get("b1").firearm.damage, 10)
		book:setProvider(function(id: string)
			if id == "b1" then
				local s = StatBook.base(Config)
				s.firearm.reloadSeconds = 0.6
				return s
			end
			return nil
		end)
		Harness.near(book:get("b1").firearm.reloadSeconds, 0.6)
		Harness.near(book:get("b2").firearm.reloadSeconds, 1.2)
		local changed = ""
		book.Changed:connect(function(id: string)
			changed = id
		end)
		book:invalidate("b1")
		Harness.eq(changed, "b1")
	end
)

Harness.test("boot: systems found by name, sorted by order then name", function()
	Harness.eq(Boot.isSystemName("MovementSystem"), true)
	Harness.eq(Boot.isSystemName("System"), false)
	Harness.eq(Boot.isSystemName("Systematic"), false)
	local sorted = Boot.sort({
		{ name = "ZSystem" },
		{ name = "BSystem", order = 50 },
		{ name = "ASystem" },
	})
	Harness.eq(sorted[1].name, "BSystem")
	Harness.eq(sorted[2].name, "ASystem")
	Harness.eq(sorted[3].name, "ZSystem")
end)
