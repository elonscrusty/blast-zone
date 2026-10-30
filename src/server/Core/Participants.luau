--!strict
-- The match roster. See shared/ParticipantRegistry for the API.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ParticipantRegistry = require(Shared.ParticipantRegistry)

return ParticipantRegistry.new(os.clock)
