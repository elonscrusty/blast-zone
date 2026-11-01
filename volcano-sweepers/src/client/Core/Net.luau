--!strict
-- Client door for remotes. Every call is safe: a missing remote or a bad name warns and does nothing.
--   Net.send(name, ...)   fire a client -> server remote (the server checks everything)
--   Net.on(name, fn)      listen to a server -> client remote; fn errors are caught and warned

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefs = require(Shared.RemoteDefs)
local Remotes = require(Shared.Remotes)

local Net = {}

local dead = false -- the Remotes folder never appeared: stop waiting for every remote

local function remote(name: string): RemoteEvent?
	if dead then
		return nil
	end
	local ok, ev = pcall(Remotes.get, name)
	if not ok then
		warn(`[Net] remote {name} unavailable: {ev}`)
		if string.find(tostring(ev), "folder never appeared", 1, true) then
			dead = true
		end
		return nil
	end
	return ev
end

-- A stand-in so callers can always call :Disconnect() on what Net.on returns.
local function stub(): RBXScriptConnection
	return { Connected = false, Disconnect = function() end } :: any
end

function Net.send(name: string, ...: any)
	local def = RemoteDefs.byName[name]
	if def == nil or def.direction ~= "toServer" then
		warn(`[Net] send: '{name}' is not a client -> server remote`)
		return
	end
	local ev = remote(name)
	if ev ~= nil then
		ev:FireServer(...)
	end
end

function Net.on(name: string, fn: (...any) -> ()): RBXScriptConnection
	local def = RemoteDefs.byName[name]
	if def == nil or def.direction ~= "toClient" then
		warn(`[Net] on: '{name}' is not a server -> client remote`)
		return stub()
	end
	local ev = remote(name)
	if ev == nil then
		return stub()
	end
	return ev.OnClientEvent:Connect(function(...)
		local ok, err = pcall(fn, ...)
		if not ok then
			warn(`[Net] handler for {name} failed: {err}`)
		end
	end)
end

return Net
