--!strict
-- What this player's power rating is. Only the server works it out (PowerSystem); this just keeps the latest
-- number for screens to read. Logic only: no screen here on purpose. Claude Design picks where it shows (lobby
-- card, results, name plate). Read it with PowerClientSystem.get() and listen to PowerClientSystem.Changed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)
local Net = require(script.Parent.Parent.Core.Net)

local PowerClientSystem = {}
PowerClientSystem.order = 230
PowerClientSystem.Changed = Signal.new() -- (payload)

local current: Types.PowerPayload? = nil

function PowerClientSystem.get(): Types.PowerPayload?
	return current
end

function PowerClientSystem.start()
	Net.on("PowerUpdate", function(payload: Types.PowerPayload)
		current = payload
		PowerClientSystem.Changed:fire(payload)
	end)
	-- The server pushes on join, but this script may not have been listening yet: ask once.
	task.delay(1, function()
		if current == nil then
			Net.send("PowerRequest")
		end
	end)
end

return PowerClientSystem
