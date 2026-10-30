--!strict
-- The one squad book for the server. MatchController seats teams in it at Spawning; SquadSystem fills in the
-- wanted size and parties first; the damage door, shots, shells and bots read it. See shared/Squads/SquadBook.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local SquadBook = require(Shared.Squads.SquadBook)

return SquadBook.new()
