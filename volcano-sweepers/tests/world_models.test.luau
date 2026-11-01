--!strict
-- The picked Toy models as wired into the world (server World/Models/Wiring): part budget, where
-- they stand, what may collide, and the part names the server hangs its tags and prompts on.
-- Everything here runs on the pure specs (no Roblox).
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local Kit = require("../src/server/World/Models/Kit")
local Parts = require("../src/server/World/Models/Parts")
local Registry = require("../src/server/World/Models/Registry")
local Wiring = require("../src/server/World/Models/Wiring")
local WorldPlan = require("../src/shared/WorldPlan")

local W = Config.World
local plan = WorldPlan.build(W)
local BUDGET = 3600 -- Parts in the whole world (phones)

local function dist(x0: number, z0: number, x1: number, z1: number): number
	return math.sqrt((x0 - x1) ^ 2 + (z0 - z1) ^ 2)
end

local function partNamed(m: Kit.Model, name: string): Kit.Spec?
	for _, s in m.parts do
		if s.name == name then
			return s
		end
	end
	return nil
end

local function listHas(list: Parts.List, name: string): Parts.Part?
	for _, p in list.parts do
		if p.name == name then
			return p
		end
	end
	return nil
end

-- How far from its origin a model reaches on the ground (parts whose bottom is below head height),
-- at model scale k.
local HEAD = 3.5
local function kitReach(m: Kit.Model, k: number): number
	local reach = 0
	for _, s in m.parts do
		local b = Kit.partBounds(s)
		if b.minY * k < HEAD then
			local mx = math.max(math.abs(b.minX), math.abs(b.maxX))
			local mz = math.max(math.abs(b.minZ), math.abs(b.maxZ))
			reach = math.max(reach, math.sqrt(mx * mx + mz * mz) * k)
		end
	end
	return reach
end

local function listReach(list: Parts.List): number
	local reach = 0
	for _, p in list.parts do
		local half = math.max(p.size[1], p.size[2], p.size[3]) / 2
		if p.pos[2] - half < HEAD then
			reach = math.max(reach, math.sqrt(p.pos[1] ^ 2 + p.pos[3] ^ 2) + half)
		end
	end
	return reach
end

local function itemReach(it: WorldPlan.Item): number
	local d = Wiring.decor[it.kind]
	if d == nil then
		return 0
	end
	local k = Wiring.decorScale(it.kind, it.scale)
	if d.landmark then
		return listReach(Wiring.landmarkSpec(d.name, k))
	end
	return kitReach(Wiring.kitSpec(d.name, it.v), k)
end

Harness.test("world models: WorldPlan part costs match the picked models", function()
	for kind, d in Wiring.decor do
		local cost = WorldPlan.partCost[kind]
		Harness.truthy(cost ~= nil, `no part cost for {kind}`)
		if d.landmark then
			local n = Wiring.landmarkParts(Wiring.landmarkSpec(d.name, 1))
			Harness.truthy(n <= cost, `{kind}: {n} parts, cost says {cost}`)
		else
			for v = 1, 1000, 7 do
				local n = #Wiring.kitSpec(d.name, v).parts
				Harness.truthy(n <= cost, `{kind} v={v}: {n} parts, cost says {cost}`)
				Harness.truthy(n <= Registry.maxParts[d.name], `{kind}: over its model budget`)
			end
		end
	end
	local count = Wiring.partCount(plan, WorldPlan.partCost)
	Harness.truthy(count.parts.gates <= #plan.gates * WorldPlan.gateCost, "gate cost")
	Harness.truthy(count.parts.posts <= #plan.posts * WorldPlan.postCost, "post cost")
	Harness.truthy(count.parts.signs <= #plan.signs * WorldPlan.signCost, "sign cost")
	Harness.truthy(count.parts.hub <= WorldPlan.hubCost, `hub {count.parts.hub} parts`)
	Harness.truthy(count.parts.volcano <= WorldPlan.volcanoCost, `volcano {count.parts.volcano}`)
	Harness.truthy(
		count.parts.lighthouse <= WorldPlan.landmarkCost,
		`lighthouse {count.parts.lighthouse}`
	)
end)

Harness.test("world models: the whole island stays inside the phone part budget", function()
	local count = Wiring.partCount(plan, WorldPlan.partCost)
	local estimate = WorldPlan.estimateParts(plan)
	local line: { string } = {}
	for name, n in count.parts do
		table.insert(line, `{name} {n}`)
	end
	table.sort(line)
	print(
		`       (world: {count.total} parts exactly, estimate {estimate}; {table.concat(line, ", ")})`
	)
	Harness.truthy(count.total <= BUDGET, `world has {count.total} parts, budget {BUDGET}`)
	Harness.truthy(estimate >= count.total, "the estimate never undercounts")
	Harness.truthy(estimate <= count.total * 1.1, "the estimate stays close")
	-- placement counts x declared part counts, kind by kind, never more than the budget allows
	local decl = 0
	for kind, n in plan.counts do
		decl += n * (WorldPlan.partCost[kind] or 1)
	end
	Harness.truthy(decl <= 1900, `decor declares {decl} parts`)
	-- caps: the big models stay a sprinkle
	local caps: { [string]: number } = {
		palm = 20,
		rock = 24,
		mushroom = 20,
		spire = 20,
		camp = 6,
		pool = 16,
		lavapool = 12,
	}
	for kind, cap in caps do
		local n = plan.counts[kind] or 0
		Harness.truthy(n <= cap, `{n} {kind}s, cap {cap}`)
		Harness.truthy(n >= 2, `only {n} {kind}s`)
	end
end)

Harness.test(
	"world models: no model sits in the hub, the volcano, a gate or a Trade Post",
	function()
		local gateHalf = Wiring.kitSpec("Gate", 1).halfX
		for i, it in plan.decor do
			local R = itemReach(it)
			if R > 0 then
				local tag = `item {i} {it.kind} (reach {R})`
				Harness.truthy(
					dist(it.x, it.z, plan.hub.x, plan.hub.z) >= plan.hub.clearRadius + R,
					`{tag} in the hub circle`
				)
				local r = math.sqrt(it.x * it.x + it.z * it.z)
				Harness.truthy(r - R >= plan.coneRadius, `{tag} on the volcano foot`)
				Harness.truthy(r + R <= plan.outerRadius, `{tag} off the island`)
				for _, g in plan.gates do
					Harness.truthy(
						dist(it.x, it.z, g.x, g.z) >= gateHalf * g.scale + R,
						`{tag} on gate {g.zoneId}`
					)
				end
				for _, p in plan.posts do
					Harness.truthy(
						dist(it.x, it.z, p.x, p.z) >= WorldPlan.POST_REACH + R - 0.01,
						`{tag} on trade post {p.zoneId}`
					)
				end
				for _, v in plan.vents do
					Harness.truthy(dist(it.x, it.z, v.x, v.z) >= 2.5 + R, `{tag} on a vent`)
				end
				for _, s in plan.signs do
					Harness.truthy(dist(it.x, it.z, s.x, s.z) >= 4 + R, `{tag} on a zone sign`)
				end
			end
		end
	end
)

Harness.test("world models: small props never collide, big ones only low and thick", function()
	for kind, d in Wiring.decor do
		if not d.solid then
			Harness.truthy(not d.landmark, `{kind}: landmarks keep their own solid rocks`)
		end
	end
	for _, name in { "Mushroom", "Camp", "Sign" } do
		local found = false
		for kind, d in Wiring.decor do
			if d.name == name then
				found = true
				Harness.eq(d.solid, false, `{kind} must be walk-through`)
			end
		end
		Harness.truthy(found or name == "Sign", `{name} not wired`)
	end
	for kind, d in Wiring.decor do
		if d.solid and not d.landmark then
			for v = 1, 1000, 37 do
				for _, s in Wiring.kitSpec(d.name, v).parts do
					if s.collide then
						local b = Kit.partBounds(s)
						Harness.truthy(b.minY < 1, `{kind}: solid {s.name} floats`)
						Harness.truthy(
							math.min(s.sx, s.sz) >= 0.5,
							`{kind}: solid {s.name} is a thin stick`
						)
					end
				end
			end
		end
	end
	-- solid landmark pieces are low enough to jump onto, so nobody is ever trapped
	for _, kind in { "pool", "lavapool" } do
		local d = Wiring.decor[kind]
		local list = Wiring.landmarkSpec(d.name, Wiring.decorScale(kind, 1.7))
		for _, p in list.parts do
			if p.collide then
				local top = p.pos[2] + p.size[2] / 2
				Harness.truthy(top <= 6, `{kind}: solid {p.name} is {top} studs tall`)
			end
		end
	end
end)

Harness.test("world models: the server's parts are in every wired model", function()
	local P = Wiring.PART
	for _, text in { "TRADE HUT", "TRADE POST" } do
		local hut = Wiring.kitSpec("TradeHut", 1, text)
		local counter = partNamed(hut, P.counter)
		Harness.truthy(counter ~= nil, "TradeHut has no Counter (VSSellPrompt)")
		if counter ~= nil then
			Harness.truthy(counter.collide, "the counter is solid (a prompt needs a part)")
		end
		local sign = partNamed(hut, "Sign")
		Harness.truthy(sign ~= nil and sign.text == text, `hut sign says {text}`)
	end
	for zoneId = 2, 5 do
		local accent = "#ABCDEF"
		local gate =
			Registry.spec("Gate", { style = Wiring.STYLE, accent = accent, ground = "#123456" })
		local plate = partNamed(gate, P.gatePlate)
		Harness.truthy(plate ~= nil, `gate {zoneId}: no GatePlate (VSGate)`)
		Harness.truthy(partNamed(gate, P.gateBeam) ~= nil, "gate: no Beam (price sign)")
		if plate ~= nil then
			Harness.eq(plate.collide, false, "the gate plate never blocks")
			Harness.eq(plate.color, accent, "the plate glows in the zone colour")
			Harness.truthy(plate.sy <= 0.5, "the plate lies flat")
		end
		-- the opening stays walk-through at the big island's gate scale
		for _, s in gate.parts do
			if s.collide then
				local b = Kit.partBounds(s)
				Harness.truthy(
					b.minX * WorldPlan.GATE_SCALE >= 10 or b.maxX * WorldPlan.GATE_SCALE <= -10,
					`solid {s.name} in the gate opening`
				)
			end
		end
	end
	local sign = Wiring.kitSpec("Sign", 3, "Fern Forest")
	local board = partNamed(sign, P.signBoard)
	Harness.truthy(board ~= nil and board.text == "Fern Forest", "sign board text")
	local volcano = Wiring.landmarkSpec("volcano", 0.5)
	for _, name in { P.craterLava, P.craterGlow, P.cone } do
		Harness.truthy(listHas(volcano, name) ~= nil, `volcano has no {name}`)
	end
	local lava = listHas(volcano, P.craterLava)
	Harness.truthy(lava ~= nil and lava.group == "glow", "crater lava pulses")
	local smoke = false
	for _, f in volcano.fx do
		smoke = smoke or f.kind == "smoke"
	end
	Harness.truthy(smoke, "the crater smokes")
	local lighthouse = Wiring.landmarkSpec("lighthouse", 1)
	Harness.truthy(lighthouse.pivots.beam ~= nil, "lighthouse beam pivot")
	-- lava and water are decor only: nothing in the pools has a script hook, only parts and fx
	for _, kind in { "lava", "spring" } do
		local list = Wiring.landmarkSpec(kind, 0.5)
		Harness.truthy(#list.parts > 0, kind)
	end
end)

Harness.test("world models: the Trade Hut fits the hub and faces the pads", function()
	local hub = plan.hub
	local m = Wiring.kitSpec("TradeHut", 1, "TRADE HUT")
	local b = Kit.bounds(m)
	local k = Wiring.HUT_SCALE
	-- hub frame: the hut looks inland, so model z runs along +a and model x along -b
	local a0, a1 = hub.hutA + b.minZ * k, hub.hutA + b.maxZ * k
	local b0, b1 = -b.maxX * k, -b.minX * k
	Harness.truthy(a0 >= hub.hut.a0 and a1 <= hub.hut.a1, `hut a {a0}..{a1}`)
	Harness.truthy(b0 >= hub.hut.b0 and b1 <= hub.hut.b1, `hut b {b0}..{b1}`)
	-- the counter faces the middle pad, and the prompt there is within selling range of it
	local counter = partNamed(m, Wiring.PART.counter)
	Harness.truthy(counter ~= nil, "counter")
	if counter ~= nil then
		local ca = hub.hutA + counter.z * k
		Harness.truthy(ca < hub.hutA, "the counter is on the pads' side")
		Harness.truthy(math.abs(ca - hub.pads[1].a) < W.sellRange, "counter near the middle pad")
	end
end)

Harness.test("world models: Trade Post stalls sit behind their pads, clear of the gates", function()
	local m = Wiring.kitSpec("TradeHut", 1, "TRADE POST")
	local b = Kit.bounds(m)
	local k = Wiring.POST_SCALE
	local hutZ = Wiring.postHutZ(plan.posts[1].counterA)
	local gate = Wiring.kitSpec("Gate", 1)
	local gb = Kit.bounds(gate)
	for _, p in plan.posts do
		local counter = partNamed(m, Wiring.PART.counter)
		Harness.truthy(counter ~= nil, "post counter")
		if counter ~= nil then
			Harness.near(hutZ + counter.z * k, p.counterA, 1e-9, "counter stands counterA out")
		end
		-- post frame: z out to sea; the stall starts just behind the pad and stays in its zone
		local zFront, zBack = hutZ + b.minZ * k, hutZ + b.maxZ * k
		Harness.truthy(zFront > 3, `stall front {zFront} sits on the pad`)
		local zone = W.zones[p.zoneId]
		local r = math.sqrt(p.x * p.x + p.z * p.z)
		local halfW = math.max(-b.minX, b.maxX) * k
		Harness.truthy(
			math.sqrt((r + zBack) ^ 2 + halfW ^ 2) < zone.outer,
			"the stall stays inside its zone"
		)
		-- sideways the stall stays clear of its gate's pillars (gate line = post offset `side`)
		local side = W.tradePost.side
		local pillarEdge = gb.maxX * WorldPlan.GATE_SCALE
		Harness.truthy(side - halfW > pillarEdge, `stall {side - halfW} vs pillar {pillarEdge}`)
		Harness.truthy(zBack < WorldPlan.POST_REACH, "decor keeps clear of the whole stall")
	end
end)

Harness.test("world models: zone signs stand inside each gate, beside the opening", function()
	Harness.eq(#plan.signs, #plan.gates)
	local signHalf = Wiring.kitSpec("Sign", 1, "X").halfX * 1.4
	for _, s in plan.signs do
		local zone = W.zones[s.zoneId]
		Harness.eq(s.text, zone.name)
		local r = math.sqrt(s.x * s.x + s.z * s.z)
		Harness.truthy(r < zone.outer - 4 and r > zone.inner + 4, "sign inside its zone")
		for _, g in plan.gates do
			if g.zoneId == s.zoneId then
				-- sideways distance from the gate line must clear the arch
				local tx, tz = -g.uz, g.ux
				local off = math.abs((s.x - g.x) * tx + (s.z - g.z) * tz)
				Harness.truthy(off - signHalf > 12 * g.scale, `sign {s.zoneId} in the gate`)
			end
		end
		for _, p in plan.posts do
			Harness.truthy(dist(s.x, s.z, p.x, p.z) > p.clearRadius + 10, "sign on a post")
		end
		for _, v in plan.vents do
			Harness.truthy(dist(s.x, s.z, v.x, v.z) > 10, "sign on a vent")
		end
	end
end)

Harness.test("world models: the volcano fits the Lava Heart's inner edge", function()
	local scale = Wiring.volcanoScale(plan.coneRadius)
	local reach, top = Wiring.volcanoBounds(scale)
	Harness.truthy(reach <= plan.coneRadius - 0.99, `volcano reaches {reach}`)
	Harness.truthy(reach >= plan.coneRadius - 2, "volcano fills the inner circle")
	Harness.truthy(top >= 60 and top <= 120, `volcano is {top} tall`)
	-- the vents (geysers) all stand outside the foot
	for _, v in plan.vents do
		Harness.truthy(math.sqrt(v.x * v.x + v.z * v.z) > reach + 4, "vent under the volcano")
	end
end)

Harness.test("world models: the lighthouse stands off the beach near the hub", function()
	local spot = Wiring.lighthouseSpot(plan.hub.angleDeg, plan.outerRadius)
	local r = math.sqrt(spot.x * spot.x + spot.z * spot.z)
	-- outside the invisible wall: nobody can reach it, it covers no ash and no sea path
	Harness.truthy(r - spot.isletRadius > plan.wallRadius + 4, "islet outside the wall")
	Harness.truthy(dist(spot.x, spot.z, plan.hub.x, plan.hub.z) < 160, "lighthouse near the hub")
	local reach = listReach(Wiring.landmarkSpec("lighthouse", 1))
	Harness.truthy(reach <= spot.isletRadius + 2, `lighthouse foot {reach} fits its islet`)
	Harness.truthy(spot.y > -1.2 and spot.y < 0.5, "islet top just above the water")
end)
