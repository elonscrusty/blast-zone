--!strict
-- Lets a player choose which of the three fighter looks to wear. The look is a Player attribute
-- (Config.Character.lookAttribute), so it holds for every spawn this session. Only outside a fight:
-- the server refuses it while a match is in combat. Saving the choice between sessions waits for Phase 5.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Looks = require(Shared.Character.Looks)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)
local Net = require(script.Parent.Parent.Core.Net)
local CharacterStyler = require(script.Parent.CharacterStyler)

local CharacterLookSystem = {}
CharacterLookSystem.order = 95

local function isKnown(name: string): boolean
	for _, known in Looks.NAMES do
		if known == name then
			return true
		end
	end
	return false
end

function CharacterLookSystem.start()
	Net.onRequest("SetLookRequest", function(player: Player, look: string)
		if not isKnown(look) or MatchContext:isCombat() then
			return
		end
		local attribute = Config.Character.lookAttribute
		if player:GetAttribute(attribute) == look then
			return
		end
		player:SetAttribute(attribute, look)
		-- A body already standing in the lobby changes at once; otherwise the next spawn wears it.
		local character = player.Character
		if character ~= nil and character.Parent ~= nil then
			CharacterStyler.apply(character)
		end
	end)
end

return CharacterLookSystem
