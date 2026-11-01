--!strict
-- The helper bots as 3D models (builder, not wired in: the main thread connects it).
--   HelperBots.build("A", level)  -> Model. A = Bumble (hover), B = Roller (wheels), C = Ember (volcano).
-- Origin = middle of the ground under the bot, -Z is forward. `level` (0..15, the shared helper
-- level) only changes the trim colour: bronze, silver, gold, volcano. Part count never changes.
-- Animator hooks: HelperBots.spinParts(model) (propeller blades / brush spokes: turn them),
-- HelperBots.bobParts(model) (bulbs and bubbles: bob them a little).

local BotSpecs = require(script.Parent.BotSpecs)
local ModelBuilder = require(script.Parent.ModelBuilder)

local HelperBots = {}

HelperBots.looks = BotSpecs.looks
HelperBots.names = BotSpecs.names

function HelperBots.build(look: string?, level: number?, opts: ModelBuilder.Opts?): Model
	local spec = BotSpecs.build(look, level)
	local model = ModelBuilder.build("HelperBot" .. spec.look, spec.parts, opts)
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

return HelperBots
