--!strict
-- The season pass against a Store (the saved profile, or SeasonMemoryStore) so Lune can test it (video 3 gap 20).
-- Only the server adds XP (the run XP of a finished match) and the client may only ASK to see its pass or to take
-- a reward it has reached.
--   onXp(player, xp, matchKey)   adds season XP once per match key.
--   claim(player, tier, row)     pays one reward (Scrap or a look) once, then marks it taken. tier 0 = take all ready.
--   unlockPaid(player)           opens the paid row (the buy step calls this; nothing sells it yet).
--   push(player)                 sends the pass.
-- Paying goes through deps.pay / deps.giveItem with a once-only key per season, tier and row, so a retry never
-- pays twice: a "duplicate" answer means it was paid before and is just marked taken.

local Config = require("../Config")
local SeasonDefs = require("./SeasonDefs")
local SeasonRules = require("./SeasonRules")
local TrackDefs = require("../Progression/TrackDefs")
local Types = require("../Types")

export type Store = {
	status: (player: any) -> string,
	read: (player: any) -> SeasonRules.State?,
	update: (player: any, fn: (SeasonRules.State) -> boolean?) -> (boolean, string?),
	release: ((player: any) -> ())?, -- only the in-memory store needs this (player left)
}

export type Deps = {
	store: Store,
	-- Pays Scrap once per key. ok, or false with a reason ("duplicate" means it was paid before).
	pay: (player: any, amount: number, key: string) -> (boolean, string?),
	-- Gives a look once per key (Scrap instead if already owned). Same answers as pay.
	giveItem: (player: any, itemId: string, key: string, dupScrap: number) -> (boolean, string?),
	send: (player: any, state: Types.SeasonState) -> (),
	now: () -> number, -- unix seconds (os.time on the server)
}

export type Service = {
	onXp: (player: any, xp: number, matchKey: string) -> boolean,
	claim: (player: any, tier: number, row: string) -> (boolean, string?),
	unlockPaid: (player: any) -> boolean,
	push: (player: any) -> (),
}

local SeasonService = {}

local function rewardView(reward: SeasonDefs.Reward): Types.SeasonRewardView
	local name: string? = nil
	if reward.itemId ~= nil then
		local def = TrackDefs.get(reward.itemId)
		name = if def then def.name else nil
	end
	return { kind = reward.kind, amount = reward.amount, itemId = reward.itemId, name = name }
end

-- What the player sees. `s` may be nil (not loaded): everything shows as locked at 0 XP.
function SeasonService.view(
	s: SeasonRules.State?,
	season: number,
	unixNow: number,
	status: string
): Types.SeasonState
	local state = if s ~= nil and s.season == season then s else SeasonRules.new(season)
	local progress = SeasonRules.progress(state.xp)
	local tiers: { Types.SeasonTierView } = {}
	for n, def in SeasonDefs.tiers do
		local freeState = "locked"
		local paidState = "locked"
		if SeasonRules.isClaimed(state, n, "free") then
			freeState = "claimed"
		elseif progress.tier >= n then
			freeState = "ready"
		end
		if SeasonRules.isClaimed(state, n, "paid") then
			paidState = "claimed"
		elseif progress.tier >= n then
			paidState = if state.paid then "ready" else "needPass"
		end
		table.insert(tiers, {
			tier = n,
			xpNeeded = n * Config.Season.xpPerTier,
			free = rewardView(def.free),
			paid = rewardView(def.paid),
			freeState = freeState,
			paidState = paidState,
		})
	end
	return {
		status = status,
		season = season,
		secondsLeft = SeasonRules.secondsLeft(unixNow),
		xp = state.xp,
		tier = progress.tier,
		maxTier = SeasonDefs.count(),
		intoTier = progress.intoTier,
		forNext = progress.forNext,
		hasPass = state.paid,
		forSale = Config.Season.forSale,
		tiers = tiers,
		justClaimed = nil,
		denied = nil,
	}
end

function SeasonService.new(deps: Deps): Service
	local store = deps.store
	local service = {} :: Service

	local function season(): number
		return SeasonRules.seasonAt(deps.now())
	end

	local function send(player: any, justClaimed: { Types.SeasonClaimView }?, denied: string?)
		local state =
			SeasonService.view(store.read(player), season(), deps.now(), store.status(player))
		state.justClaimed = justClaimed
		state.denied = denied
		deps.send(player, state)
	end

	-- Brings the saved season up to the current one (a new season starts empty).
	local function roll(player: any)
		local current = season()
		store.update(player, function(s)
			return SeasonRules.roll(s, current)
		end)
	end

	-- Pays one reward and marks it taken. ok, or false with a reason. Does not send.
	local function take(
		player: any,
		tier: number,
		row: string
	): (boolean, string?, Types.SeasonRewardView?)
		local current = season()
		local s = store.read(player)
		if s == nil then
			return false, "notLoaded", nil
		end
		if s.season ~= current then
			return false, "locked", nil
		end
		local can, why = SeasonRules.canClaim(s, tier, row)
		if not can then
			return false, why, nil
		end
		local reward = SeasonDefs.reward(tier, row) :: SeasonDefs.Reward
		local key = SeasonRules.receiptKey(current, tier, row)
		local ok, reason
		if reward.kind == "scrap" then
			ok, reason = deps.pay(player, reward.amount or 0, key)
		else
			ok, reason =
				deps.giveItem(player, reward.itemId or "", key, Config.Season.duplicateScrap)
		end
		if not ok and reason ~= "duplicate" then
			return false, reason or "failed", nil
		end
		store.update(player, function(state)
			return SeasonRules.markClaimed(state, tier, row)
		end)
		return true, nil, rewardView(reward)
	end

	function service.onXp(player: any, xp: number, matchKey: string): boolean
		roll(player)
		local result: SeasonRules.AddResult? = nil
		local ok = store.update(player, function(s)
			local r = SeasonRules.addXp(s, xp, matchKey, Config.Season.maxXpPerMatch)
			result = r
			return r.ok
		end)
		send(player, nil, nil)
		return ok and result ~= nil and result.ok
	end

	function service.claim(player: any, tier: number, row: string): (boolean, string?)
		roll(player)
		if tier == 0 then
			local s = store.read(player)
			local taken: { Types.SeasonClaimView } = {}
			if s ~= nil then
				for _, r in SeasonRules.ready(s) do
					local ok, _, view = take(player, r.tier, r.row)
					if ok and view ~= nil then
						table.insert(taken, { tier = r.tier, row = r.row, reward = view })
					end
				end
			end
			if #taken == 0 then
				send(player, nil, "nothing")
				return false, "nothing"
			end
			send(player, taken, nil)
			return true, nil
		end
		local ok, reason, view = take(player, tier, row)
		if ok and view ~= nil then
			send(player, { { tier = tier, row = row, reward = view } }, nil)
			return true, nil
		end
		send(player, nil, reason)
		return false, reason
	end

	function service.unlockPaid(player: any): boolean
		roll(player)
		local ok = store.update(player, function(s)
			return SeasonRules.openPaid(s)
		end)
		send(player, nil, nil)
		return ok
	end

	function service.push(player: any)
		roll(player)
		send(player, nil, nil)
	end

	return service
end

return SeasonService
