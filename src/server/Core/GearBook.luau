--!strict
-- Server side of gear: GearBook:of(participantId) -> { head, body, feet }. The loadout piece installs where
-- player picks come from; until then (and for every bot) nobody wears anything. Read once per match for health.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Gear = require(Shared.Gear)

local picker: ((userId: number) -> any)? = nil

local GearBook = {}

function GearBook:setPicker(fn: ((userId: number) -> any)?)
	picker = fn
end

function GearBook:of(participantId: string): { head: string, body: string, feet: string }
	return Gear.of(participantId, picker)
end

function GearBook:healthBonus(participantId: string): number
	return Gear.healthBonus(Config, GearBook:of(participantId))
end

return GearBook
