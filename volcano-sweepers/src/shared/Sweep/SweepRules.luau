--!strict
-- Pure rules behind the Sweep and Sell services: swing rate limit, flattening the facing
-- direction, which zones a player may sweep, "is something sweepable but locked", range checks.
-- No Roblox types: the server glue passes plain numbers in. Tested in tests/sweep_rules.test.luau.

local Config = require("../Config")

local SweepRules = {}

-- A swing is accepted at most once per `interval x RATE_SLACK` seconds on average (the contract's
-- 0.8: a little slack so honest network jitter never drops a swing). BURST swings may arrive
-- together after a hiccup, then the average rate applies again.
SweepRules.RATE_SLACK = 0.8
SweepRules.BURST = 2

-- A flattened facing shorter than this (looking straight up or down) is rejected.
local MIN_FLAT_LENGTH = 0.05

function SweepRules.isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- ===== swing rate limit (token bucket) =====

export type Bucket = { tokens: number, at: number }

function SweepRules.newBucket(now: number): Bucket
	return { tokens = SweepRules.BURST, at = now }
end

-- Seconds between accepted swings for a tool interval (never faster than Config.Player.minInterval).
function SweepRules.minGap(interval: number): number
	local i = interval
	if not SweepRules.isFinite(i) or i <= 0 then
		i = 1 -- bad data: be strict, not generous
	end
	return math.max(Config.Player.minInterval, i) * SweepRules.RATE_SLACK
end

-- true = accept this swing (and one token is spent). false = too early (nothing is spent).
-- One token refills every minGap(interval) seconds, up to BURST.
function SweepRules.allowSwing(bucket: Bucket, now: number, interval: number): boolean
	local gap = SweepRules.minGap(interval)
	local elapsed = now - bucket.at
	if elapsed ~= elapsed or elapsed < 0 then
		-- a clock that went backwards must not mint tokens (and keeps the old reference time)
		elapsed = 0
	else
		bucket.at = now
	end
	bucket.tokens = math.min(SweepRules.BURST, bucket.tokens + elapsed / gap)
	if bucket.tokens >= 1 - 1e-9 then
		bucket.tokens = math.max(0, bucket.tokens - 1)
		return true
	end
	return false
end

-- ===== facing =====

-- The character's LookVector with Y thrown away, scaled to length 1. The third result is false
-- when there is no usable horizontal facing (non-finite, or looking straight up / down).
function SweepRules.flattenDir(
	lookX: number,
	lookY: number,
	lookZ: number
): (number, number, boolean)
	if
		not (
			SweepRules.isFinite(lookX)
			and SweepRules.isFinite(lookY)
			and SweepRules.isFinite(lookZ)
		)
	then
		return 0, 0, false
	end
	local len = math.sqrt(lookX * lookX + lookZ * lookZ)
	if len < MIN_FLAT_LENGTH then
		return 0, 0, false
	end
	return lookX / len, lookZ / len, true
end

-- ===== zones =====

local ZONE_KEYS: { [number]: string } = {}
local FIRST_ZONE = math.huge
for _, z in Config.World.zones do
	ZONE_KEYS[z.id] = tostring(z.id)
	FIRST_ZONE = math.min(FIRST_ZONE, z.id)
end

-- Fills `out[zoneId] = true/false` from the profile's `zones` map ("1".."5" -> true). The first
-- (free) zone is always allowed. `out` is reused (no allocation). Returns how many are allowed.
function SweepRules.buildAllowed(zones: { [string]: boolean }, out: { [number]: boolean }): number
	local count = 0
	for id, key in ZONE_KEYS do
		local ok = zones[key] == true or id == FIRST_ZONE
		out[id] = ok
		if ok then
			count += 1
		end
	end
	return count
end

-- true when some cell in `cells` still holds ash but its zone is not allowed.
function SweepRules.hasLockedAsh(
	cells: { number },
	levels: { number },
	zoneOf: { number },
	allowed: { [number]: boolean }
): boolean
	for _, j in cells do
		if levels[j] > 0 and not allowed[zoneOf[j]] then
			return true
		end
	end
	return false
end

-- Counts cells per zone into `out[zoneId]` (reused; zero for zones with no cells).
function SweepRules.countByZone(
	cells: { number },
	zoneOf: { number },
	out: { [number]: number }
): number
	for id in ZONE_KEYS do
		out[id] = 0
	end
	local total = 0
	for _, j in cells do
		local z = zoneOf[j]
		out[z] = (out[z] or 0) + 1
		total += 1
	end
	return total
end

-- ===== small shared helpers =====

-- Gate for repeated messages: true (and remembers `now`) when `gap` seconds passed since the last
-- time for `key`.
function SweepRules.allowEvery(last: { [any]: number }, key: any, now: number, gap: number): boolean
	local prev = last[key]
	if prev ~= nil and now - prev < gap then
		return false
	end
	last[key] = now
	return true
end

function SweepRules.withinRange2D(
	px: number,
	pz: number,
	tx: number,
	tz: number,
	range: number
): boolean
	local dx, dz = px - tx, pz - tz
	return dx * dx + dz * dz <= range * range
end

-- Where the Trade Hut stands, from Config (same maths as Ash/Layout): the fallback sell spot.
function SweepRules.hubXZ(world: typeof(Config.World)): (number, number)
	local a = math.rad(world.hub.angleDeg)
	return world.hub.radius * math.cos(a), world.hub.radius * math.sin(a)
end

return SweepRules
