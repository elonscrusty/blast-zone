--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local LevelDefs = require("../src/shared/Level/LevelDefs")
local LevelRules = require("../src/shared/Level/LevelRules")
local MemoryStore = require("../src/shared/Progression/MemoryStore")
local ProgressRules = require("../src/shared/Progression/ProgressRules")
local ProgressService = require("../src/shared/Progression/ProgressService")
local TrackDefs = require("../src/shared/Progression/TrackDefs")
local Types = require("../src/shared/Types")

local CAP = Config.Level.maxXpPerMatch

-- ===== data checks =====

Harness.test(
	"gifts: in level order, inside the level range, real ids, no Robux anywhere",
	function()
		local last = 0
		for _, g in LevelDefs.gifts do
			Harness.truthy(g.level > last and g.level <= Config.Level.maxLevel, `level {g.level}`)
			last = g.level
			if g.kind == "scrap" then
				Harness.truthy(
					(g.amount or 0) > 0 and (g.amount or 0) <= Config.Progression.maxMatchGrant * 2
				)
			else
				local def = TrackDefs.get(g.itemId or "")
				Harness.truthy(def ~= nil, "unknown gift item " .. tostring(g.itemId))
				Harness.truthy(def ~= nil and def.cost < 0, "gift items are not for sale")
			end
		end
	end
)

Harness.test("gift looks: saveable unique ids, not in the shop tiers", function()
	local seen: { [string]: boolean } = {}
	for _, it in TrackDefs.gifts do
		Harness.truthy(string.match(it.id, "^[a-z0-9_]+$") ~= nil, it.id)
		Harness.truthy(not seen[it.id], "duplicate " .. it.id)
		seen[it.id] = true
		for _, tier in TrackDefs.tiers do
			Harness.truthy(tier.id ~= it.id, "shop clash " .. it.id)
		end
	end
end)

-- ===== curve =====

Harness.test("curve: level 1 at 0 XP, each level needs more, top level is capped", function()
	Harness.eq(LevelRules.info(0).level, 1)
	local cost1 = LevelRules.costOf(1)
	Harness.eq(LevelRules.info(cost1 - 1).level, 1)
	Harness.eq(LevelRules.info(cost1).level, 2)
	Harness.eq(LevelRules.info(cost1).intoLevel, 0)
	Harness.truthy(LevelRules.costOf(2) > cost1)
	local top = LevelRules.info(1e8)
	Harness.eq(top.level, Config.Level.maxLevel)
	Harness.eq(top.forNext, nil)
end)

-- ===== rules =====

Harness.test("addXp: levels up, pays each gift once, in one change", function()
	local p = ProgressRules.new()
	local r = LevelRules.addXp(p, 1e6 > CAP and CAP or 1e6, CAP)
	Harness.truthy(r.ok)
	Harness.eq(r.fromLevel, 1)
	Harness.eq(r.toLevel, LevelRules.levelOf(p))
	local coinsAfter = p.coins
	-- a second add that crosses no new gift pays nothing extra
	local again = LevelRules.addXp(p, 0, CAP)
	Harness.truthy(again.ok)
	Harness.eq(#again.rewards, 0)
	Harness.eq(p.coins, coinsAfter)
end)

Harness.test("addXp: a huge jump gives every gift on the way, exactly once", function()
	local p = ProgressRules.new()
	p.accountXp = 0
	local total = 0
	for _ = 1, 400 do
		total += 1
		local r = LevelRules.addXp(p, CAP, CAP)
		Harness.truthy(r.ok)
		if LevelRules.levelOf(p) >= Config.Level.maxLevel then
			break
		end
	end
	local scrap = 0
	for _, g in LevelDefs.gifts do
		Harness.truthy(p.claimedLevels[tostring(g.level)] == true, `claimed {g.level}`)
		if g.kind == "scrap" then
			scrap += g.amount or 0
		else
			Harness.truthy(ProgressRules.owns(p, g.itemId or ""), `owns {g.itemId}`)
		end
	end
	Harness.eq(p.coins, scrap)
	Harness.eq(p.totalEarned, scrap)
end)

Harness.test("addXp: refuses bad numbers and too much, table untouched", function()
	local p = ProgressRules.new()
	for _, bad in { -1, 0 / 0, 1.5, math.huge, CAP + 1 } do
		local r = LevelRules.addXp(p, bad, CAP)
		Harness.truthy(not r.ok, tostring(bad))
		Harness.eq(p.accountXp, 0)
		Harness.eq(p.coins, 0)
	end
end)

Harness.test("gift looks are owned but never worn until the player equips them", function()
	local p = ProgressRules.new()
	p.unlocked.trail_violet = true
	Harness.truthy(ProgressRules.owns(p, "trail_violet"))
	Harness.eq(ProgressRules.equippedIn(p, "trail").id, "trail_cyan")
	Harness.truthy(ProgressRules.equip(p, "trail_violet").ok)
	Harness.eq(ProgressRules.equippedIn(p, "trail").id, "trail_violet")
	local q = ProgressRules.new()
	Harness.truthy(not ProgressRules.equip(q, "trail_violet").ok, "not owned")
	Harness.truthy(not ProgressRules.unlock(q, "trail_violet").ok, "cannot be bought")
	Harness.eq(ProgressRules.level(p), 0, "reward level counts shop tiers only")
end)

Harness.test("fill: old saves without level fields get them", function()
	local p = ProgressRules.fill({ coins = 5 } :: any)
	Harness.eq(p.accountXp, 0)
	Harness.eq(type(p.claimedLevels), "table")
	local bad = ProgressRules.fill({ accountXp = "lots" } :: any)
	Harness.eq(bad.accountXp, 0)
end)

-- ===== service =====

type Rig = {
	service: ProgressService.Service,
	store: ProgressService.Store,
	player: any,
	sent: { Types.ProgressState },
}

local function rig(): Rig
	local store = MemoryStore.new()
	local sent: { Types.ProgressState } = {}
	local service = ProgressService.new({
		store = store,
		maxGrant = Config.Progression.maxMatchGrant,
		xpCap = CAP,
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

Harness.test("onXp: adds XP once per match, tells the player the level up", function()
	local r = rig()
	Harness.truthy(r.service.onXp(r.player, 300, 1))
	local last = r.sent[#r.sent]
	Harness.truthy(last.levelUp ~= nil)
	Harness.eq(last.levelUp and last.levelUp.matchId, 1)
	Harness.eq(last.level, LevelRules.info(300).level)
	local count = #r.sent
	Harness.truthy(not r.service.onXp(r.player, 300, 1), "same match again")
	Harness.eq(#r.sent, count, "a duplicate is silent")
	Harness.eq((r.store.read(r.player) :: ProgressRules.Progression).accountXp, 300)
	Harness.truthy(r.service.onXp(r.player, 50, 2))
	Harness.eq((r.store.read(r.player) :: ProgressRules.Progression).accountXp, 350)
end)

Harness.test("onXp: does not block or repeat the Scrap payout of the same match", function()
	local r = rig()
	Harness.truthy(r.service.onReward(r.player, 40, 1))
	Harness.truthy(r.service.onXp(r.player, 100, 1))
	Harness.truthy(not r.service.onReward(r.player, 40, 1))
	Harness.eq((r.store.read(r.player) :: ProgressRules.Progression).coins, 40)
end)

Harness.test("onXp: a milestone gift arrives with the level up and lands in gifts", function()
	local r = rig()
	local need = 0
	for lvl = 1, 4 do
		need += LevelRules.costOf(lvl) -- exactly level 5
	end
	Harness.truthy(r.service.onXp(r.player, 400, 1))
	Harness.truthy(r.service.onXp(r.player, need - 400, 2))
	local last = r.sent[#r.sent]
	Harness.eq(last.level, 5)
	Harness.truthy(table.find(last.gifts, "trail_violet") ~= nil, "gift owned")
	Harness.truthy(last.levelUp ~= nil and #last.levelUp.rewards > 0)
	Harness.eq(#last.unlocked, 0, "shop list is not changed by gifts")
end)

Harness.test("onXp: too much XP is refused", function()
	local r = rig()
	Harness.truthy(not r.service.onXp(r.player, CAP + 1, 1))
	Harness.eq((r.store.read(r.player) :: ProgressRules.Progression).accountXp, 0)
end)
