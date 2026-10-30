--!strict
-- A stand-in for the saved profile's chest data: lives only as long as the server. Used when the profile module
-- is missing, and by the Lune tests. It follows the same rules as the real one: a receipt key pays once, and a
-- change that is refused or errors leaves everything as it was. Clearly NOT saved: status() says "temporary".

local ChestRules = require("./ChestRules")
local ProgressRules = require("../Progression/ProgressRules")

local ChestMemoryStore = {}

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
	peek: ((player: any) -> { [string]: any })?, -- tests only: the whole data
}

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

function ChestMemoryStore.new(): Store
	local byPlayer: { [any]: { [string]: any } } = {}
	local receipts: { [any]: { [string]: boolean } } = {}

	local function mine(player: any): { [string]: any }
		local d = byPlayer[player]
		if d == nil then
			d = { chests = ChestRules.new(), progression = ProgressRules.new() }
			byPlayer[player] = d
			receipts[player] = {}
		end
		return d
	end

	local store = {} :: Store
	function store.status(_player: any): string
		return "temporary"
	end
	function store.read(player: any): ChestRules.State?
		return ChestRules.fill(deepCopy(mine(player).chests))
	end
	function store.update(player: any, fn: ({ [string]: any }) -> boolean?): (boolean, string?)
		local working = deepCopy(mine(player))
		local ok, result = pcall(fn, working)
		if not ok then
			return false, "error"
		end
		if result == false then
			return false, "rejected"
		end
		byPlayer[player] = working
		return true, nil
	end
	function store.grantOnce(
		player: any,
		key: string,
		fn: ({ [string]: any }) -> boolean?
	): (boolean, string?)
		mine(player)
		local seen = receipts[player]
		if seen[key] then
			return false, "duplicate"
		end
		local ok, reason = store.update(player, fn)
		if ok then
			seen[key] = true
		end
		return ok, reason
	end
	function store.saveNow(_player: any): boolean
		return false -- nothing is written anywhere
	end
	function store.release(player: any)
		byPlayer[player] = nil
		receipts[player] = nil
	end
	function store.peek(player: any): { [string]: any }
		return deepCopy(mine(player))
	end
	return store
end

return ChestMemoryStore
