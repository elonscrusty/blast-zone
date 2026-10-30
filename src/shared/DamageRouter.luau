--!strict
-- THE one door for damage. Zone, bullets, explosions and bots all call apply(); nothing else may change health.
--
-- The router enforces the rules every source shares, then asks the backend (piece 03) to do the health math:
--   - stale matchId            -> dropped  ("stale-match")
--   - phase not combat         -> dropped  ("not-combat")   so late hits cannot change results
--   - amount not finite / <= 0 -> dropped  ("bad-amount")
--   - target unknown / dead    -> dropped  ("no-target")
--   - a guard says no          -> dropped  (the guard's reason, e.g. "shielded")
--   - second elimination of the same target in a match is ignored (no duplicate kill credit)
-- Backend contract: backend(request) -> DamageResult. It must NOT fire events; the router does.

local Signal = require("./Signal")

export type Request = {
	matchId: number,
	targetId: string,
	amount: number,
	cause: string,
	sourceId: string?,
	weaponId: string?,
	hitPosition: any?,
}

export type Result = {
	applied: boolean,
	reason: string?,
	dealt: number,
	remaining: number,
	eliminated: boolean,
}

export type Host = {
	getMatchId: () -> number,
	allowsDamage: () -> boolean,
	isAlive: (string) -> boolean,
	markEliminated: (string) -> boolean,
	clock: () -> number,
}

local Router = {}
Router.__index = Router

local function reject(reason: string): Result
	return { applied = false, reason = reason, dealt = 0, remaining = 0, eliminated = false }
end

function Router.new(host: Host): any
	return setmetatable({
		_host = host,
		_backend = nil :: ((Request) -> Result)?,
		_guards = {} :: { (Request) -> string? },
		_eliminated = {} :: { [string]: boolean }, -- "<matchId>:<id>"
		Damaged = Signal.new(), -- ({ request, result })
		Eliminated = Signal.new(), -- (EliminationEvent)
	}, Router)
end

-- A guard returns a reason to drop the hit, or nil to let it through. Used by the spawn shield.
function Router.addGuard(self: any, guard: (Request) -> string?)
	table.insert(self._guards, guard)
end

-- Piece 03 binds the real implementation once at start-up.
function Router.bind(self: any, backend: (Request) -> Result)
	self._backend = backend
end

function Router.apply(self: any, req: Request): Result
	local host: Host = self._host
	if req.matchId ~= host.getMatchId() then
		return reject("stale-match")
	end
	if not host.allowsDamage() then
		return reject("not-combat")
	end
	local amount = req.amount
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount > 1e6 then
		return reject("bad-amount")
	end
	if not host.isAlive(req.targetId) then
		return reject("no-target")
	end
	for _, guard in self._guards do
		local ok, reason = pcall(guard, req)
		if ok and reason ~= nil then
			return reject(reason)
		end
	end
	local backend = self._backend
	if backend == nil then
		return reject("no-backend")
	end
	local ok, result = pcall(backend, req)
	if not ok then
		warn("[Damage] backend error: " .. tostring(result))
		return reject("backend-error")
	end
	local res: Result = result
	if not res.applied then
		return res
	end
	self.Damaged:fire({ request = req, result = res })
	if res.eliminated then
		local key = tostring(req.matchId) .. ":" .. req.targetId
		if self._eliminated[key] then
			return res
		end
		self._eliminated[key] = true
		host.markEliminated(req.targetId)
		self.Eliminated:fire({
			matchId = req.matchId,
			victimId = req.targetId,
			killerId = req.sourceId,
			cause = req.cause,
			weaponId = req.weaponId,
			at = host.clock(),
		})
	end
	return res
end

-- Match reset: forget who was eliminated.
function Router.reset(self: any)
	self._eliminated = {}
end

return Router
