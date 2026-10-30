--!strict
-- Shows other participants' slides and hops: the server says "p123 slid" (or hopped), this draws the
-- streak on that body. Your own slide draws its streak the moment you press, so it is skipped here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local Net = require(script.Parent.Parent.Core.Net)
local SlideTrail = require("./SlideTrail")

local SlideFxSystem = {}
SlideFxSystem.order = 120

local function characterOf(id: string): Model?
	local userId = Ids.userIdOf(id)
	if userId then
		local other = Players:GetPlayerByUserId(userId)
		return if other then other.Character else nil
	end
	for _, inst in workspace:GetChildren() do
		if inst:IsA("Model") and inst:GetAttribute(Config.Attributes.ParticipantId) == id then
			return inst
		end
	end
	return nil
end

function SlideFxSystem.start()
	local ownId = Ids.player(Players.LocalPlayer.UserId)
	local function streak(fx: { participantId: string, duration: number })
		if
			type(fx) ~= "table"
			or fx.participantId == ownId
			or not Ids.isValid(fx.participantId)
		then
			return
		end
		local character = characterOf(fx.participantId)
		if character and type(fx.duration) == "number" then
			SlideTrail.play(character, math.clamp(fx.duration, 0.05, 1))
		end
	end
	Net.on("SlideFx", streak)
	Net.on("VaultFx", streak) -- a hop over low cover gets the same streak
end

return SlideFxSystem
