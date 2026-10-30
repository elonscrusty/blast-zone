--!strict
-- Piece 43: street props that burst. Rules only (health, blasts, rubble, chunk flight), plus the
-- checks that keep the art and the server in step: every prop the server may break has art that
-- names it, and its gray box is the kind the art redraws.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local BreakRules = require("../src/shared/Breakables/BreakRules")
local ChunkFlight = require("../src/client/Props/ChunkFlight")
local ArtPlan = require("../src/server/Arena/ArtPlan")
local Layout = require("../src/server/Arena/Layout")
local StreetArt = require("../src/server/Arena/StreetArt")
local RemoteDefs = require("../src/shared/RemoteDefs")

local cfg = Config.Breakables

local function newBook()
	return BreakRules.new({ car = { health = 100, chunks = 8 } })
end

Harness.test("breakables: a prop breaks once, on the hit that empties it", function()
	local book = newBook()
	Harness.eq(BreakRules.register(book, "car-1", "car"), true)
	Harness.eq(BreakRules.damage(book, "car-1", 40), false)
	Harness.eq(BreakRules.health(book, "car-1"), 60)
	Harness.eq(BreakRules.damage(book, "car-1", 60), true)
	Harness.eq(BreakRules.isBroken(book, "car-1"), true)
	Harness.eq(BreakRules.damage(book, "car-1", 60), false) -- never twice
	Harness.eq(BreakRules.brokenCount(book), 1)
end)

Harness.test("breakables: unknown kinds, repeats and bad numbers do nothing", function()
	local book = newBook()
	Harness.eq(BreakRules.register(book, "x", "spaceship"), false)
	Harness.eq(BreakRules.register(book, "car-1", "car"), true)
	Harness.eq(BreakRules.register(book, "car-1", "car"), false)
	for _, bad in { 0, -5, 0 / 0, math.huge } do
		Harness.eq(BreakRules.damage(book, "car-1", bad), false)
		Harness.eq(BreakRules.health(book, "car-1"), 100)
	end
	Harness.eq(BreakRules.damage(book, "ghost", 50), false)
end)

Harness.test("breakables: reset brings every prop back at full health", function()
	local book = newBook()
	BreakRules.register(book, "a", "car")
	BreakRules.register(book, "b", "car")
	BreakRules.damage(book, "a", 500)
	BreakRules.damage(book, "b", 30)
	BreakRules.reset(book)
	Harness.eq(BreakRules.brokenCount(book), 0)
	Harness.eq(BreakRules.health(book, "a"), 100)
	Harness.eq(BreakRules.health(book, "b"), 100)
end)

Harness.test("breakables: blasts reach edges, not far props", function()
	Harness.near(BreakRules.blastFactor(0, 10, 0.2), 1)
	Harness.near(BreakRules.blastFactor(10, 10, 0.2), 0.2)
	Harness.eq(BreakRules.blastFactor(10.1, 10, 0.2), 0)
	Harness.eq(BreakRules.blastFactor(0 / 0, 10, 0.2), 0)
	Harness.eq(BreakRules.blastFactor(1, 0, 0.2), 0)
	local box = { x0 = 0, z0 = 0, x1 = 10, z1 = 5, h = 3 }
	Harness.eq(BreakRules.edgeDistance(5, 2, box), 0) -- inside
	Harness.eq(BreakRules.edgeDistance(13, 2, box), 3)
	Harness.near(BreakRules.edgeDistance(13, 9, box), 5)
end)

Harness.test("breakables: rubble is the same every time and stays inside the box", function()
	local box = { x0 = -5, z0 = 3, x1 = 5, z1 = 7, h = 3 }
	local a = BreakRules.rubble(box, BreakRules.seedOf("car-h1"), 6, 0.5, 1.1)
	local b = BreakRules.rubble(box, BreakRules.seedOf("car-h1"), 6, 0.5, 1.1)
	Harness.eq(#a, 6)
	for i, p in a do
		Harness.eq(p.dx, b[i].dx)
		Harness.eq(p.pick, b[i].pick)
		Harness.truthy(math.abs(p.dx) <= 5 and math.abs(p.dz) <= 2, "inside the box")
		Harness.truthy(p.sx >= 0.5 and p.sx <= 1.1 and p.sz >= 0.5 and p.sz <= 1.1, "size range")
		Harness.truthy(p.pick >= 0 and p.pick < 1, "pick is a share")
	end
	local other = BreakRules.rubble(box, BreakRules.seedOf("car-h2"), 6, 0.5, 1.1)
	Harness.truthy(other[1].dx ~= a[1].dx, "another prop, another pile")
	Harness.eq(#BreakRules.rubble(box, 1, 0, 0.5, 1.1), 0)
end)

Harness.test("breakables: a chunk flies up, lands, then shrinks away", function()
	local c = ChunkFlight.throw(0, 3, 0, 0.5, 0, 1, 1, cfg.fly.sideSpeed, cfg.fly.upSpeed)
	local g = cfg.fly.gravity
	local _, y0 = ChunkFlight.position(c, g, 0)
	Harness.near(y0, 3)
	local landT = ChunkFlight.landTime(c, g)
	Harness.truthy(landT > 0 and landT < cfg.fly.seconds, "lands before it fades")
	local x1, y1 = ChunkFlight.position(c, g, landT)
	Harness.near(y1, 0.5, 1e-6)
	local x2, y2 = ChunkFlight.position(c, g, landT + 5)
	Harness.near(x2, x1) -- no sliding after it landed
	Harness.near(y2, 0.5)
	Harness.eq(ChunkFlight.scale(0, 1.6, 0.35), 1)
	Harness.eq(ChunkFlight.scale(1.6, 1.6, 0.35), 0)
	Harness.truthy(ChunkFlight.scale(1.5, 1.6, 0.35) < 1)
end)

Harness.test(
	"breakables: every kind in the config is a StreetArt kind with sane numbers",
	function()
		local known = {
			car = true,
			barrier = true,
			dumpster = true,
			planter = true,
			bench = true,
		}
		for kind, k in cfg.kinds do
			Harness.truthy(known[kind], `{kind} has art`)
			Harness.truthy(k.health >= 40, `{kind} takes more than a couple of shots`)
			Harness.truthy(k.chunks >= 1 and k.chunks <= 16, `{kind} chunk count`)
		end
		Harness.truthy(
			cfg.fly.maxLiveChunks >= cfg.kinds.car.chunks * 2,
			"room for two cars at once"
		)
		Harness.truthy(cfg.fly.seconds <= 3, "chunks never hang around")
	end
)

local specs = {
	A = require("../src/server/Arena/LayoutA"),
	B = require("../src/server/Arena/LayoutB"),
	C = require("../src/server/Arena/LayoutC"),
	D = require("../src/server/Arena/LayoutD"),
	E = require("../src/server/Arena/LayoutE"),
	F = require("../src/server/Arena/LayoutF"),
}
local settings: ArtPlan.Settings = {
	seed = Config.Art.seed,
	towers = Config.Art.skyline.towers,
	innerGap = Config.Art.skyline.innerGap,
	outerReach = Config.Art.skyline.outerReach,
}

Harness.test(
	"breakables: on every map the props the server may break are dressed by art that names them",
	function()
		for id, spec in specs do
			local layout = Layout.compile(spec)
			local result = ArtPlan.build(layout, settings)
			local owned: { [string]: number } = {}
			for _, part in result.parts do
				if part.owner ~= nil then
					owned[part.owner] = (owned[part.owner] or 0) + 1
				end
			end
			local breakable = 0
			for _, s in layout.solids do
				local kind = StreetArt.classify(s.id)
				if kind ~= nil and cfg.kinds[kind] ~= nil and s.kind ~= "mass" then
					breakable += 1
					Harness.truthy(ArtPlan.replaces(s), `{id}: {s.id} gray box is redrawn`)
					Harness.truthy((owned[s.id] or 0) >= 3, `{id}: {s.id} has art that names it`)
					Harness.truthy(s.blocksShots, `{id}: {s.id} stops shots, so a shot can hit it`)
				end
			end
			for owner in owned do
				local found = false
				for _, s in layout.solids do
					if s.id == owner then
						found = true
					end
				end
				Harness.truthy(found, `{id}: art owner {owner} is a real solid`)
			end
			Harness.truthy(breakable >= 1 or id == "A", `{id}: some props can break`)
		end
	end
)

Harness.test("breakables: the burst remote exists and is server to client", function()
	local def = RemoteDefs.byName["PropBroken"]
	Harness.truthy(def ~= nil)
	Harness.eq(def.direction, "toClient")
end)
