--!strict
-- Keeps benches in memory for tests and for a server with no profile module (status "temporary": NOT saved).
-- Same calls as the profile-backed store in BenchSystem.

local BenchRules = require("./BenchRules")

export type MemoryStore = {
	status: (player: any) -> string,
	read: (player: any) -> BenchRules.State?,
	update: (player: any, fn: (BenchRules.State) -> boolean?) -> (boolean, string?),
	grantOnce: (player: any, key: string, fn: (BenchRules.State) -> boolean?) -> (boolean, string?),
	release: (player: any) -> (),
}

local BenchMemoryStore = {}

function BenchMemoryStore.new(): MemoryStore
	local states: { [any]: BenchRules.State } = {}
	local keys: { [any]: { [string]: boolean } } = {}
	local store = {} :: MemoryStore

	local function stateOf(player: any): BenchRules.State
		local s = states[player]
		if s == nil then
			s = BenchRules.empty()
			states[player] = s
		end
		return s
	end

	function store.status(_: any): string
		return "temporary"
	end
	function store.read(player: any): BenchRules.State?
		return BenchRules.fill(stateOf(player))
	end
	function store.update(player: any, fn: (BenchRules.State) -> boolean?): (boolean, string?)
		local copy = BenchRules.fill(stateOf(player))
		if fn(copy) == false then
			return false, "rejected"
		end
		states[player] = copy
		return true, nil
	end
	function store.grantOnce(
		player: any,
		key: string,
		fn: (BenchRules.State) -> boolean?
	): (boolean, string?)
		local seen = keys[player]
		if seen == nil then
			seen = {}
			keys[player] = seen
		end
		if seen[key] then
			return false, "duplicate"
		end
		local ok, reason = store.update(player, fn)
		if ok then
			seen[key] = true
		end
		return ok, reason
	end
	function store.release(player: any)
		states[player] = nil
		keys[player] = nil
	end
	return store
end

return BenchMemoryStore
