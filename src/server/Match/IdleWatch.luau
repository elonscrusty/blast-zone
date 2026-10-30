--!strict
-- Idle (AFK) bookkeeping. Pure, so Lune can test it: no Roblox services here.
-- IdleSystem feeds it what the server saw (position samples, shots, pickups) and asks who to warn or remove.
-- Two watches run side by side: one for fighters in a match, one for players queued in the lobby.

export type Limits = {
	warnSeconds: number,
	kickSeconds: number,
	moveStuds: number,
}

type Entry = {
	lastActive: number,
	warned: boolean,
	ax: number?, -- last position that counted as movement
	ay: number?,
	az: number?,
}

export type Sweep = {
	warn: { string }, -- newly past the warning time
	kick: { string }, -- past the removal time (already forgotten, so each is listed once)
}

export type Watch = {
	track: (id: string, now: number) -> (),
	untrack: (id: string) -> (),
	clear: () -> (),
	isTracked: (id: string) -> boolean,
	activity: (id: string, now: number) -> (),
	position: (id: string, now: number, x: number, y: number, z: number) -> (),
	secondsIdle: (id: string, now: number) -> number?,
	secondsUntilKick: (id: string, now: number) -> number?,
	sweep: (now: number) -> Sweep,
}

local IdleWatch = {}

function IdleWatch.new(limits: Limits): Watch
	assert(
		limits.warnSeconds > 0 and limits.kickSeconds > limits.warnSeconds,
		"IdleWatch: kick time must be after the warning time"
	)
	local entries: { [string]: Entry } = {}
	local self = {} :: Watch

	-- Start watching. The clock starts now, so a fresh fight or queue gets the full time.
	function self.track(id: string, now: number)
		entries[id] = { lastActive = now, warned = false }
	end

	function self.untrack(id: string)
		entries[id] = nil
	end

	function self.clear()
		entries = {}
	end

	function self.isTracked(id: string): boolean
		return entries[id] ~= nil
	end

	-- A shot, a slide, a pickup, a choice: proof a person is there. Ignored for ids not watched.
	function self.activity(id: string, now: number)
		local e = entries[id]
		if e then
			e.lastActive = math.max(e.lastActive, now)
			e.warned = false
		end
	end

	-- A position sample. Only a real walk counts: moving less than `moveStuds` from the last counted
	-- spot (jitter, being pushed a little) does not reset the clock.
	function self.position(id: string, now: number, x: number, y: number, z: number)
		local e = entries[id]
		if not e then
			return
		end
		local ax, ay, az = e.ax, e.ay, e.az
		if ax == nil or ay == nil or az == nil then
			e.ax, e.ay, e.az = x, y, z
			return
		end
		local dx, dy, dz = x - ax, y - ay, z - az
		if math.sqrt(dx * dx + dy * dy + dz * dz) >= limits.moveStuds then
			e.ax, e.ay, e.az = x, y, z
			self.activity(id, now)
		end
	end

	function self.secondsIdle(id: string, now: number): number?
		local e = entries[id]
		if not e then
			return nil
		end
		return math.max(0, now - e.lastActive)
	end

	function self.secondsUntilKick(id: string, now: number): number?
		local idle = self.secondsIdle(id, now)
		if idle == nil then
			return nil
		end
		return math.max(0, limits.kickSeconds - idle)
	end

	function self.sweep(now: number): Sweep
		local out: Sweep = { warn = {}, kick = {} }
		for id, e in entries do
			local idle = now - e.lastActive
			if idle >= limits.kickSeconds then
				table.insert(out.kick, id)
			elseif idle >= limits.warnSeconds and not e.warned then
				e.warned = true
				table.insert(out.warn, id)
			end
		end
		for _, id in out.kick do
			entries[id] = nil
		end
		table.sort(out.warn)
		table.sort(out.kick)
		return out
	end

	return self
end

return IdleWatch
