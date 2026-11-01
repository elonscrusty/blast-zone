--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local WorldPlan = require("../src/shared/WorldPlan")

local W = Config.World
local plan = WorldPlan.build(W)

local function dist(x0: number, z0: number, x1: number, z1: number): number
	return math.sqrt((x0 - x1) ^ 2 + (z0 - z1) ^ 2)
end

local function zoneOfRadius(r: number): number?
	for _, z in W.zones do
		if r >= z.inner and r <= z.outer then
			return z.id
		end
	end
	return nil
end

local function serialise(p: WorldPlan.Plan): string
	local parts: { string } = {}
	for _, it in p.decor do
		table.insert(parts, `{it.kind}:{it.zone}:{it.x}:{it.z}:{it.rot}:{it.scale}:{it.v}`)
	end
	for _, v in p.vents do
		table.insert(parts, `vent:{v.zone}:{v.x}:{v.z}`)
	end
	return table.concat(parts, "|")
end

Harness.test("world plan: same seed gives identical lists, other seed differs", function()
	local again = WorldPlan.build(W)
	Harness.eq(serialise(plan), serialise(again))
	Harness.eq(#plan.decor, #again.decor)
	local other = table.clone(W)
	other.seed = W.seed + 1
	Harness.truthy(
		serialise(WorldPlan.build(other)) ~= serialise(plan),
		"seed must change the layout"
	)
	Harness.eq(WorldPlan.default().seed, W.seed)
end)

Harness.test("world plan: decor counts and part budget", function()
	Harness.truthy(#plan.decor >= 340, `too little decor: {#plan.decor}`)
	Harness.truthy(#plan.decor <= 900, `too much decor: {#plan.decor}`)
	for kind in WorldPlan.partCost do
		Harness.truthy(
			(plan.counts[kind] or 0) >= 4,
			`kind {kind} placed too few: {plan.counts[kind] or 0}`
		)
	end
	local total = WorldPlan.estimateParts(plan)
	Harness.truthy(total <= 2500, `estimated parts {total} over budget`)
	Harness.truthy(total >= 800, `estimated parts {total} suspiciously low`)
end)

Harness.test("world plan: decor stays out of the hub circle and the volcano cone", function()
	for i, it in plan.decor do
		local dh = dist(it.x, it.z, plan.hub.x, plan.hub.z)
		Harness.truthy(
			dh >= plan.hub.clearRadius,
			`item {i} {it.kind} inside the hub circle ({dh})`
		)
		local r = math.sqrt(it.x * it.x + it.z * it.z)
		Harness.truthy(r >= plan.coneRadius + 1, `item {i} {it.kind} inside the cone (r={r})`)
		Harness.truthy(r <= plan.outerRadius - 1, `item {i} {it.kind} off the island (r={r})`)
	end
end)

Harness.test("world plan: every item sits in its own zone ring, away from boundaries", function()
	for i, it in plan.decor do
		local r = math.sqrt(it.x * it.x + it.z * it.z)
		Harness.eq(zoneOfRadius(r), it.zone, `item {i} {it.kind} wrong zone at r={r}`)
		for _, rb in plan.boundaries do
			Harness.truthy(math.abs(r - rb) >= 1.5, `item {i} {it.kind} sits on the line at {rb}`)
		end
		Harness.truthy(it.v >= 1 and it.v <= 1000, "variant range")
		Harness.truthy(it.scale > 0, "scale")
	end
end)

Harness.test("world plan: decor keeps away from gates and vents", function()
	for i, it in plan.decor do
		for _, g in plan.gates do
			Harness.truthy(
				dist(it.x, it.z, g.x, g.z) >= 14,
				`item {i} {it.kind} blocks gate {g.zoneId}`
			)
		end
		for _, v in plan.vents do
			Harness.truthy(dist(it.x, it.z, v.x, v.z) >= 4, `item {i} {it.kind} on a vent`)
		end
	end
end)

Harness.test("world plan: gates sit exactly on the ring boundaries, one per zone 2..5", function()
	Harness.eq(#plan.gates, 4)
	for _, g in plan.gates do
		local zone = nil
		for _, z in W.zones do
			if z.id == g.zoneId then
				zone = z
			end
		end
		Harness.truthy(zone ~= nil, "gate has a zone")
		if zone then
			Harness.near(math.sqrt(g.x * g.x + g.z * g.z), zone.outer, 1e-6, "gate radius")
			Harness.near(g.radius, zone.outer, 1e-9)
		end
		Harness.truthy(g.zoneId >= 2 and g.zoneId <= 5, "gate zone id")
		-- on the hub direction line
		local ang = math.deg(math.atan2(g.z, g.x))
		Harness.near(ang, W.hub.angleDeg, 1e-6, "gate angle")
	end
end)

Harness.test("world plan: vents are inside zones 3..5", function()
	Harness.truthy(#plan.vents >= 8 and #plan.vents <= 12, `vent count {#plan.vents}`)
	for i, v in plan.vents do
		local r = math.sqrt(v.x * v.x + v.z * v.z)
		Harness.truthy(v.zone >= 3 and v.zone <= 5, "vent zone")
		Harness.eq(zoneOfRadius(r), v.zone, `vent {i} wrong zone at r={r}`)
		for _, rb in plan.boundaries do
			Harness.truthy(math.abs(r - rb) >= 3, `vent {i} too close to boundary {rb}`)
		end
		for _, g in plan.gates do
			Harness.truthy(dist(v.x, v.z, g.x, g.z) >= 14, "vent next to a gate")
		end
	end
end)

local function circleRectDist(c: WorldPlan.Circle, r: WorldPlan.Rect): number
	local nx = math.clamp(c.a, r.a0, r.a1)
	local nb = math.clamp(c.b, r.b0, r.b1)
	return math.sqrt((c.a - nx) ^ 2 + (c.b - nb) ^ 2)
end

Harness.test("world plan: hub objects fit the clear circle and do not overlap", function()
	local hub = plan.hub
	Harness.eq(#hub.spawns, 8)
	Harness.truthy(#hub.pads >= 1, "sell pads")
	for _, c in hub.circles do
		Harness.truthy(
			math.sqrt(c.a * c.a + c.b * c.b) + c.r <= hub.clearRadius + 0.01,
			`{c.name} leaves the hub circle`
		)
	end
	for _, r in hub.rects do
		for _, ca in { r.a0, r.a1 } do
			for _, cb in { r.b0, r.b1 } do
				Harness.truthy(
					math.sqrt(ca * ca + cb * cb) <= hub.clearRadius,
					`{r.name} corner outside the hub circle`
				)
			end
		end
	end
	for i = 1, #hub.circles do
		for j = i + 1, #hub.circles do
			local c1, c2 = hub.circles[i], hub.circles[j]
			local d = dist(c1.a, c1.b, c2.a, c2.b)
			-- sell pads may touch edge to edge, nothing may overlap
			Harness.truthy(d >= c1.r + c2.r - 0.05, `{c1.name} overlaps {c2.name}`)
		end
		for _, rect in hub.rects do
			Harness.truthy(
				circleRectDist(hub.circles[i], rect) >= hub.circles[i].r,
				`{hub.circles[i].name} overlaps {rect.name}`
			)
		end
	end
	-- the hub circle really is the one the ash layout clears
	Harness.near(math.sqrt(hub.x ^ 2 + hub.z ^ 2), W.hub.radius, 1e-6, "hub radius")
end)

Harness.test("world plan: gates stay clear of the hub", function()
	for _, g in plan.gates do
		Harness.truthy(
			dist(g.x, g.z, plan.hub.x, plan.hub.z) >= plan.hub.clearRadius + 9,
			"gate too near hub"
		)
	end
end)

Harness.test("world plan: toWorld matches stored hub points", function()
	for _, s in plan.hub.spawns do
		local x, z = WorldPlan.toWorld(plan.hub, s.a, s.b)
		Harness.near(x, s.x, 1e-9)
		Harness.near(z, s.z, 1e-9)
	end
end)

Harness.test("world plan: ring pieces lie on their circle and close the loop", function()
	local segs = WorldPlan.ringSegments(100, 12)
	local sum = 0
	for _, s in segs do
		Harness.near(math.sqrt(s.dx * s.dx + s.dz * s.dz), 1, 1e-9, "unit direction")
		Harness.truthy(s.len <= 12.01 and s.len > 6, "segment length")
		-- direction is perpendicular to the radius at the middle of the piece
		Harness.near(
			(s.x * s.dx + s.z * s.dz) / math.sqrt(s.x * s.x + s.z * s.z),
			0,
			1e-9,
			"tangent"
		)
		sum += s.len
	end
	Harness.truthy(sum > 2 * math.pi * 100 * 0.99 and sum < 2 * math.pi * 100 * 1.001, "perimeter")
	Harness.eq(#plan.rings, 4)
	Harness.eq(#plan.ropes, 4)
	for _, rope in plan.ropes do
		Harness.truthy(#rope.segs >= 20, "rope pieces")
	end
end)

Harness.test("world plan: volcano fits inside zone 5 and tapers", function()
	local v = plan.volcano
	local inner5 = 0
	for _, z in W.zones do
		if z.id == 5 then
			inner5 = z.inner
		end
	end
	Harness.truthy(v.baseRadius <= inner5 + 0.5, "cone base within zone 5 inner radius")
	Harness.truthy(v.baseRadius >= inner5, "cone fills the inner radius")
	local prev = math.huge
	for _, t in v.tiers do
		Harness.truthy(t.r < prev, "tiers shrink")
		prev = t.r
	end
	Harness.truthy(v.lavaR < v.rimR and v.rimR < v.tiers[1].r, "crater smaller than the base")
	Harness.truthy(v.topY > 30 and v.topY < 80, "volcano height")
	Harness.truthy(#v.streaks >= 10 and #v.streaks <= 60, "lava streak count")
	for _, s in v.streaks do
		Harness.truthy(s.tier >= 1 and s.tier <= #v.tiers, "streak tier")
	end
end)

Harness.test("world plan: lerpHex mixes colours", function()
	Harness.eq(WorldPlan.lerpHex("#000000", "#FFFFFF", 0), "#000000")
	Harness.eq(WorldPlan.lerpHex("#000000", "#FFFFFF", 1), "#FFFFFF")
	Harness.eq(WorldPlan.lerpHex("#FF0000", "#0000FF", 0.5), "#800080")
end)
