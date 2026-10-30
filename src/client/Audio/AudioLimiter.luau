--!strict
-- Decides whether a sound may start. Three rules keep a firefight from turning into noise:
--   1. a cue cannot restart faster than its minGap,
--   2. a cue cannot have more than maxVoices playing,
--   3. the whole mix has a cap; the player's own sounds (priority 1) may use a reserve above it, and
--      far ambience (priority 3) is the first to be refused as the mix fills.
-- No Roblox services, so the tests can run it.

local AudioLimiter = {}
AudioLimiter.__index = AudioLimiter

export type Spec = { maxVoices: number, minGap: number, priority: number }

export type Limiter = typeof(setmetatable(
	{} :: {
		cap: number,
		reserve: number,
		total: number,
		voices: { [string]: number },
		lastStart: { [string]: number },
	},
	AudioLimiter
))

local FILL = { 1.0, 0.85, 0.6 } -- how full the mix may be before this priority is refused

function AudioLimiter.new(cap: number, reserve: number): Limiter
	return setmetatable({
		cap = cap,
		reserve = reserve,
		total = 0,
		voices = {},
		lastStart = {},
	}, AudioLimiter)
end

function AudioLimiter.tryStart(self: Limiter, name: string, spec: Spec, now: number): boolean
	local last = self.lastStart[name]
	if last ~= nil and now - last < spec.minGap then
		return false
	end
	if (self.voices[name] or 0) >= spec.maxVoices then
		return false
	end
	local priority = math.clamp(spec.priority, 1, 3)
	local limit = self.cap * FILL[priority]
	if priority == 1 then
		limit += self.reserve
	end
	if self.total >= limit then
		return false
	end
	self.lastStart[name] = now
	self.voices[name] = (self.voices[name] or 0) + 1
	self.total += 1
	return true
end

-- Call once per started voice, when it ends. Extra calls are ignored.
function AudioLimiter.finish(self: Limiter, name: string)
	local n = self.voices[name]
	if n == nil or n <= 0 then
		return
	end
	self.voices[name] = n - 1
	self.total -= 1
end

function AudioLimiter.active(self: Limiter): number
	return self.total
end

-- A new match or a reset: forget everything.
function AudioLimiter.clear(self: Limiter)
	self.total = 0
	table.clear(self.voices)
	table.clear(self.lastStart)
end

return AudioLimiter
