--!strict
-- Game modes (piece G24): who may vote, how the vote ends, and that a mode's tuning goes on and comes off cleanly.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local MatchPhase = require("../src/shared/MatchPhase")
local ModeRules = require("../src/shared/Modes/ModeRules")
local RemoteDefs = require("../src/shared/RemoteDefs")
local VoteFlow = require("../src/shared/MapVote/VoteFlow")
local ZoneModel = require("../src/server/Zone/ZoneModel")

local test, eq, truthy, near = Harness.test, Harness.eq, Harness.truthy, Harness.near

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out: any = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

local function sameTree(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not sameTree(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function first(_: number): number
	return 1
end
local function last(n: number): number
	return n
end

local function newFlow(pick: (number) -> number): VoteFlow.Flow
	return VoteFlow.new(ModeRules.pool(), pick)
end

-- A copy of just the parts of Config that modes touch.
local function configCopy(): any
	return {
		Zone = deepCopy(Config.Zone),
		Loot = deepCopy(Config.Loot),
		Containers = deepCopy(Config.Containers),
	}
end

local KNOWN_FIELDS: { [string]: boolean } = {
	zoneTimeScale = true,
	zoneDamageScale = true,
	floorGuns = true,
	floorPacks = true,
	crateWeights = true,
}

-- ===== the list =====

test("modes: the default is shown, open from the start and changes nothing", function()
	local def = ModeRules.default()
	truthy(def ~= nil)
	local d = def :: ModeRules.Def
	eq(d.id, Config.Modes.defaultId)
	eq(d.unlockLevel, 1)
	eq(next(d.tuning), nil)
	eq(ModeRules.enabled()[1].id, d.id, "the default is first in the list")
end)

test("modes: every defined mode is valid and only uses the allowed dials", function()
	local count = 0
	for id, raw in Config.Modes.defs do
		count += 1
		eq(ModeRules.problem(raw.tuning), nil, id)
		truthy(#raw.name > 0 and #raw.blurb > 0, id .. " has words")
		truthy(raw.unlockLevel >= 1 and raw.unlockLevel <= Config.Level.maxLevel, id .. " level")
		truthy(#id <= Config.Modes.maxIdLength, id .. " id length")
		for key in raw.tuning do
			truthy(KNOWN_FIELDS[key] == true, `{id} uses unknown dial {key}`)
		end
	end
	truthy(count >= 3)
end)

test("modes: nothing in a mode costs Robux or changes hits, health or speed", function()
	for id, raw in Config.Modes.defs do
		for key in raw.tuning do
			truthy(
				not string.find(string.lower(key), "robux") and not string.find(key, "price"),
				id
			)
			truthy(not string.find(string.lower(key), "health"), id)
			truthy(not string.find(string.lower(key), "speed"), id)
		end
	end
end)

test("modes: ids shown are real, unique and in the pool", function()
	local pool = ModeRules.pool()
	eq(#pool, #ModeRules.enabled())
	local seen: { [string]: boolean } = {}
	for _, m in pool do
		truthy(Config.Modes.defs[m.id] ~= nil and not seen[m.id], m.id)
		seen[m.id] = true
	end
end)

test("modes: unlock levels grow down the list so a lock is never a surprise", function()
	local lastLevel = 0
	for _, def in ModeRules.enabled() do
		truthy(def.unlockLevel >= lastLevel, def.id)
		lastLevel = def.unlockLevel
	end
end)

-- ===== who may vote =====

test("vote: an unknown mode is refused, a locked one is refused, an open one counts", function()
	local flow = newFlow(first)
	eq(ModeRules.vote(flow, "p1", "nope", 50), false)
	eq(ModeRules.vote(flow, "p1", "quick", 1), false, "level 1 cannot take a level 2 mode")
	eq(ModeRules.vote(flow, "p1", "quick", 2), true)
	eq(ModeRules.vote(flow, "p1", "loot", 3), false, "still locked at level 3")
	eq(flow.book.votes["p1"], "quick", "a refused vote leaves the old vote")
end)

test("vote: a mode that is defined but not shown cannot be voted for", function()
	local shown: { [string]: boolean } = {}
	for _, def in ModeRules.enabled() do
		shown[def.id] = true
	end
	for id in Config.Modes.defs do
		if not shown[id] then
			eq(ModeRules.canVote(id, Config.Level.maxLevel), false, id)
		end
	end
end)

test("vote: it ends at Spawning and a later vote is dropped", function()
	local flow = newFlow(first)
	flow:onPhase(MatchPhase.Waiting)
	eq(ModeRules.vote(flow, "p1", "classic", 1), true)
	flow:onPhase(MatchPhase.Countdown)
	eq(ModeRules.vote(flow, "p2", "classic", 1), true)
	flow:onPhase(MatchPhase.Spawning)
	eq(flow.locked, true)
	eq(ModeRules.vote(flow, "p3", "classic", 1), false)
	eq(flow.nextMapId, "classic")
end)

test(
	"vote: most votes win, a tie is broken by the pick, no repeat when there is a choice",
	function()
		local flow = newFlow(last)
		flow:onPhase(MatchPhase.Waiting)
		ModeRules.vote(flow, "a", "quick", 10)
		ModeRules.vote(flow, "b", "loot", 10)
		ModeRules.vote(flow, "c", "loot", 10)
		eq(flow:takeWinner(), "loot")

		local tie = newFlow(first)
		tie:setCurrentMap("classic")
		ModeRules.vote(tie, "a", "classic", 10)
		ModeRules.vote(tie, "b", "quick", 10)
		eq(tie:takeWinner(), "quick", "the mode just played does not win a tie")
	end
)

test("vote: nobody voted gives the default mode", function()
	local flow = newFlow(first)
	eq(flow:takeWinner(), nil)
	local def = ModeRules.resolve(flow.nextMapId)
	truthy(def ~= nil)
	eq((def :: ModeRules.Def).id, Config.Modes.defaultId)
end)

test("vote: a winner that is no longer shown falls back to the default", function()
	local def = ModeRules.resolve("not-a-mode")
	truthy(def ~= nil)
	eq((def :: ModeRules.Def).id, Config.Modes.defaultId)
end)

test("vote: a leaver's vote is taken back while the window is open", function()
	local flow = newFlow(first)
	ModeRules.vote(flow, "a", "quick", 10)
	flow:leave("a")
	eq(flow:takeWinner(), nil)
end)

test("state: locks are per viewer and the counts are shared", function()
	local flow = newFlow(first)
	ModeRules.vote(flow, "a", "quick", 10)
	ModeRules.vote(flow, "b", "quick", 10)
	local low = ModeRules.stateFor(flow, "c", 1)
	local high = ModeRules.stateFor(flow, "a", 10)
	eq(low.level, 1)
	eq(high.yourVote, "quick")
	eq(low.yourVote, nil)
	for i, mode in low.modes do
		eq(mode.locked, mode.unlockLevel > 1, mode.id)
		eq(mode.votes, high.modes[i].votes)
		eq(high.modes[i].locked, mode.unlockLevel > 10, mode.id)
	end
	local quick
	for _, mode in low.modes do
		if mode.id == "quick" then
			quick = mode
		end
	end
	eq(quick.votes, 2)
	eq(low.open, true)
	eq(low.nextModeId, nil)
end)

-- ===== putting a mode on the numbers =====

test("apply: Quick Blast makes every zone time shorter and the circle still works", function()
	local cfg = configCopy()
	local quick = (ModeRules.get("quick") :: ModeRules.Def).tuning
	local scale = quick.zoneTimeScale :: number
	ModeRules.apply(cfg, quick)
	for i, stage in cfg.Zone.stages do
		near(stage.warnAt, Config.Zone.stages[i].warnAt * scale)
		near(stage.closeAt, Config.Zone.stages[i].closeAt * scale)
		near(stage.closeSeconds, Config.Zone.stages[i].closeSeconds * scale)
		eq(stage.targetRadius, Config.Zone.stages[i].targetRadius, "the circle size is not changed")
		eq(stage.damagePerSecond, Config.Zone.stages[i].damagePerSecond)
	end
	local tl = ZoneModel.build(cfg.Zone)
	local lastSegment = tl.segments[#tl.segments]
	truthy(
		lastSegment.endAt < Config.Match.maxActiveSeconds - 10,
		"ends well before the safety net"
	)
	truthy(tl.finalPressureAt < Config.Match.finalPressureAtSeconds)
end)

test("apply: Loot Rush puts more guns and heals out and changes crate odds", function()
	local cfg = configCopy()
	local loot = (ModeRules.get("loot") :: ModeRules.Def).tuning
	ModeRules.apply(cfg, loot)
	eq(cfg.Loot.floorGuns.count, loot.floorGuns)
	eq(cfg.Loot.heal.floorPacks, loot.floorPacks)
	truthy(cfg.Loot.floorGuns.count > Config.Loot.floorGuns.count)
	truthy(cfg.Loot.heal.floorPacks > Config.Loot.heal.floorPacks)
	truthy(cfg.Loot.heal.floorPacks <= Config.Loot.heal.maxOnFloor, "packs fit under the floor cap")
	eq(cfg.Containers.tiers.epic.weight, (loot.crateWeights :: any).epic)
	eq(
		cfg.Containers.tiers.common.health,
		Config.Containers.tiers.common.health,
		"crate health untouched"
	)
end)

test("apply: the zone damage dial scales damage and keeps sudden death the hardest", function()
	local cfg = configCopy()
	ModeRules.apply(cfg, { zoneDamageScale = 1.5 })
	for i, stage in cfg.Zone.stages do
		near(stage.damagePerSecond, Config.Zone.stages[i].damagePerSecond * 1.5)
		eq(stage.warnAt, Config.Zone.stages[i].warnAt, "times untouched")
	end
	ZoneModel.build(cfg.Zone) -- does not throw
end)

test("apply: undo puts every number back, and a second undo does nothing", function()
	for id, raw in Config.Modes.defs do
		local cfg = configCopy()
		local before = deepCopy(cfg)
		local undo = ModeRules.apply(cfg, raw.tuning)
		undo()
		truthy(sameTree(cfg, before), `{id} did not restore`)
		cfg.Zone.stages[1].warnAt = 999
		undo()
		eq(cfg.Zone.stages[1].warnAt, 999, "the second undo changed nothing")
	end
end)

test("apply: classic changes nothing at all", function()
	local cfg = configCopy()
	local before = deepCopy(cfg)
	ModeRules.apply(cfg, (ModeRules.get("classic") :: ModeRules.Def).tuning)
	truthy(sameTree(cfg, before))
end)

test("apply: every defined mode still gives a valid circle", function()
	for id, raw in Config.Modes.defs do
		local cfg = configCopy()
		ModeRules.apply(cfg, raw.tuning)
		local ok, err = pcall(ZoneModel.build, cfg.Zone)
		truthy(ok, `{id}: {err}`)
	end
end)

test("problem: bad dials are caught", function()
	truthy(ModeRules.problem({ zoneTimeScale = 0 }) ~= nil)
	truthy(ModeRules.problem({ zoneTimeScale = 5 }) ~= nil)
	truthy(ModeRules.problem({ zoneDamageScale = 0 / 0 }) ~= nil)
	truthy(ModeRules.problem({ floorGuns = -1 }) ~= nil)
	truthy(ModeRules.problem({ floorPacks = 2.5 }) ~= nil)
	truthy(ModeRules.problem({ crateWeights = { gold = 5 } }) ~= nil)
	truthy(ModeRules.problem({ crateWeights = { common = 0, rare = 0 } }) ~= nil)
	eq(ModeRules.problem({}), nil)
end)

test("zone runner: a new match uses the numbers set just before it starts", function()
	local cfg = configCopy()
	local zoneConfig: any = cfg.Zone
	local clock = 0
	local runner = ZoneModel.newRunner({
		config = zoneConfig,
		now = function()
			return clock
		end,
		getTargets = function()
			return {}
		end,
		applyDamage = function() end,
		publish = function() end,
	})
	runner:start(1)
	local normal = runner.timeline.segments[1].closeAt
	runner:stop()

	local undo = ModeRules.apply(cfg, { zoneTimeScale = 0.5 })
	runner:start(2)
	near(runner.timeline.segments[1].closeAt, normal * 0.5, 1e-9, "the quick circle")
	runner:stop()

	undo()
	runner:start(3)
	near(runner.timeline.segments[1].closeAt, normal, 1e-9, "back to normal")
end)

-- ===== remotes =====

test("remotes: the three mode remotes exist with the right direction and shape", function()
	local vote = RemoteDefs.byName["ModeVoteRequest"]
	eq(vote.direction, "toServer")
	eq(#(vote.schema :: any), 1)
	eq(RemoteDefs.byName["ModeStateRequest"].direction, "toServer")
	eq(RemoteDefs.byName["ModeState"].direction, "toClient")
end)
