--!strict
-- Brings a Claude Design skin into the game:  lune run tools/import-design design/<file>.json
-- Checks every colour, font and size, then writes src/client/Ui/Skins/<Name>.luau.
-- After that, add the skin to Tokens.skins (and Tokens.defaultSkin if carter picked it).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local DesignImport = require("./DesignImport")

local path = process.args[1]
if not path then
	print("usage: lune run tools/import-design design/<file>.json")
	process.exit(1)
end

local ok, raw = pcall(serde.decode, "json", fs.readFile(path :: string))
if not ok then
	print("Not valid JSON: " .. tostring(raw))
	process.exit(1)
end

local source, problems = DesignImport.convert(raw)
if not source then
	print("This skin needs fixing before it can go in:")
	for _, p in problems do
		print("  - " .. p)
	end
	process.exit(1)
end

local out = `src/client/Ui/Skins/{DesignImport.fileName(raw.id)}.luau`
fs.writeFile(out, source :: string)
print("Wrote " .. out)
print(`Next: add  {raw.id} = require("./Skins/{DesignImport.fileName(raw.id)}")  to Tokens.skins.`)
