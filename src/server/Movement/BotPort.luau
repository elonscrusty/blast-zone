--!strict
-- The door bots use (piece 09 looks for Server/Movement/BotPort). A bot slides with exactly the
-- same checks, distance, cooldown and stats as a player.

local EffectiveStats = require(script.Parent.Parent.Core.EffectiveStats)
local MovementSetup = require("./MovementSetup")
local SlideService = require("./SlideService")

local BotPort = {}

-- Returns true if the slide started.
function BotPort.slide(id: string, dirX: number, dirZ: number): boolean
	return SlideService.request(id, dirX, dirZ).ok
end

function BotPort.slideReady(id: string): boolean
	return SlideService.isReady(id)
end

-- Gives the bot's body the same walk speed rules as a player and lets the slide move it.
function BotPort.registerBotBody(id: string, model: Model)
	SlideService.registerBotBody(id, model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		MovementSetup.apply(humanoid, EffectiveStats:get(id).moveSpeed)
	end
end

return BotPort
