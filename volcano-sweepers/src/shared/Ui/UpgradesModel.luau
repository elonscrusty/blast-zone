--!strict
-- View-model for the Upgrades panel: one row per upgrade line, with every string and yes/no the
-- panel shows already decided here, so Lune tests cover them. Pure: no Roblox types.
--
--   UpgradesModel.build(view) -> Model     view = the client store table (or any profile-like table)
--   UpgradesModel.levels(view) -> { [id]: level }
--   UpgradesModel.levelUps(before, view) -> { id }   lines whose level went UP since `before`
--   UpgradesModel.canBuyAny(view) -> boolean         for the red dot on the menu button
--
-- The star (Row.best, tag text Model.bestTag) = the not-maxed line with the LOWEST price right now,
-- and the panel says so ("⭐ Cheapest"): upgrade lines do different things, so the game does not
-- pretend one is "the best". Ties go to the earlier line in the catalog.
-- A player who has bought nothing yet is told how cheap the first upgrade is.

local Pricing = require("../Rules/Pricing")
local Upgrades = require("../Catalog/Upgrades")
local Types = require("../Types")
local Util = require("./ShopModelUtil")

local UpgradesModel = {}

export type Row = {
	id: string,
	name: string,
	desc: string,
	icon: string,
	level: number,
	maxLevel: number,
	maxed: boolean,
	levelText: string, -- "Level 3 of 16"
	price: number?, -- nil when maxed
	affordable: boolean,
	missing: number, -- coins still needed (0 when affordable or maxed)
	needText: string?, -- "Need 120 more coins!" (nil when affordable or maxed)
	buttonLabel: string?, -- "MAX" when maxed
	effectNow: string, -- "+16% reach"
	effectNext: string?, -- "+20%" (nil when maxed)
	effectLine: string, -- "+16% reach → +20%"
	best: boolean, -- the ⭐ cheapest next step
}

export type Model = {
	rows: { Row },
	coins: number,
	coinsText: string,
	bestId: string?,
	canBuyAny: boolean,
	allMaxed: boolean,
	hint: string, -- one friendly line under the coin counter
	bestTag: string, -- text of the star tag: "⭐ Cheapest"
	firstBuy: boolean, -- nothing bought yet
}

UpgradesModel.BEST_TAG = "⭐ Cheapest"

local ICONS: { [string]: string } = {
	power = "💪",
	backpack = "🎒",
	speed = "⚡",
	reach = "📏",
	walk = "👟",
	sell = "💰",
	luck = "🍀",
	armor = "🛡",
	sweetspot = "🎯",
	lucky_coins = "🎁",
}

function UpgradesModel.iconOf(id: string): string
	return ICONS[id] or "⭐"
end

-- "+20% reach" -> "+20%"
local function percentOnly(text: string): string
	local first = string.match(text, "^(%S+)")
	return first or text
end

local function levelOf(profile: Types.Profile, id: string): number
	local up = Upgrades.byId[id]
	local v = profile.upgrades[id]
	if up == nil or type(v) ~= "number" or v ~= v then
		return 0
	end
	return math.clamp(math.floor(v), 0, up.maxLevel)
end

function UpgradesModel.levels(view: { [string]: any }?): { [string]: number }
	local profile = Util.profile(view)
	local out: { [string]: number } = {}
	for _, id in Upgrades.order do
		out[id] = levelOf(profile, id)
	end
	return out
end

function UpgradesModel.levelUps(before: { [string]: number }, view: { [string]: any }?): { string }
	local now = UpgradesModel.levels(view)
	local ups: { string } = {}
	for _, id in Upgrades.order do
		local old = before[id]
		if type(old) == "number" and now[id] > old then
			table.insert(ups, id)
		end
	end
	return ups
end

local function buildRow(profile: Types.Profile, up: Upgrades.Upgrade): Row
	local level = levelOf(profile, up.id)
	local maxed = level >= up.maxLevel
	local price = if maxed then nil else Pricing.priceOf("upgrade", up.id, profile)
	-- a catalog that says "not maxed" but gives no price is treated as maxed (nothing to buy)
	if price == nil then
		maxed = true
	end
	local affordable = price ~= nil and profile.coins >= price
	local missing = if price ~= nil and not affordable
		then Util.missing(price, profile.coins)
		else 0
	local nowText = Upgrades.effectText(up.id, level)
	local nextText: string? = nil
	local line = `{nowText} (MAX!)`
	if not maxed then
		nextText = percentOnly(Upgrades.effectText(up.id, level + 1))
		line = `{nowText} → {nextText}`
	end
	return {
		id = up.id,
		name = up.name,
		desc = up.desc,
		icon = UpgradesModel.iconOf(up.id),
		level = level,
		maxLevel = up.maxLevel,
		maxed = maxed,
		levelText = `Level {level} of {up.maxLevel}`,
		price = price,
		affordable = affordable,
		missing = missing,
		needText = if missing > 0 then Util.needText(missing) else nil,
		buttonLabel = if maxed then "MAX" else nil,
		effectNow = nowText,
		effectNext = nextText,
		effectLine = line,
		best = false,
	}
end

function UpgradesModel.build(view: { [string]: any }?): Model
	local profile = Util.profile(view)
	local rows: { Row } = {}
	local best: Row? = nil
	local anyAffordable = false
	local allMaxed = true
	local bought = 0
	for _, id in Upgrades.order do
		local up = Upgrades.byId[id]
		local row = buildRow(profile, up)
		table.insert(rows, row)
		bought += row.level
		if not row.maxed then
			allMaxed = false
			if row.affordable then
				anyAffordable = true
			end
			local price = row.price :: number
			if best == nil or price < (best.price :: number) then
				best = row
			end
		end
	end
	if best ~= nil then
		best.best = true
	end

	local firstBuy = bought == 0
	local hint: string
	if allMaxed then
		hint = "Wow! Every upgrade is maxed out!"
	elseif firstBuy and best ~= nil and best.price ~= nil then
		hint = if anyAffordable
			then "Tap a green button to get stronger!"
			else `Your first upgrade costs only {best.price} coins! Sweep and sell to get it.`
	elseif anyAffordable then
		hint = "Green = you can buy it. ⭐ = cheapest next step."
	elseif best ~= nil then
		hint = `Cheapest next: {best.name}. {best.needText or ""}`
	else
		hint = ""
	end
	return {
		rows = rows,
		coins = profile.coins,
		coinsText = Util.coinsText(profile.coins),
		bestId = if best then best.id else nil,
		canBuyAny = anyAffordable,
		allMaxed = allMaxed,
		hint = hint,
		bestTag = UpgradesModel.BEST_TAG,
		firstBuy = firstBuy,
	}
end

function UpgradesModel.canBuyAny(view: { [string]: any }?): boolean
	return UpgradesModel.build(view).canBuyAny
end

return UpgradesModel
