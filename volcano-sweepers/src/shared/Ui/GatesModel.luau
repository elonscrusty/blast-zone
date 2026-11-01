--!strict
-- View-model for the Gates panel: the five zones as a map-like stack plus a mini ring diagram.
-- Pure: no Roblox types.
--
--   GatesModel.build(view) -> Model
--   GatesModel.canBuyAny(view) -> boolean     a gate (not the beach) you can pay for right now
--
-- State of a zone:
--   "open"    you already opened it                 (badge OPEN)
--   "next"    the next gate in line                 (price button; grey + "Need N more coins!" if short)
--   "locked"  an earlier gate is still closed       (badge LOCKED, reason "Open Fern Forest first!")
-- Only the next zone can be bought. Pricing.priceOf / Pricing.reason say the same thing the
-- server says, so the panel never promises something the server will refuse.

local Config = require("../Config")
local Pricing = require("../Rules/Pricing")
local Zones = require("../Catalog/Zones")
local Format = require("./Format")
local Util = require("./ShopModelUtil")

local GatesModel = {}

export type Row = {
	id: number,
	name: string,
	blurb: string,
	groundHex: string,
	ashHex: string,
	value: number,
	valueText: string, -- "3 coins per ash"
	compareText: string?, -- "x3 more coins per ash!" (nil for the first zone)
	ratio: number?, -- value / previous zone value
	state: string, -- open | next | locked
	unlockPrice: number, -- catalog price (0 for the beach)
	price: number?, -- what you would pay now (nil unless state = next)
	affordable: boolean,
	missing: number,
	needText: string?, -- "Need 120 more coins!"
	reasonText: string?, -- why it cannot be bought (from Pricing.reason)
	buttonLabel: string?, -- "OPEN" / "LOCKED"
	best: boolean, -- the best zone you have open ("You sweep here")
}

export type Ring = {
	id: number,
	radiusFrac: number, -- 0..1 of the whole island radius
	colorHex: string,
	state: string, -- open | next | locked
}

export type Model = {
	rows: { Row },
	rings: { Ring },
	coreFrac: number, -- radius of the volcano in the middle, same scale
	coins: number,
	coinsText: string,
	nextId: number?,
	bestId: number,
	canBuyAny: boolean,
	hint: string,
}

local function valueText(value: number): string
	return `{value} {if value == 1 then "coin" else "coins"} per ash`
end

function GatesModel.build(view: { [string]: any }?): Model
	local profile = Util.profile(view)
	local bestId = Util.bestZone(profile.zones)
	local rows: { Row } = {}
	local nextId: number? = nil
	local anyBuy = false

	for i, zone in Zones.list do
		local open = profile.zones[tostring(zone.id)] == true
		local prevOpen = zone.id <= 1 or profile.zones[tostring(zone.id - 1)] == true
		local state: string
		if open then
			state = "open"
		elseif prevOpen then
			state = "next"
		else
			state = "locked"
		end

		local price = if state == "next" then Pricing.priceOf("zone", zone.id, profile) else nil
		if state == "next" and price == nil then
			state = "locked" -- the catalog and the rules disagree: show it closed, never buyable
		end
		if state == "next" and nextId == nil then
			nextId = zone.id
		end
		local affordable = price ~= nil and profile.coins >= price
		local missing = if price ~= nil and not affordable
			then Util.missing(price, profile.coins)
			else 0
		if state == "next" and affordable then
			anyBuy = true
		end

		local prev = Zones.list[i - 1]
		local ratio: number? = nil
		local compare: string? = nil
		if prev ~= nil and prev.value > 0 then
			ratio = zone.value / prev.value
			compare = `{Util.multText(ratio :: number)} more coins per ash!`
		end

		local reason: string? = nil
		if state == "locked" then
			reason = (Pricing.reason("zone", zone.id, profile) or "Not yet") .. "!"
		elseif state == "next" and not affordable then
			reason = Util.needText(missing)
		end

		table.insert(rows, {
			id = zone.id,
			name = zone.name,
			blurb = zone.blurb,
			groundHex = zone.ground,
			ashHex = zone.ash,
			value = zone.value,
			valueText = valueText(zone.value),
			compareText = compare,
			ratio = ratio,
			state = state,
			unlockPrice = zone.unlockPrice,
			price = price,
			affordable = affordable,
			missing = missing,
			needText = if missing > 0 then Util.needText(missing) else nil,
			reasonText = reason,
			buttonLabel = if state == "open"
				then "OPEN"
				elseif state == "locked" then "LOCKED"
				else nil,
			best = zone.id == bestId,
		})
	end

	-- the ring diagram: outer radius of each zone over the island radius
	local rings: { Ring } = {}
	local worldZones = Config.World.zones
	local outermost = 1
	for _, z in worldZones do
		outermost = math.max(outermost, z.outer)
	end
	for _, z in worldZones do
		local row = rows[z.id]
		table.insert(rings, {
			id = z.id,
			radiusFrac = z.outer / outermost,
			colorHex = if row then row.groundHex else "#FFFFFF",
			state = if row then row.state else "locked",
		})
	end
	local core = 0
	local last = worldZones[#worldZones]
	if last ~= nil then
		core = last.inner / outermost
	end

	local hint: string
	local nextRow: Row? = nil
	for _, row in rows do
		if row.id == nextId then
			nextRow = row
		end
	end
	if nextRow == nil then
		hint = "Every gate is open. You can sweep the whole island!"
	elseif nextRow.affordable then
		hint = `You can open {nextRow.name} now!`
	else
		hint = `Next gate: {nextRow.name}. {nextRow.needText or ""}`
	end

	return {
		rows = rows,
		rings = rings,
		coreFrac = core,
		coins = profile.coins,
		coinsText = Util.coinsText(profile.coins),
		nextId = nextId,
		bestId = bestId,
		canBuyAny = anyBuy,
		hint = hint,
	}
end

export type Prompt = {
	enabled: boolean, -- false: the gate is already yours, so its prompt is hidden on this screen
	actionText: string, -- "Open gate (800 coins)" / "Open Fern Forest first"
}

-- What the gate's ProximityPrompt says to THIS player (the server builds one prompt for everyone;
-- the client restyles it locally). The server still checks everything when it is triggered.
function GatesModel.prompt(view: { [string]: any }?, zoneId: number): Prompt
	local model = GatesModel.build(view)
	for _, row in model.rows do
		if row.id == zoneId then
			if row.state == "open" then
				return { enabled = false, actionText = "Open" }
			elseif row.state == "next" and row.price ~= nil then
				local coins = if row.price == 1 then "coin" else "coins"
				return {
					enabled = true,
					actionText = `Open gate ({Format.compact(row.price)} {coins})`,
				}
			end
			local before = Zones.byId[zoneId - 1]
			return {
				enabled = true,
				actionText = if before then `Open {before.name} first` else "Open gate",
			}
		end
	end
	return { enabled = true, actionText = "Open gate" }
end

function GatesModel.canBuyAny(view: { [string]: any }?): boolean
	return GatesModel.build(view).canBuyAny
end

return GatesModel
