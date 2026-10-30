--!strict
-- Night traffic (piece SL). When the map for a match is built (Spawning) the server works out which
-- road stretches are free and tells everyone; it clears when the match goes back to Waiting. The
-- cars are only drawn by the clients and change nothing about shots, damage or the zone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchPhase = require(Shared.MatchPhase)
local TrafficPlan = require(Shared.Traffic.TrafficPlan)
local Types = require(Shared.Types)

local Core = script.Parent.Parent:WaitForChild("Core")
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)
local ArenaSystem = require(script.Parent.Parent:WaitForChild("Arena"):WaitForChild("ArenaSystem"))

local TrafficSystem = {}
TrafficSystem.order = 300 -- after the arena (10), so Spawning sees the new map

local rng = Random.new()
local current: Types.TrafficState = { matchId = 0, seed = 0, segments = {}, serverNow = 0 }

local function state(): Types.TrafficState
	return {
		matchId = current.matchId,
		seed = current.seed,
		segments = current.segments,
		serverNow = workspace:GetServerTimeNow(),
	}
end

local function set(matchId: number, segments: { TrafficPlan.Segment })
	current = {
		matchId = matchId,
		seed = rng:NextInteger(1, 2147483646),
		segments = segments,
		serverNow = 0,
	}
	Net.fireAll("TrafficState", state())
end

function TrafficSystem.getSegments(): { TrafficPlan.Segment }
	return current.segments
end

function TrafficSystem.start()
	if not Config.Features.traffic then
		return
	end
	MatchContext.PhaseChanged:connect(function(newPhase: string, _old: string, matchId: number)
		if newPhase == MatchPhase.Spawning then
			local layout = ArenaSystem.getLayout()
			local segments = {}
			if layout ~= nil then
				-- Looks only: a failure here must never stop a match.
				local ok, result = pcall(TrafficPlan.segments, layout.ground, layout.solids)
				if ok then
					segments = result
				else
					warn(`[traffic] no cars this match: {result}`)
				end
			end
			set(matchId, segments)
		elseif newPhase == MatchPhase.Waiting and #current.segments > 0 then
			set(matchId, {})
		end
	end)
	Net.onRequest("TrafficRequest", function(player: Player)
		Net.fire("TrafficState", player, state())
	end)
end

return TrafficSystem
