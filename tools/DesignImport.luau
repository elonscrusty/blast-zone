--!strict
-- Turns a Claude Design skin export (decoded JSON) into a skin file for src/client/Ui/Skins/.
-- Pure so Lune can test it. Missing text/shape/motion groups take the Street Sticker numbers,
-- colours and fonts must all be given. Run it with: lune run tools/import-design design/<file>.json

local Tokens = require("../src/client/Ui/Tokens")

local DesignImport = {}

local GROUPS = {
	{ name = "colors", keys = Tokens.COLOR_KEYS },
	{ name = "fonts", keys = { "display", "body" } },
	{ name = "text", keys = Tokens.TEXT_KEYS },
	{ name = "shape", keys = Tokens.SHAPE_KEYS },
	{ name = "motion", keys = Tokens.MOTION_KEYS },
}
local FILLED = { text = true, shape = true, motion = true }

-- Fills optional groups from the default skin and upper-cases hex colours.
function DesignImport.normalize(raw: any): any
	local base = Tokens.get(Tokens.defaultSkin) :: any
	local out: any = { id = raw.id, name = raw.name }
	for _, g in GROUPS do
		local src = if type(raw[g.name]) == "table" then raw[g.name] else {}
		local group = {}
		for _, key in g.keys do
			local v = src[key]
			if v == nil and FILLED[g.name] then
				v = base[g.name][key]
			end
			if g.name == "colors" and type(v) == "string" then
				v = string.upper(v)
				if string.sub(v, 1, 1) ~= "#" then
					v = "#" .. v
				end
			end
			group[key] = v
		end
		out[g.name] = group
	end
	return out
end

-- "neon_night" -> "NeonNight"
function DesignImport.fileName(id: string): string
	local parts = {}
	for word in string.gmatch(id, "[^_]+") do
		table.insert(parts, string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2))
	end
	return table.concat(parts)
end

local function value(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

-- Returns the skin file text, or nil and the list of problems.
function DesignImport.convert(raw: any): (string?, { string })
	if type(raw) ~= "table" then
		return nil, { "the file is not a JSON object" }
	end
	local skin = DesignImport.normalize(raw)
	local problems = Tokens.check(skin)
	if #problems > 0 then
		return nil, problems
	end
	local lines = {
		"--!strict",
		`-- Skin "{skin.name}", made by Claude Design and brought in with tools/import-design.`,
		"-- Only looks. Keys are listed in Tokens.luau and checked by tests/ui_tokens.test.luau.",
		"",
		"return {",
		`\tid = {value(skin.id)},`,
		`\tname = {value(skin.name)},`,
	}
	for _, g in GROUPS do
		table.insert(lines, `\t{g.name} = \{`)
		for _, key in g.keys do
			table.insert(lines, `\t\t{key} = {value(skin[g.name][key])},`)
		end
		table.insert(lines, "\t},")
	end
	table.insert(lines, "}")
	return table.concat(lines, "\n") .. "\n", {}
end

return DesignImport
