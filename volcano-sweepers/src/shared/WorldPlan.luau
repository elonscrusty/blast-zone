--!strict
-- Pure layout plan for the island scenery. NO Roblox types in here (Lune can run it): positions are
-- plain numbers, colours are hex strings. The server's World builder turns this plan into Parts.
--
--   WorldPlan.default()     the plan for Config.World, built once and cached
--   WorldPlan.build(w)      build a plan for any world table (tests use other seeds)
--   WorldPlan.postSpots(w)  where the Trade Posts stand (Ash/Layout keeps their circles clear)
--
-- Hub frame: "a" runs from the hub centre AWAY from the volcano (towards the sea), "b" runs sideways.
-- Everything in the hub is laid out in (a, b) so it is easy to test; toWorld() converts to (x, z).
-- The hub layout is designed for Config.World.hub.clearRadius = 22 (all hub objects stay inside it).

local Config = require("./Config")
local Rng = require("./Rng")

export type World = typeof(Config.World)

export type HubPt = { x: number, z: number, a: number, b: number }
export type Circle = { name: string, a: number, b: number, r: number }
export type Rect = { name: string, a0: number, a1: number, b0: number, b1: number }

export type Hub = {
	x: number,
	z: number,
	angleDeg: number,
	ux: number, -- unit vector pointing away from the volcano
	uz: number,
	tx: number, -- unit vector sideways
	tz: number,
	clearRadius: number,
	spawns: { HubPt },
	pads: { HubPt }, -- sell pads (round, 10 studs across)
	hutA: number, -- hut body centre along "a"
	hut: Rect, -- hut footprint including its awning
	signpost: HubPt, -- "gates this way"
	tutorial: HubPt, -- "Sweep the ash!"
	circles: { Circle },
	rects: { Rect },
}

export type Gate = {
	zoneId: number,
	x: number,
	z: number,
	radius: number,
	ux: number,
	uz: number,
	scale: number, -- size of the arch (1 = the first, small island's gate)
}

-- A Trade Post: a small sell stall just inside the outer edge of zones 2..5, beside the gate.
-- (ux, uz) points away from the volcano (out to sea), (tx, tz) sideways. The sell pad is at
-- (x, z); the counter stands `counterA` studs further out.
export type Post = {
	zoneId: number,
	x: number,
	z: number,
	ux: number,
	uz: number,
	tx: number,
	tz: number,
	clearRadius: number,
	counterA: number,
}

-- One straight piece of a ring: centre, unit direction along the ring, length.
export type Seg = { x: number, z: number, dx: number, dz: number, len: number }
export type Ring = { zoneId: number, inner: number, outer: number, mid: number, segs: { Seg } }
export type Rope = { zoneId: number, radius: number, segs: { Seg } }

export type Tier = { r: number, y: number, h: number, color: string }
export type Streak = { tier: number, angle: number }
export type Volcano = {
	scale: number, -- 1 = the first, small island's volcano (base radius 30)
	baseRadius: number,
	tiers: { Tier },
	rimR: number,
	rimY: number,
	rimH: number,
	lavaR: number,
	topY: number,
	streaks: { Streak },
}

export type Vent = { x: number, z: number, zone: number }

export type Item = {
	kind: string,
	zone: number,
	x: number,
	z: number,
	rot: number, -- radians about Y
	scale: number,
	v: number, -- 1..1000, picks colour/shape variants
}

export type Plan = {
	seed: number,
	hub: Hub,
	gates: { Gate },
	posts: { Post },
	rings: { Ring }, -- ground blocks for zones 1..4 (zone 5 is a disc)
	ropes: { Rope }, -- glowing line at each ring boundary
	wallRadius: number,
	wall: { Seg },
	volcano: Volcano,
	vents: { Vent },
	decor: { Item },
	counts: { [string]: number },
	coneRadius: number,
	outerRadius: number,
	boundaries: { number },
}

local WorldPlan = {}

-- Rough Part count per decor item (the builder makes about this many). Used for the budget test.
WorldPlan.partCost = {
	palm = 12,
	shell = 1,
	umbrella = 5,
	rock = 2,
	crab = 3,
	fern = 5,
	mushroom = 5,
	trunk = 4,
	firefly = 1,
	pool = 2,
	pinkrock = 2,
	spire = 4,
	rib = 4,
	crack = 1,
	lavapool = 3,
	shard = 1,
	ember = 1,
} :: { [string]: number }

WorldPlan.ventCost = 2
WorldPlan.hubCost = 130 -- hut, pads, spawns, signs (generous)
WorldPlan.gateCost = 16
WorldPlan.postCost = 22 -- pad, counter, posts, roof, sign
WorldPlan.GATE_SCALE = 1.5 -- the arches are bigger on the big island (seen from further away)
WorldPlan.RING_PIECE = 16 -- studs: target length of one coloured ground piece (at the ring middle)
WorldPlan.ROPE_PIECE = 20 -- studs: target length of one glowing boundary line piece
WorldPlan.volcanoCost = 60
WorldPlan.extraCost = 25 -- water, foam, colliders, zone 5 disc

local TAU = math.pi * 2

-- ===== small helpers =====

local function hexToRgb(h: string): (number, number, number)
	local r = tonumber(string.sub(h, 2, 3), 16) or 0
	local g = tonumber(string.sub(h, 4, 5), 16) or 0
	local b = tonumber(string.sub(h, 6, 7), 16) or 0
	return r, g, b
end

function WorldPlan.lerpHex(a: string, b: string, t: number): string
	local ar, ag, ab = hexToRgb(a)
	local br, bg, bb = hexToRgb(b)
	local function mix(p: number, q: number): number
		return math.clamp(math.floor(p + (q - p) * t + 0.5), 0, 255)
	end
	return string.format("#%02X%02X%02X", mix(ar, br), mix(ag, bg), mix(ab, bb))
end

function WorldPlan.toWorld(hub: Hub, a: number, b: number): (number, number)
	return hub.x + hub.ux * a + hub.tx * b, hub.z + hub.uz * a + hub.tz * b
end

-- Straight pieces around a circle: every piece's two ends sit exactly on the circle. About
-- targetLen long each.
function WorldPlan.ringSegments(radius: number, targetLen: number): { Seg }
	local n = math.max(3, math.ceil(TAU * radius / targetLen))
	local step = TAU / n
	local out: { Seg } = {}
	for k = 0, n - 1 do
		local a0 = k * step
		local a1 = a0 + step
		local x0, z0 = radius * math.cos(a0), radius * math.sin(a0)
		local x1, z1 = radius * math.cos(a1), radius * math.sin(a1)
		local dx, dz = x1 - x0, z1 - z0
		local len = math.sqrt(dx * dx + dz * dz)
		table.insert(
			out,
			{ x = (x0 + x1) / 2, z = (z0 + z1) / 2, dx = dx / len, dz = dz / len, len = len }
		)
	end
	return out
end

-- ===== hub =====

local function buildHub(world: World): Hub
	local ang = math.rad(world.hub.angleDeg)
	local ux, uz = math.cos(ang), math.sin(ang)
	local tx, tz = -uz, ux
	local hx, hz = world.hub.radius * ux, world.hub.radius * uz

	local function pt(a: number, b: number): HubPt
		return { x = hx + ux * a + tx * b, z = hz + uz * a + tz * b, a = a, b = b }
	end

	local spawns: { HubPt } = {}
	for j = 0, 7 do
		local phi = math.rad(110 + 20 * j)
		table.insert(spawns, pt(18 * math.cos(phi), 18 * math.sin(phi)))
	end

	local pads = { pt(-1, 0), pt(-1, 10.6), pt(-1, -10.6) }
	local hutA = 12
	local hut: Rect = { name = "hut", a0 = 4.5, a1 = 17, b0 = -7.5, b1 = 7.5 }
	local signpost = pt(-8, 0)
	local tutorial = pt(-14, 0)

	local circles: { Circle } = {}
	for i, s in spawns do
		table.insert(circles, { name = `spawn{i}`, a = s.a, b = s.b, r = 2.6 })
	end
	for i, p in pads do
		table.insert(circles, { name = `pad{i}`, a = p.a, b = p.b, r = 5 })
	end
	table.insert(circles, { name = "signpost", a = signpost.a, b = signpost.b, r = 1.6 })
	table.insert(circles, { name = "tutorial", a = tutorial.a, b = tutorial.b, r = 2 })

	return {
		x = hx,
		z = hz,
		angleDeg = world.hub.angleDeg,
		ux = ux,
		uz = uz,
		tx = tx,
		tz = tz,
		clearRadius = world.hub.clearRadius,
		spawns = spawns,
		pads = pads,
		hutA = hutA,
		hut = hut,
		signpost = signpost,
		tutorial = tutorial,
		circles = circles,
		rects = { hut },
	}
end

-- ===== volcano =====

local function buildVolcano(world: World, coneInner: number): Volcano
	local rng = Rng.new(world.seed + 31337)
	local tiers: { Tier } = {}
	local count = 10
	local baseR = coneInner + 0.2
	-- the first island's cone had a 30 stud base; everything grows with it (heights a bit less, so
	-- the big cone stays a friendly round hill and not a tower)
	local s = baseR / 30.2
	local tierH = 4.4 * s * 0.85
	local topR = 14.5 * s
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local r = topR + (baseR - topR) * (1 - t) ^ 1.35
		local color = WorldPlan.lerpHex("#6B4A44", "#C2492F", t ^ 0.9)
		table.insert(tiers, { r = r, y = i * tierH, h = tierH, color = color })
	end
	local rimY = count * tierH
	local rimH = 3 * s * 0.85
	local streaks: { Streak } = {}
	for k = 0, 5 do
		local base = math.rad(60 * k + 15)
		for i = 3, count do
			if rng:chance(0.7) then
				table.insert(streaks, { tier = i, angle = base + rng:range(-0.05, 0.05) })
			end
		end
	end
	return {
		scale = s,
		baseRadius = baseR,
		tiers = tiers,
		rimR = topR + 0.6 * s,
		rimY = rimY,
		rimH = rimH,
		lavaR = 11.2 * s,
		topY = rimY + rimH,
		streaks = streaks,
	}
end

-- ===== decor =====

type Spec = {
	kind: string,
	zone: number,
	count: number,
	-- allowed radius ranges as shares of the zone's ring: 0 = its inner edge, 1 = its outer edge
	-- (so the decor follows Config.World when the island changes size)
	bands: { { number } },
	pad: number, -- clearance radius at scale 1
	minScale: number,
	maxScale: number,
	free: boolean?, -- tiny items: only keep out of hazards, may overlap other decor
}

-- The island is big, so the scenery is sparse landmarks (palms, trunks, spires, pools drawn
-- bigger) plus a sprinkle of small things, with about the same Part count as the small island.
local SPECS: { Spec } = {
	-- Sunny Beach
	{
		kind = "palm",
		zone = 1,
		count = 16,
		bands = { { 0.62, 0.92 } },
		pad = 3,
		minScale = 1.3,
		maxScale = 1.9,
	},
	{
		kind = "umbrella",
		zone = 1,
		count = 8,
		bands = { { 0.17, 0.92 } },
		pad = 4,
		minScale = 1,
		maxScale = 1.3,
	},
	{
		kind = "rock",
		zone = 1,
		count = 20,
		bands = { { 0.07, 0.27 }, { 0.77, 0.93 } },
		pad = 2.5,
		minScale = 1.4,
		maxScale = 2.6,
	},
	{
		kind = "crab",
		zone = 1,
		count = 8,
		bands = { { 0.1, 0.93 } },
		pad = 0.8,
		minScale = 1,
		maxScale = 1.4,
		free = true,
	},
	{
		kind = "shell",
		zone = 1,
		count = 30,
		bands = { { 0.08, 0.93 } },
		pad = 0.6,
		minScale = 1,
		maxScale = 1.6,
		free = true,
	},
	-- Fern Forest
	{
		kind = "trunk",
		zone = 2,
		count = 16,
		bands = { { 0.08, 0.24 }, { 0.76, 0.92 } },
		pad = 3,
		minScale = 1.3,
		maxScale = 1.9,
	},
	{
		kind = "fern",
		zone = 2,
		count = 20,
		bands = { { 0.08, 0.92 } },
		pad = 2.5,
		minScale = 1.3,
		maxScale = 2,
	},
	{
		kind = "mushroom",
		zone = 2,
		count = 16,
		bands = { { 0.08, 0.92 } },
		pad = 1.5,
		minScale = 1.2,
		maxScale = 2.2,
	},
	{
		kind = "firefly",
		zone = 2,
		count = 30,
		bands = { { 0.06, 0.94 } },
		pad = 0.5,
		minScale = 1,
		maxScale = 1,
		free = true,
	},
	-- Hot Springs
	{
		kind = "pool",
		zone = 3,
		count = 14,
		bands = { { 0.14, 0.86 } },
		pad = 7,
		minScale = 1.2,
		maxScale = 1.8,
	},
	{
		kind = "pinkrock",
		zone = 3,
		count = 26,
		bands = { { 0.05, 0.24 }, { 0.71, 0.95 } },
		pad = 2.5,
		minScale = 1.3,
		maxScale = 2.4,
	},
	-- Crater Rim
	{
		kind = "spire",
		zone = 4,
		count = 16,
		bands = { { 0.06, 0.28 }, { 0.72, 0.94 } },
		pad = 3,
		minScale = 1.4,
		maxScale = 2.4,
	},
	{
		kind = "rib",
		zone = 4,
		count = 10,
		bands = { { 0.11, 0.92 } },
		pad = 5,
		minScale = 1.4,
		maxScale = 2,
	},
	{
		kind = "crack",
		zone = 4,
		count = 44,
		bands = { { 0.03, 0.97 } },
		pad = 1,
		minScale = 1.2,
		maxScale = 2.2,
		free = true,
	},
	-- Lava Heart
	{
		kind = "lavapool",
		zone = 5,
		count = 10,
		bands = { { 0.19, 0.88 } },
		pad = 7,
		minScale = 1.1,
		maxScale = 1.7,
	},
	{
		kind = "shard",
		zone = 5,
		count = 18,
		bands = { { 0.09, 0.31 }, { 0.75, 0.94 } },
		pad = 1.8,
		minScale = 1.2,
		maxScale = 2.2,
	},
	{
		kind = "ember",
		zone = 5,
		count = 10,
		bands = { { 0.12, 0.88 } },
		pad = 0.5,
		minScale = 1,
		maxScale = 1,
		free = true,
	},
	{
		kind = "crack",
		zone = 5,
		count = 14,
		bands = { { 0.09, 0.94 } },
		pad = 1,
		minScale = 1.2,
		maxScale = 2.2,
		free = true,
	},
}

type Ctx = {
	hub: Hub,
	gates: { Gate },
	posts: { Post },
	vents: { Vent },
	rings: { [number]: { inner: number, outer: number } }, -- zone id -> its radii
	boundaries: { number },
	coneRadius: number,
	outerRadius: number,
}

local function blocked(ctx: Ctx, x: number, z: number, pad: number): boolean
	local hx, hz = x - ctx.hub.x, z - ctx.hub.z
	local lim = ctx.hub.clearRadius + pad + 1
	if hx * hx + hz * hz < lim * lim then
		return true
	end
	local r = math.sqrt(x * x + z * z)
	if r < ctx.coneRadius + pad + 1 then
		return true
	end
	if r > ctx.outerRadius - pad - 1.5 then
		return true
	end
	for _, rb in ctx.boundaries do
		if math.abs(r - rb) < pad + 1.5 then
			return true
		end
	end
	for _, g in ctx.gates do
		local dx, dz = x - g.x, z - g.z
		local gl = 14 * g.scale + pad
		if dx * dx + dz * dz < gl * gl then
			return true
		end
	end
	for _, p in ctx.posts do
		local dx, dz = x - p.x, z - p.z
		local pl = p.clearRadius + 2 + pad
		if dx * dx + dz * dz < pl * pl then
			return true
		end
	end
	for _, v in ctx.vents do
		local dx, dz = x - v.x, z - v.z
		local vl = 4 + pad
		if dx * dx + dz * dz < vl * vl then
			return true
		end
	end
	return false
end

type Placed = { xs: { number }, zs: { number }, rs: { number } }

local function overlaps(placed: Placed, x: number, z: number, r: number): boolean
	for i = 1, #placed.xs do
		local dx, dz = x - placed.xs[i], z - placed.zs[i]
		local lim = r + placed.rs[i]
		if dx * dx + dz * dz < lim * lim then
			return true
		end
	end
	return false
end

local function scatter(ctx: Ctx, rng: Rng.Rng, spec: Spec, placed: Placed, out: { Item })
	local made = 0
	local tries = 0
	local maxTries = spec.count * 80
	local ring = ctx.rings[spec.zone]
	if ring == nil then
		return
	end
	local width = ring.outer - ring.inner
	while made < spec.count and tries < maxTries do
		tries += 1
		local band = spec.bands[rng:int(1, #spec.bands)]
		local lo, hi = ring.inner + band[1] * width, ring.inner + band[2] * width
		local r = math.sqrt(rng:range(lo * lo, hi * hi))
		local ang = rng:range(0, TAU)
		local scale = rng:range(spec.minScale, spec.maxScale)
		local rot = rng:range(0, TAU)
		local v = rng:int(1, 1000)
		local x, z = r * math.cos(ang), r * math.sin(ang)
		local pad = spec.pad * scale
		if
			not blocked(ctx, x, z, pad) and (spec.free == true or not overlaps(placed, x, z, pad))
		then
			if spec.free ~= true then
				table.insert(placed.xs, x)
				table.insert(placed.zs, z)
				table.insert(placed.rs, pad)
			end
			table.insert(out, {
				kind = spec.kind,
				zone = spec.zone,
				x = x,
				z = z,
				rot = rot,
				scale = scale,
				v = v,
			})
			made += 1
		end
	end
end

-- Geyser vents in each of zones 3..5, about one per VENT_SPACING studs around the ring (at least
-- 3), so a geyser is never far from whoever is sweeping there. Never close to the gate line.
WorldPlan.VENT_SPACING = 190

local function buildVents(world: World, hubAngleDeg: number): { Vent }
	local rng = Rng.new(world.seed + 4242)
	local offsets: { [number]: number } = { [3] = 20, [4] = 60, [5] = 100 }
	local vents: { Vent } = {}
	for _, z in world.zones do
		local offset = offsets[z.id]
		if offset ~= nil then
			local mid = (z.inner + z.outer) / 2
			local span = (z.outer - z.inner) / 2 - 6
			local n = math.max(3, math.floor(TAU * mid / WorldPlan.VENT_SPACING + 0.5))
			local jitter = math.min(10, 120 / n)
			for k = 0, n - 1 do
				local deg = offset + k * 360 / n + rng:range(-jitter, jitter)
				-- keep clear of the gate line (the hub direction) and the Trade Post beside it
				local diff = (deg - hubAngleDeg + 540) % 360 - 180
				if math.abs(diff) < 14 then
					deg += if diff >= 0 then 14 else -14
				end
				local r = mid + rng:range(-span, span)
				local a = math.rad(deg)
				table.insert(vents, { x = r * math.cos(a), z = r * math.sin(a), zone = z.id })
			end
		end
	end
	return vents
end

-- ===== trade posts =====

-- Where the Trade Posts stand: one just inside the outer edge of every zone except the outermost
-- (the hub serves that one), `tradePost.side` studs beside the gate line. Pure maths from the world
-- table; Ash/Layout calls this too, so the ash never covers a stall.
function WorldPlan.postSpots(world: World): { Post }
	local cfg = world.tradePost
	local out: { Post } = {}
	if cfg == nil then
		return out
	end
	local outerRadius = 0
	for _, z in world.zones do
		outerRadius = math.max(outerRadius, z.outer)
	end
	local base = math.rad(world.hub.angleDeg)
	for _, z in world.zones do
		if z.outer < outerRadius then
			local r = z.outer - cfg.inset
			local ang = base + cfg.side / r
			local ux, uz = math.cos(ang), math.sin(ang)
			table.insert(out, {
				zoneId = z.id,
				x = r * ux,
				z = r * uz,
				ux = ux,
				uz = uz,
				tx = -uz,
				tz = ux,
				clearRadius = cfg.clearRadius,
				counterA = 6,
			})
		end
	end
	table.sort(out, function(a: Post, b: Post): boolean
		return a.zoneId < b.zoneId
	end)
	return out
end

-- ===== the plan =====

function WorldPlan.build(world: World): Plan
	local hub = buildHub(world)

	local coneInner = math.huge
	local outerRadius = 0
	local boundaries: { number } = {}
	for _, z in world.zones do
		coneInner = math.min(coneInner, z.inner)
		outerRadius = math.max(outerRadius, z.outer)
	end
	local volcano = buildVolcano(world, coneInner)

	-- gates: one per zone 2..5 at the zone's outer boundary, on the hub direction line
	local gates: { Gate } = {}
	local ropes: { Rope } = {}
	local rings: { Ring } = {}
	local a = math.rad(world.hub.angleDeg)
	for _, z in world.zones do
		if z.id >= 2 then
			table.insert(boundaries, z.outer)
			table.insert(gates, {
				zoneId = z.id,
				x = z.outer * math.cos(a),
				z = z.outer * math.sin(a),
				radius = z.outer,
				ux = math.cos(a),
				uz = math.sin(a),
				scale = WorldPlan.GATE_SCALE,
			})
			table.insert(ropes, {
				zoneId = z.id,
				radius = z.outer,
				segs = WorldPlan.ringSegments(z.outer, WorldPlan.ROPE_PIECE),
			})
		end
		if z.id <= 4 then
			local mid = (z.inner + z.outer) / 2
			table.insert(rings, {
				zoneId = z.id,
				inner = z.inner,
				outer = z.outer,
				mid = mid,
				segs = WorldPlan.ringSegments(mid, WorldPlan.RING_PIECE),
			})
		end
	end
	table.insert(boundaries, coneInner) -- the cone edge is a boundary too

	local wallRadius = outerRadius + 4
	local vents = buildVents(world, world.hub.angleDeg)
	local posts = WorldPlan.postSpots(world)
	local ringOf: { [number]: { inner: number, outer: number } } = {}
	for _, z in world.zones do
		ringOf[z.id] = { inner = z.inner, outer = z.outer }
	end

	local ctx: Ctx = {
		hub = hub,
		gates = gates,
		posts = posts,
		vents = vents,
		rings = ringOf,
		boundaries = boundaries,
		coneRadius = volcano.baseRadius,
		outerRadius = outerRadius,
	}

	local decor: { Item } = {}
	local counts: { [string]: number } = {}
	for zoneId = 1, #world.zones do
		local rng = Rng.new(world.seed + zoneId * 104729)
		local placed: Placed = { xs = {}, zs = {}, rs = {} }
		for _, spec in SPECS do
			if spec.zone == zoneId then
				local before = #decor
				scatter(ctx, rng, spec, placed, decor)
				counts[spec.kind] = (counts[spec.kind] or 0) + (#decor - before)
			end
		end
	end

	return {
		seed = world.seed,
		hub = hub,
		gates = gates,
		posts = posts,
		rings = rings,
		ropes = ropes,
		wallRadius = wallRadius,
		wall = WorldPlan.ringSegments(wallRadius + 2, 52),
		volcano = volcano,
		vents = vents,
		decor = decor,
		counts = counts,
		coneRadius = volcano.baseRadius,
		outerRadius = outerRadius,
		boundaries = boundaries,
	}
end

-- Estimated total Part count of the finished world (decor + ground + hub + gates + volcano).
function WorldPlan.estimateParts(plan: Plan): number
	local total = WorldPlan.extraCost + WorldPlan.hubCost + WorldPlan.volcanoCost
	total += #plan.gates * WorldPlan.gateCost
	total += #plan.posts * WorldPlan.postCost
	total += #plan.vents * WorldPlan.ventCost
	total += #plan.wall
	for _, ring in plan.rings do
		total += #ring.segs
	end
	for _, rope in plan.ropes do
		total += #rope.segs
	end
	total += #plan.volcano.streaks
	for _, item in plan.decor do
		total += WorldPlan.partCost[item.kind] or 1
	end
	return total
end

local cached: Plan? = nil

function WorldPlan.default(): Plan
	local plan = cached
	if plan == nil then
		plan = WorldPlan.build(Config.World)
		cached = plan
	end
	return plan :: Plan
end

return WorldPlan
