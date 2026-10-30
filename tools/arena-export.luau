--!strict
-- Writes every arena layout (plus a few numbers) as JSON for the phone preview page.
-- Use:  lune run tools/arena-export <output.json>

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Layout = require("../src/server/Arena/Layout")
local Analysis = require("../tests/arena_analysis")
local Config = require("../src/shared/Config")

local out = process.args[1] or "arenas.json"
local specs = {
	require("../src/server/Arena/LayoutA"),
	require("../src/server/Arena/LayoutB"),
	require("../src/server/Arena/LayoutC"),
}

local result = {}
for _, spec in specs do
	local layout = Layout.compile(spec)
	local walk = Analysis.walkGrid(layout)
	local worst = 0
	for x = -100, 100, 5 do
		for z = -100, 100, 5 do
			if Analysis.walkable(walk, x, z) and Analysis.nearBlocker(layout, x, z, 3.5) then
				worst =
					math.max(worst, Analysis.exposure(layout, x, z, Config.Weapons.Firearm.range))
			end
		end
	end
	local far, near, sum = 0, 1e9, 0
	for _, s in layout.spawns do
		local d = math.sqrt((s.x - Config.Zone.centerX) ^ 2 + (s.z - Config.Zone.centerZ) ^ 2)
		far, near, sum = math.max(far, d), math.min(near, d), sum + d
	end
	local cover = 0
	for _, s in layout.solids do
		if s.kind == "cover" then
			cover += 1
		end
	end
	table.insert(result, {
		layout = layout,
		stats = {
			worstSeat = math.floor(worst * 100),
			spawnFar = math.floor(far),
			spawnNear = math.floor(near),
			spawnAvg = math.floor(sum / #layout.spawns),
			cover = cover,
		},
	})
end
fs.writeFile(out, serde.encode("json", result))
print("wrote " .. out)
