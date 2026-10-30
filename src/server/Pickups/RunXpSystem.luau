--!strict
-- Run XP wiring for this piece: elimination XP, and telling each player their own XP (XpState).
-- The ledger itself is Core/RunXp. Piece 08 hears LevelUp there and spends the offers.
--   * Elimination XP goes to the killer once per victim (the damage door fires Eliminated once), and only
--     if the killer is still alive. Zone and disconnect eliminations have no killer, so no XP.
--   * XP never comes from a client number: only the reasons named in Config.Xp.rewards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

local Net = require(script.Parent.Parent.Core.Net)
local Damage = require(script.Parent.Parent.Core.Damage)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)
local Participants = require(script.Parent.Parent.Core.Participants)
local RunXp = require(script.Parent.Parent.Core.RunXp)

local RunXpSystem = {}
RunXpSystem.order = 100

local function send(participantId: string, state: Types.XpState)
	local participant = Participants:get(participantId)
	local player = if participant then participant.player else nil
	if player == nil then
		return -- bots have no screen
	end
	Net.fire("XpState", player, {
		level = state.level,
		xp = state.xp,
		xpToNext = state.xpToNext,
		totalXp = state.totalXp,
		pendingOffers = state.pendingOffers,
		offersGranted = state.offersGranted,
	})
end

function RunXpSystem.start()
	RunXp.Changed:connect(send)

	Damage.Eliminated:connect(function(event: Types.EliminationEvent)
		local killerId = event.killerId
		if
			killerId == nil
			or killerId == event.victimId
			or not MatchContext:isCurrent(event.matchId)
			or not Participants:isAlive(killerId)
		then
			return
		end
		RunXp:award(killerId, "elimination")
	end)

	-- A client that was still loading when it was enrolled hears its XP again when the fight starts.
	MatchContext.PhaseChanged:connect(function(phase: string)
		if phase ~= "Active" then
			return
		end
		for _, participant in Participants:list() do
			local state = RunXp:get(participant.id)
			if state then
				send(participant.id, state)
			end
		end
	end)
end

return RunXpSystem
