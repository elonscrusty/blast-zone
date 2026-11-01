--!strict
-- Small pure helpers shared by the four shop view-models (Upgrades, Tools, Helpers, Gates).
-- No Roblox types in here, so Lune can test every line.
--
--   ShopModelUtil.profile(view)       a safe, complete Types.Profile built from the (maybe half
--                                     empty) client store table, so Pricing never sees a nil
--   ShopModelUtil.sellMult(view)      derived.sellMult  (1 when the server has not sent it yet)
--   ShopModelUtil.helperMult(view)    derived.helperMult (1 when missing)
--   ShopModelUtil.bestZone(zones)     highest open zone id (1 at least)
--   ShopModelUtil.missing(price, coins)  whole coins still needed (0 when you have enough)
--   ShopModelUtil.needText(missing)   "Need 120 more coins!"
--   ShopModelUtil.multText(ratio)     3 -> "x3", 2.666 -> "x2.7"
--   ShopModelUtil.coinsText(n)        1234 -> "1,234"

local Types = require("../Types")
local Tools = require("../Catalog/Tools")
local Economy = require("../Rules/Economy")
local Format = require("./Format")

local ShopModelUtil = {}

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function num(v: any, default: number): number
	if finite(v) then
		return v
	end
	return default
end

local function whole(v: any): number
	return math.max(0, math.floor(num(v, 0)))
end

-- Copies a { [string]: boolean } table, keeping only real `true` values.
local function copyFlags(src: any, into: { [string]: boolean })
	if type(src) ~= "table" then
		return
	end
	for key, value in src do
		if type(key) == "string" and value == true then
			into[key] = true
		end
	end
end

-- Copies a { [string]: number } table of whole levels.
local function copyLevels(src: any, into: { [string]: number })
	if type(src) ~= "table" then
		return
	end
	for key, value in src do
		if type(key) == "string" and finite(value) then
			into[key] = whole(value)
		end
	end
end

function ShopModelUtil.profile(view: { [string]: any }?): Types.Profile
	local v: { [string]: any } = view or {}
	local p = Economy.blankProfile()
	p.coins = math.max(0, math.floor(num(v.coins, 0)))
	p.sparks = whole(v.sparks)
	p.helpers = math.min(whole(v.helpers), 99)
	p.helperLevel = whole(v.helperLevel)
	copyLevels(v.upgrades, p.upgrades)
	copyLevels(v.sparkPerks, p.sparkPerks)
	copyFlags(v.toolsOwned, p.toolsOwned)
	copyFlags(v.zones, p.zones)
	-- the Twig Broom and the Beach are always yours
	p.toolsOwned["twig_broom"] = true
	p.zones["1"] = true
	local tool = v.tool
	if type(tool) == "string" and Tools.byId[tool] ~= nil and p.toolsOwned[tool] == true then
		p.tool = tool
	else
		p.tool = "twig_broom"
	end
	return p
end

local function derivedNumber(view: { [string]: any }?, key: string): number
	if view == nil then
		return 1
	end
	local d = view.derived
	if type(d) ~= "table" then
		return 1
	end
	local n = (d :: any)[key]
	if finite(n) and n >= 0 then
		return n
	end
	return 1
end

function ShopModelUtil.sellMult(view: { [string]: any }?): number
	return derivedNumber(view, "sellMult")
end

function ShopModelUtil.helperMult(view: { [string]: any }?): number
	return derivedNumber(view, "helperMult")
end

-- Highest open zone id (the beach counts even if the map is empty).
function ShopModelUtil.bestZone(zones: { [string]: boolean }): number
	local best = 1
	for key, open in zones do
		local id = tonumber(key)
		if open == true and id ~= nil and id == math.floor(id) and id > best then
			best = id
		end
	end
	return best
end

function ShopModelUtil.missing(price: number, coins: number): number
	if not finite(price) or not finite(coins) then
		return 0
	end
	return math.max(0, math.ceil(price - coins))
end

function ShopModelUtil.coinsText(n: number): string
	return Format.commas(n)
end

function ShopModelUtil.needText(missing: number): string
	return `Need {Format.commas(missing)} more coins!`
end

-- 3 -> "x3", 2.666 -> "x2.7", 12.4 -> "x12"
function ShopModelUtil.multText(ratio: number): string
	if not finite(ratio) or ratio <= 0 then
		return "x1"
	end
	if ratio >= 10 then
		return `x{math.floor(ratio + 0.5)}`
	end
	local tenths = math.floor(ratio * 10 + 0.5) / 10
	if tenths == math.floor(tenths) then
		return `x{math.floor(tenths)}`
	end
	return `x{string.format("%.1f", tenths)}`
end

-- Rounds an estimate so it reads like a guess a kid understands:
-- 6.4 -> 6, 47 -> 45, 128 -> 130, 12345 -> "12.3K" (as text).
function ShopModelUtil.niceNumber(n: number): string
	if not finite(n) or n <= 0 then
		return "0"
	end
	if n < 10 then
		return tostring(math.max(1, math.floor(n + 0.5)))
	elseif n < 100 then
		return tostring(math.floor(n / 5 + 0.5) * 5)
	elseif n < 1000 then
		local rounded = math.floor(n / 10 + 0.5) * 10
		if rounded >= 1000 then
			return Format.compact(rounded)
		end
		return tostring(rounded)
	end
	return Format.compact(n)
end

return ShopModelUtil
