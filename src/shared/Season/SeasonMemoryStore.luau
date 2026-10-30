--!strict
-- A stand-in for data.season in the saved profile: lives only as long as the server. Used when the profile
-- module is missing, and by the Lune tests. A change that is refused or errors leaves everything as it was.

local SeasonRules = require("./SeasonRules")
local SeasonService = require("./SeasonService")

local SeasonMemoryStore = {}

local function copy(s: SeasonRules.State): SeasonRules.State
	return {
		season = s.season,
		xp = s.xp,
		paid = s.paid,
		claimed = table.clone(s.claimed),
		keys = table.clone(s.keys),
	}
end

function SeasonMemoryStore.new(): SeasonService.Store
	local byPlayer: { [any]: SeasonRules.State } = {}

	local function mine(player: any): SeasonRules.State
		local s = byPlayer[player]
		if s == nil then
			s = SeasonRules.new(0)
			byPlayer[player] = s
		end
		return s
	end

	local store = {} :: SeasonService.Store
	function store.status(_player: any): string
		return "temporary"
	end
	function store.read(player: any): SeasonRules.State?
		return copy(mine(player))
	end
	function store.update(player: any, fn: (SeasonRules.State) -> boolean?): (boolean, string?)
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
	store.release = function(player: any)
		byPlayer[player] = nil
	end
	return store
end

return SeasonMemoryStore
