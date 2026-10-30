--!strict
-- Piece 47: 25 fighters. Every map must work at every size the crowd setting can take (carter's pick
-- is one number, Config.Arena.scale), so these checks run at all three: 1, 1.3 and 1.6.
local Harness = require("./harness")
local Layout = require("../src/server/Arena/Layout")
local Analysis = require("./arena_analysis")
local Config = require("../src/shared/Config")
local BotTuning = require("../src/server/Bots/BotTuning")
local BotRoster = require("../src/server/Bots/BotRoster")

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local SCALES = { 1, 1.3, 1.6 }
local IDS = { "A", "B", "C", "D", "E", "F" }

local function dist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

for _, scale in SCALES do
	local zone = Config.zoneAt(scale)
	for _, id in IDS do
		local spec = require(`../src/server/Arena/Layout{id}`)
		local layout = Layout.compile(spec, {
			scale = scale,
			minSpawns = Config.Arena.minSpawns,
			minContainers = Config.Arena.containerSpots,
			spawnClear = Config.Arena.spawnClearRadius,
			zoneRadius = zone.initialRadius,
		})
		local walk = Analysis.walkGrid(layout)

		Harness.test(`crowd {id} x{scale}: a spawn point for every fighter, all apart`, function()
			Harness.truthy(
				#layout.spawns >= Config.Match.maxParticipants,
				"fewer spawns than fighters"
			)
			for i, a in layout.spawns do
				for j = i + 1, #layout.spawns do
					local b = layout.spawns[j]
					Harness.truthy(
						dist(a.x, a.z, b.x, b.z) >= Config.Arena.spawnMinSeparation,
						`{a.id} and {b.id} are too close`
					)
				end
			end
		end)

		Harness.test(
			`crowd {id} x{scale}: spawns are free, reachable and in the first circle`,
			function()
				local first = layout.spawns[1]
				for _, p in layout.spawns do
					Harness.truthy(Analysis.walkable(walk, p.x, p.z), `{p.id} is inside a solid`)
					Harness.truthy(
						Analysis.reaches(walk, first.x, first.z, p.x, p.z),
						`{p.id} is cut off`
					)
					Harness.truthy(
						dist(p.x, p.z, zone.centerX, zone.centerZ) < zone.initialRadius,
						`{p.id} outside the circle`
					)
					Harness.truthy(
						not Analysis.insideAny(layout, p.x, p.z, Config.Arena.spawnClearRadius),
						`{p.id} too close to a solid`
					)
				end
			end
		)

		Harness.test(`crowd {id} x{scale}: crate points are enough, clear and reachable`, function()
			Harness.truthy(
				#layout.containers >= Config.Arena.containerSpots,
				"too few crate points"
			)
			local first = layout.spawns[1]
			for _, c in layout.containers do
				Harness.truthy(Analysis.walkable(walk, c.x, c.z), `{c.id} is inside a solid`)
				Harness.truthy(
					Analysis.reaches(walk, first.x, first.z, c.x, c.z),
					`{c.id} is cut off`
				)
			end
		end)

		Harness.test(`crowd {id} x{scale}: the first circle covers the whole map`, function()
			Harness.truthy(zone.initialRadius >= math.sqrt(2) * layout.half - 1)
		end)
	end

	Harness.test(
		`crowd x{scale}: the circle gets smaller and later, and never starts after the match cap`,
		function()
			local radius, at = zone.initialRadius, 0
			for i, s in zone.stages do
				Harness.truthy(s.warnAt >= at and s.closeAt > s.warnAt, `stage {i}: order of times`)
				Harness.truthy(s.targetRadius < radius, `stage {i}: smaller than before`)
				radius, at = s.targetRadius, s.closeAt + s.closeSeconds
			end
			Harness.truthy(
				zone.suddenDeath.startsAt >= at,
				"sudden death after the last stage closes"
			)
			Harness.truthy(zone.suddenDeath.targetRadius < radius)
			Harness.truthy(
				zone.suddenDeath.startsAt + zone.suddenDeath.closeSeconds < 210 * scale + 20
			)
		end
	)
end

Harness.test("crowd: scale 1 changes nothing about a map", function()
	for _, id in IDS do
		local spec = require(`../src/server/Arena/Layout{id}`)
		Harness.truthy(Layout.scaleSpec(spec, 1) == spec, `{id} was copied`)
		local plain = Layout.compile(spec)
		local same = Layout.compile(spec, { scale = 1 })
		Harness.eq(#same.solids, #plain.solids)
		Harness.eq(same.half, 110)
		Harness.eq(#same.spawns, #spec.spawns, "no top-up unless asked")
	end
end)

Harness.test(
	"crowd: stretching keeps heights, door widths grow and cover keeps its size",
	function()
		local spec = require("../src/server/Arena/LayoutC")
		local big = Layout.scaleSpec(spec, 1.5)
		Harness.eq(big.buildings[1].h, spec.buildings[1].h)
		Harness.truthy(big.buildings[1].x1 > spec.buildings[1].x1)
		local door0, door1 = spec.buildings[1].doors[1], big.buildings[1].doors[1]
		Harness.truthy(door1.to - door1.from > door0.to - door0.from)
		for i, b in spec.boxes do
			if b.id:find("^pillar") or b.id:find("^tree") then
				local c = big.boxes[i]
				Harness.near(c.x1 - c.x0, b.x1 - b.x0, 0.2, `{b.id} kept its size`)
			end
		end
	end
)

Harness.test("crowd: the match is for 25 and the bot names are all different", function()
	Harness.eq(Config.Match.maxParticipants, 25)
	Harness.eq(Config.Match.targetParticipants, 25)
	Harness.truthy(Config.Arena.minSpawns >= Config.Match.maxParticipants)
	local seen: { [string]: boolean } = {}
	for _, n in Config.Bots.names do
		Harness.truthy(not seen[n], `{n} twice`)
		seen[n] = true
	end
	Harness.truthy(#Config.Bots.names >= Config.Match.maxParticipants - 1, "a name for every bot")
end)

Harness.test("crowd: a lone player's fill reaches 25 and not past it", function()
	local T = BotTuning.from(Config :: any)
	Harness.eq(T.fillTo, 25)
	Harness.eq(T.maxParticipants, 25)
end)

Harness.test(
	"crowd: 24 bots fill a lone player's match; they think a bit slower the more there are",
	function()
		local T = BotTuning.from(Config :: any)
		Harness.eq(BotRoster.botsToAdd(T, 1, 0), 24)
		Harness.eq(BotRoster.botsToAdd(T, 25, 0), 0)
		local few = BotTuning.thinkGap(T, 3, T.maxParticipants)
		local half = BotTuning.thinkGap(T, 15, T.maxParticipants)
		local full = BotTuning.thinkGap(T, 24, T.maxParticipants)
		Harness.near(few, T.thinkInterval)
		Harness.truthy(half > few and full > half, "more bots, longer gap")
		Harness.near(full, T.thinkInterval * T.crowdMaxSlowdown, 1e-9)
		Harness.truthy(full < 0.25, "still quick enough to dodge and aim")
	end
)

Harness.test("crowd: the place file asks for room for a full match of real players", function()
	local project: any = serde.decode("json", fs.readFile("default.project.json"))
	local players = project.tree.Players
	Harness.truthy(players ~= nil, "default.project.json has no Players entry")
	Harness.truthy(
		players["$properties"].MaxPlayers >= Config.Match.maxParticipants,
		"Max Players is below the match size"
	)
end)
