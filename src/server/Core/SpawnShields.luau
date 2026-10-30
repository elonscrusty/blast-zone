--!strict
-- The one spawn-shield book for the server. SpawnShieldSystem fills it; the damage door, firing and
-- bots read it. See shared/SpawnShield for the API.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local SpawnShield = require(Shared.SpawnShield)

return SpawnShield.new(os.clock)
