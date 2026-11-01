--!strict
-- The MENU launcher as plain data: which tiles get a red dot, and the little note under a tile.
-- Pure: time comes in as a parameter (pass SERVER time, never the device clock).
--
--   MenuModel.offers(view) -> Offers          what each shop could sell you right now
--   MenuModel.dots(view, serverNow, acks) -> { [panelId]: true }
--   MenuModel.ack(acks, panelId, view)        the player opened that panel: what it offers now
--                                             is "seen" and stops lighting the dot
--   MenuModel.anyDot(dots) -> boolean         one dot on the MENU button for all of them
--   MenuModel.tileNote(panelId, view, serverNow) -> string?   "Ready!", "Later"
--
-- Why "acks": the cheapest upgrade costs 12-35 coins, so "you can afford something" is true almost
-- all the time and a dot that never goes out means nothing. A shop's dot now lights only when it
-- can sell you something NEW since you last looked inside. The daily gift stays lit until claimed.

local Economy = require("../Rules/Economy")
local Pricing = require("../Rules/Pricing")
local Tools = require("../Catalog/Tools")
local Upgrades = require("../Catalog/Upgrades")
local Zones = require("../Catalog/Zones")
local UiMath = require("./UiMath")
local Util = require("./ShopModelUtil")

local MenuModel = {}

export type Set = { [string]: boolean }
export type Offers = { [string]: Set }
export type Acks = { [string]: Set }

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function profileOf(view: { [string]: any }?)
	local p = Util.profile(view)
	local v: { [string]: any } = view or {}
	p.runCoins = if finite(v.runCoins) then math.max(0, v.runCoins) else 0
	p.coolDowns = if finite(v.coolDowns) then math.max(0, math.floor(v.coolDowns)) else 0
	return p
end

function MenuModel.offers(view: { [string]: any }?): Offers
	local profile = profileOf(view)
	local coins = profile.coins
	local function can(kind: string, id: string | number): boolean
		local ok, price = pcall(Pricing.priceOf, kind, id, profile)
		return ok and type(price) == "number" and price <= coins
	end
	local out: Offers = { upgrades = {}, tools = {}, gates = {}, helpers = {}, cooldown = {} }
	for _, id in Upgrades.order do
		if can("upgrade", id) then
			out.upgrades[id] = true
		end
	end
	for _, tool in Tools.list do
		if can("tool", tool.id) then
			out.tools[tool.id] = true
		end
	end
	for _, zone in Zones.list do
		if zone.id > 1 and can("zone", zone.id) then
			out.gates[tostring(zone.id)] = true
		end
	end
	if can("helper", "") then
		out.helpers.helper = true
	end
	if can("helperUp", "") then
		out.helpers.helperUp = true
	end
	local okCool, allowed = pcall(Economy.canCoolDown, profile)
	if okCool and allowed == true then
		out.cooldown.ready = true
	end
	return out
end

function MenuModel.dailyReady(view: { [string]: any }?, serverNow: number): boolean
	local daily = if view then view.daily else nil
	if type(daily) ~= "table" or not finite(daily.lastDay) then
		return false
	end
	return UiMath.dailyReady(daily.lastDay, serverNow)
end

function MenuModel.dots(
	view: { [string]: any }?,
	serverNow: number,
	acks: Acks
): { [string]: boolean }
	local dots: { [string]: boolean } = {}
	for panelId, set in MenuModel.offers(view) do
		local seen = acks[panelId]
		for key in set do
			if seen == nil or seen[key] ~= true then
				dots[panelId] = true
				break
			end
		end
	end
	if MenuModel.dailyReady(view, serverNow) then
		dots.daily = true
	end
	return dots
end

function MenuModel.ack(acks: Acks, panelId: string, view: { [string]: any }?)
	local set = MenuModel.offers(view)[panelId]
	if set == nil then
		return
	end
	acks[panelId] = table.clone(set)
end

function MenuModel.anyDot(dots: { [string]: boolean }): boolean
	for _, on in dots do
		if on then
			return true
		end
	end
	return false
end

-- A one-word note under a tile, or nil. "Later" makes the far-off Cool Down quiet for new players
-- (the tile still opens and explains what it is).
function MenuModel.tileNote(panelId: string, view: { [string]: any }?, serverNow: number): string?
	if panelId == "daily" then
		return if MenuModel.dailyReady(view, serverNow) then "Ready!" else nil
	elseif panelId == "cooldown" then
		local profile = profileOf(view)
		local ok, allowed = pcall(Economy.canCoolDown, profile)
		if ok and allowed == true then
			return "Ready!"
		end
		return if profile.coolDowns == 0 then "Later" else nil
	end
	return nil
end

return MenuModel
