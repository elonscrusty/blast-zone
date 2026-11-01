--!strict
-- View-model for the Helpers panel: six bot slots, the "Buy bot" and "Level up" buttons, and an
-- honest income guess ("about 120 coins a minute") from Catalog/Helpers. Pure: no Roblox types.
--
--   HelpersModel.build(view) -> Model
--   HelpersModel.incomePerMinute(count, level, zoneValue, sellMult, helperMult) -> number
--   HelpersModel.canBuyAny(view) -> boolean
--
-- The estimate uses your best OPEN zone (bots only sweep zones you opened), derived.sellMult and
-- derived.helperMult, exactly like the server pays them.

local Helpers = require("../Catalog/Helpers")
local Zones = require("../Catalog/Zones")
local Pricing = require("../Rules/Pricing")
local Util = require("./ShopModelUtil")

local HelpersModel = {}

export type Slot = { index: number, filled: boolean }

export type BuyInfo = {
	price: number?, -- nil when you own all six
	affordable: boolean,
	missing: number,
	needText: string?,
	label: string?, -- shown instead of a price: "ALL 6!"
	gainText: string?, -- "+about 6 coins a minute"
}

export type UpInfo = {
	price: number?, -- nil when maxed or no bots yet
	affordable: boolean,
	missing: number,
	needText: string?,
	label: string?, -- "MAX" / "GET A BOT"
	gainText: string?,
	speedNow: string, -- "x1.6"
	speedNext: string?, -- "x2" (nil at the max level)
	effectLine: string, -- "Bot speed x1.6 → x2"
}

export type Model = {
	count: number,
	max: number,
	level: number,
	maxLevel: number,
	levelText: string, -- "Level 3 of 15"
	slots: { Slot },
	buy: BuyInfo,
	up: UpInfo,
	coins: number,
	coinsText: string,
	zoneName: string,
	zoneValue: number,
	perMinute: number,
	incomeText: string, -- "about 120 coins a minute"
	canBuyAny: boolean,
	hint: string,
}

function HelpersModel.incomePerMinute(
	count: number,
	level: number,
	zoneValue: number,
	sellMult: number,
	helperMult: number
): number
	return Helpers.coinsPerSecond(count, level, zoneValue, sellMult, helperMult) * 60
end

-- How many times faster a bot is at `level` than a brand new one: 1, 1.25, 1.56 ...
local function speedRatio(level: number): number
	return Helpers.unitsPerSecond(level) / Helpers.unitsPerSecond(0)
end

local function coinsPhrase(perMinute: number): string
	local text = Util.niceNumber(perMinute)
	return `about {text} {if text == "1" then "coin" else "coins"} a minute`
end

function HelpersModel.build(view: { [string]: any }?): Model
	local profile = Util.profile(view)
	local sellMult = Util.sellMult(view)
	local helperMult = Util.helperMult(view)
	local count = math.clamp(profile.helpers, 0, Helpers.max)
	local level = math.clamp(profile.helperLevel, 0, Helpers.maxLevel)

	local zoneId = Util.bestZone(profile.zones)
	local zone = Zones.byId[zoneId] or Zones.list[1]
	local zoneValue = zone.value

	local slots: { Slot } = {}
	for i = 1, Helpers.max do
		table.insert(slots, { index = i, filled = i <= count })
	end

	local perMinute = HelpersModel.incomePerMinute(count, level, zoneValue, sellMult, helperMult)

	-- buy a bot
	local buyPrice = Pricing.priceOf("helper", "", profile)
	local buy: BuyInfo
	if buyPrice == nil then
		buy = {
			price = nil,
			affordable = false,
			missing = 0,
			needText = nil,
			label = `ALL {Helpers.max}!`,
			gainText = nil,
		}
	else
		local affordable = profile.coins >= buyPrice
		local missing = if affordable then 0 else Util.missing(buyPrice, profile.coins)
		local gain = HelpersModel.incomePerMinute(count + 1, level, zoneValue, sellMult, helperMult)
			- perMinute
		buy = {
			price = buyPrice,
			affordable = affordable,
			missing = missing,
			needText = if missing > 0 then Util.needText(missing) else nil,
			label = nil,
			gainText = `+{coinsPhrase(gain)}`,
		}
	end

	-- level up all bots
	local upPrice = Pricing.priceOf("helperUp", "", profile)
	local speedNow = Util.multText(speedRatio(level))
	local up: UpInfo
	if count < 1 then
		up = {
			price = nil,
			affordable = false,
			missing = 0,
			needText = nil,
			label = "GET A BOT",
			gainText = nil,
			speedNow = speedNow,
			speedNext = Util.multText(speedRatio(level + 1)),
			effectLine = "Level up makes every bot faster!",
		}
	elseif upPrice == nil then
		up = {
			price = nil,
			affordable = false,
			missing = 0,
			needText = nil,
			label = "MAX",
			gainText = nil,
			speedNow = speedNow,
			speedNext = nil,
			effectLine = `Bot speed {speedNow} (MAX!)`,
		}
	else
		local affordable = profile.coins >= upPrice
		local missing = if affordable then 0 else Util.missing(upPrice, profile.coins)
		local speedNext = Util.multText(speedRatio(level + 1))
		local gain = HelpersModel.incomePerMinute(count, level + 1, zoneValue, sellMult, helperMult)
			- perMinute
		up = {
			price = upPrice,
			affordable = affordable,
			missing = missing,
			needText = if missing > 0 then Util.needText(missing) else nil,
			label = nil,
			gainText = `+{coinsPhrase(gain)}`,
			speedNow = speedNow,
			speedNext = speedNext,
			effectLine = `Bot speed {speedNow} → {speedNext}`,
		}
	end

	local incomeText: string
	if count < 1 then
		incomeText = "Get a bot and it sweeps for you!"
	else
		incomeText = coinsPhrase(perMinute)
	end

	local canBuyAny = buy.affordable or up.affordable
	local hint: string
	if count < 1 then
		hint = "Bots follow you and sweep ash all by themselves."
	elseif count >= Helpers.max and level >= Helpers.maxLevel then
		hint = "All six bots are at the top level. Amazing!"
	elseif canBuyAny then
		hint = "Your bots can grow! Tap a green button."
	else
		hint = `Your bots sweep {zone.name} for you.`
	end

	return {
		count = count,
		max = Helpers.max,
		level = level,
		maxLevel = Helpers.maxLevel,
		levelText = `Level {level} of {Helpers.maxLevel}`,
		slots = slots,
		buy = buy,
		up = up,
		coins = profile.coins,
		coinsText = Util.coinsText(profile.coins),
		zoneName = zone.name,
		zoneValue = zoneValue,
		perMinute = perMinute,
		incomeText = incomeText,
		canBuyAny = canBuyAny,
		hint = hint,
	}
end

function HelpersModel.canBuyAny(view: { [string]: any }?): boolean
	return HelpersModel.build(view).canBuyAny
end

return HelpersModel
