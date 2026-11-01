--!strict
-- Everything about buying, as plain rules (the PurchaseService is only glue around this).
-- `quote` says whether a Buy is allowed right now and why not; `buy` re-checks, takes the price and
-- applies the change in ONE synchronous call, so nothing can slip in between the check and the spend.
-- Prices and reasons come from Rules/Pricing (the same functions the client draws prices with).
--
-- kinds: upgrade | tool | zone | helper | helperUp | sparkPerk (sparkPerk costs Sparks, the rest coins)

local Types = require("../Types")
local Economy = require("../Rules/Economy")
local Pricing = require("../Rules/Pricing")
local SparkPerks = require("../Catalog/SparkPerks")
local Tools = require("../Catalog/Tools")
local Upgrades = require("../Catalog/Upgrades")
local Zones = require("../Catalog/Zones")
local ProfileSchema = require("../Profile/ProfileSchema")

local PurchaseRules = {}

export type Currency = "coins" | "sparks"
export type ToastKind = "info" | "good" | "warn" | "gold"

export type Quote = {
	ok: boolean,
	reason: string, -- "" when ok
	price: number, -- 0 when the thing can't be bought at all
	currency: Currency,
}

export type Result = {
	ok: boolean,
	message: string, -- kid-friendly text for the Toast (the reason when not ok)
	toastKind: ToastKind,
	price: number,
	currency: Currency,
	keys: { string }, -- View keys the change touched (for PlayerState.touch)
}

local KINDS: { [string]: boolean } = {
	upgrade = true,
	tool = true,
	zone = true,
	helper = true,
	helperUp = true,
	sparkPerk = true,
}

local SETTING_KEYS: { [string]: boolean } = {}
for _, key in ProfileSchema.SETTING_KEYS do
	SETTING_KEYS[key] = true
end

function PurchaseRules.isKind(kind: any): boolean
	return type(kind) == "string" and KINDS[kind] == true
end

function PurchaseRules.currencyOf(kind: string): Currency
	return if kind == "sparkPerk" then "sparks" else "coins"
end

-- 1234567 -> "1,234,567" (whole numbers only; rounds down)
function PurchaseRules.fmt(n: number): string
	if n ~= n or n == math.huge or n == -math.huge then
		return "0"
	end
	local text = tostring(math.floor(math.abs(n)))
	local out = text
	while true do
		local replaced, count = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		out = replaced
		if count == 0 then
			break
		end
	end
	return if n < 0 then "-" .. out else out
end

local function wholeLevel(map: { [string]: number }, id: string): number
	local v = map[id]
	if type(v) ~= "number" or v ~= v then
		return 0
	end
	return math.max(0, math.floor(v))
end

local function fail(reason: string, currency: Currency, price: number?): Quote
	return { ok = false, reason = reason, price = price or 0, currency = currency }
end

-- Can this profile buy (kind, id) right now? Never changes anything.
function PurchaseRules.quote(kind: any, id: any, profile: Types.Profile): Quote
	if not PurchaseRules.isKind(kind) then
		return fail("Can't buy that", "coins")
	end
	local k = kind :: string
	local currency = PurchaseRules.currencyOf(k)
	local needsName = k == "upgrade" or k == "tool" or k == "sparkPerk"
	local ident: string | number
	if needsName then
		if type(id) ~= "string" then
			return fail("Can't buy that", currency)
		end
		ident = id
	elseif k == "zone" then
		if type(id) ~= "string" and type(id) ~= "number" then
			return fail("Can't buy that", currency)
		end
		ident = id
	else
		ident = "" -- helper / helperUp ignore the id
	end
	local price = Pricing.priceOf(k, ident, profile)
	if price == nil then
		return fail(Pricing.reason(k, ident, profile) or "Can't buy that", currency)
	end
	if price < 0 or price ~= price or price ~= math.floor(price) then
		return fail("Can't buy that", currency) -- a broken catalog price never goes through
	end
	local reason = Pricing.reason(k, ident, profile)
	if reason ~= nil then
		return fail(reason, currency, price)
	end
	return { ok = true, reason = "", price = price, currency = currency }
end

local function bad(reason: string, currency: Currency, price: number): Result
	return {
		ok = false,
		message = reason,
		toastKind = "warn",
		price = price,
		currency = currency,
		keys = {},
	}
end

-- Checks again, takes the price and applies the purchase to `profile` (in place). The caller then
-- touches `result.keys`, calls PlayerState.recompute and shows the Toast.
function PurchaseRules.buy(profile: Types.Profile, kind: any, id: any): Result
	local q = PurchaseRules.quote(kind, id, profile)
	if not q.ok then
		return bad(q.reason, q.currency, q.price)
	end
	local k = kind :: string
	local price = q.price

	-- take the price (quote already proved the wallet covers it)
	local keys: { string }
	if q.currency == "sparks" then
		if profile.sparks < price then
			return bad("Not enough Sparks", q.currency, price)
		end
		profile.sparks -= price
		keys = { "sparks" }
	else
		if profile.coins < price then
			return bad("Not enough coins", q.currency, price)
		end
		profile.coins -= price
		keys = { "coins" }
	end

	local message = "Got it!"
	local toastKind: ToastKind = "good"
	if k == "upgrade" then
		local name = id :: string
		local level = wholeLevel(profile.upgrades, name) + 1
		profile.upgrades[name] = level
		table.insert(keys, "upgrades")
		message = `{Upgrades.byId[name].name} level {level}! {Upgrades.effectText(name, level)}`
	elseif k == "tool" then
		local name = id :: string
		profile.toolsOwned[name] = true
		profile.tool = name -- a new tool goes straight into your hands
		table.insert(keys, "toolsOwned")
		table.insert(keys, "tool")
		message = `You got the {Tools.byId[name].name}!`
	elseif k == "zone" then
		local zid = tonumber(id) :: number
		profile.zones[tostring(zid)] = true
		table.insert(keys, "zones")
		message = `{Zones.byId[zid].name} is open!`
		toastKind = "gold"
	elseif k == "helper" then
		profile.helpers += 1
		table.insert(keys, "helpers")
		message = `New helper bot! You have {profile.helpers}.`
	elseif k == "helperUp" then
		profile.helperLevel += 1
		table.insert(keys, "helperLevel")
		message = `Your bots are level {profile.helperLevel} now!`
	else -- sparkPerk
		local name = id :: string
		local level = wholeLevel(profile.sparkPerks, name) + 1
		profile.sparkPerks[name] = level
		table.insert(keys, "sparkPerks")
		message = `{SparkPerks.byId[name].name} level {level}!`
		toastKind = "gold"
		-- some perks hand something over at once (a Cool Down would too): Head Start coins, a free tool.
		-- Coins go to the wallet only, like a Cool Down reset (they are a gift, not run earnings).
		local grantCoins, grantTool = Economy.perkGrant(name, level)
		if grantCoins > 0 then
			profile.coins = math.min(ProfileSchema.MAX.coins, profile.coins + grantCoins)
		end
		if grantTool ~= nil and Tools.byId[grantTool] ~= nil then
			profile.toolsOwned[grantTool] = true
			table.insert(keys, "toolsOwned")
			if profile.tool == ProfileSchema.START_TOOL then
				profile.tool = grantTool -- same as a Cool Down: the free broom is in your hands
				table.insert(keys, "tool")
			end
		end
	end
	return {
		ok = true,
		message = message,
		toastKind = toastKind,
		price = price,
		currency = q.currency,
		keys = keys,
	}
end

-- Put on a tool you own. Returns ok, and a short message (the tool name, or why not).
function PurchaseRules.equip(profile: Types.Profile, id: any): (boolean, string)
	if type(id) ~= "string" then
		return false, "Can't use that"
	end
	local tool = Tools.byId[id]
	if tool == nil then
		return false, "Unknown tool"
	end
	if profile.toolsOwned[id] ~= true then
		return false, "You don't own this yet"
	end
	profile.tool = id
	return true, tool.name
end

-- Only the five real settings, only true / false.
function PurchaseRules.setSetting(profile: Types.Profile, key: any, value: any): boolean
	if type(key) ~= "string" or SETTING_KEYS[key] ~= true or type(value) ~= "boolean" then
		return false
	end
	(profile.settings :: any)[key] = value
	return true
end

export type Gate = {
	state: "open" | "buy" | "short" | "blocked" | "unknown",
	text: string,
}

-- What a gate prompt should do for this player: buy it, or say why not.
function PurchaseRules.gate(profile: Types.Profile, zoneId: any): Gate
	local zid = tonumber(zoneId)
	local zone = if zid ~= nil then Zones.byId[zid] else nil
	if zone == nil then
		return { state = "unknown", text = "This gate is sleepy. Try another one!" }
	end
	if profile.zones[tostring(zone.id)] == true then
		return { state = "open", text = "Already open!" }
	end
	local q = PurchaseRules.quote("zone", zone.id, profile)
	if q.ok then
		return { state = "buy", text = "" }
	end
	if q.price > 0 then
		local missing = math.max(1, q.price - math.floor(profile.coins))
		return {
			state = "short",
			text = `Collect {PurchaseRules.fmt(missing)} more coins to open {zone.name}!`,
		}
	end
	return { state = "blocked", text = q.reason .. "!" }
end

return PurchaseRules
