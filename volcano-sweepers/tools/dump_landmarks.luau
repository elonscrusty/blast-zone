--!strict
-- Writes every landmark look as JSON, for the 3D preview page. Use (from volcano-sweepers/):
--   lune run tools/dump_landmarks <out.json>

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local BigVolcano = require("../src/server/World/Models/BigVolcano")
local HotSpring = require("../src/server/World/Models/HotSpring")
local LavaPool = require("../src/server/World/Models/LavaPool")
local Lighthouse = require("../src/server/World/Models/Lighthouse")

local out: { [string]: { [string]: any } } = {}
local kinds: { [string]: { variants: { string }, spec: (string, number?) -> any } } = {
	volcano = BigVolcano,
	lava = LavaPool,
	spring = HotSpring,
	lighthouse = Lighthouse,
}
for kind, mod in kinds do
	out[kind] = {}
	for _, v in mod.variants do
		out[kind][v] = mod.spec(v, 1)
	end
end

local path = process.args[1] or "models.json"
fs.writeFile(path, serde.encode("json", out))
print("wrote " .. path)
