--!strict
-- The helper bots as 3D models (server/Helpers/BotModel builds them; client/Vfx/BotAnim animates them).
--   HelperBots.build("B", level)  -> Model. B = Roller (wheels) is the main bot (carter's pick);
--   A = Bumble (hover) and C = Ember (volcano) are skins. No look given -> Roller.
-- Origin = middle of the ground under the bot, -Z is forward. `level` (0..15, the shared helper
-- level) only changes the trim colour: bronze, silver, gold, volcano. Part count never changes.
-- opts.lite = true builds only the basic shape (for bots far away).
-- Animator hooks: HelperBots.spinParts(model) (propeller blades / brush spokes: turn them),
-- HelperBots.bobParts(model) (bulbs and bubbles: bob them a little), HelperBots.spinAxis(look) (the
-- model-space axis the Spin parts turn around). The model's "Look" attribute names its look.

local BotSpecs = require(script.Parent.BotSpecs)
local ModelBuilder = require(script.Parent.ModelBuilder)

local HelperBots = {}

HelperBots.looks = BotSpecs.looks
HelperBots.names = BotSpecs.names
HelperBots.defaultLook = BotSpecs.defaultLook

function HelperBots.build(look: string?, level: number?, opts: ModelBuilder.Opts?): Model
	local spec = BotSpecs.build(look, level, opts ~= nil and opts.lite == true)
	local model = ModelBuilder.build("HelperBot" .. spec.look, spec.parts, opts)
	model:SetAttribute("Look", spec.look)
	model:SetAttribute("Level", spec.level)
	model:SetAttribute("Tier", BotSpecs.tierName(spec.level))
	return model
end

function HelperBots.spinParts(model: Model): { BasePart }
	return ModelBuilder.partsNamed(model, "Spin")
end

function HelperBots.bobParts(model: Model): { BasePart }
	return ModelBuilder.partsNamed(model, "Bob")
end

-- A's propeller turns about the up axis; B's brush roller about the side (X) axis. C has no Spin parts.
function HelperBots.spinAxis(look: string?): Vector3
	if look == "A" then
		return Vector3.yAxis
	end
	return Vector3.xAxis
end

return HelperBots
