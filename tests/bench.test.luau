--!strict
local Harness = require("./harness")
local BenchDefs = require("../src/shared/Bench/BenchDefs")
local BenchMemoryStore = require("../src/shared/Bench/BenchMemoryStore")
local BenchRules = require("../src/shared/Bench/BenchRules")
local BenchService = require("../src/shared/Bench/BenchService")
local BenchText = require("../src/shared/Bench/BenchText")
local Config = require("../src/shared/Config")
local Guard = require("../src/shared/Guard")
local RemoteDefs = require("../src/shared/RemoteDefs")
local Serializable = require("../src/shared/Profile/Serializable")
local Types = require("../src/shared/Types")

-- ===== the list =====

Harness.test("bench: ids are saveable and unique, every need points at a real part", function()
	local seen: { [string]: boolean } = {}
	for _, bp in BenchDefs.blueprints do
		Harness.truthy(string.match(bp.id, "^[a-z][a-z0-9_]*$") ~= nil, bp.id)
		Harness.truthy(not seen[bp.id], "duplicate " .. bp.id)
		seen[bp.id] = true
		Harness.truthy(table.find({ "head", "body", "feet" }, bp.slot) ~= nil, bp.id .. " slot")
		Harness.truthy(#bp.needs >= 2 and #bp.needs <= 3, bp.id .. " needs 2-3 parts")
		for _, need in bp.needs do
			Harness.truthy(BenchDefs.kind(need.kind) ~= nil, bp.id .. " kind")
			Harness.truthy(BenchDefs.isTier(need.tier), bp.id .. " tier")
			Harness.truthy(
				need.count >= 1 and need.count == math.floor(need.count),
				bp.id .. " count"
			)
		end
	end
	for _, k in BenchDefs.kinds do
		for t = 1, BenchDefs.maxTier do
			local key = BenchDefs.partKey(k.id, t)
			Harness.truthy(string.match(key, "^[a-z][a-z0-9_]*$") ~= nil, key)
		end
	end
end)

Harness.test(
	"bench: every tier is used by a blueprint, and the first plans are within reach of tier 1",
	function()
		local used: { [number]: boolean } = {}
		for _, bp in BenchDefs.blueprints do
			for _, need in bp.needs do
				used[need.tier] = true
			end
		end
		for t = 1, BenchDefs.maxTier do
			Harness.truthy(used[t], "no plan uses tier " .. t)
		end
		local first = BenchDefs.blueprints[1]
		for _, need in first.needs do
			Harness.eq(need.tier, 1, "first plan needs tier 1 only")
		end
	end
)

-- ===== merge =====

Harness.test("bench: three of a part make one of the next tier, and only then", function()
	local s = BenchRules.empty()
	BenchRules.add(s, "bolt", 1, 2)
	local ok, why = BenchRules.merge(s, "bolt", 1)
	Harness.eq(ok, false)
	Harness.eq(why, "notEnough")
	Harness.eq(BenchRules.count(s, "bolt", 1), 2, "nothing changed on a refusal")
	BenchRules.add(s, "bolt", 1, 2)
	ok = BenchRules.merge(s, "bolt", 1)
	Harness.eq(ok, true)
	Harness.eq(BenchRules.count(s, "bolt", 1), 1)
	Harness.eq(BenchRules.count(s, "bolt", 2), 1)
	Harness.eq(s.merges, 1)
end)

Harness.test("bench: the best tier does not merge, bad ids are refused", function()
	local s = BenchRules.empty()
	BenchRules.add(s, "coil", BenchDefs.maxTier, 5)
	local _, why = BenchRules.merge(s, "coil", BenchDefs.maxTier)
	Harness.eq(why, "maxTier")
	_, why = BenchRules.merge(s, "rocket", 1)
	Harness.eq(why, "badPart")
	_, why = BenchRules.merge(s, "coil", 0)
	Harness.eq(why, "badPart")
	_, why = BenchRules.merge(s, "coil", 1.5)
	Harness.eq(why, "badPart")
	_, why = BenchRules.merge(s, "coil", 99)
	Harness.eq(why, "badPart")
	_, why = BenchRules.merge(s, {} :: any, "x" :: any)
	Harness.eq(why, "badPart")
end)

Harness.test(
	"bench: 27 rough parts of one kind become one prime part, nothing is lost or made",
	function()
		local s = BenchRules.empty()
		BenchRules.add(s, "plate", 1, 27)
		for tier = 1, 3 do
			while BenchRules.canMerge(s, "plate", tier) do
				BenchRules.merge(s, "plate", tier)
			end
		end
		Harness.eq(BenchRules.count(s, "plate", 4), 1)
		for tier = 1, 3 do
			Harness.eq(BenchRules.count(s, "plate", tier), 0)
		end
		Harness.eq(s.merges, 13)
		Harness.eq(BenchRules.mergesAvailable(s, "plate", 4), 0)
	end
)

-- ===== build =====

Harness.test("bench: build spends the parts, marks the gear, and cannot be built twice", function()
	local s = BenchRules.empty()
	BenchRules.add(s, "bolt", 1, 3)
	BenchRules.add(s, "plate", 1, 1)
	local ok = BenchRules.build(s, "spark_cap")
	Harness.eq(ok, true)
	Harness.eq(BenchRules.count(s, "bolt", 1), 1)
	Harness.eq(BenchRules.count(s, "plate", 1), 0)
	Harness.eq(s.built.spark_cap, true)
	BenchRules.add(s, "bolt", 1, 5)
	BenchRules.add(s, "plate", 1, 5)
	local _, why = BenchRules.build(s, "spark_cap")
	Harness.eq(why, "alreadyBuilt")
	Harness.eq(BenchRules.count(s, "bolt", 1), 6, "a refusal spends nothing")
	_, why = BenchRules.build(s, "nope")
	Harness.eq(why, "badBlueprint")
	_, why = BenchRules.build(s, 7 :: any)
	Harness.eq(why, "badBlueprint")
end)

Harness.test("bench: a higher tier never stands in for a lower one", function()
	local s = BenchRules.empty()
	BenchRules.add(s, "bolt", 2, 5)
	BenchRules.add(s, "plate", 2, 5)
	local ok, why = BenchRules.build(s, "spark_cap")
	Harness.eq(ok, false)
	Harness.eq(why, "notEnough")
end)

Harness.test("bench: view shows piles, progress per need, ready and built", function()
	local s = BenchRules.empty()
	BenchRules.add(s, "coil", 1, 3)
	BenchRules.add(s, "bolt", 1, 1)
	BenchRules.add(s, "plate", 1, 1)
	local v = BenchRules.view(s)
	Harness.eq(#v.parts, 3)
	Harness.eq(v.parts[1].kind, "bolt", "kind order")
	Harness.eq(v.total, #BenchDefs.blueprints)
	local byId: { [string]: BenchRules.BlueprintView } = {}
	for _, b in v.blueprints do
		byId[b.id] = b
	end
	Harness.eq(byId.dash_kicks.ready, true) -- 2 coil + 1 bolt
	Harness.eq(byId.spark_cap.ready, false) -- needs 2 bolts
	Harness.eq(byId.spark_cap.needs[1].have, 1)
	local coilPile: BenchRules.PartView? = nil
	for _, p in v.parts do
		if p.kind == "coil" then
			coilPile = p
		end
	end
	Harness.eq((coilPile :: BenchRules.PartView).canMerge, true)
	BenchRules.build(s, "dash_kicks")
	Harness.eq(BenchRules.view(s).built, 1)
end)

-- ===== saved data =====

Harness.test("bench: fill repairs junk, keeps unknown ids, and the result is saveable", function()
	local s = BenchRules.fill({
		parts = {
			bolt_1 = 3.7,
			old_thing_9 = 2,
			coil_1 = -4,
			plate_1 = 0 / 0,
			plate_2 = "x",
			[5] = 1,
			bolt_3 = 1e9,
		},
		built = { spark_cap = true, gone_plan = true, street_vest = "yes" },
		merges = -3,
		builds = 2.9,
	})
	Harness.eq(s.parts.bolt_1, 3)
	Harness.eq(s.parts.old_thing_9, 2, "unknown ids are kept")
	Harness.eq(s.parts.coil_1, nil)
	Harness.eq(s.parts.plate_1, nil)
	Harness.eq(s.parts.plate_2, nil)
	Harness.eq(s.parts.bolt_3, nil, "a pile over the cap is dropped")
	Harness.eq(s.built.gone_plan, true)
	Harness.eq(s.built.street_vest, nil)
	Harness.eq(s.merges, 0)
	Harness.eq(s.builds, 2)
	local ok = Serializable.check(s)
	Harness.eq(ok, true)
	local empty = BenchRules.fill("junk")
	Harness.eq(next(empty.parts), nil)
end)

Harness.test("bench: a pile stops growing at the cap", function()
	local s = BenchRules.empty()
	BenchRules.add(s, "bolt", 1, BenchRules.MAX_PILE)
	BenchRules.add(s, "bolt", 1, 50)
	Harness.eq(BenchRules.count(s, "bolt", 1), BenchRules.MAX_PILE)
end)

-- ===== drops =====

Harness.test("bench: better place, more parts; every drop is tier 1 and a known kind", function()
	local d = Config.Bench.drops
	Harness.eq(BenchRules.dropCount(1, true, d, 8), d.win)
	Harness.eq(BenchRules.dropCount(1, false, d, 8), d.podium, "a shared first place is not a win")
	Harness.eq(BenchRules.dropCount(3, false, d, 8), d.podium)
	Harness.eq(BenchRules.dropCount(4, false, d, 8), d.middle)
	Harness.eq(BenchRules.dropCount(5, false, d, 8), d.other)
	Harness.eq(BenchRules.dropCount(8, false, d, 8), d.other)
	Harness.truthy(
		d.win >= d.podium and d.podium >= d.middle and d.middle >= d.other and d.other >= 1
	)
	for i = 1, 20 do
		local got = BenchRules.roll(3, function(max)
			return (i % max) + 1
		end)
		Harness.eq(#got, 3)
		for _, g in got do
			Harness.eq(g.tier, 1)
			Harness.truthy(BenchDefs.kind(g.kind) ~= nil)
		end
	end
end)

Harness.test("bench: a wild rng cannot make an unknown kind", function()
	local got = BenchRules.roll(2, function()
		return 99
	end)
	Harness.eq(got[1].kind, BenchDefs.kinds[#BenchDefs.kinds].id)
	got = BenchRules.roll(1, function()
		return -4
	end)
	Harness.eq(got[1].kind, BenchDefs.kinds[1].id)
end)

Harness.test("bench: the three kinds come up about equally often (the odds we show)", function()
	local n: { [string]: number } = {}
	local seed = 12345
	local function rng(max: number): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return (seed // 65536) % max + 1
	end
	for _, d in BenchRules.roll(3000, rng) do
		n[d.kind] = (n[d.kind] or 0) + 1
	end
	for _, k in BenchDefs.kinds do
		Harness.truthy(math.abs((n[k.id] or 0) - 1000) < 150, k.id .. " " .. tostring(n[k.id]))
	end
	Harness.truthy(string.find(BenchText.odds(), "33%", 1, true) ~= nil, BenchText.odds())
end)

-- ===== the service =====

type Rig = {
	service: BenchService.Service,
	store: BenchMemoryStore.MemoryStore,
	sent: { Types.BenchState },
	player: { name: string },
}

local function rig(): Rig
	local sent: { Types.BenchState } = {}
	local store = BenchMemoryStore.new()
	local service = BenchService.new({
		store = store,
		send = function(_, state)
			table.insert(sent, state)
		end,
		rng = function(max)
			return max -- always the last kind
		end,
		drops = Config.Bench.drops,
		fieldSize = Config.Bench.fieldSize,
	})
	return { service = service, store = store, sent = sent, player = { name = "p1" } }
end

Harness.test("bench service: a match drop pays once per match key", function()
	local r = rig()
	local got = r.service.drop(r.player, "m:a:1", 1, true)
	Harness.eq(#got, Config.Bench.drops.win)
	local again = r.service.drop(r.player, "m:a:1", 1, true)
	Harness.eq(#again, 0, "the same match pays nothing twice")
	local s = r.store.read(r.player) :: BenchRules.State
	Harness.eq(BenchRules.count(s, "coil", 1), Config.Bench.drops.win)
	local last = r.sent[#r.sent]
	Harness.eq(last.event, "dropped")
	Harness.eq(#(last.justGot :: any), Config.Bench.drops.win)
	r.service.drop(r.player, "m:a:2", 9, false)
	Harness.eq(
		BenchRules.count(r.store.read(r.player) :: BenchRules.State, "coil", 1),
		Config.Bench.drops.win + Config.Bench.drops.other
	)
end)

Harness.test("bench service: merge and build go through the store and tell the client", function()
	local r = rig()
	r.store.update(r.player, function(s)
		BenchRules.add(s, "bolt", 1, 3)
		BenchRules.add(s, "plate", 1, 1)
		return true
	end)
	local ok = r.service.merge(r.player, "bolt", 1)
	Harness.eq(ok, true)
	Harness.eq(r.sent[#r.sent].event, "merged")
	local ok2, why = r.service.merge(r.player, "bolt", 1)
	Harness.eq(ok2, false)
	Harness.eq(why, "notEnough")
	Harness.eq(r.sent[#r.sent].event, "denied")
	Harness.eq(r.sent[#r.sent].reason, "notEnough")
	local s = r.store.read(r.player) :: BenchRules.State
	Harness.eq(BenchRules.count(s, "bolt", 2), 1, "the denied merge changed nothing")
	local built, why2 = r.service.build(r.player, "night_visor")
	Harness.eq(built, false)
	Harness.eq(why2, "notEnough")
end)

Harness.test("bench service: a whole path from drops to built gear", function()
	local r = rig()
	-- 9 coils (the rng always rolls the last kind): 3 matches of 3.
	for i = 1, 3 do
		r.service.drop(r.player, "m:b:" .. i, 2, false)
	end
	for _ = 1, 3 do
		Harness.eq((r.service.merge(r.player, "coil", 1)), true)
	end
	Harness.eq(BenchRules.count(r.store.read(r.player) :: BenchRules.State, "coil", 2), 3)
	r.service.merge(r.player, "coil", 2)
	Harness.eq(BenchRules.count(r.store.read(r.player) :: BenchRules.State, "coil", 3), 1)
	r.store.update(r.player, function(s)
		BenchRules.add(s, "plate", 3, 1)
		BenchRules.add(s, "coil", 2, 1)
		return true
	end)
	local ok = r.service.build(r.player, "bulwark_coat")
	Harness.eq(ok, true)
	Harness.eq(r.sent[#r.sent].built, 1)
	Harness.eq(r.sent[#r.sent].event, "built")
end)

Harness.test("bench service: two players do not share a bench", function()
	local r = rig()
	local other = { name = "p2" }
	r.service.drop(r.player, "m:c:1", 1, true)
	Harness.eq(next((r.store.read(other) :: BenchRules.State).parts), nil)
end)

-- ===== remotes =====

Harness.test("bench remotes: tier and ids are checked before the server sees them", function()
	local merge = RemoteDefs.byName.BenchMerge
	Harness.truthy(merge ~= nil and merge.schema ~= nil)
	local schema = merge.schema :: { Guard.Field }
	local ok = Guard.validate(schema, table.pack("bolt", 2))
	Harness.eq(ok, true)
	Harness.eq((Guard.validate(schema, table.pack("bolt", 2.5))), false)
	Harness.eq((Guard.validate(schema, table.pack("bolt", 9))), false)
	Harness.eq((Guard.validate(schema, table.pack("bolt", 0 / 0))), false)
	Harness.eq((Guard.validate(schema, table.pack("bolt; drop", 2))), false)
	Harness.eq((Guard.validate(schema, table.pack("bolt"))), false)
	Harness.eq(
		(Guard.validate(RemoteDefs.byName.BenchBuild.schema :: any, table.pack("spark_cap"))),
		true
	)
	Harness.eq(
		(Guard.validate(RemoteDefs.byName.BenchBuild.schema :: any, table.pack(("x"):rep(40)))),
		false
	)
	Harness.eq(RemoteDefs.byName.BenchState.direction, "toClient")
end)

Harness.test("bench: words exist for every refusal the rules can give", function()
	for _, why in { "notEnough", "maxTier", "alreadyBuilt", "badPart", "badBlueprint" } do
		Harness.truthy(BenchText.reason(why) ~= "Cannot do that", why)
	end
	Harness.eq(BenchText.pile("bolt", 1, 3), "Rough Bolt x3")
	Harness.eq(BenchText.need("coil", 2, 5, 1), "Tuned Coil 1/1")
end)
