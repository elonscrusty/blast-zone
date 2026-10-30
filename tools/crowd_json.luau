--!strict
-- Prints the numbers the phone preview page (tools/crowd_preview.py) draws: two maps at three sizes,
-- each with its 25 spawn points. Use:  lune run tools/crowd_json

local serde = require("@lune/serde")
local Layout = require("../src/server/Arena/Layout")
local Config = require("../src/shared/Config")

local SIZES = {
	{ id = "A", scale = 1.0, name = "Packed", note = "Same street, wild and close." },
	{ id = "B", scale = 1.3, name = "Bigger", note = "Longer streets." },
	{ id = "C", scale = 1.6, name = "Huge", note = "Lots of room." },
}

local out = { sizes = {}, fighters = Config.Match.maxParticipants }
for _, size in SIZES do
	local zone = Config.zoneAt(size.scale)
	local maps = {}
	for _, mapId in { "C", "D" } do
		local spec = require(`../src/server/Arena/Layout{mapId}`)
		local layout = Layout.compile(spec, {
			scale = size.scale,
			minSpawns = Config.Arena.minSpawns,
			minContainers = Config.Arena.containerSpots,
			spawnClear = Config.Arena.spawnClearRadius,
			zoneRadius = zone.initialRadius,
		})
		local solids = {}
		for _, s in layout.solids do
			if s.kind ~= "boundary" then
				table.insert(solids, { s.kind, s.x0, s.z0, s.x1, s.z1, s.h })
			end
		end
		local ground = {}
		for _, g in layout.ground do
			table.insert(ground, { g.kind, g.x0, g.z0, g.x1, g.z1 })
		end
		local spawns, boxes = {}, {}
		for _, p in layout.spawns do
			table.insert(spawns, { p.x, p.z })
		end
		for _, p in layout.containers do
			table.insert(boxes, { p.x, p.z })
		end
		maps[mapId] =
			{ name = layout.name, solids = solids, ground = ground, spawns = spawns, boxes = boxes }
	end
	local last = zone.stages[#zone.stages]
	local stages = {}
	for _, st in zone.stages do
		table.insert(stages, { st.closeAt, st.closeSeconds, st.targetRadius })
	end
	table.insert(
		stages,
		{ zone.suddenDeath.startsAt, zone.suddenDeath.closeSeconds, zone.suddenDeath.targetRadius }
	)
	table.insert(out.sizes, {
		id = size.id,
		name = size.name,
		note = size.note,
		scale = size.scale,
		studs = 220 * size.scale,
		seconds = zone.suddenDeath.startsAt + zone.suddenDeath.closeSeconds,
		radius = zone.initialRadius,
		finalRadius = last.targetRadius,
		stages = stages,
		maps = maps,
	})
end
print(serde.encode("json", out))
