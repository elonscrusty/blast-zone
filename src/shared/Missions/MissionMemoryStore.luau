--!strict
-- A stand-in for data.missions in the saved profile: lives only as long as the server. Used when the profile
-- module is missing, and by the Lune tests. A change that is refused or errors leaves everything as it was.

local MissionRules = require("./MissionRules")
local MissionService = require("./MissionService")

local MissionMemoryStore = {}

local function copy(s: MissionRules.State): MissionRules.State
	return MissionRules.fill(s) -- fill builds fresh tables
end

function MissionMemoryStore.new(): MissionService.Store
	local byPlayer: { [any]: MissionRules.State } = {}

	local function mine(player: any): MissionRules.State
		local s = byPlayer[player]
		if s == nil then
			s = MissionRules.new(-1)
			byPlayer[player] = s
		end
		return s
	end

	local store = {} :: MissionService.Store
	function store.status(_player: any): string
		return "temporary"
	end
	function store.read(player: any): MissionRules.State?
		return copy(mine(player))
	end
	function store.update(player: any, fn: (MissionRules.State) -> boolean?): (boolean, string?)
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

return MissionMemoryStore
