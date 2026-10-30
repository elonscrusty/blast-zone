--!strict
-- Lets each key (a player's name, a remote) through at most `perSecond` times a second, with a
-- small burst. Pure: the clock is passed in, so Lune can test it. Server remotes use this first.

export type Limiter = {
	allow: (self: Limiter, key: string | number, now: number) -> boolean,
	forget: (self: Limiter, key: string | number) -> (),
}

local RateLimit = {}
RateLimit.__index = RateLimit

-- `perSecond` is the steady rate, `burst` how many calls may land at once (default = perSecond).
function RateLimit.new(perSecond: number, burst: number?): Limiter
	return setmetatable(
			{ _rate = perSecond, _burst = burst or perSecond, _state = {} },
			RateLimit
		) :: any
end

function RateLimit.allow(self: any, key: string | number, now: number): boolean
	local s = self._state[key]
	if not s then
		s = { tokens = self._burst, at = now }
		self._state[key] = s
	end
	s.tokens = math.min(self._burst, s.tokens + (now - s.at) * self._rate)
	s.at = now
	if s.tokens >= 1 then
		s.tokens -= 1
		return true
	end
	return false
end

function RateLimit.forget(self: any, key: string | number)
	self._state[key] = nil
end

return RateLimit
