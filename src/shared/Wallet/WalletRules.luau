--!strict
-- Pure rules for the saved wallet table (data.wallet in the profile): earning and spending the saved counters
-- (sparks, and any counter added to WalletDefs later). Scrap is not here; piece 18 owns it. No Roblox, so Lune
-- tests it. Every function checks first and only then changes the table, and returns a reason when it refuses,
-- leaving the table untouched.

local Config = require("../Config")
local WalletDefs = require("./WalletDefs")

export type Wallet = { [string]: number }
export type Result = { ok: boolean, reason: string? }

local WalletRules = {}

local OK: Result = { ok = true, reason = nil }

local function refuse(reason: string): Result
	return { ok = false, reason = reason }
end

local function isCount(n: any): boolean
	return type(n) == "number" and n == n and n >= 0 and n < 1e9 and n == math.floor(n)
end

function WalletRules.new(): Wallet
	local w: Wallet = {}
	for _, def in WalletDefs.list do
		if def.saved then
			w[def.id] = 0
		end
	end
	return w
end

-- Fills in anything missing or the wrong type, in place, and returns the same table. Unknown extra keys are
-- kept (a newer version of the game may have saved another counter).
function WalletRules.fill(raw: any): Wallet
	local w = raw :: any
	for _, def in WalletDefs.list do
		if def.saved then
			local n = w[def.id]
			if not isCount(n) then
				w[def.id] = 0
			elseif n > Config.Wallet.maxBalance then
				w[def.id] = Config.Wallet.maxBalance
			end
		end
	end
	return w :: Wallet
end

function WalletRules.balance(w: Wallet, id: string): number
	local n = w[id]
	return if isCount(n) then n else 0
end

-- Adds to a saved counter. Refuses a bad amount, an unknown or unsaved counter, or a grant over the sanity cap.
-- Stops at the balance cap instead of wrapping (the extra is dropped and "capped" is not an error).
function WalletRules.add(w: Wallet, id: string, amount: number): Result
	if not WalletDefs.isSaved(id) then
		return refuse("unknownCounter")
	end
	if not isCount(amount) then
		return refuse("badAmount")
	end
	if amount > Config.Wallet.maxGrant then
		return refuse("tooMuch")
	end
	w[id] = math.min(Config.Wallet.maxBalance, WalletRules.balance(w, id) + amount)
	return OK
end

-- Takes from a saved counter, all or nothing.
function WalletRules.spend(w: Wallet, id: string, amount: number): Result
	if not WalletDefs.isSaved(id) then
		return refuse("unknownCounter")
	end
	if not isCount(amount) or amount == 0 then
		return refuse("badAmount")
	end
	if WalletRules.balance(w, id) < amount then
		return refuse("tooPoor")
	end
	w[id] -= amount
	return OK
end

-- What a finished match pays in sparks. `won` is false for a shared first place (a draw).
function WalletRules.sparksFor(place: number, won: boolean): number
	if won then
		return Config.Wallet.sparks.win
	end
	if place >= 1 and place <= 3 then
		return Config.Wallet.sparks.podium
	end
	return 0
end

-- Once-only key for a match payout (the profile also keeps the match receipt, see WalletService).
function WalletRules.matchKey(matchKey: string): string
	return matchKey .. ":sparks"
end

return WalletRules
