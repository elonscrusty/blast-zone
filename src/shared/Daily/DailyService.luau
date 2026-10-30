--!strict
-- Daily challenges against a Store (the saved profile, or DailyMemoryStore) so Lune can test them (piece 25).
-- Only the server counts: progress comes from match events (RunXp awards, match results), never from a client.
--   count(player, kind, amount)  adds progress, then pays anything that just finished.
--   push(player)                 sends today's board (and first pays anything finished but not paid yet).
-- Paying goes through deps.pay with a once-only key per day and challenge, so a retry never pays twice.

local DailyRules = require("./DailyRules")
local Types = require("../Types")

export type Store = {
	status: (player: any) -> string,
	read: (player: any) -> DailyRules.State?,
	update: (player: any, fn: (DailyRules.State) -> boolean?) -> (boolean, string?),
	release: ((player: any) -> ())?, -- only the in-memory store needs this (player left)
}

export type Deps = {
	store: Store,
	-- Pays coins once per key. ok, or false with a reason ("duplicate" means it was paid before).
	pay: (player: any, amount: number, key: string) -> (boolean, string?),
	send: (player: any, state: Types.DailyState) -> (),
	now: () -> number, -- unix seconds (os.time on the server)
	rewards: { [string]: number },
	resetHour: number,
}

export type Service = {
	count: (player: any, kind: string, amount: number) -> { string },
	push: (player: any) -> (),
	today: () -> number,
}

local DailyService = {}

function DailyService.new(deps: Deps): Service
	local store = deps.store
	local service = {} :: Service

	local function today(): number
		return DailyRules.dayOf(deps.now(), deps.resetHour)
	end
	service.today = today

	local function send(player: any, justPaid: string?)
		local day = today()
		local s = store.read(player)
		local state: Types.DailyState = {
			status = store.status(player),
			day = day,
			secondsLeft = DailyRules.secondsLeft(deps.now(), deps.resetHour),
			challenges = DailyRules.view(s, day, deps.rewards),
			justPaid = justPaid,
		}
		deps.send(player, state)
	end

	-- Pays every finished, unpaid challenge. Returns the ids paid now.
	local function settle(player: any): { string }
		local paidNow: { string } = {}
		local s = store.read(player)
		if s == nil then
			return paidNow
		end
		local day = today()
		for _, def in DailyRules.readyToPay(s, day) do
			local amount = DailyRules.rewardFor(def, deps.rewards)
			local ok, reason = deps.pay(player, amount, DailyRules.receiptKey(day, def.id))
			if ok or reason == "duplicate" then
				store.update(player, function(state)
					return DailyRules.markPaid(state, day, def.id)
				end)
				if ok then
					table.insert(paidNow, def.id)
				end
			end
		end
		return paidNow
	end

	function service.count(player: any, kind: string, amount: number): { string }
		local day = today()
		local changed = false
		local done: { string } = {}
		local ok = store.update(player, function(state)
			local rolled = DailyRules.roll(state, day)
			local before = 0
			for _, n in state.progress do
				before += n
			end
			done = DailyRules.add(state, day, kind, amount)
			local after = 0
			for _, n in state.progress do
				after += n
			end
			changed = rolled or after ~= before
			return changed
		end)
		if not ok or not changed then
			return {}
		end
		local paid = settle(player)
		send(player, paid[1])
		return done
	end

	function service.push(player: any)
		local day = today()
		store.update(player, function(state)
			return DailyRules.roll(state, day)
		end)
		local paid = settle(player)
		send(player, paid[1])
	end

	return service
end

return DailyService
