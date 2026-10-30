--!strict
-- Name plates over every fighter (piece 44). Pure: no Roblox. The server keeps Health, MaxHealth,
-- Alive, Level and PlateName on each fighter's model; this turns those into what a plate shows.

export type Attributes = {
	Health: any,
	MaxHealth: any,
	Alive: any,
	Level: any,
	PlateName: any,
}

export type Config = {
	maxNameLength: number,
	lowHealthFraction: number,
	showOwnPlate: boolean,
}

export type View = {
	visible: boolean,
	name: string,
	levelText: string,
	fraction: number, -- 0..1 of the bar
	low: boolean, -- health is low: the bar takes the danger colour
}

local MomentRules = require("./MomentRules")

local PlateRules = {}

PlateRules.MAX_LEVEL_SHOWN = 99

local function number(v: any): number?
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else nil
end

-- "7" for level 7, "99+" past the cap, "1" for anything that is not a sane number.
function PlateRules.levelText(level: any): string
	local n = number(level)
	if n == nil or n < 1 then
		return "1"
	end
	n = math.floor(n)
	if n > PlateRules.MAX_LEVEL_SHOWN then
		return `{PlateRules.MAX_LEVEL_SHOWN}+`
	end
	return tostring(n)
end

function PlateRules.fraction(health: any, max: any): number
	local h, m = number(health), number(max)
	if h == nil or m == nil or m <= 0 then
		return 0
	end
	return math.clamp(h / m, 0, 1)
end

-- What one plate shows. A plate is on while the fighter is alive and the server has told us their
-- health. `isSelf` plates are off unless the config says otherwise (your own bar is in the HUD).
function PlateRules.view(attrs: Attributes, isSelf: boolean, cfg: Config): View
	local max = number(attrs.MaxHealth)
	local health = number(attrs.Health)
	local name = if type(attrs.PlateName) == "string" and #attrs.PlateName > 0
		then MomentRules.shortName(attrs.PlateName, cfg.maxNameLength)
		else "?"
	local fraction = PlateRules.fraction(health, max)
	return {
		visible = attrs.Alive ~= false
			and health ~= nil
			and max ~= nil
			and max > 0
			and (not isSelf or cfg.showOwnPlate),
		name = name,
		levelText = PlateRules.levelText(attrs.Level),
		fraction = fraction,
		low = fraction > 0 and fraction <= cfg.lowHealthFraction,
	}
end

-- A level-up is the level going UP from a level we already saw. The first number a model ever shows
-- (a late joiner, a fresh spawn) is not a level-up, so nobody bursts on arrival.
function PlateRules.leveledUp(previous: any, now: any): boolean
	local a, b = number(previous), number(now)
	return a ~= nil and b ~= nil and b > a
end

-- Height of the floor under a fighter: the root part sits `hipHeight + half its own height` above it.
function PlateRules.floorY(rootY: number, rootHeight: number, hipHeight: number): number
	return rootY - hipHeight - rootHeight / 2
end

-- Which rings to draw. Your own ring and an enemy ring are separate switches.
function PlateRules.wantsRing(isSelf: boolean, ownRing: boolean, enemyRing: boolean): boolean
	return if isSelf then ownRing else enemyRing
end

-- How far a burst has opened, 0..1, for the ring on the floor and the arrow over the head.
function PlateRules.burstProgress(elapsed: number, seconds: number): number
	if seconds <= 0 then
		return 1
	end
	return math.clamp(elapsed / seconds, 0, 1)
end

-- Cheap smooth ease-out (1 - (1 - t)^3), for opening rings and rising arrows.
function PlateRules.easeOut(t: number): number
	local u = 1 - math.clamp(t, 0, 1)
	return 1 - u * u * u
end

return PlateRules
