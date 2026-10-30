--!strict
-- Pure rules for the saved progression table (data.progression in the profile): earning coins, unlocking
-- the next tier, equipping what you own. No Roblox, so Lune tests it. Every function checks first and only
-- then changes the table, and returns false (with a reason) when it refuses, leaving the table untouched.

local TrackDefs = require("./TrackDefs")

local ProgressRules = {}

export type Progression = {
	coins: number,
	totalEarned: number,
	unlocked: { [string]: boolean },
	equipped: { [string]: string },
	grantedKeys: { [string]: number },
}

export type Result = { ok: boolean, reason: string? }

local function refuse(reason: string): Result
	return { ok = false, reason = reason }
end

local OK: Result = { ok = true, reason = nil }

function ProgressRules.new(): Progression
	return { coins = 0, totalEarned = 0, unlocked = {}, equipped = {}, grantedKeys = {} }
end

-- Fills in anything missing or the wrong type, in place, and returns the same table. Unknown extra keys and
-- unknown item ids are left alone (a newer version of the game may have saved them).
function ProgressRules.fill(raw: any): Progression
	local p = raw :: any
	if type(p.coins) ~= "number" or p.coins ~= p.coins or p.coins < 0 then
		p.coins = 0
	end
	if type(p.totalEarned) ~= "number" or p.totalEarned ~= p.totalEarned or p.totalEarned < 0 then
		p.totalEarned = 0
	end
	for _, key in { "unlocked", "equipped", "grantedKeys" } do
		if type(p[key]) ~= "table" then
			p[key] = {}
		end
	end
	return p
end

local function isCount(n: any): boolean
	return type(n) == "number" and n == n and n >= 0 and n < 1e9 and n == math.floor(n)
end

-- Is this item usable by this player? Defaults always are.
function ProgressRules.owns(p: Progression, itemId: string): boolean
	local def = TrackDefs.get(itemId)
	if def == nil then
		return false
	end
	return def.cost == 0 or p.unlocked[itemId] == true
end

-- What is equipped in a slot right now (a default if nothing, or if the saved id is unknown or not owned).
function ProgressRules.equippedIn(p: Progression, slot: TrackDefs.Slot): TrackDefs.Item
	local id = p.equipped[slot]
	if id ~= nil then
		local def = TrackDefs.get(id)
		if def ~= nil and def.slot == slot and ProgressRules.owns(p, id) then
			return def
		end
	end
	return TrackDefs.defaultFor(slot)
end

-- The next tier that is not unlocked yet, or nil when the track is finished.
function ProgressRules.nextTier(p: Progression): TrackDefs.Item?
	for _, tier in TrackDefs.tiers do
		if not p.unlocked[tier.id] then
			return tier
		end
	end
	return nil
end

-- Adds coins from a finished match. `maxGrant` is a sanity cap so a bug upstream cannot mint a fortune.
function ProgressRules.addCoins(p: Progression, amount: number, maxGrant: number): Result
	if not isCount(amount) then
		return refuse("badAmount")
	end
	if amount > maxGrant then
		return refuse("tooMuch")
	end
	if p.coins + amount >= 1e9 then
		return refuse("full")
	end
	p.coins += amount
	p.totalEarned += amount
	return OK
end

-- Unlocks the next tier only: the id must be exactly nextTier, and the player must afford it.
function ProgressRules.unlock(p: Progression, itemId: string): Result
	local tier = ProgressRules.nextTier(p)
	if tier == nil then
		return refuse("trackDone")
	end
	if tier.id ~= itemId then
		return refuse("notNext")
	end
	if p.coins < tier.cost then
		return refuse("tooPoor")
	end
	p.coins -= tier.cost
	p.unlocked[tier.id] = true
	return OK
end

-- Equips an owned item in its own slot. Equipping what is already on is fine.
function ProgressRules.equip(p: Progression, itemId: string): Result
	local def = TrackDefs.get(itemId)
	if def == nil then
		return refuse("unknownItem")
	end
	if not ProgressRules.owns(p, itemId) then
		return refuse("notOwned")
	end
	p.equipped[def.slot] = itemId
	return OK
end

return ProgressRules
