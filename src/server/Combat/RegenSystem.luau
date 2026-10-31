--!strict
-- Feel pass 2: health comes back by itself. Everyone in the fight, players and bots alike, gets a
-- little back once they have not been hurt for a few seconds. The server does all of it (Config.Regen).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local RegenRules = require(Shared.RegenRules)

local Core = script.Parent.Parent.Core
local MatchContext = require(Core.MatchContext)
local Participants = require(Core.Participants)

local Combatants = require(script.Parent.Combatants)

local RegenSystem = {}
RegenSystem.order = 150 -- after combat, streaks and pickups

local rules = RegenRules.new(Config.Regen)

local function tick(now: number)
	for _, p in Participants:aliveList() do
		local id = p.id
		local hp = Combatants.health(id)
		if hp ~= nil then
			local give = rules:step(id, hp, Combatants.maxHealth(id), now)
			if give > 0 then
				Combatants.heal(id, give)
				rules:applied(id, Combatants.health(id) or hp)
			end
		end
	end
end

function RegenSystem.start()
	if not Config.Regen.enabled then
		return
	end
	local acc = 0
	local last = os.clock()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		acc += now - last
		last = now
		if acc < Config.Regen.tickSeconds then
			return
		end
		acc = 0
		-- Only in the fight itself: the waiting room and the results screen heal nobody.
		if MatchContext:isCombat() then
			tick(now)
		end
	end)
	MatchContext.MatchStarted:connect(function()
		rules:clear()
	end)
end

return RegenSystem
