--!strict
-- Sends the big-moment call-outs (piece 44). Only the server decides a moment happened; the payload is
-- checked with the same rules the client uses before it leaves, so a bug here cannot send junk.
-- Streaks go to the player who earned them, and to everyone when the tier says so.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MomentRules = require(Shared.Moments.MomentRules)

local Net = require(script.Parent.Parent.Core.Net)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)

local Moments = {}

type Participant = { id: string, displayName: string, player: any? }

local function send(payload: MomentRules.Payload, only: Player?)
	if not Config.Moments.enabled then
		return
	end
	if not MomentRules.isValid(payload) then
		warn(`[Moments] dropped a bad {payload.kind} payload`)
		return
	end
	if only ~= nil then
		Net.fire("Moment", only, payload)
	else
		Net.fireAll("Moment", payload)
	end
end

-- `tier` is the entry of Config.Streaks.tiers the kill reached.
function Moments.streak(participant: Participant, streak: number, tier: any)
	local moment = tier.moment
	if type(moment) ~= "string" then
		return
	end
	local payload: MomentRules.Payload = {
		kind = "streak",
		matchId = MatchContext:getMatchId(),
		tier = moment,
		streak = streak,
		actorId = participant.id,
		actorName = participant.displayName,
		heal = if tier.heal > 0 then tier.heal else nil,
	}
	if tier.announceAll == true then
		send(payload, nil)
	elseif participant.player ~= nil then
		send(payload, participant.player)
	end
end

function Moments.zone(kind: "zoneClosing" | "suddenDeath", matchId: number, stage: number)
	send({ kind = kind, matchId = matchId, stage = stage }, nil)
end

return Moments
