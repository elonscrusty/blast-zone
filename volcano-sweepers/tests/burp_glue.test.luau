--!strict
local BurpDirector = require("../src/shared/Burp/BurpDirector")
local BurpGlue = require("../src/shared/Burp/BurpGlue")
local Config = require("../src/shared/Config")
local Finds = require("../src/shared/Catalog/Finds")
local Harness = require("./harness")
local Rng = require("../src/shared/Rng")
local Zones = require("../src/shared/Catalog/Zones")

local hub = Config.World.hub
local hubX = hub.radius * math.cos(math.rad(hub.angleDeg))
local hubZ = hub.radius * math.sin(math.rad(hub.angleDeg))
local NAN = 0 / 0
local INF = math.huge

Harness.test("glue: knockback points away from the blast, up, and is bounded", function()
	local vx, vy, vz = BurpGlue.knockback(10, 0, 0, 0)
	Harness.near(vx, BurpGlue.knockOut, 1e-9)
	Harness.near(vz, 0, 1e-9)
	Harness.near(vy, BurpGlue.knockUp, 1e-9)
	local ax, _, az = BurpGlue.knockback(-3, -4, 0, 0)
	Harness.near(ax, -3 / 5 * BurpGlue.knockOut, 1e-9)
	Harness.near(az, -4 / 5 * BurpGlue.knockOut, 1e-9)
	local rng = Rng.new(5)
	for _ = 1, 500 do
		local x, z = rng:range(-300, 300), rng:range(-300, 300)
		local bx, bz = rng:range(-300, 300), rng:range(-300, 300)
		local a, b, c = BurpGlue.knockback(x, z, bx, bz, rng:range(0, 500), rng:range(0, 500))
		Harness.truthy(a == a and b == b and c == c, "never NaN")
		Harness.truthy(math.sqrt(a * a + b * b + c * c) <= BurpGlue.maxKnock + 1e-6, "bounded")
		Harness.truthy(b >= 0, "never pushes into the ground")
	end
end)

Harness.test("glue: knockback survives zero distance and garbage numbers", function()
	local vx, vy, vz = BurpGlue.knockback(5, 5, 5, 5)
	Harness.truthy(vx == vx and vy == vy and vz == vz)
	Harness.truthy(vx > 0 and vy > 0, "standing on the centre still gets bounced")
	for _, bad in { NAN, INF, -INF } do
		local a, b, c = BurpGlue.knockback(bad, 0, 0, 0, bad, bad)
		Harness.truthy(a == a and b == b and c == c, "nan/inf input")
		Harness.truthy(math.sqrt(a * a + b * b + c * c) <= BurpGlue.maxKnock + 1e-6)
		local d, e, f = BurpGlue.knockback(0, 0, bad, bad)
		Harness.truthy(d == d and e == e and f == f)
	end
	local _, hugeUp = BurpGlue.knockback(1, 0, 0, 0, 1e9, 1e9)
	Harness.truthy(hugeUp <= BurpGlue.maxKnock, "caller cannot ask for more than maxKnock")
end)

Harness.test("glue: 2.5 s hit shield", function()
	Harness.eq(BurpGlue.canBeHit(0, 100), true, "never hit before")
	Harness.eq(BurpGlue.canBeHit(100, 100), false, "same instant")
	Harness.eq(BurpGlue.canBeHit(100, 102.4), false, "inside the shield")
	Harness.eq(BurpGlue.canBeHit(100, 102.5), true, "shield over")
	Harness.eq(BurpGlue.canBeHit(100, 130), true)
	Harness.eq(BurpGlue.canBeHit(200, 100), true, "clock went backwards: not immune forever")
	Harness.eq(BurpGlue.canBeHit(NAN, 100), true)
	Harness.eq(BurpGlue.canBeHit(0, NAN), false, "no usable time: no hit")
end)

Harness.test("glue: drop fraction is 0.2 x (1 - armor), clamped", function()
	Harness.near(BurpGlue.dropFraction(0), 0.2, 1e-9)
	Harness.near(BurpGlue.dropFraction(0.5), 0.1, 1e-9)
	Harness.near(BurpGlue.dropFraction(Config.Player.maxArmor), 0.2 * (1 - 0.8), 1e-9)
	Harness.near(BurpGlue.dropFraction(5), 0.2 * (1 - Config.Player.maxArmor), 1e-9, "armor capped")
	Harness.near(BurpGlue.dropFraction(-1), 0.2, 1e-9, "negative armor is ignored")
	Harness.near(BurpGlue.dropFraction(NAN), 0.2, 1e-9)
end)

Harness.test("glue: zoneOf never returns nil and matches the rings", function()
	for _, z in Config.World.zones do
		Harness.eq(BurpGlue.zoneOf((z.inner + z.outer) / 2, 0), z.id)
		Harness.eq(BurpGlue.zoneOf(0, -(z.inner + z.outer) / 2), z.id)
	end
	Harness.eq(BurpGlue.zoneOf(0, 0), 5, "volcano cone counts as the lava heart")
	Harness.eq(BurpGlue.zoneOf(900, 900), 1, "far outside is the beach")
	Harness.eq(BurpGlue.zoneOf(NAN, 3), 1)
end)

Harness.test("glue: the hub is a safe circle", function()
	Harness.eq(BurpGlue.inHub(hubX, hubZ), true)
	Harness.eq(BurpGlue.inHub(hubX + hub.clearRadius - 0.5, hubZ), true)
	Harness.eq(BurpGlue.inHub(hubX + hub.clearRadius + 0.5, hubZ), false)
	Harness.eq(BurpGlue.inHub(0, 0), false)
	Harness.eq(BurpGlue.inHub(NAN, 0), false)
end)

Harness.test("glue: fallSeconds and buffUntil are clamped", function()
	Harness.near(BurpGlue.fallSeconds(12, 10), 2, 1e-9)
	Harness.near(BurpGlue.fallSeconds(10.01, 10), 0.2, 1e-9)
	Harness.near(BurpGlue.fallSeconds(5, 10), 0.2, 1e-9, "already late")
	Harness.near(BurpGlue.fallSeconds(100, 10), 8, 1e-9)
	Harness.near(BurpGlue.fallSeconds(NAN, 10), 2, 1e-9)
	Harness.near(BurpGlue.buffUntil(100, 280, 1), 280, 1e-9)
	Harness.near(BurpGlue.buffUntil(100, 280, 1.5), 370, 1e-9)
	Harness.near(BurpGlue.buffUntil(100, 280, 99), 100 + 180 * BurpGlue.maxBuffMult, 1e-9)
	Harness.near(BurpGlue.buffUntil(100, 280, 0.2), 280, 1e-9, "never shorter than asked")
	Harness.near(BurpGlue.buffUntil(100, 50, 2), 100, 1e-9, "already over")
	Harness.near(BurpGlue.buffUntil(100, 280, NAN), 280, 1e-9)
end)

Harness.test("glue: tint is red in rumble and pops, calm otherwise", function()
	Harness.truthy(BurpGlue.tintFor("rumble", "pops") > 0)
	Harness.eq(BurpGlue.tintFor("event", "pops"), 1)
	Harness.truthy(BurpGlue.tintFor("event", "ashStorm") > 0)
	Harness.truthy(BurpGlue.tintFor("event", "ashStorm") < 1)
	Harness.eq(BurpGlue.tintFor("recover", "pops"), 0)
	Harness.eq(BurpGlue.tintFor("calm", nil), 0)
end)

-- ===== commands =====

local function bomb(id: number, landsAt: number): any
	return { id = id, x = 40, z = 50, radius = 7, landsAt = landsAt }
end

Harness.test("glue: commands keep event order and fill in what the glue needs", function()
	local book = BurpGlue.newBook()
	local events: { BurpDirector.BurpEvent } = {
		{ kind = "phase", phase = "rumble", burpKind = "pops", startsAt = 100, endsAt = 106 },
		{ kind = "bombs", bombs = { bomb(1, 102), bomb(2, 102.5) } },
		{ kind = "land", bombId = 1 },
		{ kind = "rain", fraction = 0.3 },
		{ kind = "golden", cells = 12, untilAt = 145 },
		{ kind = "geysers", spots = { { x = 1, z = 2 }, { x = 3, z = 4 } } },
		{ kind = "perfect", untilAt = 280 },
	}
	local cmds = BurpGlue.buildCommands(book, events, 100)
	local kinds = {}
	for _, c in cmds do
		table.insert(kinds, c.kind)
	end
	Harness.eq(table.concat(kinds, ","), "phase,bombs,land,rain,golden,geysers,perfect")
	local info = cmds[1].info :: any
	Harness.eq(info.phase, "rumble")
	Harness.eq(info.kind, "pops")
	Harness.eq(info.startsAt, 100)
	Harness.eq(info.endsAt, 106)
	Harness.near(cmds[1].tint :: number, 0.6, 1e-9)
	Harness.eq(#(cmds[2].bombs :: any), 2)
	Harness.eq((cmds[3].bomb :: any).id, 1, "land carries the bomb itself")
	Harness.eq(book.count, 1, "bomb 2 is still in the air")
	Harness.near(cmds[4].fraction :: number, 0.3, 1e-9)
	Harness.eq(cmds[5].cells, 12)
	Harness.eq(cmds[5].untilAt, 145)
	Harness.eq(#(cmds[6].spots :: any), 2)
	Harness.eq(cmds[7].untilAt, 280)
end)

Harness.test("glue: a land for an unknown or already-landed bomb is dropped", function()
	local book = BurpGlue.newBook()
	local cmds = BurpGlue.buildCommands(book, {
		{ kind = "land", bombId = 99 },
		{ kind = "bombs", bombs = { bomb(1, 102) } },
		{ kind = "land", bombId = 1 },
		{ kind = "land", bombId = 1 },
	}, 100)
	Harness.eq(#cmds, 2, "bombs + one land")
	Harness.eq(cmds[2].kind, "land")
	Harness.eq(book.count, 0)
end)

Harness.test("glue: live bombs are capped at 40 and the book forgets stale ones", function()
	local book = BurpGlue.newBook()
	local many: { any } = {}
	for k = 1, 60 do
		table.insert(many, bomb(k, 102))
	end
	local cmds = BurpGlue.buildCommands(book, { { kind = "bombs", bombs = many } }, 100)
	Harness.eq(#(cmds[1].bombs :: any), BurpGlue.maxLiveBombs)
	Harness.eq(book.count, BurpGlue.maxLiveBombs)
	-- the same ids again are not accepted twice
	local again = BurpGlue.buildCommands(book, { { kind = "bombs", bombs = many } }, 100)
	Harness.eq(#again, 0)
	-- much later the director never landed them (it went to sleep): the book empties itself
	BurpGlue.buildCommands(book, {}, 200)
	Harness.eq(book.count, 0)
	Harness.eq(next(book.bombs), nil)
end)

Harness.test("glue: malformed events are dropped, never thrown", function()
	local book = BurpGlue.newBook()
	local events: { any } = {
		{ kind = "phase", phase = "bogus", startsAt = 1, endsAt = 2 },
		{ kind = "phase", phase = "event", startsAt = NAN, endsAt = 2 },
		{ kind = "phase", phase = "calm", burpKind = "nonsense", startsAt = 1, endsAt = 2 },
		{ kind = "bombs", bombs = { { id = 1, x = NAN, z = 0, radius = 7, landsAt = 5 } } },
		{ kind = "bombs", bombs = { { id = 2, x = 0, z = 0, radius = 0, landsAt = 5 } } },
		{ kind = "bombs" },
		{ kind = "rain", fraction = NAN },
		{ kind = "rain", fraction = 0 },
		{ kind = "golden", cells = 0, untilAt = 500 },
		{ kind = "golden", cells = 10, untilAt = 50 },
		{ kind = "geysers", spots = { { x = NAN, z = 1 } } },
		{ kind = "perfect", untilAt = 50 },
		{ kind = "perfect" },
		{ kind = "mystery" },
	}
	local cmds = BurpGlue.buildCommands(book, events, 100)
	-- only the calm phase (kind scrubbed to nil) and the empty geyser list survive
	Harness.eq(#cmds, 2)
	Harness.eq(cmds[1].kind, "phase")
	Harness.eq((cmds[1].info :: any).kind, nil)
	Harness.eq(cmds[2].kind, "geysers")
	Harness.eq(#(cmds[2].spots :: any), 0)
end)

Harness.test("glue: golden cells and geyser spots are capped", function()
	local book = BurpGlue.newBook()
	local spots: { any } = {}
	for k = 1, 40 do
		table.insert(spots, { x = k, z = k })
	end
	local cmds = BurpGlue.buildCommands(book, {
		{ kind = "golden", cells = 100000, untilAt = 500 },
		{ kind = "geysers", spots = spots },
	}, 100)
	Harness.eq(cmds[1].cells, BurpGlue.maxGoldenCells)
	Harness.eq(#(cmds[2].spots :: any), BurpGlue.maxGeyserSpots)
end)

Harness.test("glue: commands from a real director run are all well formed", function()
	local director = BurpDirector.new(Rng.new(11))
	local book = BurpGlue.newBook()
	local players = {
		{ userId = 1, x = 150, z = 20, zone = 2 },
		{ userId = 2, x = 80, z = -30, zone = 4 },
	}
	local counts: { [string]: number } = {}
	local t = 0
	local flying = 0
	while t < 1500 do
		local events =
			director:step(t, { playerPositions = players, cleanTotal = 0.5, playerCount = 2 })
		local rawBombs, rawLands = 0, 0
		for _, ev in events do
			if ev.kind == "bombs" then
				rawBombs += #(ev.bombs :: any)
			elseif ev.kind == "land" then
				rawLands += 1
			end
		end
		local cmds = BurpGlue.buildCommands(book, events, t)
		for _, c in cmds do
			counts[c.kind] = (counts[c.kind] or 0) + 1
			if c.kind == "bombs" then
				flying += #(c.bombs :: any)
			elseif c.kind == "land" then
				flying -= 1
			end
		end
		Harness.truthy(flying >= 0, "never more landings than bombs")
		Harness.truthy(book.count <= BurpGlue.maxLiveBombs)
		Harness.eq(book.count, flying, "the book matches the bombs in the air")
		t += 0.25
	end
	for _, kind in { "phase", "bombs", "land", "rain", "golden", "geysers", "perfect" } do
		Harness.truthy((counts[kind] or 0) > 0, `a 25 minute run produced a {kind} command`)
	end
end)

-- ===== dodge rounds =====

Harness.test("glue: dodge rounds count those present and not hit", function()
	local r = BurpGlue.newRound()
	BurpGlue.roundLand(r, { 3, 1, 2 })
	BurpGlue.roundHit(r, 2)
	BurpGlue.roundLand(r, { 1, 2, 3, 4 })
	BurpGlue.roundHit(r, 2)
	local dodged = BurpGlue.roundFinish(r)
	Harness.eq(table.concat(dodged :: any, ","), "1,3,4")
	Harness.eq(#BurpGlue.roundFinish(r), 0, "finish resets the round")
end)

Harness.test("glue: events with no landed bomb never give a dodge", function()
	local r = BurpGlue.newRound()
	Harness.eq(#BurpGlue.roundFinish(r), 0)
	BurpGlue.roundHit(r, 5) -- a stray hit report alone changes nothing
	Harness.eq(#BurpGlue.roundFinish(r), 0)
end)

Harness.test("glue: a hit before the round reset does not carry over", function()
	local r = BurpGlue.newRound()
	BurpGlue.roundLand(r, { 1 })
	BurpGlue.roundHit(r, 1)
	BurpGlue.roundReset(r)
	BurpGlue.roundLand(r, { 1 })
	Harness.eq(table.concat(BurpGlue.roundFinish(r) :: any, ","), "1")
end)

-- ===== geyser gems =====

Harness.test("glue: gem pickup radius is 6 flat, with a height limit", function()
	Harness.eq(BurpGlue.inPickupRange(0, 3, 0, 5.9, 2.5, 0), true)
	Harness.eq(BurpGlue.inPickupRange(0, 3, 0, 6, 2.5, 0), true, "exactly on the edge")
	Harness.eq(BurpGlue.inPickupRange(0, 3, 0, 6.1, 2.5, 0), false)
	Harness.eq(BurpGlue.inPickupRange(0, 3, 0, 4.5, 2.5, 4.5), false, "6.36 studs away")
	Harness.eq(BurpGlue.inPickupRange(0, 60, 0, 0, 2.5, 0), false, "far above")
	Harness.eq(BurpGlue.inPickupRange(0, 3, 0, 8, 2.5, 0, 10), true, "custom radius")
	Harness.eq(BurpGlue.inPickupRange(NAN, 3, 0, 0, 2.5, 0), false)
	Harness.eq(BurpGlue.inPickupRange(0, 3, 0, INF, 2.5, 0), false)
end)

Harness.test("glue: gem rarity thresholds", function()
	Harness.eq(BurpGlue.gemRarity(0), "common")
	Harness.eq(BurpGlue.gemRarity(0.69), "common")
	Harness.eq(BurpGlue.gemRarity(0.7), "uncommon")
	Harness.eq(BurpGlue.gemRarity(0.93), "rare")
	Harness.eq(BurpGlue.gemRarity(5), "rare")
	Harness.eq(BurpGlue.gemRarity(NAN), "common")
end)

Harness.test("glue: gem coins scale with the zone, capped by what the player unlocked", function()
	local only1 = { ["1"] = true }
	local upTo3 = { ["1"] = true, ["2"] = true, ["3"] = true }
	local all = { ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, ["5"] = true }
	Harness.eq(BurpGlue.effectiveZone(5, only1), 1)
	Harness.eq(BurpGlue.effectiveZone(5, upTo3), 3)
	Harness.eq(BurpGlue.effectiveZone(2, upTo3), 2)
	Harness.eq(BurpGlue.effectiveZone(5, {}), 1, "even with nothing saved")
	Harness.eq(BurpGlue.effectiveZone(NAN, all), 1)
	local last = 0
	for zone = 1, 5 do
		local c = BurpGlue.geyserCoins(zone, all, 1)
		Harness.truthy(c > last, "richer zones pay more")
		Harness.eq(c, math.floor(BurpGlue.gemBaseCoins * Zones.valueOf(zone) + 0.5))
		last = c
	end
	Harness.eq(
		BurpGlue.geyserCoins(5, only1, 1),
		BurpGlue.geyserCoins(1, only1, 1),
		"locked zone pays zone 1"
	)
	Harness.truthy(BurpGlue.geyserCoins(3, all, 7) > BurpGlue.geyserCoins(3, all, 1))
	Harness.truthy(BurpGlue.geyserCoins(1, only1, 0) >= 1, "always at least one coin")
	Harness.truthy(BurpGlue.geyserCoins(1, only1, NAN) >= 1)
end)

Harness.test("glue: gem offsets stay in the ring and spread out", function()
	local rng = Rng.new(8)
	for _ = 1, 100 do
		local list = BurpGlue.gemOffsets(rng, 3, 5, 9)
		Harness.eq(#list, 3)
		for _, o in list do
			local r = math.sqrt(o.x * o.x + o.z * o.z)
			Harness.truthy(r >= 5 - 1e-9 and r <= 9 + 1e-9, `radius {r}`)
		end
	end
	Harness.eq(#BurpGlue.gemOffsets(rng, 0, 5, 9), 0)
	Harness.eq(#BurpGlue.gemOffsets(rng, NAN, 5, 9), 0)
	Harness.eq(#BurpGlue.gemOffsets(rng, 999, 5, 9), 20, "capped")
end)

Harness.test("glue: spots snap to distinct nearest vents", function()
	local vents = { { x = 0, z = 0 }, { x = 100, z = 0 }, { x = 200, z = 0 } }
	local snapped =
		BurpGlue.snapSpots({ { x = 90, z = 5 }, { x = 95, z = -5 }, { x = 190, z = 0 } }, vents)
	Harness.eq(snapped[1].x, 100)
	Harness.eq(snapped[2].x, 0, "second spot gets the next nearest free vent")
	Harness.eq(snapped[3].x, 200)
	local more = BurpGlue.snapSpots({ { x = 1, z = 1 }, { x = 2, z = 2 } }, { { x = 50, z = 50 } })
	Harness.eq(more[1].x, 50)
	Harness.eq(more[2].x, 2, "no vent left: keep the spot")
	Harness.eq(#BurpGlue.snapSpots({ { x = 1, z = 1 } }, {}), 1)
end)

-- ===== set claims =====

local setById = Finds.setById :: { [string]: any }
local list = Finds.list :: { { id: string, set: string } }

local function foundAll(setId: string): { [string]: number }
	local out: { [string]: number } = {}
	for _, id in BurpGlue.setMembers(list, setId) do
		out[id] = 1
	end
	return out
end

Harness.test("glue: every real set has five finds", function()
	for _, set in Finds.sets do
		Harness.eq(#BurpGlue.setMembers(list, set.id), 5, set.id)
	end
	Harness.eq(#BurpGlue.setMembers(list, "nope"), 0)
end)

Harness.test("glue: set claim rules", function()
	local finds = foundAll("beach")
	local ok, why = BurpGlue.claimCheck("beach", finds, {}, setById, list)
	Harness.eq(ok, true)
	Harness.eq(why, "ok")

	ok, why = BurpGlue.claimCheck("beach", finds, { beach = true }, setById, list)
	Harness.eq(ok, false)
	Harness.eq(why, "claimed")

	ok, why = BurpGlue.claimCheck("forest", finds, {}, setById, list)
	Harness.eq(ok, false)
	Harness.eq(why, "incomplete", "other set's finds do not count")

	finds["shiny_shell"] = nil
	ok, why = BurpGlue.claimCheck("beach", finds, {}, setById, list)
	Harness.eq(why, "incomplete", "one missing find")
	finds["shiny_shell"] = 0
	ok, why = BurpGlue.claimCheck("beach", finds, {}, setById, list)
	Harness.eq(why, "incomplete", "count 0 is not found")
	finds["shiny_shell"] = NAN
	ok, why = BurpGlue.claimCheck("beach", finds, {}, setById, list)
	Harness.eq(why, "incomplete", "nan count is not found")
	finds["shiny_shell"] = 7
	ok, why = BurpGlue.claimCheck("beach", finds, {}, setById, list)
	Harness.eq(ok, true, "found many times is fine")

	for _, bad in { "", "nope", "BEACH", "__index", "beach ", "rainbow2" } do
		ok, why = BurpGlue.claimCheck(bad, finds, {}, setById, list)
		Harness.eq(ok, false, bad)
		Harness.eq(why, "unknown", bad)
	end
end)

Harness.test(
	"glue: a set with no finds is never claimable; the rainbow set needs its own five",
	function()
		local ok, why = BurpGlue.claimCheck("ghost", {}, {}, { ghost = true }, list)
		Harness.eq(ok, false)
		Harness.eq(why, "empty")
		local all: { [string]: number } = {}
		for _, f in list do
			if f.set ~= "rainbow" then
				all[f.id] = 3
			end
		end
		ok, why = BurpGlue.claimCheck("rainbow", all, {}, setById, list)
		Harness.eq(ok, false)
		Harness.eq(why, "incomplete")
		ok = BurpGlue.claimCheck("rainbow", foundAll("rainbow"), {}, setById, list)
		Harness.eq(ok, true)
	end
)

Harness.test("glue: find and set texts", function()
	Harness.eq(BurpGlue.findToast("common", "Shiny Shell"), nil)
	Harness.eq(BurpGlue.findToast("uncommon", "X"), nil)
	local rare = BurpGlue.findToast("rare", "Fire Opal") :: any
	Harness.eq(rare.kind, "gold")
	Harness.truthy(string.find(rare.text, "Fire Opal", 1, true) ~= nil)
	local leg = BurpGlue.findToast("legendary", "Volcano Heart") :: any
	Harness.eq(leg.kind, "gold")
	Harness.eq(BurpGlue.setClaimText(0.03), "Set complete! +3% coins forever")
	Harness.eq(BurpGlue.setClaimText(0.1), "Set complete! +10% coins forever")
	Harness.eq(BurpGlue.setClaimText(NAN), "Set complete! +0% coins forever")
end)
