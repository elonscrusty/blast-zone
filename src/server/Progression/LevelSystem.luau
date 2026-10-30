--!strict
-- Account level on the server (piece 34). Watches the run XP ledger during a match (the same XP that fills the
-- upgrade bar), and when the match pays its rewards, adds that XP to the player's saved account XP. The numbers
-- come from the server's own ledger and MatchSystem.RewardGranted; no client number is ever used. Bots have no
-- account, so they are skipped. Levels, gifts and saving are in ProgressionSystem / shared/Level.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ids = require(Shared.Ids)

local Server = script.Parent.Parent
local MatchContext = require(Server.Core.MatchContext)
local RunXp = require(Server.Core.RunXp)

local LevelSystem = {}
LevelSystem.order = 65 -- after ProgressionSystem (60)

-- Latest run XP total per participant, tagged with the match it belongs to. Kept here because the ledger
-- forgets people when the roster clears, which can be before the reward is paid.
local seen: { [string]: { matchId: number, xp: number } } = {}

function LevelSystem.start()
	local ProgressionSystem = require(Server.Progression.ProgressionSystem)
	local Match = require(Server.Match.MatchSystem)

	RunXp.Changed:connect(function(id: string, state)
		seen[id] = { matchId = MatchContext:getMatchId(), xp = state.totalXp }
	end)

	Match.RewardGranted:connect(
		function(participantId: string, _amount: number, _place: number, matchId: number)
			local entry = seen[participantId]
			seen[participantId] = nil
			local userId = Ids.userIdOf(participantId)
			if userId == nil or entry == nil or entry.matchId ~= matchId or entry.xp <= 0 then
				return
			end
			local player = Players:GetPlayerByUserId(userId)
			if player ~= nil then
				ProgressionSystem.onXp(player, entry.xp, matchId)
			end
		end
	)
end

return LevelSystem
