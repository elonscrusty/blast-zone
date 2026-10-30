--!strict
-- Which winner pose to draw for a participant: the one the player picked (Player attribute set by the server),
-- else the default. Bots always use the default.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local EmoteRules = require(Shared.Character.EmoteRules)
local Ids = require(Shared.Ids)

local WinPose = {}

function WinPose.of(participantId: string): string
	local tuning = Config.Emotes
	local userId = Ids.userIdOf(participantId)
	local player = if userId ~= nil then Players:GetPlayerByUserId(userId) else nil
	local picked = if player ~= nil then player:GetAttribute(tuning.winPoseAttribute) else nil
	return EmoteRules.winPoseOr(picked, tuning.defaultWinPose)
end

return WinPose
