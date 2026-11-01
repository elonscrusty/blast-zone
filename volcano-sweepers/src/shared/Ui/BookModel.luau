--!strict
-- The Finds Book as plain data for the panel to draw. Pure: give it the player's state (the client
-- store view, or a profile) and it returns every string, colour (hex text), count and flag.
--   BookModel.build(source, luckMult?) -> View       the whole book, grouped by set
--   BookModel.badge(source) -> boolean                true when a finished set is waiting to be claimed
--   BookModel.columns(width, count, minCell, gap)     how many tiles per row for a width
--   BookModel.iconFor(findId) -> emoji
-- `source` may be missing keys (the store is empty before the first State): nothing throws.

local Finds = require("../Catalog/Finds")
local Zones = require("../Catalog/Zones")
local FindRoller = require("../Finds/FindRoller")
local Format = require("./Format")

local BookModel = {}

export type Source = { [string]: any }

export type Entry = {
	id: string,
	name: string, -- the real name
	shownName: string, -- "???" until found
	icon: string,
	rarity: string,
	rarityLabel: string,
	colorHex: string, -- rarity colour
	found: boolean,
	count: number,
	countText: string, -- "x3", "" when not found
	coins: number,
	coinsText: string,
	zone: number, -- 0 = anywhere
	zoneText: string,
	oddsText: string, -- "62%"
	oddsLine: string, -- "Common: 62% of finds"
	hint: string, -- "Easy to find!"
}

export type SetView = {
	id: string,
	name: string,
	zone: number,
	found: number,
	total: number,
	progressText: string, -- "3/5"
	complete: boolean,
	claimed: boolean,
	claimable: boolean, -- complete and not yet claimed
	reward: number, -- 0.03
	rewardText: string, -- "+3% coins forever"
	rewardLine: string, -- one friendly sentence for the set header
	entries: { Entry },
}

export type Legend = {
	id: string,
	label: string,
	colorHex: string,
	oddsText: string,
	yourOddsText: string?, -- only when Treasure Luck changes the odds
}

export type View = {
	found: number,
	total: number,
	fraction: number,
	headerText: string, -- "Found 12 / 30"
	sets: { SetView },
	legend: { Legend },
	tipText: string,
	claimable: number, -- finished sets waiting for CLAIM
	badge: boolean,
}

-- A picture for every find (plain emoji, no asset ids). Old, widely supported emoji only.
local ICONS: { [string]: string } = {
	shiny_shell = "🐚",
	starfish_sam = "⭐",
	bottle_note = "🍾",
	pearl_pebble = "🌕",
	golden_sand_dollar = "🏅",
	fuzzy_acorn = "🌰",
	rainbow_feather = "🦜",
	glow_mushroom = "🍄",
	frog_crown = "🐸",
	fern_star = "🌿",
	warm_pebble = "🔸",
	bubble_gem = "💎",
	steam_whistle = "📯",
	pink_crystal = "💠",
	spring_spirit = "👻",
	ember_chip = "🔥",
	bone_whistle = "🦴",
	fire_opal = "🧡",
	ruby_spire = "🏮",
	dragon_scale = "🐉",
	glass_marble = "🔮",
	lava_bead = "🔴",
	glowing_geode = "💜",
	magma_pearl = "🌋",
	volcano_heart = "❤️",
	sprinkle_stone = "🍬",
	cloud_cookie = "🍪",
	giggle_gem = "😄",
	sunshine_star = "🌟",
	unicorn_egg = "🦄",
}
local FALLBACK_ICON = "💎"

local HINTS: { [string]: string } = {
	common = "Easy to find!",
	uncommon = "You need a little luck.",
	rare = "Very lucky to find!",
	legendary = "Super duper rare!",
}

function BookModel.iconFor(findId: string): string
	return ICONS[findId] or FALLBACK_ICON
end

local function count(map: any, id: string): number
	if type(map) ~= "table" then
		return 0
	end
	local v = (map :: { [string]: any })[id]
	if type(v) ~= "number" or v ~= v or v < 0 then
		return 0
	end
	return math.floor(v)
end

local function flag(map: any, id: string): boolean
	return type(map) == "table" and (map :: { [string]: any })[id] == true
end

-- 0.03 -> "3", 0.025 -> "2.5"
local function percentNumber(fraction: number): string
	local tenths = math.floor(fraction * 1000 + 0.5) / 10
	if tenths == math.floor(tenths) then
		return tostring(math.floor(tenths))
	end
	return string.format("%.1f", tenths)
end

function BookModel.rewardText(reward: number): string
	return `+{percentNumber(reward)}% coins forever`
end

local function zoneName(zone: number): string
	if zone == 0 then
		return "everywhere"
	end
	local z = Zones.byId[zone]
	return if z then z.name else "the island"
end

local function entryFor(find: Finds.Find, owned: number): Entry
	local rarity = Finds.rarityById[find.rarity]
	local label = if rarity then rarity.label else find.rarity
	local odds = Finds.oddsText(find.rarity)
	local found = owned > 0
	local anywhere = find.zone == 0
	local zoneText: string
	if found then
		zoneText = if anywhere then "Pops up anywhere!" else `Found in {zoneName(find.zone)}`
	else
		zoneText = if anywhere then "Could pop up anywhere!" else `Hides in {zoneName(find.zone)}`
	end
	return {
		id = find.id,
		name = find.name,
		shownName = if found then find.name else "???",
		icon = BookModel.iconFor(find.id),
		rarity = find.rarity,
		rarityLabel = label,
		colorHex = if rarity then rarity.colorHex else "#B8C4CC",
		found = found,
		count = owned,
		countText = if found then `x{Format.compact(owned)}` else "",
		coins = find.coins,
		coinsText = if found then `Worth {Format.compact(find.coins)} coins` else "Worth: ???",
		zone = find.zone,
		zoneText = zoneText,
		oddsText = odds,
		oddsLine = `{label}: {odds} of finds`,
		hint = HINTS[find.rarity] or "",
	}
end

local function setView(set: Finds.FindSet, finds: any, claimedMap: any): SetView
	local entries: { Entry } = {}
	local foundCount = 0
	for _, find in Finds.inSet(set.id) do
		local entry = entryFor(find, count(finds, find.id))
		if entry.found then
			foundCount += 1
		end
		table.insert(entries, entry)
	end
	local total = #entries
	local complete = total > 0 and foundCount >= total
	local claimed = flag(claimedMap, set.id)
	local rewardText = BookModel.rewardText(set.reward)
	local line: string
	if claimed then
		line = rewardText
	elseif complete then
		line = `Set complete! {rewardText}`
	else
		line = `Find all {total}: {rewardText}`
	end
	return {
		id = set.id,
		name = set.name,
		zone = set.zone,
		found = foundCount,
		total = total,
		progressText = `{foundCount}/{total}`,
		complete = complete,
		claimed = claimed,
		claimable = complete and not claimed,
		reward = set.reward,
		rewardText = rewardText,
		rewardLine = line,
		entries = entries,
	}
end

local function pct(fraction: number): string
	return `{math.floor(fraction * 100 + 0.5)}%`
end

-- luckMult is derived.luck (1 = no bonus). The book shows the plain odds, plus "with your luck"
-- numbers when the Treasure Luck upgrade or perk changes them.
function BookModel.build(source: Source, luckMult: number?): View
	local finds = source.finds
	local claimedMap = source.setsClaimed
	local sets: { SetView } = {}
	local found, total, claimable = 0, 0, 0
	for _, set in Finds.sets do
		local view = setView(set, finds, claimedMap)
		found += view.found
		total += view.total
		if view.claimable then
			claimable += 1
		end
		table.insert(sets, view)
	end

	local luck = luckMult
	if type(luck) ~= "number" or luck ~= luck or luck < 1 then
		luck = 1
	end
	local bonus = (luck :: number) - 1
	local lucky = bonus > 0.0001
	local yours = FindRoller.rarityOdds(bonus, Finds.rarities :: any)
	local legend: { Legend } = {}
	for _, r in Finds.rarities do
		local base = Finds.oddsText(r.id)
		local mine = pct(yours[r.id] or 0)
		table.insert(legend, {
			id = r.id,
			label = r.label,
			colorHex = r.colorHex,
			oddsText = base,
			yourOddsText = if lucky and mine ~= base then mine else nil,
		})
	end

	local chance = math.floor(FindRoller.chance(bonus) * 100 + 0.5)
	local tip = `About {chance} in every 100 clean patches hides a treasure!`
	if lucky then
		tip ..= " Your luck is helping."
	end

	return {
		found = found,
		total = total,
		fraction = if total > 0 then found / total else 0,
		headerText = `Found {found} / {total}`,
		sets = sets,
		legend = legend,
		tipText = tip,
		claimable = claimable,
		badge = claimable > 0,
	}
end

function BookModel.badge(source: Source): boolean
	return BookModel.build(source, 1).badge
end

-- Tiles per row: as many as fit (each at least minCell wide with `gap` between), never more than
-- `tiles` and never fewer than 1. Bad numbers give 1.
function BookModel.columns(width: number, tiles: number, minCell: number, gap: number): number
	if width ~= width or width <= 0 or tiles < 1 or minCell <= 0 then
		return 1
	end
	local fit = math.floor((width + gap) / (minCell + gap))
	return math.clamp(fit, 1, math.max(1, math.floor(tiles)))
end

return BookModel
