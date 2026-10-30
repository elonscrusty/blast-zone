--!strict
-- Current matchId and phase. See shared/MatchContext for the API. Only piece 05 calls setPhase/beginMatch.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local MatchContext = require(Shared.MatchContext)

return MatchContext.new(os.clock)
