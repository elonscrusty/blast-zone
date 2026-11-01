--!strict
-- Writes every model in every style as JSON, for the 3D preview page.
-- Run (from volcano-sweepers/):  lune run tools/dump_models <out.json>

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Registry = require("../src/server/World/Models/Registry")
local Styles = require("../src/server/World/Models/Styles")

local out: { [string]: { [string]: any } } = {}
for _, style in Styles.ids do
	local perStyle: { [string]: any } = {}
	for _, name in Registry.names do
		local params: any = { style = style, v = 7 }
		if name == "Gate" then
			params.accent = "#9BFF8A"
			params.ground = "#6FBF5A"
		end
		perStyle[name] = Registry.spec(name, params)
		-- a couple of variants so the preview scene is not a row of clones
		for i, v in { 31, 88 } do
			params.v = v
			params.text = if name == "Sign" then ({ "SELL ->", "GATE" })[i] else nil
			perStyle[`{name}:{i + 1}`] = Registry.spec(name, params)
		end
	end
	out[style] = perStyle
end
fs.writeFile(process.args[1] or "models.json", serde.encode("json", out))
print("wrote", process.args[1] or "models.json")
