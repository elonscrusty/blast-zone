--!strict
-- Runs every `*.test.luau` file in this folder, then prints a summary. Use:  lune run tests/run
-- New pieces only add a test file; nobody edits this file.

local fs = require("@lune/fs")
local Harness = require("./harness")

local names = {}
for _, file in fs.readDir("tests") do
	local name = string.match(file, "^(.+)%.test%.luau$")
	if name then
		table.insert(names, name)
	end
end
table.sort(names)

for _, name in names do
	print(name)
	require(`./{name}.test`)
end

Harness.summary()
