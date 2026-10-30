--!strict
-- Who may play which emote, and when. Pure (no Roblox), so Lune tests it; the server asks it before every emote.
--
-- carter said "all of them": every emote is free and each player picks one of the three winner poses.
-- Optional (Config.Emotes.trackUnlocks): emotes open on the coin track (piece 18) when the player owns enough
-- track tiers, counted in order from the first. No new prices, nothing new to buy, nothing saved here.
--   starter set: slots 1-2 free, slot 3 at tier 2, slot 4 at tier 4
--   the other two sets: slots 1-4 at tiers 1, 3, 5, 6

local Emotes = require("./Emotes")
local TrackDefs = require("../Progression/TrackDefs")

local EmoteRules = {}

local STARTER_TIERS = { 0, 0, 2, 4 }
local EXTRA_TIERS = { 1, 3, 5, 6 }

EmoteRules.STOP = "stop" -- the id a client sends to end its own emote
EmoteRules.WIN_PREFIX = "win_" -- "win_A" / "win_B" / "win_C": the id a client sends to pick its winner pose

export type Scheme = {
	starterSet: string, -- listed first; with track unlocks its first two are the free ones
	trackUnlocks: boolean, -- false: everything is free
}

export type Entry = {
	id: string,
	name: string,
	set: Emotes.SetKey,
	tier: number, -- track tiers needed, 0 = free
	owned: boolean,
}

export type Check = {
	emoteId: string,
	scheme: Scheme,
	tiersOwned: number,
	hasBody: boolean, -- a living character to dance with
	inCombat: boolean, -- an alive participant in a combat phase: no emotes in a fight
	now: number,
	lastAt: number?, -- when this player last started an emote
	cooldown: number,
}

-- How many track tiers a player owns, counted in order (the track is bought in order, so this is the tier reached).
function EmoteRules.tiersOwned(unlocked: { [string]: boolean }): number
	local n = 0
	for _, tier in TrackDefs.tiers do
		if unlocked[tier.id] ~= true then
			break
		end
		n += 1
	end
	return n
end

-- Same count from the list the client gets in ProgressState.
function EmoteRules.tiersOwnedFromList(ids: { string }): number
	local set: { [string]: boolean } = {}
	for _, id in ids do
		set[id] = true
	end
	return EmoteRules.tiersOwned(set)
end

local function starterOf(scheme: Scheme): string
	return if Emotes.isSet(scheme.starterSet) then scheme.starterSet else "A"
end

-- Track tiers needed for an emote (0 = free); nil for an unknown id.
function EmoteRules.tierFor(emoteId: string, scheme: Scheme): number?
	local def = Emotes.get(emoteId)
	if def == nil then
		return nil
	end
	if not scheme.trackUnlocks then
		return 0
	end
	local starter = starterOf(scheme)
	local tiers = if def.set == starter then STARTER_TIERS else EXTRA_TIERS
	return tiers[def.slot]
end

function EmoteRules.owns(emoteId: string, scheme: Scheme, tiersOwned: number): boolean
	local need = EmoteRules.tierFor(emoteId, scheme)
	return need ~= nil and tiersOwned >= need
end

-- Every emote for the picker: starter set first, then the others in A, B, C order; inside a set by slot.
function EmoteRules.list(scheme: Scheme, tiersOwned: number): { Entry }
	local starter = starterOf(scheme)
	local order: { string } = { starter }
	for _, key in Emotes.SETS do
		if key ~= starter then
			table.insert(order, key)
		end
	end
	local out: { Entry } = {}
	for _, key in order do
		for _, def in Emotes.LIST do
			if def.set == key then
				local tier = EmoteRules.tierFor(def.id, scheme) :: number
				table.insert(out, {
					id = def.id,
					name = def.name,
					set = def.set,
					tier = tier,
					owned = tiersOwned >= tier,
				})
			end
		end
	end
	return out
end

-- May this player start this emote now? Refusals say why (shown to nobody, but tests and logs read them).
function EmoteRules.canPlay(c: Check): (boolean, string?)
	if Emotes.get(c.emoteId) == nil then
		return false, "unknown"
	end
	if not c.hasBody then
		return false, "noBody"
	end
	if c.inCombat then
		return false, "inCombat"
	end
	if not EmoteRules.owns(c.emoteId, c.scheme, c.tiersOwned) then
		return false, "locked"
	end
	if c.lastAt ~= nil and c.now - c.lastAt < c.cooldown then
		return false, "cooldown"
	end
	return true, nil
end

-- "win_B" -> "B"; nil when the id is not a winner pose pick.
function EmoteRules.winPoseFrom(id: string): Emotes.SetKey?
	if string.sub(id, 1, #EmoteRules.WIN_PREFIX) ~= EmoteRules.WIN_PREFIX then
		return nil
	end
	local key = string.sub(id, #EmoteRules.WIN_PREFIX + 1)
	if Emotes.isSet(key) then
		return key :: Emotes.SetKey
	end
	return nil
end

-- The winner pose to draw for a saved/attribute value; anything odd falls back to the default.
function EmoteRules.winPoseOr(value: any, default: string): Emotes.SetKey
	if Emotes.isSet(value) then
		return value :: Emotes.SetKey
	end
	return if Emotes.isSet(default) then default :: Emotes.SetKey else "A"
end

return EmoteRules
