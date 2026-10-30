--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local CoinLooks = require("../src/shared/Progression/CoinLooks")
local MemoryStore = require("../src/shared/Progression/MemoryStore")
local ProgressRules = require("../src/shared/Progression/ProgressRules")
local ProgressService = require("../src/shared/Progression/ProgressService")
local TrackDefs = require("../src/shared/Progression/TrackDefs")
local Types = require("../src/shared/Types")

local MAX = Config.Progression.maxMatchGrant

local function fresh(): ProgressRules.Progression
	return ProgressRules.new()
end

-- ===== data checks =====

Harness.test("the coin name on the results screen is the picked look's name", function()
	Harness.eq(CoinLooks.get(Config.Progression.look).name, Config.Rewards.currencyName)
	Harness.truthy(CoinLooks.looks[Config.Progression.look] ~= nil, "look key exists")
end)

Harness.test(
	"track: ids are saveable and unique, prices go up, every slot has a free default",
	function()
		local seen: { [string]: boolean } = {}
		local last = 0
		for _, tier in TrackDefs.tiers do
			Harness.truthy(string.match(tier.id, "^[a-z0-9_]+$") ~= nil, tier.id)
			Harness.truthy(not seen[tier.id], "duplicate " .. tier.id)
			seen[tier.id] = true
			Harness.truthy(tier.cost > last, tier.id .. " costs more than the one before")
			last = tier.cost
		end
		for _, slot in TrackDefs.slots do
			Harness.eq(TrackDefs.defaultFor(slot).cost, 0)
		end
	end
)

Harness.test("track items are looks only: no stat fields at all", function()
	local allowed = { id = true, slot = true, name = true, color = true, cost = true }
	for _, it in TrackDefs.tiers do
		for key in it :: any do
			Harness.truthy(allowed[key] == true, "unexpected field " .. tostring(key))
		end
	end
end)

-- ===== rules =====

Harness.test("addCoins: only whole, non-negative, capped amounts", function()
	local p = fresh()
	Harness.truthy(ProgressRules.addCoins(p, 48, MAX).ok)
	Harness.eq(p.coins, 48)
	Harness.eq(p.totalEarned, 48)
	for _, bad in { -5, 0.5, 0 / 0, math.huge, MAX + 1 } do
		Harness.truthy(not ProgressRules.addCoins(p, bad, MAX).ok, "refuses " .. tostring(bad))
	end
	Harness.eq(p.coins, 48, "refused amounts change nothing")
	Harness.eq(p.totalEarned, 48)
end)

Harness.test("unlock: next tier only, must afford, spends exactly the price", function()
	local p = fresh()
	local first, second = TrackDefs.tiers[1], TrackDefs.tiers[2]
	Harness.eq(ProgressRules.unlock(p, first.id).reason, "tooPoor")
	p.coins = second.cost + first.cost
	Harness.eq(ProgressRules.unlock(p, second.id).reason, "notNext", "no skipping ahead")
	Harness.eq(ProgressRules.unlock(p, "no_such_item").reason, "notNext")
	Harness.truthy(ProgressRules.unlock(p, first.id).ok)
	Harness.eq(p.coins, second.cost)
	Harness.eq(ProgressRules.unlock(p, first.id).reason, "notNext", "cannot buy twice")
	Harness.truthy(ProgressRules.unlock(p, second.id).ok)
	Harness.eq(p.coins, 0)
end)

Harness.test("unlock: a finished track refuses", function()
	local p = fresh()
	p.coins = 99999
	for _, tier in TrackDefs.tiers do
		Harness.truthy(ProgressRules.unlock(p, tier.id).ok)
	end
	Harness.eq(ProgressRules.unlock(p, TrackDefs.tiers[1].id).reason, "trackDone")
	Harness.eq(ProgressRules.nextTier(p), nil)
end)

Harness.test("equip: only owned items go in their own slot; defaults are always owned", function()
	local p = fresh()
	local tier = TrackDefs.tiers[1]
	Harness.eq(ProgressRules.equip(p, tier.id).reason, "notOwned")
	Harness.eq(ProgressRules.equip(p, "nope").reason, "unknownItem")
	Harness.truthy(ProgressRules.equip(p, "trail_cyan").ok)
	p.unlocked[tier.id] = true
	Harness.truthy(ProgressRules.equip(p, tier.id).ok)
	Harness.eq(ProgressRules.equippedIn(p, tier.slot).id, tier.id)
end)

Harness.test("equippedIn: unknown or not-owned saved ids fall back to the default", function()
	local p = fresh()
	p.equipped.trail = "trail_from_the_future"
	Harness.eq(ProgressRules.equippedIn(p, "trail").id, "trail_cyan")
	p.equipped.trail = TrackDefs.tiers[1].id -- saved but never bought
	Harness.eq(ProgressRules.equippedIn(p, "trail").id, "trail_cyan")
	p.equipped.tracer = "trail_cyan" -- wrong slot
	Harness.eq(ProgressRules.equippedIn(p, "tracer").id, "tracer_cyan")
end)

Harness.test("fill: repairs missing or broken parts, keeps what it does not know", function()
	local raw: any =
		{ coins = "lots", unlocked = 5, extra = "keep me", equipped = { trail = "x_future" } }
	local p = ProgressRules.fill(raw)
	Harness.eq(p.coins, 0)
	Harness.eq(p.totalEarned, 0)
	Harness.eq(type(p.unlocked), "table")
	Harness.eq(type(p.grantedKeys), "table")
	Harness.eq(p.equipped.trail, "x_future")
	Harness.eq((p :: any).extra, "keep me")
	Harness.eq(ProgressRules.fill({}).coins, 0)
end)

-- ===== service (with the in-memory store, and one that is not loaded) =====

type Rig = {
	service: ProgressService.Service,
	sent: { Types.ProgressState },
	looks: { string },
	saves: number,
	store: ProgressService.Store,
}

local function rig(store: ProgressService.Store?): Rig
	local used: ProgressService.Store = store or MemoryStore.new()
	local r: Rig = { service = nil :: any, sent = {}, looks = {}, saves = 0, store = used }
	local counting: ProgressService.Store = {
		status = used.status,
		read = used.read,
		update = used.update,
		grantOnce = used.grantOnce,
		saveNow = function(player: any): boolean
			r.saves += 1
			return used.saveNow(player)
		end,
	}
	r.service = ProgressService.new({
		store = counting,
		maxGrant = MAX,
		xpCap = Config.Level.maxXpPerMatch,
		receiptKey = function(matchId: number): string
			return "job:" .. tostring(matchId)
		end,
		send = function(_player: any, state: Types.ProgressState)
			table.insert(r.sent, state)
		end,
		applyLook = function(_player: any, trailId: string, tracerId: string)
			table.insert(r.looks, trailId .. "/" .. tracerId)
		end,
	})
	return r
end

local ME = { name = "me" }

Harness.test("reward: a match pays once, even when asked again and again", function()
	local r = rig()
	Harness.truthy(r.service.onReward(ME, 48, 7))
	for _ = 1, 5 do
		Harness.truthy(not r.service.onReward(ME, 48, 7), "repeat pays nothing")
	end
	local read = r.store.read(ME)
	Harness.eq((read :: ProgressRules.Progression).coins, 48)
	Harness.eq(#r.sent, 1, "only the first answer is sent")
	Harness.eq((r.sent[1].gained :: any).amount, 48)
	Harness.eq((r.sent[1].gained :: any).matchId, 7)
	Harness.truthy(r.saves >= 1, "a reward asks for a save")
end)

Harness.test(
	"reward: the next match pays again; a bad amount pays nothing and uses up nothing",
	function()
		local r = rig()
		Harness.truthy(not r.service.onReward(ME, -3, 1), "negative")
		Harness.truthy(not r.service.onReward(ME, MAX + 1, 1), "too big")
		Harness.truthy(
			r.service.onReward(ME, 10, 1),
			"the same match can still pay its real amount"
		)
		Harness.truthy(r.service.onReward(ME, 20, 2))
		Harness.eq((r.store.read(ME) :: ProgressRules.Progression).coins, 30)
	end
)

Harness.test(
	"unlock: spends coins, wears the new look, tells the player; a refusal changes nothing",
	function()
		local r = rig()
		local tier = TrackDefs.tiers[1]
		Harness.truthy(not r.service.unlock(ME, tier.id), "too poor")
		Harness.eq(r.sent[#r.sent].denied, "tooPoor")
		r.service.onReward(ME, 150, 1)
		Harness.truthy(r.service.unlock(ME, tier.id))
		local read = r.store.read(ME) :: ProgressRules.Progression
		Harness.eq(read.coins, 150 - tier.cost)
		Harness.truthy(read.unlocked[tier.id])
		Harness.eq(r.looks[#r.looks], tier.id .. "/tracer_cyan")
		local last = r.sent[#r.sent]
		Harness.eq(last.equipped.trail, tier.id)
		Harness.eq(last.denied, nil)
		Harness.truthy(not r.service.unlock(ME, tier.id), "cannot buy it again")
		Harness.eq((r.store.read(ME) :: ProgressRules.Progression).coins, 150 - tier.cost)
	end
)

Harness.test("equip: refuses what is not owned; switching back to a default works", function()
	local r = rig()
	Harness.truthy(not r.service.equip(ME, TrackDefs.tiers[1].id))
	Harness.eq(r.sent[#r.sent].denied, "notOwned")
	r.service.onReward(ME, 150, 1)
	r.service.unlock(ME, TrackDefs.tiers[1].id)
	Harness.truthy(r.service.equip(ME, "trail_cyan"))
	Harness.eq(r.sent[#r.sent].equipped.trail, "trail_cyan")
end)

Harness.test("profile not loaded: nothing is paid, nothing is spent, the player is told", function()
	local broken: ProgressService.Store = {
		status = function(_p: any): string
			return "failed"
		end,
		read = function(_p: any): ProgressRules.Progression?
			return nil
		end,
		update = function(_p: any, _fn: any): (boolean, string?)
			return false, "notLoaded"
		end,
		grantOnce = function(_p: any, _key: string, _fn: any): (boolean, string?)
			return false, "notLoaded"
		end,
		saveNow = function(_p: any): boolean
			return false
		end,
	}
	local r = rig(broken)
	Harness.truthy(not r.service.onReward(ME, 48, 1))
	Harness.truthy(not r.service.unlock(ME, TrackDefs.tiers[1].id))
	Harness.eq(r.sent[1].status, "failed")
	Harness.eq(r.sent[1].coins, 0)
	Harness.eq(r.sent[1].denied, "notLoaded")
	Harness.eq(#r.looks, 0, "no look is applied without data")
end)

Harness.test("two players keep separate coins", function()
	local r = rig()
	local other = { name = "other" }
	r.service.onReward(ME, 40, 1)
	r.service.onReward(other, 15, 1) -- same match, different player: both are paid
	Harness.eq((r.store.read(ME) :: ProgressRules.Progression).coins, 40)
	Harness.eq((r.store.read(other) :: ProgressRules.Progression).coins, 15)
end)

-- ===== words for the screens =====

local ProgressText = require("../src/client/Progression/ProgressText")

local function state(over: { [string]: any }): Types.ProgressState
	local s: any = {
		status = "ready",
		coins = 0,
		totalEarned = 0,
		unlocked = {},
		equipped = { trail = "trail_cyan", tracer = "tracer_cyan" },
	}
	for k, v in over do
		s[k] = v
	end
	return s
end

Harness.test(
	"strip: shows the gain, the gap to the next tier, and offers UNLOCK only when affordable",
	function()
		local first = TrackDefs.tiers[1]
		local a = ProgressText.strip(
			state({ coins = 68, gained = { matchId = 1, amount = 48 } }),
			"Volts",
			first
		)
		Harness.eq(a.amount, "+48 Volts")
		Harness.eq(a.hint, "32 more for Coral Spark")
		Harness.near(a.fill, 0.68)
		Harness.eq(a.action, "track")
		local b = ProgressText.strip(state({ coins = 100 }), "Volts", first)
		Harness.eq(b.action, "unlock")
		Harness.eq(b.fill, 1)
		Harness.eq(b.amount, "100 Volts")
	end
)

Harness.test("strip: a finished track and an unloaded profile are said plainly", function()
	local done = ProgressText.strip(state({ coins = 5 }), "Volts", nil)
	Harness.eq(done.hint, "All rewards unlocked!")
	Harness.eq(done.action, "track")
	Harness.truthy(
		ProgressText.strip(state({ status = "failed" }), "Volts", TrackDefs.tiers[1]).note ~= nil
	)
	Harness.truthy(
		ProgressText.strip(state({ status = "temporary" }), "Volts", TrackDefs.tiers[1]).note ~= nil
	)
	Harness.eq(ProgressText.strip(state({}), "Volts", TrackDefs.tiers[1]).note, nil)
end)

Harness.test("card status: worn, owned, or the price", function()
	local s = state({
		unlocked = { "trail_coral" },
		equipped = { trail = "trail_coral", tracer = "tracer_cyan" },
	})
	Harness.eq(ProgressText.cardStatus(TrackDefs.get("trail_coral") :: any, s, "Volts"), "WORN")
	Harness.eq(ProgressText.cardStatus(TrackDefs.get("trail_cyan") :: any, s, "Volts"), "OWNED")
	Harness.eq(
		ProgressText.cardStatus(TrackDefs.get("tracer_gold") :: any, s, "Volts"),
		"160 Volts"
	)
end)

Harness.test("every refusal reason has words", function()
	for _, why in
		{ "tooPoor", "notNext", "notOwned", "notLoaded", "trackDone", "error", "rejected" }
	do
		Harness.truthy(ProgressText.denied(why, "Volts") ~= nil, why)
	end
	Harness.eq(ProgressText.denied(nil, "Volts"), nil)
end)

Harness.test(
	"level: counts the tiers bought, and the service tells listeners about every change",
	function()
		local p = fresh()
		Harness.eq(ProgressRules.level(p), 0)
		p.coins = 99999
		ProgressRules.unlock(p, TrackDefs.tiers[1].id)
		ProgressRules.unlock(p, TrackDefs.tiers[2].id)
		Harness.eq(ProgressRules.level(p), 2)

		local told = 0
		local r = rig()
		local service = ProgressService.new({
			store = r.store,
			maxGrant = MAX,
			xpCap = Config.Level.maxXpPerMatch,
			receiptKey = function(matchId: number): string
				return "k" .. tostring(matchId)
			end,
			send = function(_player: any, _state: Types.ProgressState) end,
			applyLook = function(_player: any, _trail: string, _tracer: string) end,
			changed = function(_player: any)
				told += 1
			end,
		})
		service.onReward(ME, 120, 1)
		service.onReward(ME, 120, 1) -- duplicate: silent
		service.unlock(ME, TrackDefs.tiers[1].id)
		Harness.eq(told, 2)
	end
)
