--!strict
-- Builds the effect pools once, before the first fight, so nothing is created in the middle of a shot.

local Fx = require("./Fx")

local EffectsSystem = {}
EffectsSystem.order = 40

function EffectsSystem.start()
	Fx.start()
end

return EffectsSystem
