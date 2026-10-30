--!strict
-- Piece 36: small rewards for knockout streaks. Listens to eliminations, asks StreakRules what the
-- kill earned, then heals and/or boosts speed on the server. The call-out goes out as a Moment (piece 44);
-- the big banner is drawn by Moments/MomentBannerSystem. Clients never ask for any of this.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local StreakRules = require(Shared.StreakRules)

local Core = script.Parent.Parent.Core
local Damage = require(Core.Damage)
local Participants = require(Core.Participants)
local MatchContext = require(Core.MatchContext)
local EffectiveStats = require(Core.EffectiveStats)

local Combatants = require(script.Parent.Combatants)
local MovementSetup = require(script.Parent.Parent.Movement.MovementSetup)
local Moments = require(script.Parent.Parent.Moments.Moments)

local StreakSystem = {}
StreakSystem.order = 140 -- after combat and upgrades

local rules = StreakRules.new(Config.Streaks)
local boostUntil: { [string]: number } = {} -- id -> os.clock when the boost ends
local boostMultiplier: { [string]: number } = {}

local function humanoidOf(id: string): Humanoid?
	local model = Combatants.model(id)
	return model and model:FindFirstChildOfClass("Humanoid")
end

local function applySpeed(id: string)
	local humanoid = humanoidOf(id)
	if humanoid == nil then
		return
	end
	local mult = boostMultiplier[id] or 1
	MovementSetup.setSpeed(humanoid, EffectiveStats:get(id).moveSpeed * mult)
end

local function startBoost(id: string, mult: number, seconds: number)
	local endsAt = os.clock() + seconds
	boostUntil[id] = endsAt
	boostMultiplier[id] = mult
	applySpeed(id)
	local matchId = MatchContext:getMatchId()
	task.delay(seconds, function()
		-- A newer boost replaced this one, or the match moved on: leave it alone.
		if boostUntil[id] ~= endsAt or not MatchContext:isCurrent(matchId) then
			return
		end
		boostUntil[id] = nil
		boostMultiplier[id] = nil
		applySpeed(id)
	end)
end

local function clearBoosts()
	table.clear(boostUntil)
	table.clear(boostMultiplier)
end

function StreakSystem.start()
	if not Config.Streaks.enabled then
		return
	end
	Damage.Eliminated:connect(function(e)
		local victim = e.victimId
		rules:reset(victim)
		boostUntil[victim] = nil
		boostMultiplier[victim] = nil
		local killer = e.killerId
		-- Self-kills and zone deaths have no killer credit (Contracts: Damage).
		if killer == nil or killer == victim or not Participants:isAlive(killer) then
			return
		end
		if not MatchContext:isCombat() or not MatchContext:isCurrent(e.matchId) then
			return
		end
		local _, reward = rules:recordKill(killer, os.clock())
		if reward == nil then
			return
		end
		local tier = reward.tier
		if tier.heal > 0 then
			Combatants.heal(killer, tier.heal)
		end
		if tier.speedSeconds > 0 and tier.speedMultiplier > 1 then
			startBoost(killer, tier.speedMultiplier, tier.speedSeconds)
		end
		local p = Participants:get(killer)
		if p ~= nil then
			Moments.streak(p, reward.streak, tier)
		end
	end)
	-- An upgrade landing mid-boost keeps the boost on top of the new speed.
	EffectiveStats.Changed:connect(function(id: string)
		if boostMultiplier[id] ~= nil then
			applySpeed(id)
		end
	end)
	MatchContext.PhaseChanged:connect(function(phase: string)
		if phase == "Resetting" or phase == "Waiting" then
			rules:clear()
			clearBoosts()
		end
	end)
end

return StreakSystem
