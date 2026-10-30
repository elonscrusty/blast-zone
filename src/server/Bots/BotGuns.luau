--!strict
-- How a bot fights with each gun, and which found guns are worth walking to. Pure, so Lune can
-- test it. The numbers are about distance habits only; the guns' own numbers live in
-- Config.Weapons.Guns and bots get exactly what a player gets.

export type Profile = {
	idealFraction: number?, -- fights at this share of the gun's range (nil = the bot default)
	closeRange: number?, -- backs away when closer than this (nil = the bot default)
	fireFraction: number?, -- only pulls the trigger inside this share of the range (nil = 0.95)
}

local BotGuns = {}

local PROFILES: { [string]: Profile } = {
	breaker = { idealFraction = 0.45, closeRange = 3, fireFraction = 0.8 }, -- rush in, never kite
	hornet = { idealFraction = 0.55, closeRange = 10, fireFraction = 0.95 }, -- mid range spray
	longline = { idealFraction = 0.8, closeRange = 30, fireFraction = 0.98 }, -- stay far, back off
}

-- Higher is better to hold. The pistol is the floor; a bot only swaps UP, so two guns on the
-- ground never make it swap back and forth.
local RANK: { [string]: number } = {
	breaker = 2,
	longline = 2,
	hornet = 3,
}

local EMPTY: Profile = {}

function BotGuns.profile(gunId: string?): Profile
	if gunId == nil then
		return EMPTY
	end
	return PROFILES[gunId] or EMPTY
end

function BotGuns.rank(gunId: string?): number
	if gunId == nil then
		return 0
	end
	return RANK[gunId] or 0
end

-- True when picking up `offered` is an upgrade over `holding` (nil holding = the pistol).
function BotGuns.wants(holding: string?, offered: string): boolean
	return BotGuns.rank(offered) > BotGuns.rank(holding)
end

return BotGuns
