--!strict
-- What this player knows about their ranked standing. Only the server writes it (RankedUpdate); screens read it
-- and ask for the switch (RankedToggle). Never work out points or tiers on the client.
-- For Claude Design: read `RankedClient.get()` and listen to `RankedClient.Changed`. Draw nothing here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local Net = require(script.Parent.Parent.Core.Net)

local RankedClient = {}
RankedClient.Changed = Signal.new() -- (payload: Types.RankedPayload)

local current: Types.RankedPayload? = nil
local started = false

function RankedClient.get(): Types.RankedPayload?
	return current
end

-- Ask the server to turn the ranked switch on or off. The server answers with RankedUpdate either way.
function RankedClient.setEnabled(on: boolean)
	Net.send("RankedToggle", on)
end

function RankedClient.ensureStarted()
	if started then
		return
	end
	started = true
	Net.on("RankedUpdate", function(payload: Types.RankedPayload)
		current = payload
		RankedClient.Changed:fire(payload)
	end)
	Net.send("RankedRequest") -- a late start still gets the standing
end

return RankedClient
