--!strict
-- Sends player-behaviour events to Roblox AnalyticsService (see them in Creator Hub > Analytics).
-- Server only. Other pieces report with AnalyticsSystem.funnelStep(player, name) and AnalyticsSystem.gunPicked(player, id).

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = script.Parent.Parent:WaitForChild("Core")

local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local MatchContext = require(Core.MatchContext)
local Damage = require(Core.Damage)
local Participants = require(Core.Participants)
local AnalyticsTracker = require(script.Parent.AnalyticsTracker)

local FIELD_KEYS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01,
	Enum.AnalyticsCustomFieldKeys.CustomField02,
	Enum.AnalyticsCustomFieldKeys.CustomField03,
}

local AnalyticsSystem = {}
AnalyticsSystem.order = 900 -- after the pieces whose events it listens to

local tracker: any = nil
local lastOutcome = "win"

-- Analytics must never break the game: every send is wrapped.
local sink: AnalyticsTracker.Sink = {
	custom = function(player, eventName, value, fields)
		local keyed: { [Enum.AnalyticsCustomFieldKeys]: string } = {}
		for i, text in fields do
			if FIELD_KEYS[i] then
				keyed[FIELD_KEYS[i]] = text
			end
		end
		local ok, err = pcall(function()
			AnalyticsService:LogCustomEvent(player, eventName, value, keyed)
		end)
		if not ok then
			warn(`[analytics] {eventName} not sent: {err}`)
		end
	end,
	funnel = function(player, step, stepName)
		local ok, err = pcall(function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
		end)
		if not ok then
			warn(`[analytics] step {stepName} not sent: {err}`)
		end
	end,
}

function AnalyticsSystem.funnelStep(player: Player, stepName: string)
	if tracker then
		tracker:funnelStep(player, stepName)
	end
end

function AnalyticsSystem.gunPicked(player: Player, gunId: string)
	if tracker then
		tracker:gunPicked(player, gunId)
	end
end

local function playerOf(participantId: string): Player?
	local userId = Ids.userIdOf(participantId)
	return if userId then Players:GetPlayerByUserId(userId) else nil
end

function AnalyticsSystem.start()
	local guns = { Config.Weapons.Firearm.id, Config.Weapons.Explosive.id }
	tracker = AnalyticsTracker.new(sink, guns, os.clock)

	Players.PlayerAdded:Connect(function(player)
		tracker:funnelStep(player, "joined")
	end)
	for _, player in Players:GetPlayers() do
		tracker:funnelStep(player, "joined")
	end
	Players.PlayerRemoving:Connect(function(player)
		tracker:forget(player)
	end)

	Damage.Eliminated:connect(function(event)
		local victim = playerOf(event.victimId)
		if not victim then
			return
		end
		local killer = if event.killerId == nil or event.killerId == event.victimId
			then "none"
			elseif Ids.isBot(event.killerId) then "bot"
			else "player"
		tracker:died(victim, event.cause, killer, event.weaponId)
	end)

	MatchContext.PhaseChanged:connect(function(phase, _old, matchId)
		if phase == "Spawning" then
			-- Everyone is enrolled by now.
			tracker:matchStarted(matchId, Participants:list())
		elseif phase == "Finished" then
			local alive = Participants:aliveCount()
			lastOutcome = if alive == 1 then "win" elseif alive == 0 then "draw" else "abandoned"
			tracker:matchEnded(matchId, Participants:list(), lastOutcome)
		end
	end)
end

return AnalyticsSystem
