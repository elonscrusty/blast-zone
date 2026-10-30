--!strict
-- Whole-game wiring: reads the source files and checks the pieces are plugged into each other.
-- Every "...System" module can start, every remote has a server side and a client side, and nobody
-- sends a remote the wrong way. Catches a piece that merged without its other half.
local fs = require("@lune/fs")
local Harness = require("./harness")
local RemoteDefs = require("../src/shared/RemoteDefs")

local function luauFiles(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			luauFiles(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

-- Source without comments, so a name in a comment never counts as wiring.
local function code(path: string): string
	local source = fs.readFile(path)
	source = string.gsub(source, "%-%-%[(=*)%[.-%]%1%]", "")
	source = string.gsub(source, "%-%-[^\n]*", "")
	return source
end

local function sideSources(dir: string): { [string]: string }
	local files = {}
	luauFiles(dir, files)
	local out = {}
	for _, path in files do
		out[path] = code(path)
	end
	return out
end

local server = sideSources("src/server")
local client = sideSources("src/client")

local function mentions(sources: { [string]: string }, name: string): boolean
	local quoted = '"' .. name .. '"'
	for _, source in sources do
		if string.find(source, quoted, 1, true) then
			return true
		end
	end
	return false
end

local function calls(
	sources: { [string]: string },
	pattern: string
): { { name: string, path: string } }
	local out = {}
	for path, source in sources do
		for name in string.gmatch(source, pattern) do
			table.insert(out, { name = name, path = path })
		end
	end
	return out
end

Harness.test("wiring: every System module has a start and returns itself", function()
	local files = {}
	luauFiles("src/server", files)
	luauFiles("src/client", files)
	local count = 0
	for _, path in files do
		local name = string.match(path, "([%w_]+System)%.luau$")
		if name then
			count += 1
			local source = code(path)
			Harness.truthy(
				string.find(source, "function " .. name .. ".start(", 1, true),
				path .. " has no " .. name .. ".start()"
			)
			Harness.truthy(
				string.find(source, "return " .. name .. "%s*$"),
				path .. " must end with return " .. name
			)
		end
	end
	Harness.truthy(count > 40, "found the systems")
end)

Harness.test("wiring: every client ask has exactly one server handler", function()
	local handlers: { [string]: number } = {}
	for _, call in calls(server, 'onRequest%(%s*"([%w_]+)"') do
		handlers[call.name] = (handlers[call.name] or 0) + 1
	end
	for _, def in RemoteDefs.list do
		if def.direction == "toServer" then
			Harness.eq(handlers[def.name] or 0, 1, def.name .. ": server handlers")
			Harness.truthy(mentions(client, def.name), def.name .. ": no client ever sends it")
		end
	end
end)

Harness.test("wiring: every server message is sent and heard", function()
	for _, def in RemoteDefs.list do
		if def.direction == "toClient" then
			Harness.truthy(mentions(server, def.name), def.name .. ": the server never sends it")
			-- An unheard RemoteEvent piles its messages up on the client.
			Harness.truthy(mentions(client, def.name), def.name .. ": no client listens")
		end
	end
end)

Harness.test("wiring: remotes only go the way RemoteDefs says", function()
	local function check(list: { { name: string, path: string } }, direction: string)
		for _, call in list do
			local def = RemoteDefs.byName[call.name]
			Harness.truthy(def ~= nil, call.path .. ": unknown remote " .. call.name)
			if def then
				Harness.eq(def.direction, direction, call.path .. ": " .. call.name)
			end
		end
	end
	check(calls(server, 'Net%.onRequest%(%s*"([%w_]+)"'), "toServer")
	check(calls(server, 'Net%.fire%a*%(%s*"([%w_]+)"'), "toClient")
	check(calls(client, 'Net%.send%(%s*"([%w_]+)"'), "toServer")
	check(calls(client, 'Net%.on%(%s*"([%w_]+)"'), "toClient")
end)

Harness.test("wiring: only the match flow loads characters", function()
	for path, source in server do
		local loads = string.find(source, ":LoadCharacter(", 1, true) ~= nil
			or string.find(source, "CharacterAutoLoads", 1, true) ~= nil
		if loads then
			Harness.eq(path, "src/server/Match/MatchSystem.luau", "loads characters")
		end
	end
end)
