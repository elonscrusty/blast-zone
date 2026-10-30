--!strict
-- Client door for remotes. The client only asks; the server decides.
--   Net.send("FireRequest", origin, dir, seq)            -- toServer remotes
--   Net.on("MatchState", function(state) ... end)         -- toClient remotes
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefs = require(Shared.RemoteDefs)
local Remotes = require(Shared.Remotes)

local Net = {}

function Net.send(name: string, ...: any)
	local def = RemoteDefs.byName[name]
	assert(
		def ~= nil and def.direction == "toServer",
		"Net.send: '" .. name .. "' is not a toServer remote"
	)
	Remotes.get(name):FireServer(...)
end

function Net.on(name: string, handler: (...any) -> ()): RBXScriptConnection
	local def = RemoteDefs.byName[name]
	assert(
		def ~= nil and def.direction == "toClient",
		"Net.on: '" .. name .. "' is not a toClient remote"
	)
	return Remotes.get(name).OnClientEvent:Connect(handler)
end

return Net
