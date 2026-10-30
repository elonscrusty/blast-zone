--!strict
-- The rules for coins and the track, written against a Store (the saved profile, or MemoryStore) so Lune can test
-- them. It never trusts a client: the client may only ASK to unlock or equip; amounts come from the match.
--   onReward   a match paid `amount` to this player. Pays once per match key; duplicates and bad numbers pay nothing.
--   unlock     buys the next tier if affordable (one change, all or nothing).
--   equip      puts an owned item on.
-- After every change it tells the player (`send`) and tells the world which look to show (`applyLook`).

local ProgressRules = require("./ProgressRules")
local TrackDefs = require("./TrackDefs")
local Types = require("../Types")

export type Store = {
	status: (player: any) -> string,
	read: (player: any) -> ProgressRules.Progression?,
	update: (player: any, fn: (ProgressRules.Progression) -> boolean?) -> (boolean, string?),
	grantOnce: (
		player: any,
		key: string,
		fn: (ProgressRules.Progression) -> boolean?
	) -> (boolean, string?),
	saveNow: (player: any) -> boolean,
	release: ((player: any) -> ())?, -- only the in-memory store needs this (player left)
}

export type Deps = {
	store: Store,
	maxGrant: number,
	receiptKey: (matchId: number) -> string,
	send: (player: any, state: Types.ProgressState) -> (),
	applyLook: (player: any, trailId: string, tracerId: string) -> (),
	changed: ((player: any) -> ())?, -- told after every state push (coins, unlock, equip, load)
}

export type Service = {
	onReward: (player: any, amount: number, matchId: number) -> boolean,
	unlock: (player: any, itemId: string) -> boolean,
	equip: (player: any, itemId: string) -> boolean,
	push: (player: any) -> (),
}

local ProgressService = {}

local function stateOf(
	store: Store,
	player: any,
	gained: { matchId: number, amount: number }?,
	denied: string?
)
	local status = store.status(player)
	local p = store.read(player)
	local unlocked: { string } = {}
	local equipped: { [string]: string } = {}
	local coins, total = 0, 0
	if p ~= nil then
		coins, total = p.coins, p.totalEarned
		for _, tier in TrackDefs.tiers do
			if p.unlocked[tier.id] then
				table.insert(unlocked, tier.id)
			end
		end
		for _, slot in TrackDefs.slots do
			equipped[slot] = ProgressRules.equippedIn(p, slot).id
		end
	end
	local state: Types.ProgressState = {
		status = status,
		coins = coins,
		totalEarned = total,
		unlocked = unlocked,
		equipped = equipped,
		gained = gained,
		denied = denied,
	}
	return state
end

function ProgressService.new(deps: Deps): Service
	local store = deps.store
	local service = {} :: Service

	local function look(player: any)
		local p = store.read(player)
		if p == nil then
			return
		end
		deps.applyLook(
			player,
			ProgressRules.equippedIn(p, "trail").id,
			ProgressRules.equippedIn(p, "tracer").id
		)
	end

	local function push(player: any, gained: { matchId: number, amount: number }?, denied: string?)
		deps.send(player, stateOf(store, player, gained, denied))
		if deps.changed ~= nil then
			deps.changed(player)
		end
	end

	function service.push(player: any)
		look(player)
		push(player, nil, nil)
	end

	function service.onReward(player: any, amount: number, matchId: number): boolean
		local ok, reason = store.grantOnce(player, deps.receiptKey(matchId), function(p)
			return ProgressRules.addCoins(p, amount, deps.maxGrant).ok
		end)
		if ok then
			store.saveNow(player)
			push(player, { matchId = matchId, amount = amount }, nil)
		else
			-- A duplicate is silent (the first answer already went out). A load problem is shown as the status.
			if reason ~= "duplicate" then
				push(player, nil, reason)
			end
		end
		return ok
	end

	function service.unlock(player: any, itemId: string): boolean
		local why: string? = nil
		local ok, reason = store.update(player, function(p)
			local r = ProgressRules.unlock(p, itemId)
			if not r.ok then
				why = r.reason
				return false
			end
			ProgressRules.equip(p, itemId) -- a new look is worn at once
			return true
		end)
		if ok then
			store.saveNow(player)
			look(player)
			push(player, nil, nil)
		else
			push(player, nil, why or reason)
		end
		return ok
	end

	function service.equip(player: any, itemId: string): boolean
		local why: string? = nil
		local ok, reason = store.update(player, function(p)
			local r = ProgressRules.equip(p, itemId)
			if not r.ok then
				why = r.reason
				return false
			end
			return true
		end)
		if ok then
			look(player)
			push(player, nil, nil)
		else
			push(player, nil, why or reason)
		end
		return ok
	end

	return service
end

return ProgressService
