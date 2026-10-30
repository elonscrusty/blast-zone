--!strict
-- The top-bar counters against a Store (the saved profile, or WalletMemoryStore) so Lune can test them (piece G17).
-- Only the server changes a balance; a client can only ASK to see the list (WalletRequest).
--   onMatch(player, place, won, matchKey)  pays sparks for a finished match, once per match key.
--   grant(player, id, amount, key)         the same for any other server rule (a chest, a mission): once per key.
--   spend(player, id, amount)              takes from a saved counter, all or nothing. For a shop or chest piece.
--   push(player)                           sends the current list.
-- Scrap is read through deps.scrap (piece 18 owns it); the wallet never writes it.

local Types = require("../Types")
local WalletDefs = require("./WalletDefs")
local WalletRules = require("./WalletRules")

export type Store = {
	status: (player: any) -> string,
	read: (player: any) -> WalletRules.Wallet?,
	update: (player: any, fn: (WalletRules.Wallet) -> boolean?) -> (boolean, string?),
	grantOnce: (
		player: any,
		key: string,
		fn: (WalletRules.Wallet) -> boolean?
	) -> (boolean, string?),
	saveNow: (player: any) -> boolean,
	release: ((player: any) -> ())?, -- only the in-memory store needs this (player left)
}

export type Deps = {
	store: Store,
	scrap: (player: any) -> number?, -- the player's Scrap, or nil until it is loaded
	send: (player: any, state: Types.WalletState) -> (),
}

export type Service = {
	onMatch: (player: any, place: number, won: boolean, matchKey: string) -> boolean,
	grant: (player: any, id: string, amount: number, key: string) -> (boolean, string?),
	spend: (player: any, id: string, amount: number) -> (boolean, string?),
	balance: (player: any, id: string) -> number?,
	push: (player: any) -> (),
}

local WalletService = {}

function WalletService.view(
	status: string,
	wallet: WalletRules.Wallet?,
	scrap: number?
): Types.WalletState
	local items: { Types.WalletItem } = {}
	for _, def in WalletDefs.list do
		local amount = 0
		if def.saved then
			amount = if wallet then WalletRules.balance(wallet, def.id) else 0
		else
			amount = scrap or 0
		end
		if def.always or amount > 0 then
			table.insert(
				items,
				{ id = def.id, name = def.name, short = def.short, amount = amount }
			)
		end
	end
	return { status = status, items = items }
end

function WalletService.new(deps: Deps): Service
	local store = deps.store
	local service = {} :: Service

	function service.push(player: any)
		deps.send(
			player,
			WalletService.view(store.status(player), store.read(player), deps.scrap(player))
		)
	end

	function service.balance(player: any, id: string): number?
		if not WalletDefs.isSaved(id) then
			return nil
		end
		local w = store.read(player)
		return if w then WalletRules.balance(w, id) else nil
	end

	function service.grant(player: any, id: string, amount: number, key: string): (boolean, string?)
		local why: string? = nil
		local ok, reason = store.grantOnce(player, key, function(w)
			local r = WalletRules.add(w, id, amount)
			if not r.ok then
				why = r.reason
			end
			return r.ok
		end)
		if ok then
			store.saveNow(player)
			service.push(player)
		end
		return ok, why or reason
	end

	function service.onMatch(player: any, place: number, won: boolean, matchKey: string): boolean
		local amount = WalletRules.sparksFor(place, won)
		if amount <= 0 then
			return false
		end
		local ok = service.grant(player, "sparks", amount, WalletRules.matchKey(matchKey))
		return ok
	end

	function service.spend(player: any, id: string, amount: number): (boolean, string?)
		local why: string? = nil
		local ok, reason = store.update(player, function(w)
			local r = WalletRules.spend(w, id, amount)
			if not r.ok then
				why = r.reason
			end
			return r.ok
		end)
		if ok then
			store.saveNow(player)
			service.push(player)
		end
		return ok, why or reason
	end

	return service
end

return WalletService
