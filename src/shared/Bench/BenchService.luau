--!strict
-- The bench against a Store (the saved profile, or BenchMemoryStore) so Lune can test it (video 3 gap 14).
-- The server decides everything: a client can only ASK to merge or build; drops come from match results.
--   push(player)                       sends the bench
--   merge(player, kind, tier)          3 of one part -> 1 of the next tier
--   build(player, blueprintId)         spends the parts, marks the gear built
--   drop(player, key, place, won)      parts after a match, once per key (a repeat pays nothing)
-- Every answer goes out as a BenchState with `event` set ("merged", "built", "denied").

local BenchRules = require("./BenchRules")
local Types = require("../Types")

export type Store = {
	status: (player: any) -> string,
	read: (player: any) -> BenchRules.State?,
	update: (player: any, fn: (BenchRules.State) -> boolean?) -> (boolean, string?),
	grantOnce: (player: any, key: string, fn: (BenchRules.State) -> boolean?) -> (boolean, string?),
}

export type Deps = {
	store: Store,
	send: (player: any, state: Types.BenchState) -> (),
	rng: (max: number) -> number, -- a whole number 1..max
	drops: { [string]: number },
	fieldSize: number,
}

export type Service = {
	push: (player: any) -> (),
	merge: (player: any, kind: any, tier: any) -> (boolean, string?),
	build: (player: any, blueprintId: any) -> (boolean, string?),
	drop: (player: any, key: string, place: number, won: boolean?) -> { BenchRules.Drop },
}

local BenchService = {}

function BenchService.new(deps: Deps): Service
	local store = deps.store
	local service = {} :: Service

	local function send(player: any, event: string?, reason: string?, justGot: { BenchRules.Drop }?)
		local s = store.read(player) or BenchRules.empty()
		local v = BenchRules.view(s)
		deps.send(player, {
			status = store.status(player),
			parts = v.parts,
			blueprints = v.blueprints,
			built = v.built,
			total = v.total,
			justGot = justGot,
			event = event,
			reason = reason,
		})
	end

	function service.push(player: any)
		send(player, nil, nil, nil)
	end

	local function change(
		player: any,
		event: string,
		fn: (BenchRules.State) -> (boolean, string?)
	): (boolean, string?)
		local failure: string? = nil
		local ok, reason = store.update(player, function(state)
			local done, why = fn(state)
			failure = why
			return done
		end)
		if not ok then
			local why = failure or reason or "busy"
			send(player, "denied", why, nil)
			return false, why
		end
		send(player, event, nil, nil)
		return true, nil
	end

	function service.merge(player: any, kind: any, tier: any): (boolean, string?)
		return change(player, "merged", function(state)
			return BenchRules.merge(state, kind, tier)
		end)
	end

	function service.build(player: any, blueprintId: any): (boolean, string?)
		return change(player, "built", function(state)
			return BenchRules.build(state, blueprintId)
		end)
	end

	function service.drop(
		player: any,
		key: string,
		place: number,
		won: boolean?
	): { BenchRules.Drop }
		local count = BenchRules.dropCount(place, won, deps.drops, deps.fieldSize)
		local got = BenchRules.roll(count, deps.rng)
		local ok = store.grantOnce(player, key, function(state)
			BenchRules.addDrops(state, got)
			return true
		end)
		if not ok then
			return {}
		end
		send(player, "dropped", nil, got)
		return got
	end

	return service
end

return BenchService
