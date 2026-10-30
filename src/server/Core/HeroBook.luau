--!strict
-- Server side of the hero roster: HeroBook:of(participantId) -> hero id. The loadout piece installs where
-- player picks come from; until then every player is the default hero. Bots get theirs by number.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local HeroRoster = require(Shared.HeroRoster)

local picker: ((userId: number) -> string?)? = nil

local HeroBook = {}

function HeroBook:setPicker(fn: ((userId: number) -> string?)?)
	picker = fn
end

function HeroBook:of(participantId: string): string
	return HeroRoster.heroOf(Config, participantId, picker)
end

return HeroBook
