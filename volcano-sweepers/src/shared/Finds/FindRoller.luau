--!strict
-- Rolls for a hidden find when a cell is swept to bare ground. Pure: the catalogs are parameters.
--   finds    = list of { id, rarity, zone, ... }   zone 1..5, or 0 for a rainbow find (any zone)
--   rarities = list of { id, weight, ... }         ordered common -> legendary
-- `luck` is a bonus fraction (0 = none, 0.5 = +50% chance) from the Treasure Luck upgrade and friends.
--
-- Two independent rolls per cleared cell:
--   1. rainbow: very rare, zone 0 finds, can drop in any zone.
--   2. normal: ~3% base, picks a rarity by weight (luck shifts weight toward rarer ones) and then a
--      find of that rarity in the cell's zone.

local Rng = require("../Rng")

type Rng = Rng.Rng

export type Find = { id: string, rarity: string, zone: number }
export type Rarity = { id: string, weight: number }

local FindRoller = {}

FindRoller.baseChance = 0.03 -- per cleared cell, luck 0
FindRoller.maxChance = 0.2 -- luck can never push the chance past this
FindRoller.rainbowChance = 0.0004 -- per cleared cell, luck 0
FindRoller.rainbowMaxChance = 0.004
FindRoller.rainbowLuckShare = 0.5 -- luck helps rainbow finds only this much as much
FindRoller.rarityShift = 0.25 -- weight x (1 + shift x luck x rarityRank), rank 0 = most common
FindRoller.maxLuck = 8 -- luck above this stops helping (keeps odds sane even if a stat goes wrong)

local function cleanLuck(luck: number): number
	if luck ~= luck then
		return 0
	end
	return math.clamp(luck, 0, FindRoller.maxLuck)
end

-- Chance that a cleared cell gives a normal find (for the UI and for tests).
function FindRoller.chance(luck: number): number
	return math.min(FindRoller.maxChance, FindRoller.baseChance * (1 + cleanLuck(luck)))
end

function FindRoller.rainbowChanceFor(luck: number): number
	local l = cleanLuck(luck) * FindRoller.rainbowLuckShare
	return math.min(FindRoller.rainbowMaxChance, FindRoller.rainbowChance * (1 + l))
end

local function rarityWeight(rarities: { Rarity }, rank: number, luck: number): number
	return math.max(0, rarities[rank].weight) * (1 + FindRoller.rarityShift * luck * (rank - 1))
end

-- Share of finds that are each rarity at this luck, for the book's odds table: { [rarityId] = 0..1 }.
function FindRoller.rarityOdds(luck: number, rarities: { Rarity }): { [string]: number }
	local l = cleanLuck(luck)
	local total = 0
	for rank = 1, #rarities do
		total += rarityWeight(rarities, rank, l)
	end
	local out: { [string]: number } = {}
	for rank, r in rarities do
		out[r.id] = if total > 0 then rarityWeight(rarities, rank, l) / total else 0
	end
	return out
end

-- Index of the finds catalog: byZone[zone][rarityId] = list of finds. Cached per catalog table.
type Index = { rarities: { Rarity }, byZone: { [number]: { [string]: { Find } } } }
local cache: { [{ Find }]: Index } = setmetatable({}, { __mode = "k" }) :: any

local function indexFor(finds: { Find }, rarities: { Rarity }): Index
	local hit = cache[finds]
	if hit and hit.rarities == rarities then
		return hit
	end
	local byZone: { [number]: { [string]: { Find } } } = {}
	for _, f in finds do
		local zone = byZone[f.zone]
		if zone == nil then
			zone = {}
			byZone[f.zone] = zone
		end
		local list = zone[f.rarity]
		if list == nil then
			list = {}
			zone[f.rarity] = list
		end
		table.insert(list, f)
	end
	local idx: Index = { rarities = rarities, byZone = byZone }
	cache[finds] = idx
	return idx
end

-- Pick a find from one zone's buckets: rarity by (luck-shifted) weight among rarities that exist there.
local function pickFrom(
	rng: Rng,
	buckets: { [string]: { Find } }?,
	rarities: { Rarity },
	luck: number
): Find?
	if buckets == nil then
		return nil
	end
	local weights: { number } = {}
	local total = 0
	for rank, r in rarities do
		local w = if buckets[r.id] then rarityWeight(rarities, rank, luck) else 0
		weights[rank] = w
		total += w
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:next() * total
	for rank, w in weights do
		roll -= w
		if roll < 0 and w > 0 then
			return rng:pick(buckets[rarities[rank].id])
		end
	end
	-- floating point edge: take the last rarity that has finds
	for rank = #rarities, 1, -1 do
		if weights[rank] > 0 then
			return rng:pick(buckets[rarities[rank].id])
		end
	end
	return nil
end

-- One roll for one cleared cell. Returns the find or nil.
function FindRoller.roll(
	rng: Rng,
	luck: number,
	zoneId: number,
	finds: { Find },
	rarities: { Rarity }
): Find?
	local l = cleanLuck(luck)
	local idx = indexFor(finds, rarities)
	if idx.byZone[0] and rng:chance(FindRoller.rainbowChanceFor(l)) then
		local f = pickFrom(rng, idx.byZone[0], rarities, l)
		if f then
			return f
		end
	end
	if not rng:chance(FindRoller.chance(l)) then
		return nil
	end
	return pickFrom(rng, idx.byZone[zoneId], rarities, l)
end

return FindRoller
