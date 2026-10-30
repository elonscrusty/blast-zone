--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local MemoryStore = require("../src/shared/Progression/MemoryStore")
local ProgressRules = require("../src/shared/Progression/ProgressRules")
local ProgressService = require("../src/shared/Progression/ProgressService")
local Receipts = require("../src/shared/Profile/Receipts")
local SeasonDefs = require("../src/shared/Season/SeasonDefs")
local SeasonMemoryStore = require("../src/shared/Season/SeasonMemoryStore")
local SeasonRules = require("../src/shared/Season/SeasonRules")
local SeasonService = require("../src/shared/Season/SeasonService")
local SeasonText = require("../src/shared/Season/SeasonText")
local TrackDefs = require("../src/shared/Progression/TrackDefs")
local Types = require("../src/shared/Types")

local PER = Config.Season.xpPerTier
local CAP = Config.Season.maxXpPerMatch
local DAY = 86400
local START = Config.Season.startUnix
local LENGTH = Config.Season.lengthDays * DAY
local TOP = SeasonDefs.count()

-- ===== the list =====

Harness.test(
	"pass: 20 tiers, every look is a real not-for-sale pass item, no Robux words",
	function()
		Harness.eq(TOP, 20)
		for n, tier in SeasonDefs.tiers do
			for _, row in { "free", "paid" } do
				local reward = SeasonDefs.reward(n, row) :: SeasonDefs.Reward
				Harness.truthy(reward ~= nil, `tier {n} {row} missing`)
				if reward.kind == "scrap" then
					local amount = reward.amount or 0
					Harness.truthy(
						amount > 0 and amount <= Config.Progression.maxMatchGrant,
						`tier {n} {row} scrap`
					)
					Harness.eq(reward.itemId, nil)
				else
					local def = TrackDefs.get(reward.itemId or "")
					Harness.truthy(def ~= nil, `tier {n} {row} unknown look`)
					Harness.truthy(
						def ~= nil and def.cost == -1,
						`tier {n} {row} look must not be for sale`
					)
					Harness.truthy(
						table.find(TrackDefs.passItems :: { any }, def :: any) ~= nil,
						`tier {n} {row} look is not a pass item`
					)
				end
			end
			Harness.truthy(tier.free ~= nil and tier.paid ~= nil)
		end
		Harness.eq(SeasonDefs.reward(0, "free"), nil)
		Harness.eq(SeasonDefs.reward(TOP + 1, "free"), nil)
		Harness.eq(SeasonDefs.reward(1, "gold"), nil)
	end
)

Harness.test(
	"pass: the paid row is worth more than the free row, and each look is used once",
	function()
		local free, paid = 0, 0
		local used: { [string]: boolean } = {}
		for n = 1, TOP do
			for _, row in { "free", "paid" } do
				local r = SeasonDefs.reward(n, row) :: SeasonDefs.Reward
				if r.kind == "scrap" then
					if row == "free" then
						free += r.amount or 0
					else
						paid += r.amount or 0
					end
				else
					Harness.truthy(
						not used[r.itemId or ""],
						"look used twice: " .. tostring(r.itemId)
					)
					used[r.itemId or ""] = true
				end
			end
		end
		Harness.truthy(paid > free, "paid scrap should be more")
		Harness.eq(#TrackDefs.passItems, 8)
		for _, it in TrackDefs.passItems do
			Harness.truthy(used[it.id] == true, it.id .. " is never given")
			Harness.truthy(string.match(it.id, "^[a-z0-9_]+$") ~= nil, it.id)
			Harness.truthy(TrackDefs.get(it.id) == it, it.id .. " not found by id")
		end
	end
)

Harness.test("pass: no pass look clashes with the shop, the track or the level gifts", function()
	local others: { [string]: boolean } = {}
	for _, list in { TrackDefs.defaults, TrackDefs.tiers, TrackDefs.gifts, TrackDefs.shop } do
		for _, it in list do
			others[it.id] = true
		end
	end
	for _, it in TrackDefs.passItems do
		Harness.truthy(not others[it.id], it.id .. " is already another item")
	end
end)

Harness.test("pass: nothing is for sale and no product number is made up", function()
	Harness.eq(Config.Season.forSale, false)
	for key in Config.Season :: any do
		Harness.truthy(
			string.lower(tostring(key)):find("product") == nil,
			"product field " .. tostring(key)
		)
	end
end)

Harness.test("pass: receipt keys fit the profile receipt rules", function()
	local key = SeasonRules.receiptKey(12, 20, "paid")
	Harness.truthy(Receipts.isValidKey(key), key)
	Harness.truthy(SeasonRules.receiptKey(1, 3, "free") ~= SeasonRules.receiptKey(2, 3, "free"))
end)

-- ===== the clock =====

Harness.test("season clock: starts at the start time, turns every lengthDays", function()
	Harness.eq(SeasonRules.seasonAt(START - 5 * DAY), 1, "before the start is season 1")
	Harness.eq(SeasonRules.seasonAt(START), 1)
	Harness.eq(SeasonRules.seasonAt(START + LENGTH - 1), 1)
	Harness.eq(SeasonRules.seasonAt(START + LENGTH), 2)
	Harness.eq(SeasonRules.seasonAt(START + 5 * LENGTH + 3), 6)
	Harness.eq(SeasonRules.secondsLeft(START + LENGTH - 1), 1)
	Harness.eq(SeasonRules.secondsLeft(START), LENGTH)
	Harness.eq(SeasonRules.secondsLeft(START + LENGTH), LENGTH)
end)

-- ===== the saved table =====

Harness.test("fill: repairs a broken table, keeps good numbers", function()
	local s = SeasonRules.fill({
		season = "x",
		xp = -3,
		paid = "yes",
		claimed = 5,
		keys = { "a", 4, "b" },
	})
	Harness.eq(s.season, 0)
	Harness.eq(s.xp, 0)
	Harness.eq(s.paid, false)
	Harness.eq(next(s.claimed), nil)
	Harness.eq(#s.keys, 2)
	local good = SeasonRules.fill({
		season = 3,
		xp = 450,
		paid = true,
		claimed = { ["1:free"] = true, bad = 7 },
		keys = {},
	})
	Harness.eq(good.season, 3)
	Harness.eq(good.xp, 450)
	Harness.eq(good.paid, true)
	Harness.eq(good.claimed["1:free"], true)
	Harness.eq(good.claimed.bad, nil)
end)

Harness.test(
	"roll: a new season wipes xp, claims and the paid row; the same season keeps them",
	function()
		local s = SeasonRules.new(1)
		SeasonRules.addXp(s, 300, "k1", CAP)
		SeasonRules.openPaid(s)
		Harness.truthy(SeasonRules.markClaimed(s, 1, "free"))
		Harness.eq(SeasonRules.roll(s, 1), false)
		Harness.eq(s.xp, 300)
		Harness.eq(SeasonRules.roll(s, 2), true)
		Harness.eq(s.season, 2)
		Harness.eq(s.xp, 0)
		Harness.eq(s.paid, false)
		Harness.eq(next(s.claimed), nil)
		Harness.eq(#s.keys, 0)
	end
)

-- ===== xp and tiers =====

Harness.test("progress: tiers every xpPerTier, stops at the top", function()
	local p0 = SeasonRules.progress(0)
	Harness.eq(p0.tier, 0)
	Harness.eq(p0.forNext, PER)
	local p = SeasonRules.progress(PER * 3 + 7)
	Harness.eq(p.tier, 3)
	Harness.eq(p.intoTier, 7)
	local top = SeasonRules.progress(PER * TOP + 500)
	Harness.eq(top.tier, TOP)
	Harness.eq(top.forNext, nil)
	Harness.eq(SeasonRules.maxXp(), PER * TOP)
end)

Harness.test("addXp: whole capped amounts, once per match key, total stops at the top", function()
	local s = SeasonRules.new(1)
	local r = SeasonRules.addXp(s, PER + 5, "m1", CAP)
	Harness.truthy(r.ok)
	Harness.eq(r.fromTier, 0)
	Harness.eq(r.toTier, 1)
	Harness.eq(SeasonRules.addXp(s, 50, "m1", CAP).reason, "duplicate")
	Harness.eq(s.xp, PER + 5, "a repeat changes nothing")
	for _, bad in { -5, 0, 0.5, 0 / 0, math.huge } do
		Harness.eq(SeasonRules.addXp(s, bad, "m2", CAP).reason, "badAmount", tostring(bad))
	end
	Harness.eq(SeasonRules.addXp(s, CAP + 1, "m2", CAP).reason, "tooMuch")
	Harness.eq(SeasonRules.addXp(s, 10, "", CAP).reason, "badKey")
	Harness.eq(s.xp, PER + 5)
	Harness.eq(#s.keys, 1, "refused keys are not remembered")
	s.xp = SeasonRules.maxXp() - 3
	Harness.truthy(SeasonRules.addXp(s, 100, "m3", CAP).ok)
	Harness.eq(s.xp, SeasonRules.maxXp())
end)

Harness.test("addXp: only the newest keys are remembered", function()
	local s = SeasonRules.new(1)
	for i = 1, Config.Season.keepKeys + 5 do
		SeasonRules.addXp(s, 1, "k" .. i, CAP)
	end
	Harness.eq(#s.keys, Config.Season.keepKeys)
	Harness.eq(s.keys[#s.keys], "k" .. (Config.Season.keepKeys + 5))
end)

-- ===== claiming =====

Harness.test("canClaim: not reached, paid row closed, taken, bad numbers", function()
	local s = SeasonRules.new(1)
	Harness.eq(select(2, SeasonRules.canClaim(s, 1, "free")), "locked")
	s.xp = PER * 2
	Harness.truthy(SeasonRules.canClaim(s, 2, "free"))
	Harness.eq(select(2, SeasonRules.canClaim(s, 3, "free")), "locked", "tier 3 not reached")
	Harness.eq(select(2, SeasonRules.canClaim(s, 1, "paid")), "needPass")
	SeasonRules.openPaid(s)
	Harness.truthy(SeasonRules.canClaim(s, 1, "paid"))
	Harness.truthy(SeasonRules.markClaimed(s, 1, "paid"))
	Harness.eq(select(2, SeasonRules.canClaim(s, 1, "paid")), "claimed")
	Harness.eq(SeasonRules.markClaimed(s, 1, "paid"), false, "no second mark")
	Harness.eq(select(2, SeasonRules.canClaim(s, 0, "free")), "badTier")
	Harness.eq(select(2, SeasonRules.canClaim(s, TOP + 1, "free")), "badTier")
	Harness.eq(select(2, SeasonRules.canClaim(s, 1.5, "free")), "badTier")
	Harness.eq(select(2, SeasonRules.canClaim(s, 1, "gold")), "badRow")
end)

Harness.test("ready: low tiers first, free before paid, paid only when open", function()
	local s = SeasonRules.new(1)
	s.xp = PER * 2
	local r = SeasonRules.ready(s)
	Harness.eq(#r, 2)
	Harness.eq(r[1].tier, 1)
	Harness.eq(r[2].tier, 2)
	SeasonRules.openPaid(s)
	r = SeasonRules.ready(s)
	Harness.eq(#r, 4)
	Harness.eq(r[1].row, "free")
	Harness.eq(r[2].row, "paid")
	SeasonRules.markClaimed(s, 1, "free")
	Harness.eq(#SeasonRules.ready(s), 3)
end)

-- ===== the service =====

type Rig = {
	service: SeasonService.Service,
	store: SeasonService.Store,
	player: any,
	sent: { Types.SeasonState },
	paid: { { amount: number, key: string } },
	given: { { itemId: string, key: string, dup: number } },
	clock: { now: number },
	failPay: { on: boolean },
	seen: { [string]: boolean },
}

local function rig(): Rig
	local store = SeasonMemoryStore.new()
	local sent: { Types.SeasonState } = {}
	local paid: { { amount: number, key: string } } = {}
	local given: { { itemId: string, key: string, dup: number } } = {}
	local clock = { now = START + DAY }
	local failPay = { on = false }
	local seen: { [string]: boolean } = {}
	local service = SeasonService.new({
		store = store,
		pay = function(_player: any, amount: number, key: string): (boolean, string?)
			if failPay.on then
				return false, "saveFailed"
			end
			if seen[key] then
				return false, "duplicate"
			end
			seen[key] = true
			table.insert(paid, { amount = amount, key = key })
			return true, nil
		end,
		giveItem = function(
			_player: any,
			itemId: string,
			key: string,
			dup: number
		): (boolean, string?)
			if failPay.on then
				return false, "saveFailed"
			end
			if seen[key] then
				return false, "duplicate"
			end
			seen[key] = true
			table.insert(given, { itemId = itemId, key = key, dup = dup })
			return true, nil
		end,
		send = function(_player: any, state: Types.SeasonState)
			table.insert(sent, state)
		end,
		now = function()
			return clock.now
		end,
	})
	return {
		service = service,
		store = store,
		player = {},
		sent = sent,
		paid = paid,
		given = given,
		clock = clock,
		failPay = failPay,
		seen = seen,
	}
end

local function last(r: Rig): Types.SeasonState
	return r.sent[#r.sent]
end

Harness.test("service: onXp adds season XP once per match and tells the player", function()
	local r = rig()
	Harness.truthy(r.service.onXp(r.player, PER * 2 + 10, "m1"))
	Harness.eq(last(r).xp, PER * 2 + 10)
	Harness.eq(last(r).tier, 2)
	Harness.eq(last(r).intoTier, 10)
	Harness.eq(last(r).tiers[2].freeState, "ready")
	Harness.eq(last(r).tiers[3].freeState, "locked")
	Harness.eq(last(r).status, "temporary")
	Harness.eq(last(r).maxTier, TOP)
	Harness.eq(last(r).forSale, false)
	Harness.truthy(not r.service.onXp(r.player, 500, "m1"), "same match again")
	Harness.eq(last(r).xp, PER * 2 + 10)
	Harness.truthy(not r.service.onXp(r.player, CAP + 1, "m2"), "over the cap")
	Harness.truthy(not r.service.onXp(r.player, -4, "m3"))
	Harness.eq(last(r).xp, PER * 2 + 10)
end)

Harness.test("claim: pays the reward once, marks it taken, tells the player", function()
	local r = rig()
	r.service.onXp(r.player, PER * 5, "m1")
	local ok = r.service.claim(r.player, 1, "free")
	Harness.truthy(ok)
	Harness.eq(#r.paid, 1)
	Harness.eq(r.paid[1].amount, (SeasonDefs.reward(1, "free") :: SeasonDefs.Reward).amount)
	Harness.eq(r.paid[1].key, SeasonRules.receiptKey(1, 1, "free"))
	Harness.eq(last(r).tiers[1].freeState, "claimed")
	local claimed = last(r).justClaimed
	Harness.truthy(claimed ~= nil and claimed[1].tier == 1 and claimed[1].row == "free")
	local ok2, why = r.service.claim(r.player, 1, "free")
	Harness.truthy(not ok2)
	Harness.eq(why, "claimed")
	Harness.eq(#r.paid, 1, "no second payment")
	Harness.eq(last(r).denied, "claimed")
end)

Harness.test("claim: a look is given as an item; tier 5 free is a look", function()
	local r = rig()
	r.service.onXp(r.player, PER * 5, "m1")
	Harness.truthy(r.service.claim(r.player, 5, "free"))
	Harness.eq(#r.given, 1)
	Harness.eq(r.given[1].itemId, "tracer_sky")
	Harness.eq(r.given[1].dup, Config.Season.duplicateScrap)
	local view = (last(r).justClaimed :: { Types.SeasonClaimView })[1].reward
	Harness.eq(view.kind, "item")
	Harness.eq(view.name, "Sky Shot")
end)

Harness.test("claim: not reached, paid row closed, bad row or tier", function()
	local r = rig()
	r.service.onXp(r.player, PER * 2, "m1")
	local ok, why = r.service.claim(r.player, 3, "free")
	Harness.truthy(not ok)
	Harness.eq(why, "locked")
	ok, why = r.service.claim(r.player, 1, "paid")
	Harness.truthy(not ok)
	Harness.eq(why, "needPass")
	ok, why = r.service.claim(r.player, 99, "free")
	Harness.eq(why, "badTier")
	ok, why = r.service.claim(r.player, 1, "zzz")
	Harness.eq(why, "badRow")
	Harness.eq(#r.paid + #r.given, 0, "nothing was paid")
end)

Harness.test("claim: a failed payment leaves it untaken, and a retry pays it", function()
	local r = rig()
	r.service.onXp(r.player, PER, "m1")
	r.failPay.on = true
	local ok, why = r.service.claim(r.player, 1, "free")
	Harness.truthy(not ok)
	Harness.eq(why, "saveFailed")
	Harness.eq(last(r).tiers[1].freeState, "ready")
	r.failPay.on = false
	Harness.truthy(r.service.claim(r.player, 1, "free"))
	Harness.eq(#r.paid, 1)
	Harness.eq(last(r).tiers[1].freeState, "claimed")
end)

Harness.test(
	"claim: a payment that was made but not marked is just marked, never paid twice",
	function()
		local r = rig()
		r.service.onXp(r.player, PER, "m1")
		r.seen[SeasonRules.receiptKey(1, 1, "free")] = true -- paid before, mark was lost
		Harness.truthy(r.service.claim(r.player, 1, "free"))
		Harness.eq(#r.paid, 0)
		Harness.eq(last(r).tiers[1].freeState, "claimed")
	end
)

Harness.test("claim all: tier 0 takes everything ready in order, paid only when open", function()
	local r = rig()
	r.service.onXp(r.player, PER * 3, "m1")
	Harness.truthy(r.service.claim(r.player, 0, "free"))
	Harness.eq(#r.paid + #r.given, 3, "3 free rewards")
	Harness.eq(#(last(r).justClaimed :: { Types.SeasonClaimView }), 3)
	local ok, why = r.service.claim(r.player, 0, "free")
	Harness.truthy(not ok)
	Harness.eq(why, "nothing")
	Harness.truthy(r.service.unlockPaid(r.player))
	Harness.eq(last(r).hasPass, true)
	Harness.eq(last(r).tiers[1].paidState, "ready")
	Harness.truthy(r.service.claim(r.player, 0, "free"))
	Harness.eq(#r.paid + #r.given, 6, "3 paid rewards")
	Harness.eq(r.given[1].itemId, "trail_dusk", "tier 3 paid is a look")
	Harness.eq(last(r).tiers[3].paidState, "claimed")
end)

Harness.test("unlockPaid: opens the row once; a second call changes nothing", function()
	local r = rig()
	Harness.eq(r.service.unlockPaid(r.player), true)
	Harness.eq(r.service.unlockPaid(r.player), false)
	r.service.onXp(r.player, PER, "m1")
	Harness.eq(last(r).tiers[1].paidState, "ready")
end)

Harness.test(
	"new season: xp, claims and the paid row start over, and rewards can be earned again",
	function()
		local r = rig()
		r.service.onXp(r.player, PER * 2, "m1")
		r.service.unlockPaid(r.player)
		r.service.claim(r.player, 1, "free")
		Harness.eq(last(r).season, 1)
		r.clock.now = START + LENGTH + 100
		r.service.push(r.player)
		Harness.eq(last(r).season, 2)
		Harness.eq(last(r).xp, 0)
		Harness.eq(last(r).hasPass, false)
		Harness.eq(last(r).tiers[1].freeState, "locked")
		r.service.onXp(r.player, PER, "m1") -- a match key from last season counts again
		Harness.eq(last(r).xp, PER)
		local paidBefore = #r.paid
		Harness.truthy(r.service.claim(r.player, 1, "free"))
		Harness.eq(#r.paid, paidBefore + 1, "season 2 pays under its own key")
		Harness.eq(r.paid[#r.paid].key, SeasonRules.receiptKey(2, 1, "free"))
	end
)

Harness.test("view: before anything is loaded, everything shows locked at zero", function()
	local v = SeasonService.view(nil, 1, START, "loading")
	Harness.eq(v.xp, 0)
	Harness.eq(v.tier, 0)
	Harness.eq(v.status, "loading")
	Harness.eq(#v.tiers, TOP)
	Harness.eq(v.tiers[1].freeState, "locked")
	Harness.eq(v.tiers[1].paidState, "locked")
	Harness.eq(v.tiers[TOP].xpNeeded, PER * TOP)
end)

Harness.test("view: a paid row waiting for the pass says needPass, not ready", function()
	local s = SeasonRules.new(1)
	s.xp = PER
	local v = SeasonService.view(s, 1, START, "ready")
	Harness.eq(v.tiers[1].freeState, "ready")
	Harness.eq(v.tiers[1].paidState, "needPass")
end)

-- ===== giving looks through the coin service =====

local function coinRig()
	local store = MemoryStore.new()
	local sent: { Types.ProgressState } = {}
	local service = ProgressService.new({
		store = store,
		maxGrant = Config.Progression.maxMatchGrant,
		xpCap = Config.Level.maxXpPerMatch,
		receiptKey = function(matchId: number): string
			return `job:{matchId}`
		end,
		send = function(_player: any, state: Types.ProgressState)
			table.insert(sent, state)
		end,
		applyLook = function() end,
	})
	return { service = service, store = store, player = {}, sent = sent }
end

Harness.test("giveItem: gives a pass look once per key, shows it as owned, never power", function()
	local r = coinRig()
	local ok = r.service.giveItem(r.player, "trail_aqua", "s:1:10:free", 40)
	Harness.truthy(ok)
	local p = r.store.read(r.player) :: ProgressRules.Progression
	Harness.truthy(ProgressRules.owns(p, "trail_aqua"))
	local state = r.sent[#r.sent]
	Harness.truthy(table.find(state.gifts, "trail_aqua") ~= nil, "listed with the owned looks")
	local ok2, why = r.service.giveItem(r.player, "trail_aqua", "s:1:10:free", 40)
	Harness.truthy(not ok2)
	Harness.eq(why, "duplicate")
end)

Harness.test("giveItem: a look already owned pays Scrap instead, once", function()
	local r = coinRig()
	r.service.giveItem(r.player, "tracer_sky", "s:1:5:free", 40)
	Harness.truthy(r.service.giveItem(r.player, "tracer_sky", "s:2:5:free", 40))
	local p = r.store.read(r.player) :: ProgressRules.Progression
	Harness.eq(p.coins, 40)
	Harness.eq(p.totalEarned, 40)
	Harness.truthy(not r.service.giveItem(r.player, "tracer_sky", "s:2:5:free", 40))
	Harness.eq((r.store.read(r.player) :: ProgressRules.Progression).coins, 40)
end)

Harness.test("giveItem: only not-for-sale looks, never a shop tier or a made-up id", function()
	local r = coinRig()
	for _, id in { "trail_coral", "trail_cyan", "nope", "" } do
		local ok, why = r.service.giveItem(r.player, id, "s:1:1:free", 40)
		Harness.truthy(not ok, id)
		Harness.eq(why, "unknownItem")
	end
	local p = r.store.read(r.player) :: ProgressRules.Progression
	Harness.truthy(not ProgressRules.owns(p, "trail_coral"), "shop tier was not given")
end)

Harness.test("a pass look can be worn like any owned look", function()
	local r = coinRig()
	r.service.giveItem(r.player, "trail_royal", "s:1:15:paid", 40)
	Harness.truthy(r.service.equip(r.player, "trail_royal"))
	local p = r.store.read(r.player) :: ProgressRules.Progression
	Harness.eq(ProgressRules.equippedIn(p, "trail").id, "trail_royal")
	Harness.truthy(not r.service.equip(r.player, "tracer_citrus"), "not owned yet")
end)

-- ===== words =====

Harness.test("text: tiny words for rewards, the clock and the bar", function()
	Harness.eq(SeasonText.reward("scrap", 25, nil, "Scrap"), "+25 Scrap")
	Harness.eq(SeasonText.reward("item", nil, "Sky Shot", "Scrap"), "Sky Shot")
	Harness.eq(SeasonText.timer(3 * 86400 + 5 * 3600), "Ends in 3d 5h")
	Harness.eq(SeasonText.timer(2 * 3600 + 10 * 60), "Ends in 2h 10m")
	Harness.eq(SeasonText.timer(30), "Ends in 1m")
	Harness.eq(SeasonText.timer(-4), "Ends in 1m")
	Harness.eq(SeasonText.tier(3, 20), "TIER 3/20")
	Harness.eq(SeasonText.xp(40, 120), "40/120")
	Harness.eq(SeasonText.xp(0, nil), "MAX")
	Harness.eq(SeasonText.denied("needPass"), "Paid row is locked")
	Harness.eq(SeasonText.denied(nil), "")
	Harness.eq(SeasonText.denied("weird"), "Try again")
end)
