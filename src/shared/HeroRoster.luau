--!strict
-- Who plays which hero right now. Pure (no Roblox), so Lune can test it.
--   HeroRoster.heroOf(cfg, participantId, playerPick) -> hero id (always a real hero)
-- Players play the hero they picked in the loadout (`playerPick(userId)` answers from the server's loadout
-- store); bots play a hero by their number. A client never says which hero it is.
local Heroes = require("./Heroes")
local Ids = require("./Ids")

local HeroRoster = {}

function HeroRoster.heroOf(
	cfg: any,
	participantId: string,
	playerPick: ((userId: number) -> string?)?
): string
	local userId = Ids.userIdOf(participantId)
	if userId ~= nil then
		local pick = if playerPick then playerPick(userId) else nil
		return Heroes.sanitize(pick)
	end
	local digits = string.match(participantId, "^b(%d+)$")
	if digits ~= nil then
		return Heroes.forBot(cfg, tonumber(digits) or 0)
	end
	return Heroes.default
end

return HeroRoster
