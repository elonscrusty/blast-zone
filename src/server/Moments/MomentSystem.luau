--!strict
-- Piece 44 on the server: the zone moments ("circle closing", "sudden death") and the run level that
-- every client shows on a name plate. Streak call-outs come from Combat/StreakSystem. Clients ask for nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

local Core = script.Parent.Parent.Core
local MatchContext = require(Core.MatchContext)
local RunXp = require(Core.RunXp)

local Combatants = require(script.Parent.Parent.Combat.Combatants)
local ZoneSystem = require(script.Parent.Parent.Zone.ZoneSystem)
local Moments = require(script.Parent.Moments)

local MomentSystem = {}
MomentSystem.order = 150 -- after combat and zone

function MomentSystem.start()
	-- The circle starts to close: one banner for everyone, once per stage.
	ZoneSystem.Event:connect(function(event: { kind: string, matchId: number, stage: number })
		if not MatchContext:isCurrent(event.matchId) then
			return
		end
		if event.kind == "ClosingStarted" then
			Moments.zone("zoneClosing", event.matchId, event.stage)
		elseif event.kind == "SuddenDeath" then
			Moments.zone("suddenDeath", event.matchId, event.stage)
		end
	end)

	-- The run level goes onto the fighter's model so every client can draw it (and burst when it rises).
	RunXp.Changed:connect(function(id: string, state: Types.XpState)
		local model = Combatants.model(id)
		if model ~= nil then
			model:SetAttribute("Level", state.level)
		end
	end)
end

return MomentSystem
