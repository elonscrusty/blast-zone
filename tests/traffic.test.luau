--!strict
-- Piece SL: night traffic. The cars are looks only, so these checks are about the road stretches
-- they use (free of solids, on every map at every crowd size) and the small rules the client follows.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local RemoteDefs = require("../src/shared/RemoteDefs")
local Layout = require("../src/server/Arena/Layout")
local TrafficPlan = require("../src/shared/Traffic/TrafficPlan")

local cfg: any = Config.Traffic

local function road(x0: number, z0: number, x1: number, z1: number): TrafficPlan.Ground
	return { kind = "road", x0 = x0, z0 = z0, x1 = x1, z1 = z1 }
end

local function crate(x0: number, z0: number, x1: number, z1: number): TrafficPlan.Solid
	return { blocksMove = true, x0 = x0, z0 = z0, x1 = x1, z1 = z1 }
end

Harness.test("a long road gets one lane each way, driving on the right", function()
	local segs = TrafficPlan.segments({ road(-100, -10, 100, 10) }, {})
	Harness.eq(#segs, 2)
	local east, west = segs[1], segs[2]
	Harness.eq(east.axis, "x")
	Harness.eq(east.dir, 1)
	Harness.eq(east.fixed, 5, "facing east the right side is south (+z)")
	Harness.eq(west.dir, -1)
	Harness.eq(west.fixed, -5)
	Harness.eq(east.from, -100 + cfg.edgeInset)
	Harness.eq(east.to, 100 - cfg.edgeInset)
	local tall = TrafficPlan.segments({ road(-10, -100, 10, 100) }, {})
	Harness.eq(tall[1].axis, "z")
	Harness.eq(tall[1].fixed, -5, "facing south the right side is west (-x)")
	Harness.eq(tall[2].fixed, 5)
end)

Harness.test("roads that are narrow, short or not roads get no cars", function()
	Harness.eq(#TrafficPlan.segments({ road(-100, -4, 100, 4) }, {}), 0, "narrow")
	Harness.eq(#TrafficPlan.segments({ road(-15, -10, 15, 10) }, {}), 0, "short")
	local walk: TrafficPlan.Ground = { kind = "sidewalk", x0 = -100, z0 = -10, x1 = 100, z1 = 10 }
	Harness.eq(#TrafficPlan.segments({ walk }, {}), 0, "sidewalk")
end)

Harness.test(
	"a solid on a lane cuts it; one beside the lane or one that does not block does not",
	function()
		local ground = { road(-100, -10, 100, 10) }
		local cut = TrafficPlan.segments(ground, { crate(-2, 3, 2, 7) }) -- on the +z (east-bound) lane
		local east = 0
		for _, s in cut do
			if s.dir == 1 then
				east += 1
				Harness.truthy(
					s.to <= -2 - cfg.solidMargin + 0.001 or s.from >= 2 + cfg.solidMargin - 0.001,
					"keeps clear"
				)
			end
		end
		Harness.eq(east, 2, "east lane is in two pieces")
		Harness.eq(#cut, 3, "west lane untouched")
		Harness.eq(#TrafficPlan.segments(ground, { crate(-2, 40, 2, 44) }), 2, "far off the road")
		local soft: TrafficPlan.Solid = { blocksMove = false, x0 = -2, z0 = 3, x1 = 2, z1 = 7 }
		Harness.eq(#TrafficPlan.segments(ground, { soft }), 2, "does not block")
		-- a crate every 20 studs leaves nothing long enough
		local many: { TrafficPlan.Solid } = {}
		for x = -90, 90, 20 do
			table.insert(many, crate(x, 3, x + 2, 7))
		end
		Harness.eq(#TrafficPlan.segments(ground, many), 1, "only the open lane is left")
	end
)

Harness.test("every map at every crowd size has road stretches, clear of every solid", function()
	for _, scale in { 1, 1.3, 1.6 } do
		local zone = Config.zoneAt(scale)
		for _, id in { "A", "B", "C", "D", "E", "F" } do
			local spec = require(`../src/server/Arena/Layout{id}`)
			local layout = Layout.compile(spec, {
				scale = scale,
				minSpawns = Config.Arena.minSpawns,
				minContainers = Config.Arena.containerSpots,
				spawnClear = Config.Arena.spawnClearRadius,
				zoneRadius = zone.initialRadius,
			})
			local segs = TrafficPlan.segments(layout.ground, layout.solids)
			Harness.truthy(#segs >= 4, `{id} x{scale}: stretches ({#segs})`)
			Harness.truthy(#TrafficPlan.populate(segs, 7, cfg.maxCars) >= 3, `{id} x{scale}: cars`)
			for _, s in segs do
				Harness.truthy(
					TrafficPlan.length(s) >= cfg.segmentMinLength - 0.001,
					`{id}: long enough`
				)
				Harness.truthy(
					s.from >= -layout.half and s.to <= layout.half,
					`{id}: inside the arena`
				)
				for along = s.from, s.to, 2 do
					local x, z =
						if s.axis == "x" then along else s.fixed,
						if s.axis == "x" then s.fixed else along
					for _, solid in layout.solids do
						if solid.blocksMove then
							local inside = x > solid.x0 - cfg.solidMargin + 0.5
								and x < solid.x1 + cfg.solidMargin - 0.5
								and z > solid.z0 - cfg.solidMargin + 0.5
								and z < solid.z1 + cfg.solidMargin - 0.5
							if inside then
								error(
									`{id} x{scale}: a car would drive through {solid.id} at {x},{z}`
								)
							end
						end
					end
				end
			end
		end
	end
end)

Harness.test("the same seed gives the same cars; they stay in their stretch, spaced out", function()
	local segs = TrafficPlan.segments({ road(-100, -10, 100, 10), road(-10, -100, 10, 100) }, {})
	local a = TrafficPlan.populate(segs, 99, cfg.maxCars)
	local b = TrafficPlan.populate(segs, 99, cfg.maxCars)
	Harness.eq(#a, #b)
	for i, car in a do
		Harness.eq(car.dist, b[i].dist)
		Harness.eq(car.color, b[i].color)
	end
	Harness.truthy(#a >= 1 and #a <= cfg.maxCars, "count")
	local perSeg: { [number]: { TrafficPlan.Car } } = {}
	for _, car in a do
		local seg = segs[car.seg]
		Harness.truthy(car.dist >= 0 and car.dist < TrafficPlan.length(seg), "inside the stretch")
		Harness.truthy(car.color >= 1 and car.color <= #cfg.colors, "colour")
		Harness.truthy(car.speed >= cfg.speedMin and car.speed <= cfg.speedMax, "speed")
		perSeg[car.seg] = perSeg[car.seg] or {}
		table.insert(perSeg[car.seg], car)
	end
	for i, list in perSeg do
		local len = TrafficPlan.length(segs[i])
		for _, car in list do
			Harness.eq(car.speed, list[1].speed, "one stretch, one speed")
		end
		Harness.truthy(#list <= math.max(1, math.floor(len / cfg.carGap)), "fits")
		table.sort(list, function(p, q)
			return p.dist < q.dist
		end)
		for k = 2, #list do
			Harness.truthy(list[k].dist - list[k - 1].dist >= cfg.carGap - 0.01, "gap between cars")
		end
	end
end)

Harness.test("the cap holds, and no road or a cap of 0 means no cars", function()
	local segs = TrafficPlan.segments({ road(-100, -10, 100, 10), road(-10, -100, 10, 100) }, {})
	Harness.truthy(#TrafficPlan.populate(segs, 5, 3) <= 3, "cap 3")
	Harness.eq(#TrafficPlan.populate(segs, 5, 0), 0)
	Harness.eq(#TrafficPlan.populate({}, 5, 14), 0)
	Harness.truthy(cfg.phoneMaxCars < cfg.maxCars, "phones draw fewer")
end)

Harness.test("a car moves along its lane, loops, and faces the way it drives", function()
	local east: TrafficPlan.Segment = { axis = "x", dir = 1, fixed = 5, from = -50, to = 50 }
	local west: TrafficPlan.Segment = { axis = "x", dir = -1, fixed = -5, from = -50, to = 50 }
	local south: TrafficPlan.Segment = { axis = "z", dir = 1, fixed = -5, from = -50, to = 50 }
	local x, z, dx, dz = TrafficPlan.pose(east, 10)
	Harness.eq(x, -40)
	Harness.eq(z, 5)
	Harness.eq(dx, 1)
	Harness.eq(dz, 0)
	x, z, dx, dz = TrafficPlan.pose(west, 10)
	Harness.eq(x, 40)
	Harness.eq(dx, -1)
	x, z, dx, dz = TrafficPlan.pose(south, 0)
	Harness.eq(x, -5)
	Harness.eq(z, -50)
	Harness.eq(dz, 1)
	Harness.near(TrafficPlan.advance(10, 100, 20, 1, 0.5), 20)
	Harness.near(TrafficPlan.advance(95, 100, 20, 1, 0.5), 5, 0.001, "loops")
	Harness.near(TrafficPlan.advance(10, 100, 20, 0.2, 0.5), 12, 0.001, "braking")
end)

Harness.test("cars fade at the ends of a stretch and around the local fighter", function()
	Harness.eq(TrafficPlan.endAlpha(0, 100), 0)
	Harness.eq(TrafficPlan.endAlpha(50, 100), 1)
	Harness.eq(TrafficPlan.endAlpha(100, 100), 0)
	Harness.near(TrafficPlan.endAlpha(cfg.endFadeStuds / 2, 100), 0.5)
	Harness.eq(TrafficPlan.nearAlpha(0), 0, "on top of you")
	Harness.eq(TrafficPlan.nearAlpha(cfg.fadeInner), 0)
	Harness.eq(TrafficPlan.nearAlpha(cfg.fadeOuter), 1)
	Harness.eq(TrafficPlan.nearAlpha(500), 1)
	Harness.truthy(cfg.fadeInner < cfg.fadeOuter)
end)

Harness.test("cars brake for a shot, hold, then speed up again", function()
	Harness.eq(TrafficPlan.speedFactor(nil), 1)
	Harness.eq(TrafficPlan.speedFactor(0), cfg.slowFactor)
	Harness.eq(TrafficPlan.speedFactor(cfg.slowHoldSeconds), cfg.slowFactor)
	local mid = TrafficPlan.speedFactor(cfg.slowHoldSeconds + cfg.slowRecoverSeconds / 2)
	Harness.truthy(mid > cfg.slowFactor and mid < 1, "between")
	Harness.eq(TrafficPlan.speedFactor(cfg.slowHoldSeconds + cfg.slowRecoverSeconds + 1), 1)
	Harness.truthy(cfg.slowFactor > 0 and cfg.slowFactor < 1, "never stops dead")
end)

Harness.test("distance from a shot to a stretch", function()
	local seg: TrafficPlan.Segment = { axis = "x", dir = 1, fixed = 5, from = -50, to = 50 }
	Harness.eq(TrafficPlan.distanceTo(seg, 0, 5), 0)
	Harness.eq(TrafficPlan.distanceTo(seg, 20, 15), 10)
	Harness.eq(TrafficPlan.distanceTo(seg, 60, 5), 10, "past the end")
	local tall: TrafficPlan.Segment = { axis = "z", dir = 1, fixed = -5, from = -50, to = 50 }
	Harness.eq(TrafficPlan.distanceTo(tall, 5, 0), 10)
end)

Harness.test("cars on north-south lanes ride higher than east-west ones", function()
	local e: TrafficPlan.Segment = { axis = "x", dir = 1, fixed = 0, from = 0, to = 50 }
	local n: TrafficPlan.Segment = { axis = "z", dir = 1, fixed = 0, from = 0, to = 50 }
	Harness.truthy(TrafficPlan.height(n) > TrafficPlan.height(e))
end)

Harness.test("traffic remotes: the server tells, a client may only ask", function()
	local state = RemoteDefs.byName.TrafficState :: any
	local ask = RemoteDefs.byName.TrafficRequest :: any
	Harness.eq(state.direction, "toClient")
	Harness.eq(ask.direction, "toServer")
	Harness.truthy(ask.rate ~= nil and ask.rate.perSecond <= 2, "rate limited")
	Harness.eq(#ask.schema, 0, "takes no arguments")
	Harness.truthy(Config.Features.traffic, "on by default")
end)
