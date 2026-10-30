--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local DailyDefs = require("../src/shared/Daily/DailyDefs")
local Guard = require("../src/shared/Guard")
local MissionDefs = require("../src/shared/Missions/MissionDefs")
local MissionMemoryStore = require("../src/shared/Missions/MissionMemoryStore")
local MissionRules = require("../src/shared/Missions/MissionRules")
local MissionService = require("../src/shared/Missions/MissionService")
local MissionText = require("../src/shared/Missions/MissionText")
local Receipts = require("../src/shared/Profile/Receipts")
local RemoteDefs = require("../src/shared/RemoteDefs")
local Types = require("../src/shared/Types")

local CFG = Config.Missions
local DAY = 86400
-- Day 20752 was a Monday (26 Oct 2026). Weeks start there.
local MONDAY = 20752
local T0 = MONDAY * DAY + 5 * 3600 -- Monday 05:00 UTC
local WEEK = MissionRules.weekOf(T0, 0)
local CAP = Config.Progression.maxMatchGrant

-- ===== the lists =====

Harness.test("missions: ids are saveable and unique, goals and kinds are valid", function()
	local seen: { [string]: boolean } = {}
	for _, def in MissionDefs.weekly do
		Harness.truthy(string.match(def.id, "^[a-z0-9_]+$") ~= nil, def.id)
		Harness.truthy(not seen[def.id], "duplicate " .. def.id)
		seen[def.id] = true
		Harness.truthy(def.goal >= 1 and def.goal == math.floor(def.goal), def.id .. " goal")
		Harness.truthy(table.find(DailyDefs.kinds, def.kind) ~= nil, def.id .. " kind")
		Harness.truthy(CFG.weeklyRewards[def.tier] ~= nil, def.id .. " tier reward")
	end
	for _, def in MissionDefs.awards do
		Harness.truthy(string.match(def.id, "^[a-z0-9_]+$") ~= nil, def.id)
		Harness.truthy(not seen[def.id], "duplicate " .. def.id)
		seen[def.id] = true
		Harness.truthy(def.goal >= 1 and def.goal == math.floor(def.goal), def.id .. " goal")
		Harness.truthy(table.find(DailyDefs.kinds, def.kind) ~= nil, def.id .. " kind")
		Harness.truthy(def.reward >= 1, def.id .. " reward")
		Harness.truthy(
			Receipts.isValidKey(MissionRules.receiptKey("award", 0, 0, def.id)),
			def.id .. " key"
		)
	end
	for _, tier in MissionDefs.tiers do
		Harness.truthy(#MissionDefs.weeklyOfTier(tier) >= 3, tier .. " needs 3+ to avoid repeats")
	end
end)

Harness.test(
	"missions: every pay stays under the coin grant cap, and weekly beats daily",
	function()
		for _, n in CFG.weeklyRewards do
			Harness.truthy(n >= 1 and n <= CAP, "weekly reward")
		end
		Harness.truthy(CFG.weeklyBonus >= 1 and CFG.weeklyBonus <= CAP, "bonus")
		Harness.truthy(#CFG.loginRewards >= 2, "a row of days")
		for _, n in CFG.loginRewards do
			Harness.truthy(n >= 1 and n <= CAP, "login reward")
		end
		for _, def in MissionDefs.awards do
			Harness.truthy(def.reward <= CAP, def.id)
		end
		for tier, n in CFG.weeklyRewards do
			Harness.truthy(
				n > Config.Daily.rewards[tier],
				tier .. " weekly should pay more than daily"
			)
		end
	end
)

Harness.test("missions: awards grow with the goal inside one kind", function()
	local lastGoal: { [string]: number } = {}
	local lastReward: { [string]: number } = {}
	for _, def in MissionDefs.awards do
		Harness.truthy(def.goal > (lastGoal[def.kind] or 0), def.id .. " goal order")
		Harness.truthy(def.reward >= (lastReward[def.kind] or 0), def.id .. " reward order")
		lastGoal[def.kind] = def.goal
		lastReward[def.kind] = def.reward
	end
end)

Harness.test("missions: receipt keys fit the profile rules and never clash", function()
	local keys = {
		MissionRules.receiptKey("week", 2900, 20752, "w_elims_12"),
		MissionRules.receiptKey("bonus", 2900, 20752, nil),
		MissionRules.receiptKey("award", 2900, 20752, "a_elims_10"),
		MissionRules.receiptKey("login", 2900, 20752, nil),
	}
	local seen: { [string]: boolean } = {}
	for _, key in keys do
		Harness.truthy(Receipts.isValidKey(key), key)
		Harness.truthy(not seen[key], "clash " .. key)
		seen[key] = true
		Harness.truthy(string.sub(key, 1, 2) ~= "d:", "daily keys start with d:")
	end
end)

-- ===== weeks =====

Harness.test("missions: a week runs Monday to Sunday and the countdown hits that moment", function()
	Harness.eq(MissionRules.weekOf(MONDAY * DAY, 0), MissionRules.weekOf(T0, 0))
	Harness.eq(
		MissionRules.weekOf((MONDAY + 7) * DAY - 1, 0),
		WEEK,
		"Sunday night is still this week"
	)
	Harness.eq(MissionRules.weekOf((MONDAY + 7) * DAY, 0), WEEK + 1, "next Monday is a new week")
	Harness.eq(MissionRules.weekOf(MONDAY * DAY - 1, 0), WEEK - 1, "Sunday before is the old week")
	Harness.eq(
		MissionRules.weekOf(MONDAY * DAY + 3 * 3600, 4),
		WEEK - 1,
		"before 04:00 Monday is still last week"
	)
	Harness.eq(MissionRules.weekSecondsLeft(T0, 0), 7 * DAY - 5 * 3600)
	Harness.eq(MissionRules.weekSecondsLeft((MONDAY + 7) * DAY - 1, 0), 1)
	Harness.eq(MissionRules.weekSecondsLeft(MONDAY * DAY, 0), 7 * DAY)
	Harness.eq(
		MissionRules.weekSecondsLeft(MONDAY * DAY + 3600, 4),
		3 * 3600,
		"reset hour 4: last week ends at 04:00 Monday"
	)
end)

Harness.test(
	"missions: each week has one easy, one medium, one hard, all different kinds",
	function()
		local sets: { [string]: boolean } = {}
		for week = WEEK - 50, WEEK + 150 do
			local picks = MissionRules.pick(week)
			Harness.eq(#picks, 3, "three a week")
			local kinds: { [string]: boolean } = {}
			local key = ""
			for i, def in picks do
				Harness.eq(def.tier, MissionDefs.tiers[i], "tier order")
				Harness.truthy(not kinds[def.kind], "repeat kind in week " .. week)
				kinds[def.kind] = true
				Harness.eq(MissionRules.pick(week)[i].id, def.id, "same answer twice")
				key ..= def.id .. ","
			end
			sets[key] = true
		end
		local count = 0
		for _ in sets do
			count += 1
		end
		Harness.truthy(count >= 8, "weeks should not all look alike, got " .. count)
	end
)

-- ===== saved table =====

Harness.test("missions: fill repairs garbage and keeps good numbers", function()
	local s = MissionRules.fill({
		week = "x",
		progress = { a = 3, b = -1, c = 1.5, d = "no", [5] = 2 },
		claimed = { a = true, b = false, c = "yes" },
		bonus = "true",
		life = { elims = 12, wins = 0 / 0 },
		awards = { a_wins_1 = true },
		loginDay = {},
		loginCount = -4,
	})
	Harness.eq(s.week, -1)
	Harness.eq(s.progress.a, 3)
	Harness.eq(s.progress.b, nil)
	Harness.eq(s.progress.c, nil)
	Harness.eq(s.progress.d, nil)
	Harness.eq(s.claimed.a, true)
	Harness.eq(s.claimed.b, nil)
	Harness.eq(s.claimed.c, nil)
	Harness.eq(s.bonus, false)
	Harness.eq(s.life.elims, 12)
	Harness.eq(s.life.wins, nil)
	Harness.eq(s.awards.a_wins_1, true)
	Harness.eq(s.loginDay, -1)
	Harness.eq(s.loginCount, 0)
	local empty = MissionRules.fill(nil)
	Harness.eq(empty.week, -1)
	Harness.eq(empty.loginCount, 0)
end)

-- ===== counting =====

local function weekly(week: number, tier: string): MissionDefs.Weekly
	for _, def in MissionRules.pick(week) do
		if def.tier == tier then
			return def
		end
	end
	error("no " .. tier)
end

Harness.test("missions: progress caps at the goal and says 'ready' once", function()
	local s = MissionRules.new(WEEK)
	local def = weekly(WEEK, "easy")
	local readyCount = 0
	for _ = 1, def.goal + 5 do
		for _, id in MissionRules.add(s, WEEK, def.kind, 1) do
			if id == def.id then
				readyCount += 1
			end
		end
	end
	Harness.eq(readyCount, 1, "ready only the moment it is reached")
	Harness.eq(s.progress[def.id], def.goal, "capped")
	Harness.eq(s.life[def.kind], def.goal + 5, "life keeps counting")
end)

Harness.test("missions: bad amounts count nothing", function()
	local s = MissionRules.new(WEEK)
	for _, bad in { 0, -3, 1.5, 0 / 0, math.huge, 1e12 } do
		MissionRules.add(s, WEEK, "elims", bad)
	end
	Harness.eq(s.life.elims, nil)
	Harness.eq(next(s.progress), nil)
end)

Harness.test("missions: a kind that is not on this week still counts for awards", function()
	local s = MissionRules.new(WEEK)
	local onWeek: { [string]: boolean } = {}
	for _, def in MissionRules.pick(WEEK) do
		onWeek[def.kind] = true
	end
	local other: string? = nil
	for _, kind in DailyDefs.kinds do
		if not onWeek[kind] then
			other = kind
		end
	end
	Harness.truthy(other ~= nil)
	MissionRules.add(s, WEEK, other :: string, 3)
	Harness.eq(s.life[other :: string], 3)
	Harness.eq(next(s.progress), nil, "no weekly progress")
end)

Harness.test("missions: an award becomes ready when the lifetime total reaches its goal", function()
	local s = MissionRules.new(WEEK)
	local got: { string } = {}
	for _ = 1, 10 do
		for _, id in MissionRules.add(s, WEEK, "elims", 1) do
			table.insert(got, id)
		end
	end
	Harness.truthy(table.find(got, "a_elims_10") ~= nil, "10 eliminations opens the first award")
	Harness.eq(table.find(got, "a_elims_50"), nil)
	-- a second call at the same total does not announce it again
	Harness.eq(#MissionRules.add(s, WEEK, "elims", 0), 0)
end)

Harness.test(
	"missions: a new week wipes weekly progress but keeps awards, life and login",
	function()
		local s = MissionRules.new(WEEK)
		local def = weekly(WEEK, "easy")
		MissionRules.add(s, WEEK, def.kind, def.goal)
		s.claimed[def.id] = true
		s.bonus = true
		s.awards.a_wins_1 = true
		s.loginCount = 4
		s.loginDay = 20750
		Harness.truthy(MissionRules.roll(s, WEEK + 1))
		Harness.eq(next(s.progress), nil)
		Harness.eq(next(s.claimed), nil)
		Harness.eq(s.bonus, false)
		Harness.eq(s.life[def.kind], def.goal)
		Harness.eq(s.awards.a_wins_1, true)
		Harness.eq(s.loginCount, 4)
		Harness.eq(s.loginDay, 20750)
		Harness.eq(MissionRules.roll(s, WEEK + 1), false, "same week twice changes nothing")
	end
)

-- ===== claiming =====

local function finish(s: MissionRules.State, week: number, def: MissionDefs.Weekly)
	MissionRules.add(s, week, def.kind, def.goal)
end

Harness.test("missions: a weekly claim needs the goal, the right week and a real id", function()
	local s = MissionRules.new(WEEK)
	local def = weekly(WEEK, "medium")
	local amount, why = MissionRules.claimInfo(s, WEEK, MONDAY, "week", def.id, CFG)
	Harness.eq(amount, nil)
	Harness.eq(why, "notDone")
	finish(s, WEEK, def)
	amount = MissionRules.claimInfo(s, WEEK, MONDAY, "week", def.id, CFG)
	Harness.eq(amount, CFG.weeklyRewards.medium)
	local _, oldWhy = MissionRules.claimInfo(s, WEEK + 1, MONDAY + 7, "week", def.id, CFG)
	Harness.eq(oldWhy, "oldWeek")
	local _, unknownWhy = MissionRules.claimInfo(s, WEEK, MONDAY, "week", "w_nope", CFG)
	Harness.eq(unknownWhy, "unknown")
	local _, nilWhy = MissionRules.claimInfo(s, WEEK, MONDAY, "week", nil, CFG)
	Harness.eq(nilWhy, "unknown")
	-- a weekly mission from another week's pick is refused even when its id is real
	local elsewhere: MissionDefs.Weekly? = nil
	for _, other in MissionDefs.weekly do
		local onWeek = false
		for _, p in MissionRules.pick(WEEK) do
			onWeek = onWeek or p.id == other.id
		end
		if not onWeek then
			elsewhere = other
		end
	end
	local _, offWhy =
		MissionRules.claimInfo(s, WEEK, MONDAY, "week", (elsewhere :: MissionDefs.Weekly).id, CFG)
	Harness.eq(offWhy, "unknown")
	Harness.eq(MissionRules.markClaimed(s, WEEK, MONDAY, "week", def.id, CFG), true)
	Harness.eq(MissionRules.markClaimed(s, WEEK, MONDAY, "week", def.id, CFG), false, "twice")
	local _, againWhy = MissionRules.claimInfo(s, WEEK, MONDAY, "week", def.id, CFG)
	Harness.eq(againWhy, "claimed")
end)

Harness.test("missions: the week bonus needs all three claimed, then pays once", function()
	local s = MissionRules.new(WEEK)
	local _, why = MissionRules.claimInfo(s, WEEK, MONDAY, "bonus", nil, CFG)
	Harness.eq(why, "notDone")
	for _, def in MissionRules.pick(WEEK) do
		finish(s, WEEK, def)
		Harness.eq(MissionRules.markClaimed(s, WEEK, MONDAY, "week", def.id, CFG), true)
		if def.tier ~= "hard" then
			local _, still = MissionRules.claimInfo(s, WEEK, MONDAY, "bonus", nil, CFG)
			Harness.eq(still, "notDone", "not before the third")
		end
	end
	Harness.eq(MissionRules.claimInfo(s, WEEK, MONDAY, "bonus", nil, CFG), CFG.weeklyBonus)
	Harness.eq(MissionRules.markClaimed(s, WEEK, MONDAY, "bonus", nil, CFG), true)
	Harness.eq(MissionRules.markClaimed(s, WEEK, MONDAY, "bonus", nil, CFG), false)
end)

Harness.test("missions: an award is claimed once and never expires", function()
	local s = MissionRules.new(WEEK)
	local _, why = MissionRules.claimInfo(s, WEEK, MONDAY, "award", "a_wins_1", CFG)
	Harness.eq(why, "notDone")
	MissionRules.add(s, WEEK, "wins", 1)
	local def = MissionDefs.getAward("a_wins_1") :: MissionDefs.Award
	Harness.eq(MissionRules.claimInfo(s, WEEK, MONDAY, "award", "a_wins_1", CFG), def.reward)
	-- still claimable weeks later
	MissionRules.roll(s, WEEK + 9)
	Harness.eq(
		MissionRules.claimInfo(s, WEEK + 9, MONDAY + 63, "award", "a_wins_1", CFG),
		def.reward
	)
	Harness.eq(MissionRules.markClaimed(s, WEEK + 9, MONDAY + 63, "award", "a_wins_1", CFG), true)
	local _, again = MissionRules.claimInfo(s, WEEK + 9, MONDAY + 63, "award", "a_wins_1", CFG)
	Harness.eq(again, "claimed")
	local _, nope = MissionRules.claimInfo(s, WEEK + 9, MONDAY + 63, "award", "a_nope", CFG)
	Harness.eq(nope, "unknown")
end)

Harness.test(
	"missions: login days go in order, one a day, and a missed day costs nothing",
	function()
		local s = MissionRules.new(WEEK)
		local n = #CFG.loginRewards
		local day = MONDAY
		for step = 1, n * 2 do
			Harness.eq(MissionRules.loginStep(s, CFG), (step - 1) % n + 1, "step " .. step)
			local amount = MissionRules.claimInfo(s, WEEK, day, "login", nil, CFG)
			Harness.eq(amount, CFG.loginRewards[(step - 1) % n + 1], "pay " .. step)
			Harness.eq(MissionRules.markClaimed(s, WEEK, day, "login", nil, CFG), true)
			-- same day again: refused
			local _, why = MissionRules.claimInfo(s, WEEK, day, "login", nil, CFG)
			Harness.eq(why, "claimed")
			Harness.eq(MissionRules.markClaimed(s, WEEK, day, "login", nil, CFG), false)
			day += if step % 3 == 0 then 4 else 1 -- some days missed: the row still goes on
		end
		Harness.eq(s.loginCount, n * 2)
	end
)

-- ===== what the player sees =====

Harness.test("missions: the view shows ready, claimed and the login row", function()
	local s = MissionRules.new(WEEK)
	local easy = weekly(WEEK, "easy")
	finish(s, WEEK, easy)
	local rows, bonus, awards, login = MissionRules.view(s, WEEK, MONDAY, CFG)
	Harness.eq(#rows, 3)
	Harness.eq(rows[1].id, easy.id)
	Harness.eq(rows[1].ready, true)
	Harness.eq(rows[1].claimed, false)
	Harness.eq(rows[1].reward, CFG.weeklyRewards.easy)
	Harness.eq(rows[2].ready, false)
	Harness.eq(bonus.have, 0)
	Harness.eq(bonus.need, 3)
	Harness.eq(bonus.ready, false)
	Harness.eq(#awards, #MissionDefs.awards)
	Harness.eq(login.canClaim, true)
	Harness.eq(login.next, 1)
	Harness.eq(#login.rewards, #CFG.loginRewards)

	local state: Types.MissionsState = {
		status = "ready",
		weekSecondsLeft = 100,
		weekly = rows,
		bonus = bonus,
		awards = awards,
		login = login,
	}
	-- one mission, today's login, and any award the same count happened to open
	local awardsReady = 0
	for _, award in awards do
		if award.ready then
			awardsReady += 1
		end
	end
	Harness.eq(MissionRules.readyCount(state), 2 + awardsReady)

	-- a profile that is not loaded: nothing can be claimed
	local nrows, nbonus, nawards, nlogin = MissionRules.view(nil, WEEK, MONDAY, CFG)
	Harness.eq(nrows[1].progress, 0)
	Harness.eq(nbonus.ready, false)
	Harness.eq(nawards[1].ready, false)
	Harness.eq(nlogin.canClaim, false)
end)

Harness.test("missions: words are short and handle edges", function()
	Harness.eq(MissionText.goal("elims", 12), "Get 12 eliminations")
	Harness.eq(MissionText.weekTimer(3 * DAY + 5 * 3600), "New in 3d 5h")
	Harness.eq(MissionText.weekTimer(2 * 3600 + 120), "New in 2h 2m")
	Harness.eq(MissionText.weekTimer(0), "New in 1m")
	Harness.eq(MissionText.weekTimer(-50), "New in 1m")
	Harness.eq(MissionText.weekTimer(59), "New in 1m")
	Harness.eq(MissionText.loginTimer(26 * 3600), "Next in 26h 0m")
	Harness.eq(MissionText.day(3), "Day 3")
	Harness.eq(MissionText.reward(60, "Scrap"), "+60 Scrap")
	Harness.eq(MissionText.claimed("login", 25, "Scrap"), "LOGIN! +25 Scrap")
	Harness.eq(MissionText.claimed("bonus", 100, "Scrap"), "WEEK BONUS! +100 Scrap")
	Harness.eq(MissionText.claimed("week:w_elims_12", 60, "Scrap"), "CLAIMED! +60 Scrap")
end)

-- ===== service (rules + store + pay) =====

local function rig(startTime: number)
	local clock = startTime
	local store = MissionMemoryStore.new()
	local wallet: { [any]: number } = {}
	local keys: { [string]: boolean } = {}
	local sent: { Types.MissionsState } = {}
	local payFails = false
	local service = MissionService.new({
		store = store,
		pay = function(player: any, amount: number, key: string): (boolean, string?)
			if payFails then
				return false, "notLoaded"
			end
			if keys[key] then
				return false, "duplicate"
			end
			keys[key] = true
			wallet[player] = (wallet[player] or 0) + amount
			return true, nil
		end,
		send = function(_player: any, state: Types.MissionsState)
			table.insert(sent, state)
		end,
		now = function()
			return clock
		end,
		config = CFG,
		resetHour = 0,
	})
	return {
		service = service,
		store = store,
		wallet = wallet,
		keys = keys,
		sent = sent,
		setTime = function(t: number)
			clock = t
		end,
		setPayFails = function(v: boolean)
			payFails = v
		end,
	}
end

Harness.test("missions service: counting is silent until something can be claimed", function()
	local r = rig(T0)
	local p = {}
	local def = weekly(WEEK, "hard")
	for _ = 1, def.goal - 1 do
		r.service.count(p, def.kind, 1)
	end
	Harness.eq(#r.sent, 0, "no message while only counting")
	r.service.count(p, def.kind, 1)
	Harness.truthy(#r.sent >= 1, "told once it can be claimed")
	local last = r.sent[#r.sent]
	local row = last.weekly[3]
	Harness.eq(row.id, def.id)
	Harness.eq(row.ready, true)
	Harness.eq(r.wallet[p], nil, "counting never pays")
end)

Harness.test(
	"missions service: claim pays once, double taps and replays pay nothing more",
	function()
		local r = rig(T0)
		local p = {}
		local def = weekly(WEEK, "medium")
		r.service.count(p, def.kind, def.goal)
		local ok = r.service.claim(p, "week", def.id)
		Harness.eq(ok, true)
		Harness.eq(r.wallet[p], CFG.weeklyRewards.medium)
		local again, why = r.service.claim(p, "week", def.id)
		Harness.eq(again, false)
		Harness.eq(why, "claimed")
		Harness.eq(r.wallet[p], CFG.weeklyRewards.medium, "still one payment")
		local last = r.sent[#r.sent]
		local shown = nil
		for _, m in last.weekly do
			if m.id == def.id then
				shown = m
			end
		end
		Harness.truthy(shown ~= nil and shown.claimed and not shown.ready, "shown claimed")
		local told = 0
		for _, st in r.sent do
			if st.justClaimed == "week:" .. def.id then
				told += 1
				Harness.eq(st.justAmount, CFG.weeklyRewards.medium)
			end
		end
		Harness.eq(told, 1, "the claim is announced once")
	end
)

Harness.test("missions service: a claim that is not earned is refused and pays nothing", function()
	local r = rig(T0)
	local p = {}
	local def = weekly(WEEK, "easy")
	for _, args in
		{
			{ "week", def.id }, -- not done
			{ "week", "w_nope" },
			{ "week", nil },
			{ "bonus", nil },
			{ "award", "a_elims_1000" },
			{ "award", "../../" },
			{ "wins", "a_wins_1" },
			{ "", nil },
		}
	do
		local ok = r.service.claim(p, args[1] :: string, args[2] :: string?)
		Harness.eq(ok, false, tostring(args[1]) .. " " .. tostring(args[2]))
	end
	Harness.eq(r.wallet[p], nil)
	Harness.eq(next(r.keys), nil)
end)

Harness.test("missions service: a failed payment is not marked, and a later claim works", function()
	local r = rig(T0)
	local p = {}
	local def = weekly(WEEK, "easy")
	r.service.count(p, def.kind, def.goal)
	r.setPayFails(true)
	local ok, why = r.service.claim(p, "week", def.id)
	Harness.eq(ok, false)
	Harness.eq(why, "notLoaded")
	Harness.eq(r.wallet[p], nil)
	Harness.eq(r.sent[#r.sent].weekly[1].ready, true, "still claimable")
	r.setPayFails(false)
	Harness.eq(r.service.claim(p, "week", def.id), true)
	Harness.eq(r.wallet[p], CFG.weeklyRewards.easy)
end)

Harness.test("missions service: paid before but never marked just gets marked", function()
	local r = rig(T0)
	local p = {}
	local def = weekly(WEEK, "easy")
	r.service.count(p, def.kind, def.goal)
	r.keys[MissionRules.receiptKey("week", WEEK, MONDAY, def.id)] = true -- the money went out, the mark was lost
	local ok, why = r.service.claim(p, "week", def.id)
	Harness.eq(ok, false)
	Harness.eq(why, "duplicate")
	Harness.eq(r.wallet[p], nil, "not paid twice")
	Harness.eq(r.sent[#r.sent].weekly[1].claimed, true)
end)

Harness.test("missions service: the whole week, bonus last, and a new week starts clean", function()
	local r = rig(T0)
	local p = {}
	local total = 0
	for _, def in MissionRules.pick(WEEK) do
		r.service.count(p, def.kind, def.goal)
		Harness.eq(r.service.claim(p, "week", def.id), true)
		total += CFG.weeklyRewards[def.tier]
	end
	Harness.eq(r.service.claim(p, "bonus"), true)
	total += CFG.weeklyBonus
	Harness.truthy(r.wallet[p] >= total, "weekly + bonus paid") -- awards are not claimed, so exactly total
	Harness.eq(r.wallet[p], total)
	Harness.eq(r.service.claim(p, "bonus"), false)

	r.setTime(T0 + 7 * DAY)
	r.service.push(p)
	local last = r.sent[#r.sent]
	for _, m in last.weekly do
		Harness.eq(m.progress, 0)
		Harness.eq(m.claimed, false)
	end
	Harness.eq(last.bonus.claimed, false)
	-- last week's mission cannot be claimed in the new week
	local old = MissionRules.pick(WEEK)[1]
	local picksNow = MissionRules.pick(WEEK + 1)
	local stillOn = false
	for _, m in picksNow do
		stillOn = stillOn or m.id == old.id
	end
	if not stillOn then
		Harness.eq(r.service.claim(p, "week", old.id), false)
	end
end)

Harness.test("missions service: login days pay one a day and go round the row", function()
	local r = rig(T0)
	local p = {}
	local n = #CFG.loginRewards
	local total = 0
	for i = 1, n + 1 do
		r.setTime(T0 + (i - 1) * DAY)
		Harness.eq(r.service.claim(p, "login"), true, "day " .. i)
		Harness.eq(r.service.claim(p, "login"), false, "second tap on day " .. i)
		total += CFG.loginRewards[(i - 1) % n + 1]
	end
	Harness.eq(r.wallet[p], total)
	local last = r.sent[#r.sent]
	Harness.eq(last.login.canClaim, false)
	Harness.eq(last.login.count, n + 1)
	Harness.eq(last.login.next, 2)
	Harness.truthy(last.login.secondsLeft > 0 and last.login.secondsLeft <= DAY)
	Harness.eq(last.weekSecondsLeft, MissionRules.weekSecondsLeft(T0 + n * DAY, 0))
end)

Harness.test("missions service: awards count across weeks and pay once", function()
	local r = rig(T0)
	local p = {}
	for i = 0, 3 do
		r.setTime(T0 + i * 7 * DAY)
		r.service.count(p, "elims", 3)
	end
	-- 12 eliminations in all: the first award (10) is claimable even though no single week had 10
	local first = MissionDefs.getAward("a_elims_10") :: MissionDefs.Award
	Harness.eq(r.service.claim(p, "award", "a_elims_10"), true)
	Harness.eq(r.wallet[p], first.reward)
	Harness.eq(r.service.claim(p, "award", "a_elims_10"), false)
	Harness.eq(r.service.claim(p, "award", "a_elims_50"), false)
	Harness.eq(r.wallet[p], first.reward)
end)

Harness.test("missions service: two players never share progress", function()
	local r = rig(T0)
	local a, b = {}, {}
	local def = weekly(WEEK, "easy")
	r.service.count(a, def.kind, def.goal)
	Harness.eq(r.service.claim(b, "week", def.id), false)
	Harness.eq(r.service.claim(a, "week", def.id), true)
	Harness.eq(r.wallet[b], nil)
end)

Harness.test("missions service: nothing loaded means nothing counts and nothing pays", function()
	local store = MissionMemoryStore.new()
	local dead: MissionService.Store = {
		status = function(_p: any)
			return "failed"
		end,
		read = function(_p: any)
			return nil
		end,
		update = function(_p: any, _fn: any)
			return false, "notLoaded"
		end,
		release = nil,
	}
	local _ = store
	local paid = 0
	local sent = 0
	local service = MissionService.new({
		store = dead,
		pay = function(_p: any, _a: number, _k: string)
			paid += 1
			return true, nil
		end,
		send = function(_p: any, state: Types.MissionsState)
			sent += 1
			Harness.eq(state.login.canClaim, false)
			Harness.eq(state.status, "failed")
		end,
		now = function()
			return T0
		end,
		config = CFG,
		resetHour = 0,
	})
	Harness.eq(#service.count({}, "elims", 1), 0)
	Harness.eq(service.claim({}, "login"), false)
	Harness.eq(service.claim({}, "award", "a_elims_10"), false)
	service.push({})
	Harness.eq(paid, 0)
	Harness.truthy(sent >= 1)
end)

-- ===== the remotes =====

Harness.test("missions remotes: the claim shape is checked and junk is refused", function()
	local def = RemoteDefs.byName["MissionClaim"]
	Harness.truthy(def ~= nil and def.direction == "toServer")
	local schema = def.schema :: { Guard.Field }
	Harness.eq((Guard.validate(schema, table.pack("week", "w_elims_12"))), true)
	Harness.eq((Guard.validate(schema, table.pack("login"))), true, "id is optional")
	Harness.eq((Guard.validate(schema, table.pack("award", "a_wins_1", "extra"))), false)
	Harness.eq((Guard.validate(schema, table.pack())), false)
	Harness.eq((Guard.validate(schema, table.pack(12))), false)
	Harness.eq((Guard.validate(schema, table.pack("week", "bad id!"))), false)
	Harness.eq((Guard.validate(schema, table.pack("week", string.rep("a", 80)))), false)
	Harness.eq((Guard.validate(schema, table.pack("week", {}))), false)
	local req = RemoteDefs.byName["MissionsRequest"]
	Harness.truthy(req ~= nil and req.direction == "toServer")
	Harness.truthy(RemoteDefs.byName["MissionsState"].direction == "toClient")
end)
