--!strict
-- THE damage door. Everything that hurts a participant calls Damage:apply(request).
--   Damage:apply({ matchId = ..., targetId = ..., amount = 10, cause = "bullet", sourceId = ..., weaponId = ... })
-- Piece 03 binds the health math once: Damage:bind(function(request) -> DamageResult end).
-- Listen with Damage.Damaged:connect(fn({ request, result })) and Damage.Eliminated:connect(fn(event)).
-- Stale-match, non-combat and double-elimination cases are already handled here.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DamageRouter = require(Shared.DamageRouter)
local MatchContext = require(script.Parent.MatchContext)
local MatchPhase = require(Shared.MatchPhase)
local Participants = require(script.Parent.Participants)

local router = DamageRouter.new({
	getMatchId = function()
		return MatchContext:getMatchId()
	end,
	allowsDamage = function()
		return MatchPhase.allowsDamage(MatchContext:getPhase())
	end,
	isAlive = function(id: string)
		return Participants:isAlive(id)
	end,
	markEliminated = function(id: string)
		return Participants:markEliminated(id)
	end,
	clock = os.clock,
})

MatchContext.MatchStarted:connect(function()
	router:reset()
end)

return router
