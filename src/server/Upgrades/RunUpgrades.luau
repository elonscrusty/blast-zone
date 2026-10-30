--!strict
-- Per-match upgrade state for every participant: what they own, which offer is open, and the
-- checks on a pick. Pure (no Roblox calls), so Lune tests it. UpgradeSystem wires it to the game.
--
-- An offer lives from issue() until it is picked, the player is eliminated, or the match is
-- cleared. Offers carry the matchId and a counter in their id, so a tap from an older offer or an
-- older match can never land on a newer one. A new offer is locked for a moment so a tap meant for
-- the old card cannot take the new one by accident.

export type Stacks = { [string]: number }

export type Option = {
	id: string,
	name: string,
	description: string,
	icon: string,
	stacks: number,
	maxStacks: number,
	change: string?,
	kind: string?,
}

export type OfferPayload = {
	offerId: string,
	matchId: number,
	options: { Option },
}

-- The part of shared/UpgradeDefs this file uses. `ctx` is opaque here.
export type Defs = {
	roll: (stacks: Stacks, ctx: any, rand: () -> number, count: number?) -> { string },
	canOffer: (id: string, stacks: Stacks, ctx: any) -> (boolean, string?),
	option: (id: string, stacks: Stacks, ctx: any) -> Option,
	resolve: (base: any, stacks: Stacks) -> any,
	cloneSheet: (sheet: any) -> any,
}

export type ChooseResult = {
	ok: boolean,
	reason: string?,
	upgradeId: string?,
	stacks: number?,
	text: string?, -- the change line, e.g. "Reload 1.2s → 0.96s"
}

type Entry = {
	matchId: number,
	stacks: Stacks,
	active: OfferPayload?,
	choices: { string },
	eliminated: boolean,
	seq: number,
	lockedUntil: number,
	sheet: any?,
}

local RunUpgrades = {}
RunUpgrades.__index = RunUpgrades

-- ctx: { base, hasExplosive, ... } as UpgradeDefs expects. rand returns [0, 1). now is a clock in seconds.
function RunUpgrades.new(
	defs: Defs,
	ctx: any,
	rand: () -> number,
	now: () -> number,
	lockSeconds: number
): any
	return setmetatable({
		_defs = defs,
		_ctx = ctx,
		_rand = rand,
		_now = now,
		_lock = lockSeconds,
		_entries = {} :: { [string]: Entry },
	}, RunUpgrades)
end

-- Starts (or restarts) a participant with no upgrades.
function RunUpgrades.enroll(self: any, id: string, matchId: number)
	self._entries[id] = {
		matchId = matchId,
		stacks = {},
		active = nil,
		choices = {},
		eliminated = false,
		seq = 0,
		lockedUntil = 0,
		sheet = nil,
	}
end

function RunUpgrades.remove(self: any, id: string)
	self._entries[id] = nil
end

function RunUpgrades.clear(self: any)
	self._entries = {}
end

function RunUpgrades.isEnrolled(self: any, id: string): boolean
	return self._entries[id] ~= nil
end

function RunUpgrades.hasActive(self: any, id: string): boolean
	local e: Entry? = self._entries[id]
	return e ~= nil and e.active ~= nil
end

-- Eliminated players keep their numbers but cannot hold or take offers. Returns true if an offer was open.
function RunUpgrades.eliminate(self: any, id: string): boolean
	local e: Entry? = self._entries[id]
	if e == nil then
		return false
	end
	local hadOffer = e.active ~= nil
	e.eliminated = true
	e.active = nil
	e.choices = {}
	return hadOffer
end

-- Opens one offer. Returns the payload, or nil and a reason:
-- "unknown", "eliminated", "active_exists", "nothing_eligible".
function RunUpgrades.issue(self: any, id: string): (OfferPayload?, string?)
	local e: Entry? = self._entries[id]
	if e == nil then
		return nil, "unknown"
	end
	if e.eliminated then
		return nil, "eliminated"
	end
	if e.active ~= nil then
		return nil, "active_exists"
	end
	local defs: Defs = self._defs
	local choices = defs.roll(e.stacks, self._ctx, self._rand, nil)
	if #choices == 0 then
		return nil, "nothing_eligible"
	end
	e.seq += 1
	local options: { Option } = {}
	for _, upgradeId in choices do
		table.insert(options, defs.option(upgradeId, e.stacks, self._ctx))
	end
	local payload: OfferPayload = {
		offerId = `u{e.matchId}-{id}-{e.seq}`,
		matchId = e.matchId,
		options = options,
	}
	e.active = payload
	e.choices = choices
	e.lockedUntil = self._now() + self._lock
	return payload, nil
end

local function fail(reason: string): ChooseResult
	return { ok = false, reason = reason }
end

-- The pick. Every check is here, whatever the client sent. Reasons when it fails:
-- "unknown", "eliminated", "stale_match", "no_offer", "stale_offer", "bad_option", "too_fast",
-- "offer_invalid" (the offer no longer fits the build: it is dropped, issue() a new one).
function RunUpgrades.choose(
	self: any,
	id: string,
	matchId: number,
	offerId: string,
	optionIndex: number
): ChooseResult
	local e: Entry? = self._entries[id]
	if e == nil then
		return fail("unknown")
	end
	if e.eliminated then
		return fail("eliminated")
	end
	if e.matchId ~= matchId then
		return fail("stale_match")
	end
	local active = e.active
	if active == nil then
		return fail("no_offer")
	end
	if offerId ~= active.offerId then
		return fail("stale_offer")
	end
	if
		type(optionIndex) ~= "number"
		or optionIndex ~= math.floor(optionIndex)
		or optionIndex < 1
		or optionIndex > #e.choices
	then
		return fail("bad_option")
	end
	if self._now() < e.lockedUntil then
		return fail("too_fast")
	end

	local defs: Defs = self._defs
	local upgradeId = e.choices[optionIndex]
	if not defs.canOffer(upgradeId, e.stacks, self._ctx) then
		e.active = nil
		e.choices = {}
		return fail("offer_invalid")
	end

	local text = defs.option(upgradeId, e.stacks, self._ctx).change
	e.stacks[upgradeId] = (e.stacks[upgradeId] or 0) + 1
	e.sheet = nil
	e.active = nil
	e.choices = {}
	return {
		ok = true,
		reason = nil,
		upgradeId = upgradeId,
		stacks = e.stacks[upgradeId],
		text = text,
	}
end

function RunUpgrades.stacksOf(self: any, id: string): Stacks
	local e: Entry? = self._entries[id]
	if e == nil then
		return {}
	end
	return table.clone(e.stacks)
end

-- The effective sheet for a participant (base + owned upgrades), or nil if unknown.
-- A copy every time, so a caller cannot edit the cached one.
function RunUpgrades.sheet(self: any, id: string): any?
	local e: Entry? = self._entries[id]
	if e == nil then
		return nil
	end
	local defs: Defs = self._defs
	if e.sheet == nil then
		e.sheet = defs.resolve(self._ctx.base, e.stacks)
	end
	return defs.cloneSheet(e.sheet)
end

return RunUpgrades
