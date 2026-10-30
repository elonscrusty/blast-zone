--!strict
-- Rain for each match (piece 38). The server picks one level when the match starts and tells
-- everyone; it clears when the match goes back to Waiting. Clients only draw it. Weather changes
-- nothing about shots, damage or the zone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchPhase = require(Shared.MatchPhase)
local Types = require(Shared.Types)
local WeatherPlan = require(Shared.Weather.WeatherPlan)

local Core = script.Parent.Parent:WaitForChild("Core")
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)

local WeatherSystem = {}
WeatherSystem.order = 300

local rng = Random.new()
local current: Types.WeatherState = { matchId = 0, level = WeatherPlan.CLEAR, serverNow = 0 }
local lastLevel: string? = nil

local function state(): Types.WeatherState
	return {
		matchId = current.matchId,
		level = current.level,
		serverNow = workspace:GetServerTimeNow(),
	}
end

function WeatherSystem.getLevel(): string
	return current.level
end

local function set(matchId: number, level: string)
	current = { matchId = matchId, level = level, serverNow = 0 }
	Net.fireAll("WeatherState", state())
end

function WeatherSystem.start()
	MatchContext.MatchStarted:connect(function(matchId: number)
		local level = WeatherPlan.pick(rng:NextNumber(), lastLevel)
		lastLevel = level
		set(matchId, level)
	end)
	MatchContext.PhaseChanged:connect(function(newPhase: string, _old: string, matchId: number)
		if newPhase == MatchPhase.Waiting and current.level ~= WeatherPlan.CLEAR then
			set(matchId, WeatherPlan.CLEAR)
		end
	end)
	Net.onRequest("WeatherRequest", function(player: Player)
		Net.fire("WeatherState", player, state())
	end)
end

return WeatherSystem
