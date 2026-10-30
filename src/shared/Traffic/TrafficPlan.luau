--!strict
-- Pure rules for the night traffic (piece SL), tested in Lune. The server turns a map's roads into
-- lane segments; the client fills them with cars and moves them. Cars are only for show: they never
-- hit, block or shoot anything. A car stays inside one free stretch of its lane (no solid in the
-- way) and loops it. No Roblox services in here.

local Config = require("../Config")

export type Rect = { x0: number, z0: number, x1: number, z1: number }
export type Ground = { kind: string, x0: number, z0: number, x1: number, z1: number }
export type Solid = { blocksMove: boolean, x0: number, z0: number, x1: number, z1: number }

-- axis "x" runs east-west at z = fixed, axis "z" runs north-south at x = fixed. dir 1 = toward
-- larger coordinates. from < to, both along the axis.
export type Segment = { axis: string, dir: number, fixed: number, from: number, to: number }
export type Car = { seg: number, dist: number, speed: number, color: number }

local TrafficPlan = {}

local function cfg(): any
	return Config.Traffic
end

-- Take the blocked spans out of [a, b] and return what is left, longest-first order not needed.
local function freeSpans(
	a: number,
	b: number,
	blocked: { { number } },
	minLength: number
): { { number } }
	table.sort(blocked, function(p, q)
		return p[1] < q[1]
	end)
	local out: { { number } } = {}
	local cursor = a
	for _, span in blocked do
		if span[1] > cursor and span[1] - cursor >= minLength then
			table.insert(out, { cursor, span[1] })
		end
		cursor = math.max(cursor, span[2])
	end
	if b - cursor >= minLength then
		table.insert(out, { cursor, b })
	end
	return out
end

-- Two lanes (one each way, driving on the right) for every road wide and long enough, cut into the
-- stretches no solid touches. The result is the same for the same map every time.
function TrafficPlan.segments(ground: { Ground }, solids: { Solid }): { Segment }
	local c = cfg()
	local out: { Segment } = {}
	for _, g in ground do
		if g.kind ~= "road" then
			continue
		end
		local w, d = g.x1 - g.x0, g.z1 - g.z0
		local axis = if w >= d then "x" else "z"
		local width = math.min(w, d)
		local a = (if axis == "x" then g.x0 else g.z0) + c.edgeInset
		local b = (if axis == "x" then g.x1 else g.z1) - c.edgeInset
		if width < c.roadMinWidth or b - a < c.laneMinLength then
			continue
		end
		local centre = if axis == "x" then (g.z0 + g.z1) / 2 else (g.x0 + g.x1) / 2
		for _, dir in { 1, -1 } do
			-- Facing east the right-hand side is +z; facing south it is -x.
			local side = if axis == "x" then dir else -dir
			local fixed = centre + side * width / 4
			local blocked: { { number } } = {}
			for _, s in solids do
				if not s.blocksMove then
					continue
				end
				local lo, hi, near0, near1
				if axis == "x" then
					lo, hi, near0, near1 = s.x0, s.x1, s.z0, s.z1
				else
					lo, hi, near0, near1 = s.z0, s.z1, s.x0, s.x1
				end
				if fixed > near0 - c.solidMargin and fixed < near1 + c.solidMargin then
					table.insert(blocked, { lo - c.solidMargin, hi + c.solidMargin })
				end
			end
			for _, span in freeSpans(a, b, blocked, c.segmentMinLength) do
				table.insert(out, {
					axis = axis,
					dir = dir,
					fixed = fixed,
					from = span[1],
					to = span[2],
				})
			end
		end
	end
	return out
end

-- Small seeded generator so every client builds the same cars from the same seed.
local function nextRandom(state: number): (number, number)
	local s = (state * 1103515245 + 12345) % 2147483648
	return s, s / 2147483648
end

function TrafficPlan.length(seg: Segment): number
	return seg.to - seg.from
end

-- Cars for the segments: about one per studsPerCar of lane, at most maxCars, never more than fit
-- in a stretch with carGap between them. Cars of one stretch share a speed, so they never catch up.
function TrafficPlan.populate(segments: { Segment }, seed: number, maxCars: number): { Car }
	local c = cfg()
	local count = #segments
	if count == 0 or maxCars <= 0 then
		return {}
	end
	local total = 0
	local capacity: { number } = {}
	for i, seg in segments do
		local len = TrafficPlan.length(seg)
		total += len
		capacity[i] = math.max(1, math.floor(len / c.carGap))
	end
	local want = math.min(maxCars, math.max(1, math.floor(total / c.studsPerCar)))
	local assigned: { number } = table.create(count, 0)
	for _ = 1, want do
		local best, bestScore = 0, -1
		for i, seg in segments do
			if assigned[i] < capacity[i] then
				local score = TrafficPlan.length(seg) / (assigned[i] + 1)
				if score > bestScore then
					best, bestScore = i, score
				end
			end
		end
		if best == 0 then
			break
		end
		assigned[best] += 1
	end

	local state = math.floor(seed) % 2147483648
	local cars: { Car } = {}
	for i, seg in segments do
		local n = assigned[i]
		if n == 0 then
			continue
		end
		local r
		state, r = nextRandom(state)
		local speed = c.speedMin + r * (c.speedMax - c.speedMin)
		state, r = nextRandom(state)
		local offset = r
		local gap = TrafficPlan.length(seg) / n
		for k = 0, n - 1 do
			state, r = nextRandom(state)
			table.insert(cars, {
				seg = i,
				dist = (k + offset) % n * gap,
				speed = speed,
				color = 1 + math.floor(r * #c.colors) % #c.colors,
			})
		end
	end
	return cars
end

-- Where a car is, and which way it faces.
function TrafficPlan.pose(seg: Segment, dist: number): (number, number, number, number)
	local along = if seg.dir == 1 then seg.from + dist else seg.to - dist
	if seg.axis == "x" then
		return along, seg.fixed, seg.dir, 0
	end
	return seg.fixed, along, 0, seg.dir
end

-- New distance along the stretch; a car loops back to the start.
function TrafficPlan.advance(
	dist: number,
	length: number,
	speed: number,
	factor: number,
	dt: number
): number
	return (dist + speed * factor * dt) % length
end

-- Cars thin out at both ends of a stretch so the loop never pops. 0 = gone, 1 = solid.
function TrafficPlan.endAlpha(dist: number, length: number): number
	local fade = cfg().endFadeStuds
	return math.clamp(math.min(dist, length - dist) / fade, 0, 1)
end

-- Cars thin out around the local fighter so a car never hides who you are fighting.
function TrafficPlan.nearAlpha(distance: number): number
	local c = cfg()
	return math.clamp((distance - c.fadeInner) / (c.fadeOuter - c.fadeInner), 0, 1)
end

-- Distance from a point to a stretch (to the nearest point on its line).
function TrafficPlan.distanceTo(seg: Segment, x: number, z: number): number
	local along, across
	if seg.axis == "x" then
		along, across = x, z - seg.fixed
	else
		along, across = z, x - seg.fixed
	end
	local nearest = math.clamp(along, seg.from, seg.to)
	return math.sqrt((along - nearest) ^ 2 + across ^ 2)
end

-- Cars brake when a shot goes off near their stretch, hold, then speed up again.
-- `since` = seconds since the last shot near the stretch (nil = none).
function TrafficPlan.speedFactor(since: number?): number
	if since == nil then
		return 1
	end
	local c = cfg()
	if since <= c.slowHoldSeconds then
		return c.slowFactor
	end
	local back = math.clamp((since - c.slowHoldSeconds) / c.slowRecoverSeconds, 0, 1)
	return c.slowFactor + (1 - c.slowFactor) * back
end

-- Height of a car off the street. Cars on north-south lanes ride a little higher, so the two
-- never share a spot where the roads cross.
function TrafficPlan.height(seg: Segment): number
	local c = cfg()
	return c.hoverHeight + (if seg.axis == "z" then c.crossLift else 0)
end

return TrafficPlan
