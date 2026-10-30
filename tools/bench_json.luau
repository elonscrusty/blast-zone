--!strict
-- Prints the bench parts list as JSON for tools/bench_preview.py (run from the repo root: lune run tools/bench_json).
-- The 3D colours are preview-only; the real look is Claude Design's.
local serde = require("@lune/serde")
local BenchDefs = require("../src/shared/Bench/BenchDefs")

local colors = { "#9aa7b5", "#36d9e8", "#ffc44d", "#e94cff" }
local tiers = {}
for i, t in BenchDefs.tiers do
	table.insert(tiers, { tier = t.tier, name = t.name, color = colors[i] })
end
print(serde.encode("json", { tiers = tiers, kinds = BenchDefs.kinds, blueprints = BenchDefs.blueprints, mergeCount = BenchDefs.mergeCount }))
