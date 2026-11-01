--!strict
-- ONE place that says what a thing costs and whether you can buy it. The server re-checks every
-- Buy with these exact functions; the client uses them to draw prices and greyed buttons.
-- kinds: upgrade | tool | zone | helper | helperUp | sparkPerk
-- Prices are whole numbers. sparkPerk prices are in Sparks, everything else is in coins.

local Types = require("../Types")
local Helpers = require("../Catalog/Helpers")
local SparkPerks = require("../Catalog/SparkPerks")
local Tools = require("../Catalog/Tools")
local Upgrades = require("../Catalog/Upgrades")
local Zones = require("../Catalog/Zones")

local Pricing = {}

export type Kind = "upgrade" | "tool" | "zone" | "helper" | "helperUp" | "sparkPerk"

local function zoneNumber(id: string | number): number?
	local n = if type(id) == "number" then id else tonumber(id)
	if n == nil or n ~= n or n ~= math.floor(n) then
		return nil
	end
	return n
end

local function level(map: { [string]: number }, id: string): number
	local v = map[id]
	if type(v) ~= "number" or v ~= v then
		return 0
	end
	return math.max(0, math.floor(v))
end

-- Share of upgrade cost removed by the Haggler Spark perk (0..0.15).
function Pricing.upgradeDiscount(profile: Types.Profile): number
	return SparkPerks.value("haggler", level(profile.sparkPerks, "haggler"))
end

-- The price of the next purchase of this thing, or nil when it can't be bought now
-- (unknown id, owned, maxed, or its gate isn't open yet).
function Pricing.priceOf(kind: string, id: string | number, profile: Types.Profile): number?
	if kind == "upgrade" then
		if type(id) ~= "string" then
			return nil
		end
		local cost = Upgrades.cost(id, level(profile.upgrades, id))
		if cost == nil then
			return nil
		end
		return math.max(1, math.floor(cost * (1 - Pricing.upgradeDiscount(profile)) + 0.5))
	elseif kind == "tool" then
		local tool = if type(id) == "string" then Tools.byId[id] else nil
		if not tool or profile.toolsOwned[tool.id] == true then
			return nil
		end
		return tool.price
	elseif kind == "zone" then
		local zid = zoneNumber(id)
		local zone = if zid then Zones.byId[zid] else nil
		if not zone or profile.zones[tostring(zone.id)] == true then
			return nil
		end
		if zone.id > 1 and profile.zones[tostring(zone.id - 1)] ~= true then
			return nil -- gates open one ring at a time
		end
		return zone.unlockPrice
	elseif kind == "helper" then
		return Helpers.price(profile.helpers)
	elseif kind == "helperUp" then
		if profile.helpers < 1 then
			return nil
		end
		return Helpers.upgradeCost(profile.helperLevel)
	elseif kind == "sparkPerk" then
		if type(id) ~= "string" then
			return nil
		end
		return SparkPerks.cost(id, level(profile.sparkPerks, id))
	end
	return nil
end

-- nil when you can buy it right now. Otherwise a short, kid-friendly reason.
function Pricing.reason(kind: string, id: string | number, profile: Types.Profile): string?
	local price = Pricing.priceOf(kind, id, profile)
	if price == nil then
		if kind == "upgrade" then
			return if Upgrades.byId[id :: string] then "Maxed out!" else "Unknown upgrade"
		elseif kind == "tool" then
			local tool = if type(id) == "string" then Tools.byId[id] else nil
			if not tool then
				return "Unknown tool"
			end
			return "You own this"
		elseif kind == "zone" then
			local zid = zoneNumber(id)
			local zone = if zid then Zones.byId[zid] else nil
			if not zone then
				return "Unknown zone"
			elseif profile.zones[tostring(zone.id)] == true then
				return "Already open"
			end
			local before = Zones.byId[zone.id - 1]
			return `Open {if before then before.name else "the last zone"} first`
		elseif kind == "helper" then
			return "You have all 6 bots"
		elseif kind == "helperUp" then
			if profile.helpers < 1 then
				return "Get a helper bot first"
			end
			return "Bots are maxed out!"
		elseif kind == "sparkPerk" then
			return if SparkPerks.byId[id :: string] then "Maxed out!" else "Unknown perk"
		end
		return "Can't buy that"
	end
	if kind == "sparkPerk" then
		if profile.sparks < price then
			return `Need {price - profile.sparks} more Sparks`
		end
	elseif profile.coins < price then
		return `Need {price - profile.coins} more coins`
	end
	return nil
end

return Pricing
