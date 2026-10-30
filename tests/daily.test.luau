--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local DailyDefs = require("../src/shared/Daily/DailyDefs")
local DailyMemoryStore = require("../src/shared/Daily/DailyMemoryStore")
local DailyRules = require("../src/shared/Daily/DailyRules")
local DailyService = require("../src/shared/Daily/DailyService")
local DailyText = require("../src/shared/Daily/DailyText")
local Types = require("../src/shared/Types")

local REWARDS = Config.Daily.rewards
local DAY = 86400
local T0 = 20000 * DAY + 5 * 3600 -- day 20000, 05:00 UTC

-- ===== the list =====

Harness.test(
	"daily: ids are saveable and unique, goals are whole numbers, every tier has a kind mix",
	function()
		local seen: { [string]: boolean } = {}
		for _, def in DailyDefs.list do
			Harness.truthy(string.match(def.id, "^[a-z0-9_]+$") ~= nil, def.id)
			Harness.truthy(not seen[def.id], "duplicate " .. def.id)
			seen[def.id] = true
			Harness.truthy(def.goal >= 1 and def.goal == math.floor(def.goal), def.id .. " goal")
			Harness.truthy(table.find(DailyDefs.kinds, def.kind) ~= nil, def.id .. " kind")
			Harness.truthy(REWARDS[def.tier] ~= nil and REWARDS[def.tier] > 0, def.id .. " reward")
		end
		for _, tier in DailyDefs.tiers do
			Harness.truthy(#DailyDefs.ofTier(tier) >= 3, tier .. " needs 3+ to avoid repeats")
		end
	end
)

Harness.test("daily: rewards stay under the coin grant cap", function()
	for _, n in REWARDS do
		Harness.truthy(n <= Config.Progression.maxMatchGrant, "reward over cap")
	end
end)

Harness.test("daily: receipt keys fit the profile receipt rules", function()
	local key = DailyRules.receiptKey(20000, "elims_10")
	Harness.truthy(#key <= 100 and string.match(key, "^[%w_:%.%-]+$") ~= nil, key)
end)

-- ===== days and picks =====

Harness.test(
	"daily: the day changes at the reset hour, and the countdown hits that moment",
	function()
		Harness.eq(DailyRules.dayOf(T0, 0), 20000)
		Harness.eq(DailyRules.dayOf(20001 * DAY - 1, 0), 20000)
		Harness.eq(DailyRules.dayOf(20001 * DAY, 0), 20001)
		Harness.eq(
			DailyRules.dayOf(20000 * DAY + 3 * 3600, 4),
			19999,
			"before 04:00 is still yesterday"
		)
		Harness.eq(DailyRules.secondsLeft(T0, 0), 19 * 3600)
		Harness.eq(DailyRules.secondsLeft(20001 * DAY - 1, 0), 1)
	end
)

Harness.test(
	"daily: each day has one easy, one medium, one hard, all different kinds, same on every call",
	function()
		local seenSets: { [string]: boolean } = {}
		for day = 19990, 20090 do
			local picks = DailyRules.pick(day)
			Harness.eq(#picks, 3, "three a day")
			local kinds: { [string]: boolean } = {}
			local key = ""
			for i, def in picks do
				Harness.eq(def.tier, DailyDefs.tiers[i], "tier order")
				Harness.truthy(not kinds[def.kind], "repeat kind on day " .. day)
				kinds[def.kind] = true
				Harness.eq(DailyRules.pick(day)[i].id, def.id, "same answer twice")
				key ..= def.id .. ","
			end
			seenSets[key] = true
		end
		local n = 0
		for _ in seenSets do
			n += 1
		end
		Harness.truthy(n >= 10, `days should vary, only {n} different sets`)
	end
)

-- ===== progress rules =====

Harness.test(
	"daily: progress counts only today's challenges of that kind and stops at the goal",
	function()
		local day = 20000
		local picks = DailyRules.pick(day)
		local s = DailyRules.new(day)
		local target = picks[1]
		local done = DailyRules.add(s, day, target.kind, target.goal - 1)
		Harness.eq(#done, 0)
		done = DailyRules.add(s, day, target.kind, 5)
		Harness.eq(done[1], target.id, "just finished")
		Harness.eq(s.progress[target.id], target.goal, "capped")
		Harness.eq(#DailyRules.add(s, day, target.kind, 1), 0, "finishing twice does not count")
		for _, kind in DailyDefs.kinds do
			local onToday = false
			for _, def in picks do
				onToday = onToday or def.kind == kind
			end
			if not onToday then
				DailyRules.add(s, day, kind, 3)
				for id in s.progress do
					Harness.truthy(DailyDefs.get(id).kind ~= kind, "off-day kind counted")
				end
			end
		end
	end
)

Harness.test("daily: bad amounts count nothing", function()
	local day = 20000
	local kind = DailyRules.pick(day)[1].kind
	local s = DailyRules.new(day)
	for _, bad in { -1, 0, 0.5, 0 / 0, math.huge, 1e12 } do
		Harness.eq(#DailyRules.add(s, day, kind, bad), 0)
	end
	Harness.eq(next(s.progress), nil, "nothing stored")
end)

Harness.test("daily: a new day wipes progress and paid marks", function()
	local s = DailyRules.new(20000)
	local def = DailyRules.pick(20000)[1]
	DailyRules.add(s, 20000, def.kind, def.goal)
	Harness.truthy(DailyRules.markPaid(s, 20000, def.id))
	Harness.truthy(DailyRules.roll(s, 20001))
	Harness.eq(next(s.progress), nil)
	Harness.eq(next(s.paid), nil)
	Harness.truthy(not DailyRules.roll(s, 20001), "same day: no change")
end)

Harness.test(
	"daily: cannot mark paid what is unfinished, off today, or from another day",
	function()
		local s = DailyRules.new(20000)
		local def = DailyRules.pick(20000)[2]
		Harness.truthy(not DailyRules.markPaid(s, 20000, def.id), "unfinished")
		DailyRules.add(s, 20000, def.kind, def.goal)
		Harness.truthy(not DailyRules.markPaid(s, 19999, def.id), "wrong day")
		Harness.truthy(not DailyRules.markPaid(s, 20000, "not_a_challenge"), "unknown id")
		Harness.truthy(DailyRules.markPaid(s, 20000, def.id))
	end
)

Harness.test("daily: fill repairs junk from a save", function()
	local s = DailyRules.fill({ day = "x", progress = { a = -3, b = 2, c = 0 / 0 }, paid = 7 })
	Harness.eq(s.day, -1)
	Harness.eq(s.progress.a, nil)
	Harness.eq(s.progress.b, 2)
	Harness.eq(s.progress.c, nil)
	Harness.eq(type(s.paid), "table")
end)

-- ===== service (rules + store + pay) =====

local function rig(startTime: number)
	local clock = startTime
	local store = DailyMemoryStore.new()
	local wallet: { [any]: number } = {}
	local keys: { [string]: boolean } = {}
	local sent: { Types.DailyState } = {}
	local payFails = false
	local service = DailyService.new({
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
		send = function(_player: any, state: Types.DailyState)
			table.insert(sent, state)
		end,
		now = function()
			return clock
		end,
		rewards = REWARDS,
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

Harness.test("daily service: finishing a challenge pays its tier reward once", function()
	local r = rig(T0)
	local p = {}
	local hard = DailyRules.pick(20000)[3]
	for _ = 1, hard.goal + 4 do
		r.service.count(p, hard.kind, 1)
	end
	Harness.eq(r.wallet[p], REWARDS.hard, "paid once")
	local last = r.sent[#r.sent]
	Harness.eq(last.day, 20000)
	Harness.eq(#last.challenges, 3)
	for _, c in last.challenges do
		if c.id == hard.id then
			Harness.truthy(c.paid, "shown paid")
			Harness.eq(c.progress, c.goal)
		end
	end
	local paidMsgs = 0
	for _, st in r.sent do
		if st.justPaid == hard.id then
			paidMsgs += 1
		end
	end
	Harness.eq(paidMsgs, 1, "one 'just paid' message")
end)

Harness.test("daily service: two players keep their own progress", function()
	local r = rig(T0)
	local a, b = {}, {}
	local easy = DailyRules.pick(20000)[1]
	r.service.count(a, easy.kind, easy.goal)
	Harness.eq(r.wallet[a], REWARDS.easy)
	Harness.eq(r.wallet[b], nil)
	r.service.count(b, easy.kind, 1)
	Harness.eq(r.wallet[b], if easy.goal == 1 then REWARDS.easy else nil)
end)

Harness.test("daily service: a failed payment is tried again later and still pays once", function()
	local r = rig(T0)
	local p = {}
	local easy = DailyRules.pick(20000)[1]
	r.setPayFails(true)
	r.service.count(p, easy.kind, easy.goal)
	Harness.eq(r.wallet[p], nil, "not paid yet")
	r.setPayFails(false)
	r.service.push(p)
	Harness.eq(r.wallet[p], REWARDS.easy, "paid on retry")
	r.service.push(p)
	r.service.count(p, easy.kind, 1)
	Harness.eq(r.wallet[p], REWARDS.easy, "never twice")
end)

Harness.test("daily service: an already-paid key marks it paid without paying again", function()
	local r = rig(T0)
	local p = {}
	local easy = DailyRules.pick(20000)[1]
	r.keys[DailyRules.receiptKey(20000, easy.id)] = true -- paid by an earlier save, mark lost
	r.service.count(p, easy.kind, easy.goal)
	Harness.eq(r.wallet[p], nil)
	Harness.truthy((r.store.read(p) :: any).paid[easy.id], "marked paid")
end)

Harness.test("daily service: tomorrow brings new challenges and a fresh board", function()
	local r = rig(T0)
	local p = {}
	local easy = DailyRules.pick(20000)[1]
	r.service.count(p, easy.kind, easy.goal)
	r.setTime(T0 + DAY)
	r.service.push(p)
	local last = r.sent[#r.sent]
	Harness.eq(last.day, 20001)
	for _, c in last.challenges do
		Harness.eq(c.progress, 0)
		Harness.truthy(not c.paid)
	end
	local tomorrowEasy = DailyRules.pick(20001)[1]
	r.service.count(p, tomorrowEasy.kind, tomorrowEasy.goal)
	Harness.eq(r.wallet[p], REWARDS.easy * 2, "a new day pays again")
end)

Harness.test("daily service: counting something off today's list sends nothing", function()
	local r = rig(T0)
	local p = {}
	local onToday: { [string]: boolean } = {}
	for _, def in DailyRules.pick(20000) do
		onToday[def.kind] = true
	end
	r.service.push(p)
	local before = #r.sent
	for _, kind in DailyDefs.kinds do
		if not onToday[kind] then
			r.service.count(p, kind, 1)
		end
	end
	r.service.count(p, "made_up_kind", 1)
	Harness.eq(#r.sent, before)
end)

-- ===== text =====

Harness.test("daily text: lines, progress and timer read right", function()
	Harness.eq(DailyText.line("elims", 5), "Get 5 eliminations")
	Harness.eq(DailyText.line("elims", 1), "Get 1 elimination")
	Harness.eq(DailyText.line("crates", 3), "Open 3 crates")
	Harness.eq(DailyText.line("wins", 1), "Win 1 match")
	Harness.eq(DailyText.line("top3", 3), "Finish top 3 in 3 matches")
	Harness.eq(DailyText.progress(2, 5), "2/5")
	Harness.eq(DailyText.timer(19 * 3600 + 5 * 60), "New in 19h 5m")
	Harness.eq(DailyText.timer(59), "New in 1m")
	for _, kind in DailyDefs.kinds do
		Harness.truthy(DailyText.line(kind, 2) ~= "", kind)
	end
end)

-- ===== the coin side (piece 18's ProgressService.grant) =====

Harness.test("daily coins: ProgressService.grant pays once per key and respects the cap", function()
	local MemoryStore = require("../src/shared/Progression/MemoryStore")
	local ProgressService = require("../src/shared/Progression/ProgressService")
	local store = MemoryStore.new()
	local svc = ProgressService.new({
		store = store,
		maxGrant = Config.Progression.maxMatchGrant,
		receiptKey = function(matchId: number): string
			return "m:" .. matchId
		end,
		send = function() end,
		applyLook = function() end,
	})
	local p = {}
	local key = DailyRules.receiptKey(20000, "wins_1")
	Harness.truthy((svc.grant(p, REWARDS.hard, key)))
	local ok, reason = svc.grant(p, REWARDS.hard, key)
	Harness.truthy(not ok and reason == "duplicate", "second time is a duplicate")
	Harness.eq((store.read(p) :: any).coins, REWARDS.hard)
	Harness.truthy(
		not (svc.grant(p, Config.Progression.maxMatchGrant + 1, "d:1:x")),
		"over cap refused"
	)
end)

Harness.test("daily looks: the picked look exists, and every look has a color per tier", function()
	local DailyLooks = require("../src/shared/Daily/DailyLooks")
	Harness.truthy(DailyLooks.looks[Config.Daily.look] ~= nil, "Config.Daily.look")
	for key, look in DailyLooks.looks do
		for _, tier in DailyDefs.tiers do
			Harness.truthy(look.tierColors[tier] ~= nil, key .. " " .. tier)
		end
	end
end)
