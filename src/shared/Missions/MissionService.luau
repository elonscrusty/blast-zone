--!strict
-- Weekly missions, achievements and login days against a Store (the saved profile, or MissionMemoryStore) so Lune
-- can test them (piece 48). Only the server counts: progress comes from match events, never from a client.
--   count(player, kind, amount)         adds progress; tells the player only when something became claimable.
--   claim(player, what, id)             pays once (a once-only key), then marks it claimed, then sends the board.
--   push(player)                        sends the board.
-- A client can only ASK to claim. The server checks the goal, the week and the day, and pays at most once per key.

local DailyRules = require("../Daily/DailyRules")
local MissionRules = require("./MissionRules")
local Types = require("../Types")

export type Store = {
	status: (player: any) -> string,
	read: (player: any) -> MissionRules.State?,
	update: (player: any, fn: (MissionRules.State) -> boolean?) -> (boolean, string?),
	release: ((player: any) -> ())?, -- only the in-memory store needs this (player left)
}

export type Deps = {
	store: Store,
	-- Pays coins once per key. ok, or false with a reason ("duplicate" means it was paid before).
	pay: (player: any, amount: number, key: string) -> (boolean, string?),
	send: (player: any, state: Types.MissionsState) -> (),
	now: () -> number, -- unix seconds (os.time on the server)
	config: MissionRules.Config,
	resetHour: number,
}

export type Service = {
	count: (player: any, kind: string, amount: number) -> { string },
	claim: (player: any, what: string, id: string?) -> (boolean, string?),
	push: (player: any) -> (),
	week: () -> number,
}

local MissionService = {}

function MissionService.new(deps: Deps): Service
	local store = deps.store
	local cfg = deps.config
	local service = {} :: Service

	local function week(): number
		return MissionRules.weekOf(deps.now(), deps.resetHour)
	end
	service.week = week

	local function day(): number
		return DailyRules.dayOf(deps.now(), deps.resetHour)
	end

	local function send(player: any, justClaimed: string?, justAmount: number?)
		local s = store.read(player)
		local weekly, bonus, awards, login = MissionRules.view(s, week(), day(), cfg)
		login.secondsLeft = DailyRules.secondsLeft(deps.now(), deps.resetHour)
		deps.send(player, {
			status = store.status(player),
			weekSecondsLeft = MissionRules.weekSecondsLeft(deps.now(), deps.resetHour),
			weekly = weekly,
			bonus = bonus,
			awards = awards,
			login = login,
			justClaimed = justClaimed,
			justAmount = justAmount,
		})
	end

	function service.count(player: any, kind: string, amount: number): { string }
		local w = week()
		local ready: { string } = {}
		local ok = store.update(player, function(state)
			MissionRules.roll(state, w)
			ready = MissionRules.add(state, w, kind, amount)
			return true
		end)
		if not ok then
			return {}
		end
		if #ready > 0 then
			send(player, nil, nil) -- something can be claimed now: let the lobby button show it
		end
		return ready
	end

	-- what: "week" | "award" | "bonus" | "login". Returns true if this call paid.
	function service.claim(player: any, what: string, id: string?): (boolean, string?)
		local w = week()
		local d = day()
		-- Roll first, so a claim in a new week sees the new week (and an old week's claim is refused).
		store.update(player, function(state)
			return MissionRules.roll(state, w)
		end)
		local s = store.read(player)
		if s == nil then
			send(player, nil, nil)
			return false, "notLoaded"
		end
		local amount, key = MissionRules.claimInfo(s, w, d, what, id, cfg)
		if amount == nil or key == nil then
			send(player, nil, nil)
			return false, key
		end
		local paid, reason = deps.pay(player, amount, key)
		if not paid and reason ~= "duplicate" then
			send(player, nil, nil)
			return false, reason
		end
		-- "duplicate": it was paid before but never marked (a save was lost). Mark it, say nothing new.
		store.update(player, function(state)
			return MissionRules.markClaimed(state, w, d, what, id, cfg)
		end)
		if paid then
			local label = if what == "week"
				then "week:" .. tostring(id)
				elseif what == "award" then "award:" .. tostring(id)
				else what
			send(player, label, amount)
			return true, nil
		end
		send(player, nil, nil)
		return false, reason
	end

	function service.push(player: any)
		local w = week()
		store.update(player, function(state)
			return MissionRules.roll(state, w)
		end)
		send(player, nil, nil)
	end

	return service
end

return MissionService
