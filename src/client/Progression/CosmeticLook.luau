--!strict
-- Which color to draw for a player's slide trail and shot tracer. The server copies each player's chosen item id
-- onto the Player as an attribute; anything unknown or missing falls back to the free default. Looks only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local TrackDefs = require(Shared.Progression.TrackDefs)

local CosmeticLook = {}

local function colorFor(player: Player?, attribute: string, slot: TrackDefs.Slot): Color3
	local def = TrackDefs.defaultFor(slot)
	if player ~= nil then
		local id = player:GetAttribute(attribute)
		if type(id) == "string" then
			local found = TrackDefs.get(id)
			if found ~= nil and found.slot == slot then
				def = found
			end
		end
	end
	return Color3.fromHex(def.color)
end

function CosmeticLook.trailColor(character: Model): Color3
	return colorFor(
		Players:GetPlayerFromCharacter(character),
		Config.Progression.attributes.trail,
		"trail"
	)
end

-- participantId is "p123" for players; bots have no look and get the default.
function CosmeticLook.tracerColor(participantId: string?): Color3
	local player: Player? = nil
	if participantId ~= nil then
		local userId = Ids.userIdOf(participantId)
		if userId ~= nil then
			player = Players:GetPlayerByUserId(userId)
		end
	end
	return colorFor(player, Config.Progression.attributes.tracer, "tracer")
end

return CosmeticLook
