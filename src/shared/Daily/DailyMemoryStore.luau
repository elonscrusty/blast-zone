--!strict
-- A stand-in for data.daily in the saved profile: lives only as long as the server. Used when the profile
-- module is missing, and by the Lune tests. A change that is refused or errors leaves everything as it was.

local DailyRules = require("./DailyRules")
local DailyService = require("./DailyService")

local DailyMemoryStore = {}

local function copy(s: DailyRules.State): DailyRules.State
	return { day = s.day, progress = table.clone(s.progress), paid = table.clone(s.paid) }
end

function DailyMemoryStore.new(): DailyService.Store
	local byPlayer: { [any]: DailyRules.State } = {}

	local function mine(player: any): DailyRules.State
		local s = byPlayer[player]
		if s == nil then
			s = DailyRules.new(-1)
			byPlayer[player] = s
		end
		return s
	end

	local store = {} :: DailyService.Store
	function store.status(_player: any): string
		return "temporary"
	end
	function store.read(player: any): DailyRules.State?
		return copy(mine(player))
	end
	function store.update(player: any, fn: (DailyRules.State) -> boolean?): (boolean, string?)
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

return DailyMemoryStore
