--!strict
-- A stand-in for the saved profile (piece 17): coins live only as long as the server. Used when the profile
-- module is missing, and by the Lune tests. It follows the same rules as the real one: a receipt key pays once,
-- and a change that is refused leaves everything as it was. Clearly NOT saved: status() says "temporary".

local ProgressRules = require("./ProgressRules")

local ProgressService = require("./ProgressService")

export type Store = ProgressService.Store

local MemoryStore = {}

local function copy(p: ProgressRules.Progression): ProgressRules.Progression
	return {
		coins = p.coins,
		totalEarned = p.totalEarned,
		unlocked = table.clone(p.unlocked),
		equipped = table.clone(p.equipped),
		grantedKeys = table.clone(p.grantedKeys),
		accountXp = p.accountXp,
		claimedLevels = table.clone(p.claimedLevels),
	}
end

function MemoryStore.new(): Store
	local byPlayer: { [any]: ProgressRules.Progression } = {}
	local receipts: { [any]: { [string]: boolean } } = {}

	local function mine(player: any): ProgressRules.Progression
		local p = byPlayer[player]
		if p == nil then
			p = ProgressRules.new()
			byPlayer[player] = p
			receipts[player] = {}
		end
		return p
	end

	local store = {} :: Store
	function store.status(_player: any): string
		return "temporary"
	end
	function store.read(player: any): ProgressRules.Progression?
		return copy(mine(player))
	end
	function store.update(
		player: any,
		fn: (ProgressRules.Progression) -> boolean?
	): (boolean, string?)
		local working = copy(mine(player))
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
		fn: (ProgressRules.Progression) -> boolean?
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
	store.release = function(player: any)
		byPlayer[player] = nil
		receipts[player] = nil
	end
	return store
end

return MemoryStore
