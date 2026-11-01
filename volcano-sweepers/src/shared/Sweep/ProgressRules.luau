--!strict
-- Pure rules behind AshService: island clean milestones (parties), their coin gifts, which
-- progress changes are worth sending, delta chunking, how fast the ash regrows, the starting fill,
-- and spreading dropped backpack ash over nearby cells. Tested in tests/progress_rules.test.luau.
--
-- REGROW NUMBERS (units of ash per second for the whole island):
--   rate(n) = min(18, 0.9 + 1.1 x (n - 1))       n = players in the server, 0 players = 0
--   solo 0.9 u/s, 4 players 4.2 u/s, 16 players 17.4 u/s (cap 18).
-- Why: the test measures a lone player with the starter Twig Broom: about 9 units/s while swinging
-- through fresh ash, but only about 2 units/s once the backpack (30) and the 12 s trips to the hut
-- are counted. 5 x 0.9 = 4.5 >= 2, so one player can never strip the island faster than it grows
-- back 5 times over and always finds ash in the zones they own. Real play is slower than the peak,
-- so progress is steady, never a grind. Each extra friend adds 1.1 u/s (about half a starter
-- player's trip-adjusted pace), so a bigger group keeps the island alive but can still win it clean.
-- Regrowth lands more in zones that someone has unlocked (see AshService), so ash is where it is
-- wanted.
--
-- ADAPTIVE PART (so fast sweepers are never starved and a full server never runs dry; balanced by
-- tests/pacing.test.luau, which runs the real rules with 1, 2, 4 and 16 sweepers):
--   worked  = max(total clean, cleanest zone)   (kids empty their best zone and leave cheap ones full)
--   boost   = 1 + (BOOST_MULT - 1) x pressure, BOOST_MULT = 3
--   pressure= max(ramp(total clean, 0.70, 0.95), ramp(cleanest zone, 0.60, 0.95))
--   demand  = share(worked) x measured sweep rate (units/s, smoothed), share 0.35 -> 0.85
--             as worked goes from 50% to 95% clean
--   fed     = ramp(worked, 0.1, 0.8) x paceShare(n) x summed pace   (pace = what each kid COULD
--             sweep with their stats, trips counted; paceShare 0.5 solo, +0.12 a friend, max 0.95)
--   rate    = min(totalCap(n), max(base x boost, demand, fed)),  totalCap = 30 u/s a player, <= 480
-- The shares stay below 1, so a group that sweeps hard still makes net progress, and the cap grows
-- with the server so each kid's supply holds up as friends join. Regrowth comes in small piles
-- (AshGrid.REGROW_PILE) so a swing through regrown ash still feels full.

local Config = require("../Config")
local Tools = require("../Catalog/Tools")
local Zones = require("../Catalog/Zones")

local ProgressRules = {}

-- ===== milestones =====

ProgressRules.MILESTONES = { 0.25, 0.5, 0.75, 1.0 }
-- A celebrated milestone re-arms once the fraction falls max(REARM_DIP, REARM_SHARE x milestone)
-- below it: 25% re-arms under 15%, 50% under 30%, 75% under 45%, 100% under 60%. An Ash Storm
-- (about -20% clean) does not re-arm a party on its own, so parties stay special.
ProgressRules.REARM_DIP = 0.10
ProgressRules.REARM_SHARE = 0.4

-- The fraction a celebrated milestone must fall below before it can be celebrated again.
function ProgressRules.rearmBelow(milestone: number): number
	return milestone - math.max(ProgressRules.REARM_DIP, milestone * ProgressRules.REARM_SHARE)
end
-- After a party, no other party (any zone or the island) for this many seconds. A milestone
-- reached meanwhile is NOT lost: it is celebrated when the cooldown ends if it still holds.
ProgressRules.PARTY_COOLDOWN = 300
-- Tracker keys: zone ids 1..5, and this key for the whole island.
ProgressRules.ISLAND = 0

export type Tracker = {
	celebrated: { [number]: number }, -- key -> highest celebrated milestone index
	lastPartyAt: number?, -- time of the last party (only when update() is given `now`)
}

function ProgressRules.newTracker(): Tracker
	return { celebrated = {}, lastPartyAt = nil }
end

-- Feed the current clean fraction (0..1) of one zone (or ISLAND). Returns the milestone that was
-- just reached (0.25 / 0.5 / 0.75 / 1.0) or nil. A jump over several milestones celebrates only the
-- highest. A milestone that was celebrated is not celebrated again until the fraction dipped under
-- rearmBelow(milestone) (and then climbed back). With `now` (seconds), parties also keep
-- PARTY_COOLDOWN apart: during the cooldown nothing fires and nothing is marked, so the milestone
-- fires once the cooldown is over (if the fraction still holds).
function ProgressRules.update(
	tracker: Tracker,
	key: number,
	fraction: number,
	now: number?
): number?
	if fraction ~= fraction then
		return nil
	end
	local cooling = now ~= nil
		and tracker.lastPartyAt ~= nil
		and now - (tracker.lastPartyAt :: number) < ProgressRules.PARTY_COOLDOWN
	local ms = ProgressRules.MILESTONES
	local done = tracker.celebrated[key] or 0
	-- re-arm: walk down while the fraction fell REARM_DIP below the last celebrated milestone
	while done > 0 and fraction < ProgressRules.rearmBelow(ms[done]) do
		done -= 1
	end
	-- reach: the highest milestone above `done` that the fraction now covers
	local reached = 0
	for j = #ms, done + 1, -1 do
		if fraction >= ms[j] - 1e-9 then
			reached = j
			break
		end
	end
	if reached > 0 and not cooling then
		tracker.celebrated[key] = reached
		if now ~= nil then
			tracker.lastPartyAt = now
		end
		return ms[reached]
	end
	tracker.celebrated[key] = done
	return nil
end

-- ===== gifts =====

ProgressRules.ZONE_GIFT_PER_VALUE = 400
ProgressRules.ISLAND_GIFT_PER_VALUE = 4000
-- "Value" of the whole island for the gift: about one Fern Forest unit. Keeps the island party a
-- friendly mid-game gift (12K coins) instead of dwarfing the gate prices.
ProgressRules.ISLAND_UNIT_VALUE = 3
ProgressRules.GIFT_MIN = 50
ProgressRules.GIFT_MAX = 250000

-- Coins every player gets for a party. zone = 0 means the whole island.
function ProgressRules.gift(zone: number): number
	local raw
	if zone == ProgressRules.ISLAND then
		raw = ProgressRules.ISLAND_GIFT_PER_VALUE * ProgressRules.ISLAND_UNIT_VALUE
	else
		raw = ProgressRules.ZONE_GIFT_PER_VALUE * Zones.valueOf(zone)
	end
	return math.clamp(math.floor(raw), ProgressRules.GIFT_MIN, ProgressRules.GIFT_MAX)
end

-- The gift one player gets: never more than a party of their OWN best zone is worth, so a
-- veteran's Lava Heart party cannot buy a newcomer's first gates for them.
function ProgressRules.giftFor(zone: number, playerBestZone: number): number
	local full = ProgressRules.gift(zone)
	local best = if type(playerBestZone) == "number" and playerBestZone == playerBestZone
		then math.clamp(math.floor(playerBestZone), 1, 5)
		else 1
	local own = ProgressRules.gift(best)
	return math.min(full, own)
end

-- Only players who swept within this many seconds get the coin gift (everyone gets the x2).
ProgressRules.GIFT_RECENT_SECONDS = 120

function ProgressRules.earnsGift(lastSweepAt: number, now: number): boolean
	return lastSweepAt == lastSweepAt
		and lastSweepAt > 0
		and now - lastSweepAt <= ProgressRules.GIFT_RECENT_SECONDS
end

-- 0.25 -> 25 (what the Party remote carries)
function ProgressRules.percent(milestone: number): number
	return math.floor(milestone * 100 + 0.5)
end

-- ===== progress remote =====

ProgressRules.PROGRESS_STEP = 0.005

-- Round to 3 decimals: smaller payloads, and stable values to compare.
function ProgressRules.round3(f: number): number
	return math.floor(f * 1000 + 0.5) / 1000
end

-- true when any key of `cur` differs from `last` by >= threshold (a key missing from `last` counts
-- as changed).
function ProgressRules.changedEnough(
	last: { [number]: number },
	cur: { [number]: number },
	threshold: number
): boolean
	for key, v in cur do
		local prev = last[key]
		if prev == nil or math.abs(v - prev) >= threshold - 1e-9 then
			return true
		end
	end
	return false
end

function ProgressRules.copyInto(dst: { [number]: number }, src: { [number]: number })
	for key, v in src do
		dst[key] = v
	end
end

-- ===== delta chunking =====

ProgressRules.MAX_PAIRS = 400

-- Splits a flat {idx, level, idx, level, ...} list into chunks of at most maxPairs pairs. Empty in
-- gives {} (nothing to send). A dangling odd element is dropped. Small lists come back as the SAME
-- table (no copy) in a one-chunk list.
function ProgressRules.chunkDelta(flat: { number }, maxPairs: number): { { number } }
	local pairsCount = math.floor(#flat / 2)
	if pairsCount <= 0 then
		return {}
	end
	local per = math.max(1, math.floor(maxPairs))
	if pairsCount <= per and #flat == pairsCount * 2 then
		return { flat }
	end
	local chunks: { { number } } = {}
	local at = 1
	while at <= pairsCount * 2 do
		local last = math.min(pairsCount * 2, at + per * 2 - 1)
		local chunk = table.create(last - at + 1)
		table.move(flat, at, last, 1, chunk)
		table.insert(chunks, chunk)
		at = last + 1
	end
	return chunks
end

-- ===== regrow =====

ProgressRules.REGROW_BASE = 0.9 -- units per second for one player
ProgressRules.REGROW_PER_EXTRA = 1.1 -- each further player
ProgressRules.REGROW_CAP = 18

-- Units of ash per second the island regrows with this many players.
function ProgressRules.regrowRate(players: number): number
	if players ~= players or players < 1 then
		return 0
	end
	local n = math.min(players, Config.Game.MaxPlayers)
	return math.min(
		ProgressRules.REGROW_CAP,
		ProgressRules.REGROW_BASE + ProgressRules.REGROW_PER_EXTRA * (n - 1)
	)
end

ProgressRules.BOOST_MULT = 3
ProgressRules.BOOST_TOTAL_FROM = 0.70 -- total clean where the boost starts ...
ProgressRules.BOOST_ZONE_FROM = 0.60 -- ... and the cleanest zone's clean fraction where it starts
ProgressRules.BOOST_FULL_AT = 0.95 -- both ramps reach full boost here
ProgressRules.DEMAND_SHARE_LOW = 0.35 -- share of the measured sweep rate fed back at <= 50% clean
ProgressRules.DEMAND_SHARE_HIGH = 0.85 -- ... and at >= 95% clean (always below 1)
ProgressRules.TOTAL_CAP_PER_PLAYER = 30 -- the cap grows with the server, so friends never starve ...
ProgressRules.TOTAL_CAP = 480 -- ... and no regrow rate is above this, whatever happens
ProgressRules.SMOOTH_ALPHA = 0.3 -- sweep-rate smoothing per regrow step

-- The most the island regrows per second with this many players.
function ProgressRules.totalCap(players: number): number
	if players ~= players or players < 1 then
		return 0
	end
	local n = math.min(players, Config.Game.MaxPlayers)
	return math.min(ProgressRules.TOTAL_CAP, ProgressRules.TOTAL_CAP_PER_PLAYER * n)
end

local function ramp(x: number, from: number, to: number): number
	if x ~= x then
		return 0
	end
	return math.clamp((x - from) / (to - from), 0, 1)
end

-- Share of the players' sweep rate that the island puts back (0.35 .. 0.85).
function ProgressRules.demandShare(cleanTotal: number): number
	local t = ramp(cleanTotal, 0.5, ProgressRules.BOOST_FULL_AT)
	return ProgressRules.DEMAND_SHARE_LOW
		+ (ProgressRules.DEMAND_SHARE_HIGH - ProgressRules.DEMAND_SHARE_LOW) * t
end

-- Units per second to regrow right now.
--   players        ready players
--   cleanTotal     0..1 whole-island clean fraction
--   cleanestZone   0..1 clean fraction of the cleanest zone (the one closest to running dry)
--   sweepRate      smoothed units per second the players are removing
function ProgressRules.adaptiveRate(
	players: number,
	cleanTotal: number,
	cleanestZone: number,
	sweepRate: number,
	pace: number?
): number
	local base = ProgressRules.regrowRate(players)
	if base <= 0 then
		return 0
	end
	local pressure = math.max(
		ramp(cleanTotal, ProgressRules.BOOST_TOTAL_FROM, ProgressRules.BOOST_FULL_AT),
		ramp(cleanestZone, ProgressRules.BOOST_ZONE_FROM, ProgressRules.BOOST_FULL_AT)
	)
	local boosted = base * (1 + (ProgressRules.BOOST_MULT - 1) * pressure)
	local demand = 0
	if sweepRate == sweepRate and sweepRate > 0 and sweepRate < math.huge then
		-- players work their best zone and leave the cheap ones full, so the island-wide fraction
		-- alone would say "dirty" forever: the zone they are emptying counts too
		local worked = cleanTotal
		if cleanestZone > worked then
			worked = cleanestZone
		end
		demand = ProgressRules.demandShare(worked) * sweepRate
	end
	-- the island also answers what the players COULD sweep, not only what they found: a big
	-- vacuum in an emptied zone gets fed, up to paceShare of the summed pace when the zone is bare
	local want = pace or 0
	if want == want and want > 0 and want < math.huge then
		local worked = cleanTotal
		if cleanestZone > worked then
			worked = cleanestZone
		end
		local fed = ProgressRules.paceShare(players) * want
		local need = ramp(worked, ProgressRules.PACE_RAMP_FROM, ProgressRules.PACE_RAMP_FULL)
		demand = math.max(demand, need * fed)
	end
	return math.max(base, math.min(ProgressRules.totalCap(players), math.max(boosted, demand)))
end

-- What one player could sweep per second with these stats (fresh ash, trips to the hut counted).
-- AshService sums it over the ready players and passes it to regrowBudget, so bigger tools find more
-- ash. 0 for junk input.
function ProgressRules.pace(d: {
	reach: number,
	arcDeg: number,
	power: number,
	interval: number,
	capacity: number,
}): number
	local cells = Tools.cellsHit(d.reach, d.arcDeg, Config.World.cellSize)
	local raw = cells * math.min(d.power, 4) / d.interval
	local cap = d.capacity
	if
		not (
			raw == raw
			and raw > 0
			and raw < math.huge
			and cap == cap
			and cap > 0
			and cap < math.huge
		)
	then
		return 0
	end
	return cap / (cap / raw + Config.Player.tripSeconds)
end

-- Share of the players' summed pace the island can feed back. Solo it is half (the whole island's
-- starting ash is theirs too); every friend adds a bit because a crowd shares that starting ash, so
-- each kid's supply holds up as the server fills. Always below 1: sweeping hard still wins zones.
ProgressRules.PACE_SHARE = 0.5
ProgressRules.PACE_SHARE_PER_EXTRA = 0.12
ProgressRules.PACE_SHARE_MAX = 0.95
-- ... fed from when the worked zone is this clean, fully once it is this clean (a half-swept zone is
-- already thin: walking from pile to pile, not sweeping, is what slows kids down)
ProgressRules.PACE_RAMP_FROM = 0.1
ProgressRules.PACE_RAMP_FULL = 0.8

function ProgressRules.paceShare(players: number): number
	if players ~= players or players < 1 then
		return 0
	end
	local n = math.min(players, Config.Game.MaxPlayers)
	return math.min(
		ProgressRules.PACE_SHARE_MAX,
		ProgressRules.PACE_SHARE + ProgressRules.PACE_SHARE_PER_EXTRA * (n - 1)
	)
end

-- Moving average for the measured sweep rate.
function ProgressRules.smooth(avg: number, sample: number): number
	if sample ~= sample or sample < 0 then
		sample = 0
	end
	return avg + (sample - avg) * ProgressRules.SMOOTH_ALPHA
end

-- Whole units to regrow this step. `carry` is the fraction left over from earlier steps; pass back
-- the second result next time. dt is capped so a long stall never causes a flood. The last three
-- arguments are optional (left out = no boost, no demand): see adaptiveRate.
function ProgressRules.regrowBudget(
	players: number,
	dt: number,
	carry: number,
	cleanTotal: number?,
	cleanestZone: number?,
	sweepRate: number?,
	pace: number?
): (number, number)
	local step = math.clamp(dt, 0, 5)
	local rate = ProgressRules.adaptiveRate(
		players,
		cleanTotal or 0,
		cleanestZone or 0,
		sweepRate or 0,
		pace
	)
	local total = carry + rate * step
	local whole = math.floor(total)
	return whole, total - whole
end

-- ===== starting fill =====

-- A start level 0..max for one cell so the average fill is `targetFill` (0..1) with some variety:
-- target x max +/- 2, then dithered to a whole number.
function ProgressRules.startLevel(
	rng: { next: (any) -> number },
	targetFill: number,
	max: number
): number
	local v = targetFill * max + (rng:next() - 0.5) * 4
	return math.clamp(math.floor(v + rng:next()), 0, max)
end

-- ===== dropping ash back on the ground =====

-- Puts `units` back, one unit per cell per pass, over `cells` (starting at index `startAt`), until
-- the units run out or the cells are full. `grid.add(grid, cellIndex, n)` returns how many fit.
-- Returns how many units were placed.
function ProgressRules.spreadDrop(
	grid: { add: (any, number, number) -> number },
	cells: { number },
	units: number,
	startAt: number
): number
	local count = #cells
	if count == 0 or units ~= units or units < 1 then
		return 0
	end
	local left = math.floor(math.min(units, 1000))
	local placed = 0
	local offset = math.floor(math.max(0, startAt)) % count
	for _ = 1, Config.World.maxUnitsPerCell do
		local before = left
		for k = 1, count do
			if left <= 0 then
				break
			end
			local j = cells[(offset + k - 1) % count + 1]
			local put = grid:add(j, 1)
			if put > 0 then
				left -= put
				placed += put
			end
		end
		if left <= 0 or left == before then
			break
		end
	end
	return placed
end

return ProgressRules
