--!strict
-- A stand-in for data.wallet in the saved profile: lives only as long as the server. Used when the profile
-- module is missing, and by the Lune tests. Same rules as the real one: a receipt key pays once, and a change
-- that is refused or errors leaves everything as it was. Clearly NOT saved: status() says "temporary".

local WalletRules = require("./WalletRules")
local WalletService = require("./WalletService")

local WalletMemoryStore = {}

function WalletMemoryStore.new(): WalletService.Store
	local byPlayer: { [any]: WalletRules.Wallet } = {}
	local receipts: { [any]: { [string]: boolean } } = {}

	local function mine(player: any): WalletRules.Wallet
		local w = byPlayer[player]
		if w == nil then
			w = WalletRules.new()
			byPlayer[player] = w
			receipts[player] = {}
		end
		return w
	end

	local store = {} :: WalletService.Store
	function store.status(_player: any): string
		return "temporary"
	end
	function store.read(player: any): WalletRules.Wallet?
		return table.clone(mine(player))
	end
	function store.update(player: any, fn: (WalletRules.Wallet) -> boolean?): (boolean, string?)
		local working = table.clone(mine(player))
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
		fn: (WalletRules.Wallet) -> boolean?
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

return WalletMemoryStore
