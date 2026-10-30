--!strict
-- Chests against a Store (the saved profile, or ChestMemoryStore) so Lune can test them (gap 19).
-- Only the server earns and opens: a client can only ASK to see its chests or to open one it owns.
--   onMatch  a finished match may give chests (place, win, and the free-chest meter). Once per key.
--   award    gives one chest from another server rule (daily login, missions, level gifts), once per key.
--   open     takes one chest, rolls the prizes and pays them in ONE change, then sends the reveal.
--   push     sends the chest screen's numbers.

local ChestDefs = require("./ChestDefs")
local ChestRules = require("./ChestRules")
local Types = require("../Types")

export type Store = {
	status: (player: any) -> string,
	read: (player: any) -> ChestRules.State?,
	update: (player: any, fn: ({ [string]: any }) -> boolean?) -> (boolean, string?),
	grantOnce: (
		player: any,
		key: string,
		fn: ({ [string]: any }) -> boolean?
	) -> (boolean, string?),
	saveNow: (player: any) -> boolean,
	release: ((player: any) -> ())?,
}

export type Deps = {
	store: Store,
	send: (player: any, state: Types.ChestState) -> (),
	random: () -> number, -- 0 up to (not including) 1; the server's Random
	maxStored: number,
	meterGoal: number,
	maxGrant: number, -- the most Scrap one prize may add (Config.Progression.maxMatchGrant)
	changed: ((player: any) -> ())?, -- told after a chest opened (Scrap or looks changed, so refresh the coin screen)
}

export type Service = {
	onMatch: (player: any, place: number, won: boolean, key: string) -> { string },
	award: (player: any, kind: string, key: string) -> (boolean, string?),
	open: (player: any, kind: any) -> boolean,
	push: (player: any) -> (),
}

local ChestService = {}

function ChestService.new(deps: Deps): Service
	local store = deps.store
	local service = {} :: Service

	local function send(
		player: any,
		extra: { justAwarded: { string }?, reveal: Types.ChestReveal?, denied: string? }?
	)
		local s = store.read(player)
		local owned: { [string]: number } = {}
		if s ~= nil then
			for _, kind in ChestDefs.kinds do
				owned[kind] = ChestRules.count(s, kind)
			end
		end
		local state: Types.ChestState = {
			status = store.status(player),
			owned = owned,
			meter = if s ~= nil then s.meter else 0,
			meterGoal = deps.meterGoal,
			opened = if s ~= nil then s.opened else 0,
			justAwarded = if extra ~= nil then extra.justAwarded else nil,
			reveal = if extra ~= nil then extra.reveal else nil,
			denied = if extra ~= nil then extra.denied else nil,
		}
		deps.send(player, state)
	end

	function service.push(player: any)
		send(player, nil)
	end

	function service.onMatch(player: any, place: number, won: boolean, key: string): { string }
		local given: { string } = {}
		local ok = store.grantOnce(player, key, function(data)
			if type(data.chests) ~= "table" then
				data.chests = {}
			end
			given = ChestRules.forMatch(
				ChestRules.fill(data.chests),
				place,
				won,
				deps.meterGoal,
				deps.maxStored
			)
			return true -- the meter moved even when no chest came
		end)
		if ok then
			store.saveNow(player)
			send(player, { justAwarded = if #given > 0 then given else nil })
		end
		return if ok then given else {}
	end

	function service.award(player: any, kind: string, key: string): (boolean, string?)
		local why: string? = nil
		local ok, reason = store.grantOnce(player, key, function(data)
			if type(data.chests) ~= "table" then
				data.chests = {}
			end
			local given, refusal =
				ChestRules.award(ChestRules.fill(data.chests), kind, deps.maxStored)
			if not given then
				why = refusal
				return false
			end
			return true
		end)
		if ok then
			store.saveNow(player)
			send(player, { justAwarded = { kind } })
		end
		return ok, why or reason
	end

	function service.open(player: any, kind: any): boolean
		local result: ChestRules.OpenResult? = nil
		local opened = 0
		local ok, reason = store.update(player, function(data)
			local r = ChestRules.open(data, kind, deps.random, deps.maxGrant)
			result = r
			if r.ok then
				opened = (data.chests :: any).opened
			end
			return r.ok
		end)
		local r = result
		if ok and r ~= nil then
			store.saveNow(player)
			if deps.changed ~= nil then
				deps.changed(player)
			end
			send(player, {
				reveal = { id = opened, kind = r.kind, prizes = r.prizes :: any },
			})
			return true
		end
		send(player, { denied = if r ~= nil then r.reason else reason })
		return false
	end

	return service
end

return ChestService
