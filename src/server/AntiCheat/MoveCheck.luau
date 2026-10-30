--!strict
-- "Could this player really have got here?" Pure maths (no game objects), so Lune can test it.
-- A player's own client moves its body, so a cheat can teleport, speed up or fly. Each frame the
-- server hands in where the body is now. Walking fills a distance budget (walk speed + slack),
-- moving spends it. A slide adds one-off credit. A move the budget cannot pay for is held for a
-- short grace (the slide request may still be on its way); if nothing explains it, the verdict is
-- "snap": put the body back at the last good spot.
--
--   local check = MoveCheck.new(Config.AntiCheat)
--   check:reset(id, x, y, z, now)            -- new body, or the server moved it
--   check:addCredit(id, studs, now)          -- a slide was accepted
--   local verdict, gx, gy, gz = check:step(id, x, y, z, now, walkSpeed)  -- "ok" | "hold" | "snap"
--   On "snap" move the body to gx, gy, gz; the checker already expects it there.

export type Settings = {
	speedSlack: number,
	burstSeconds: number,
	leeway: number,
	graceSeconds: number,
	slideCreditSeconds: number,
	riseSlope: number,
	riseLeeway: number,
}

export type Verdict = "ok" | "hold" | "snap"

type Entry = {
	x: number,
	y: number,
	z: number,
	at: number,
	budget: number,
	rise: number,
	credit: number,
	creditUntil: number,
	heldSince: number?,
	snaps: number,
}

local MoveCheck = {}
MoveCheck.__index = MoveCheck

function MoveCheck.new(settings: Settings): any
	return setmetatable({ _s = settings, _entries = {} :: { [string]: Entry } }, MoveCheck)
end

local function finite(n: number): boolean
	return n == n and n > -1e7 and n < 1e7
end

local function settings(self: any): Settings
	return self._s
end

local function cap(s: Settings, speed: number): number
	return math.max(0, speed) * (1 + s.speedSlack) * s.burstSeconds + s.leeway
end

-- Trust this spot as good (a new body, or the server just placed it). The budget starts full.
function MoveCheck.reset(self: any, id: string, x: number, y: number, z: number, now: number)
	local old: Entry? = self._entries[id]
	self._entries[id] = {
		x = x,
		y = y,
		z = z,
		at = now,
		budget = math.huge, -- trimmed to the cap on the first step
		rise = settings(self).riseLeeway,
		credit = 0,
		creditUntil = 0,
		heldSince = nil,
		snaps = if old then old.snaps else 0,
	}
end

function MoveCheck.forget(self: any, id: string)
	self._entries[id] = nil
end

-- A slide was accepted: this many extra studs may be covered for a short while.
function MoveCheck.addCredit(self: any, id: string, studs: number, now: number)
	local e: Entry? = self._entries[id]
	if e == nil or not finite(studs) or studs <= 0 then
		return
	end
	e.credit += studs
	e.creditUntil = now + self._s.slideCreditSeconds
end

function MoveCheck.step(
	self: any,
	id: string,
	x: number,
	y: number,
	z: number,
	now: number,
	speed: number
): (Verdict, number, number, number)
	local s: Settings = self._s
	local e: Entry? = self._entries[id]
	if e == nil then
		self:reset(id, x, y, z, now)
		return "ok", x, y, z
	end
	local dt = math.max(0, now - e.at)
	e.at = now
	local refill = math.max(0, speed) * (1 + s.speedSlack)
	e.budget = math.min(cap(s, speed), e.budget + refill * dt)
	e.rise = math.min(s.riseLeeway, e.rise + s.riseLeeway * dt)
	if now > e.creditUntil then
		e.credit = 0
	end

	local across = math.sqrt((x - e.x) ^ 2 + (z - e.z) ^ 2)
	-- Going up more steeply than a ramp spends a small budget (steps, curbs); flying drains it.
	local steepRise = (y - e.y) - across * s.riseSlope
	local fine = finite(x)
		and finite(y)
		and finite(z)
		and across <= e.budget + e.credit
		and steepRise <= e.rise
	if fine then
		if steepRise > 0 then
			e.rise -= steepRise
		end
		e.budget -= across
		if e.budget < 0 then
			e.credit = math.max(0, e.credit + e.budget)
			e.budget = 0
		end
		e.x, e.y, e.z = x, y, z
		e.heldSince = nil
		return "ok", x, y, z
	end

	if e.heldSince == nil then
		e.heldSince = now
	end
	if now - (e.heldSince :: number) < s.graceSeconds then
		return "hold", e.x, e.y, e.z
	end
	-- Put back with nothing saved up, so snapping again and again is never faster than walking.
	e.heldSince = nil
	e.snaps += 1
	e.budget = 0
	e.rise = 0
	e.credit = 0
	return "snap", e.x, e.y, e.z
end

-- A move is waiting to be explained: shots and pickups should wait too.
function MoveCheck.isHeld(self: any, id: string): boolean
	local e: Entry? = self._entries[id]
	return e ~= nil and e.heldSince ~= nil
end

-- The last spot the server believes. nil when this id is not watched.
function MoveCheck.good(self: any, id: string): (number?, number?, number?)
	local e: Entry? = self._entries[id]
	if e == nil then
		return nil, nil, nil
	end
	return e.x, e.y, e.z
end

function MoveCheck.snaps(self: any, id: string): number
	local e: Entry? = self._entries[id]
	return if e then e.snaps else 0
end

return MoveCheck
