--!strict
-- Run XP ledger (shared/RunXp). Enrolling a participant resets their XP to level 1.
--   RunXp:award(participantId, "containerBreak" | "orbPickup" | "elimination")
--   RunXp.LevelUp:connect(function(participantId, level, pendingOffers) ... end)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local RunXp = require(Shared.RunXp)
local Participants = require(script.Parent.Participants)

local ledger = RunXp.new(Config.Xp)

Participants.Enrolled:connect(function(p)
	ledger:reset(p.id)
end)

-- Cleared with the roster (and on disconnect), so the ledger never keeps people from old matches.
Participants.Removed:connect(function(p)
	ledger:forget(p.id)
end)

return ledger
