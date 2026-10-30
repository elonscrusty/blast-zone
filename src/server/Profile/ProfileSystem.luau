--!strict
-- Starts saving first, so every other system can rely on Profiles being ready to use.

local Profiles = require(script.Parent.Profiles)

local ProfileSystem = {}
ProfileSystem.order = 10

function ProfileSystem.start()
	Profiles.init()
end

return ProfileSystem
