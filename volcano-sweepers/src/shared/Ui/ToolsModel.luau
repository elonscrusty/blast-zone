--!strict
-- View-model for the Tools panel: the eight tools with their state (equipped / owned / can buy /
-- saving up / locked), stat bars and the "next tool" highlight. Pure: no Roblox types.
--
--   ToolsModel.build(view) -> Model
--   ToolsModel.glyphOf(id) -> emoji used as the tool's picture (no asset ids anywhere)
--   ToolsModel.canBuyAny(view) -> boolean
--
-- Status of a row:
--   "equipped"  in your hands now                    (button: EQUIPPED, grey tick)
--   "owned"     yours, tap to put it on              (button: EQUIP)
--   "buy"       not owned and you have the coins     (button: price, green)
--   "short"     the NEXT tool up, coins not enough   (button: price, grey, "Need N more coins!")
--   "locked"    further ahead than the next tool, coins not enough (padlock, price grey)
-- "Next tool" = the lowest tier above the best tool you own that you do not own yet.

local Pricing = require("../Rules/Pricing")
local Tools = require("../Catalog/Tools")
local Types = require("../Types")
local Util = require("./ShopModelUtil")

local ToolsModel = {}

export type StatBar = {
	key: string, -- reach | width | power | speed | bag
	label: string,
	text: string, -- "13", "150°", "2.0", "3.1/s", "+170"
	fraction: number, -- 0..1 of the best tool in the game
	equippedFraction: number, -- the same stat for the tool in your hands (for a marker line)
}

export type Row = {
	id: string,
	name: string,
	tier: number,
	glyph: string,
	colorHex: string,
	trait: string,
	blurb: string,
	price: number,
	owned: boolean,
	equipped: boolean,
	isNext: boolean,
	status: string,
	affordable: boolean, -- can buy right now (only when not owned)
	missing: number,
	needText: string?,
	stats: { StatBar },
	badge: string?, -- "NEXT" for the next-tier tool
}

export type Model = {
	rows: { Row },
	equippedId: string,
	nextId: string?,
	coins: number,
	coinsText: string,
	canBuyAny: boolean,
	hint: string,
}

local GLYPHS: { [string]: string } = {
	twig_broom = "🧹",
	push_broom = "🧹",
	leaf_blower = "💨",
	dust_vac = "🌀",
	turbo_vac = "🚀",
	lava_mop = "🔥",
	dragon_vac = "🐉",
	volcano_vac = "🌋",
}

function ToolsModel.glyphOf(id: string): string
	return GLYPHS[id] or "🧹"
end

-- ===== stats =====
local function perSecond(tool: Tools.Tool): number
	return 1 / math.max(0.05, tool.interval)
end

local function maxOf(pick: (Tools.Tool) -> number): number
	local best = 0
	for _, tool in Tools.list do
		best = math.max(best, pick(tool))
	end
	return math.max(best, 1e-6)
end

local MAX = {
	reach = maxOf(function(t)
		return t.reach
	end),
	width = maxOf(function(t)
		return t.arcDeg
	end),
	power = maxOf(function(t)
		return t.power
	end),
	speed = maxOf(perSecond),
	bag = maxOf(function(t)
		return t.capacityBonus
	end),
}

local function fraction(value: number, max: number): number
	if value <= 0 then
		return 0
	end
	-- never invisible: even the tiniest real value shows a stub of bar
	return math.clamp(value / max, 0.06, 1)
end

local function oneDecimal(n: number): string
	local tenths = math.floor(n * 10 + 0.5) / 10
	if tenths == math.floor(tenths) then
		return tostring(math.floor(tenths))
	end
	return string.format("%.1f", tenths)
end

local function statBars(tool: Tools.Tool, equipped: Tools.Tool): { StatBar }
	local function bar(
		key: string,
		label: string,
		text: string,
		value: number,
		eqValue: number,
		max: number
	): StatBar
		return {
			key = key,
			label = label,
			text = text,
			fraction = fraction(value, max),
			equippedFraction = fraction(eqValue, max),
		}
	end
	return {
		bar("reach", "Reach", oneDecimal(tool.reach), tool.reach, equipped.reach, MAX.reach),
		bar(
			"width",
			"Width",
			`{math.floor(tool.arcDeg + 0.5)}°`,
			tool.arcDeg,
			equipped.arcDeg,
			MAX.width
		),
		bar("power", "Power", oneDecimal(tool.power), tool.power, equipped.power, MAX.power),
		bar(
			"speed",
			"Speed",
			`{oneDecimal(perSecond(tool))}/s`,
			perSecond(tool),
			perSecond(equipped),
			MAX.speed
		),
		bar(
			"bag",
			"Bag",
			if tool.capacityBonus > 0 then `+{math.floor(tool.capacityBonus)}` else "+0",
			tool.capacityBonus,
			equipped.capacityBonus,
			MAX.bag
		),
	}
end

-- The tier of the best tool you own (1 at least).
local function bestOwnedTier(profile: Types.Profile): number
	local best = 1
	for _, tool in Tools.list do
		if profile.toolsOwned[tool.id] == true and tool.tier > best then
			best = tool.tier
		end
	end
	return best
end

function ToolsModel.nextId(view: { [string]: any }?): string?
	local profile = Util.profile(view)
	local above = bestOwnedTier(profile)
	for _, tool in Tools.list do
		if tool.tier > above and profile.toolsOwned[tool.id] ~= true then
			return tool.id
		end
	end
	return nil
end

function ToolsModel.build(view: { [string]: any }?): Model
	local profile = Util.profile(view)
	local equippedTool = Tools.byId[profile.tool] or Tools.list[1]
	local nextId = ToolsModel.nextId(view)
	local rows: { Row } = {}
	local anyBuy = false
	local nextRow: Row? = nil

	for _, tool in Tools.list do
		local owned = profile.toolsOwned[tool.id] == true
		local equipped = owned and tool.id == equippedTool.id
		local isNext = tool.id == nextId
		local price = Pricing.priceOf("tool", tool.id, profile)
		local affordable = (not owned) and price ~= nil and profile.coins >= price
		local missing = 0
		if (not owned) and price ~= nil and not affordable then
			missing = Util.missing(price, profile.coins)
		end
		local status: string
		if equipped then
			status = "equipped"
		elseif owned then
			status = "owned"
		elseif affordable then
			status = "buy"
		elseif isNext then
			status = "short"
		else
			status = "locked"
		end
		if status == "buy" then
			anyBuy = true
		end
		local row: Row = {
			id = tool.id,
			name = tool.name,
			tier = tool.tier,
			glyph = ToolsModel.glyphOf(tool.id),
			colorHex = tool.color,
			trait = tool.trait,
			blurb = tool.blurb,
			price = tool.price,
			owned = owned,
			equipped = equipped,
			isNext = isNext,
			status = status,
			affordable = affordable,
			missing = missing,
			needText = if missing > 0 then Util.needText(missing) else nil,
			stats = statBars(tool, equippedTool),
			badge = if isNext then "NEXT" else nil,
		}
		table.insert(rows, row)
		if isNext then
			nextRow = row
		end
	end

	local hint: string
	if nextRow == nil then
		hint = "You have every tool. You are a sweeping legend!"
	elseif nextRow.affordable then
		hint = `You can get the {nextRow.name} now!`
	else
		hint = `Next tool: {nextRow.name}. {nextRow.needText or ""}`
	end

	return {
		rows = rows,
		equippedId = equippedTool.id,
		nextId = nextId,
		coins = profile.coins,
		coinsText = Util.coinsText(profile.coins),
		canBuyAny = anyBuy,
		hint = hint,
	}
end

function ToolsModel.canBuyAny(view: { [string]: any }?): boolean
	return ToolsModel.build(view).canBuyAny
end

return ToolsModel
