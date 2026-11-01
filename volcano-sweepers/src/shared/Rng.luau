--!strict
-- Small seedable random generator that works in Lune tests AND in Roblox (Random.new is not in
-- Lune). Same seed -> same numbers on every machine. Use this in all pure logic; the server seeds it
-- from os.time()/tick() at the call site, tests seed with a fixed number.

export type Rng = {
	next: (self: Rng) -> number, -- float in [0, 1)
	int: (self: Rng, lo: number, hi: number) -> number, -- integer in [lo, hi]
	range: (self: Rng, lo: number, hi: number) -> number, -- float in [lo, hi)
	chance: (self: Rng, p: number) -> boolean,
	pick: <T>(self: Rng, list: { T }) -> T,
	state: number,
}

local Rng = {}

local function step(self: Rng): number
	-- mulberry32
	local s = bit32.band(self.state + 0x6D2B79F5, 0xFFFFFFFF)
	self.state = s
	local t = bit32.bxor(s, bit32.rshift(s, 15))
	t = bit32.band(
		t * (bit32.bor(s, 1) % 0x10000)
			+ bit32.band(t * (bit32.rshift(bit32.bor(s, 1), 16)) * 0x10000, 0xFFFFFFFF),
		0xFFFFFFFF
	)
	t = bit32.bxor(t, bit32.rshift(t, 7))
	t = bit32.bxor(t, bit32.rshift(bit32.bxor(t, bit32.rshift(t, 14)), 3))
	return bit32.band(t, 0xFFFFFFFF) / 4294967296
end

local methods = {}
function methods.next(self: Rng): number
	return step(self)
end
function methods.range(self: Rng, lo: number, hi: number): number
	return lo + step(self) * (hi - lo)
end
function methods.int(self: Rng, lo: number, hi: number): number
	return lo + math.floor(step(self) * (hi - lo + 1))
end
function methods.chance(self: Rng, p: number): boolean
	return step(self) < p
end
function methods.pick<T>(self: Rng, list: { T }): T
	return list[1 + math.floor(step(self) * #list)]
end

function Rng.new(seed: number): Rng
	local self = { state = bit32.band(math.floor(seed), 0xFFFFFFFF) }
	return setmetatable(self, { __index = methods }) :: any
end

return Rng
