--!strict
-- Pure helpers for the Roblox glue in server/Burp and server/Finds. Everything here runs in Lune:
-- no Instances, no Vector3, no clocks. The glue passes numbers in and gets numbers or plain tables out.
--
--   * knockback maths (never NaN, bounded)         * hit shield + armor drop rules
--   * director events -> a flat list of commands   * "was anyone hit" bookkeeping for burpDodged
--   * geyser gem pickup range, coins, scatter      * Finds Book set-claim rules

local BurpDirector = require("./BurpDirector")
local Config = require("../Config")
local Layout = require("../Ash/Layout")
local Rng = require("../Rng")
local Types = require("../Types")
local Zones = require("../Catalog/Zones")

type Rng = Rng.Rng
type Bomb = Types.Bomb
type Spot = BurpDirector.Spot

local BurpGlue = {}

-- ===== numbers (all tunable here, all covered by tests) =====
BurpGlue.shieldSeconds = 2.5 -- a player hit by lava cannot be hit again for this long
BurpGlue.dropBase = 0.2 -- share of the backpack lost per hit before armor
BurpGlue.knockOut = 32 -- studs/s away from the blast centre
BurpGlue.knockUp = 48 -- studs/s up (about 6 studs of air under normal gravity)
BurpGlue.maxKnock = 90 -- no velocity we hand to the physics engine is longer than this
BurpGlue.maxLiveBombs = 40 -- hard cap on server-side lava bomb parts
BurpGlue.maxGoldenCells = 400 -- BurpTuning.goldenMaxCells (380) fits under this
BurpGlue.maxGeyserSpots = 12
BurpGlue.maxBuffMult = 4 -- Spark "long buffs" can stretch the perfect buff at most this much
BurpGlue.pickupRadius = 6 -- studs, flat distance
BurpGlue.pickupHeight = 12 -- studs of vertical slack (the gem floats above the ground)
BurpGlue.gemBaseCoins = 15 -- x zone value x rarity multiplier = base coins of one geyser gem

local HUGE = 1e15

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -HUGE and n < HUGE
end
BurpGlue.finite = finite

local function clamp01(n: number): number
	if n ~= n then
		return 0
	end
	return math.clamp(n, 0, 1)
end

-- ===== where is a point =====

-- Zone id for a world point. Unlike Layout.zoneAt it never returns nil: inside the lava heart's hole
-- is zone 5 (innermost), far outside the beach is zone 1 (outermost). Non-finite input -> zone 1.
function BurpGlue.zoneOf(x: number, z: number): number
	if not (finite(x) and finite(z)) then
		return 1
	end
	local r = math.sqrt(x * x + z * z)
	local innermost, outermost = Config.World.zones[1], Config.World.zones[1]
	for _, zone in Config.World.zones do
		if r >= zone.inner and r < zone.outer then
			return zone.id
		end
		if zone.inner < innermost.inner then
			innermost = zone
		end
		if zone.outer > outermost.outer then
			outermost = zone
		end
	end
	if r < innermost.inner then
		return innermost.id
	end
	return outermost.id
end

-- The hub (spawn + Trade Hut) is a safe zone: lava never bounces anyone standing in it.
function BurpGlue.inHub(x: number, z: number): boolean
	if not (finite(x) and finite(z)) then
		return false
	end
	local hub = Config.World.hub
	local a = math.rad(hub.angleDeg)
	local dx, dz = x - hub.radius * math.cos(a), z - hub.radius * math.sin(a)
	return dx * dx + dz * dz <= hub.clearRadius * hub.clearRadius
end

-- ===== hit rules =====

-- Shield rule: a hit player is safe for shieldSeconds. `lastHitAt` and `now` are on the same clock.
function BurpGlue.canBeHit(lastHitAt: number, now: number): boolean
	if not finite(now) then
		return false
	end
	if not finite(lastHitAt) or lastHitAt > now then
		return true -- a clock that ran backwards must not make a player immune forever
	end
	return now - lastHitAt >= BurpGlue.shieldSeconds
end

-- Share of the backpack lost to one hit: 0.2 x (1 - armor). Armor is clamped to 0..maxArmor.
function BurpGlue.dropFraction(armor: number): number
	local a = if finite(armor) then math.clamp(armor, 0, Config.Player.maxArmor) else 0
	return clamp01(BurpGlue.dropBase * (1 - a))
end

local function speed(v: number?, default: number): number
	if v == nil or not finite(v) then
		return default
	end
	return math.clamp(v, 0, BurpGlue.maxKnock)
end

-- Velocity (vx, vy, vz) that bounces a player at (px, pz) away from a blast at (bx, bz): `out` studs/s
-- horizontally, `up` studs/s up. Standing exactly on the centre (or bad numbers) pushes along +X so
-- there is always a direction. The result is never NaN and never longer than maxKnock.
function BurpGlue.knockback(
	px: number,
	pz: number,
	bx: number,
	bz: number,
	out: number?,
	up: number?
): (number, number, number)
	local o = speed(out, BurpGlue.knockOut)
	local u = speed(up, BurpGlue.knockUp)
	local dx, dz = px - bx, pz - bz
	if not (finite(dx) and finite(dz)) then
		dx, dz = 0, 0
	end
	local len = math.sqrt(dx * dx + dz * dz)
	local vx, vz
	if len < 0.05 then
		vx, vz = o, 0
	else
		vx, vz = dx / len * o, dz / len * o
	end
	local mag = math.sqrt(vx * vx + u * u + vz * vz)
	if mag > BurpGlue.maxKnock then
		local k = BurpGlue.maxKnock / mag
		vx, u, vz = vx * k, u * k, vz * k
	end
	return vx, u, vz
end

-- Seconds a bomb part takes to fall: landsAt - now, kept between 0.2 s and 8 s (bad numbers -> 2).
function BurpGlue.fallSeconds(landsAt: number, now: number): number
	if not (finite(landsAt) and finite(now)) then
		return 2
	end
	return math.clamp(landsAt - now, 0.2, 8)
end

-- A buff that should last (untilAt - now) seconds, stretched by the best "long buffs" multiplier in
-- the server (1..maxBuffMult). Returns the absolute end time.
function BurpGlue.buffUntil(now: number, untilAt: number, mult: number): number
	if not (finite(now) and finite(untilAt)) then
		return now
	end
	local m = if finite(mult) then math.clamp(mult, 1, BurpGlue.maxBuffMult) else 1
	return now + math.max(0, untilAt - now) * m
end

-- ===== phase look =====

-- How red the sky gets (0 = normal .. 1 = fully angry) for a phase.
function BurpGlue.tintFor(phase: string, kind: string?): number
	if phase == "rumble" then
		return 0.6
	elseif phase == "event" then
		return if kind == "pops" then 1 else 0.4
	end
	return 0
end

-- ===== director events -> commands =====

export type Command = {
	kind: "phase" | "bombs" | "land" | "rain" | "golden" | "geysers" | "perfect",
	info: Types.BurpInfo?, -- phase: ready for the Burp remote
	tint: number?, -- phase: 0..1
	bombs: { Bomb }?, -- bombs: accepted bombs only (also what the Bombs remote should carry)
	bomb: Bomb?, -- land: the bomb that landed (looked up from the book)
	fraction: number?, -- rain
	cells: number?, -- golden
	spots: { Spot }?, -- geysers
	untilAt: number?, -- golden / perfect
}

-- Remembers the bombs we accepted until they land (the director's "land" event only has an id).
export type Book = { bombs: { [number]: Bomb }, count: number }

function BurpGlue.newBook(): Book
	return { bombs = {}, count = 0 }
end

local PHASES: { [string]: boolean } = { calm = true, rumble = true, event = true, recover = true }
local KINDS: { [string]: boolean } = { pops = true, ashStorm = true, golden = true, geysers = true }

local function validBomb(b: any): boolean
	return type(b) == "table"
		and finite(b.id)
		and finite(b.x)
		and finite(b.z)
		and finite(b.landsAt)
		and finite(b.radius)
		and b.radius > 0
end

-- Turns the director's events (in order) into commands, dropping anything malformed. Bombs are put
-- in `book` (refused past maxLiveBombs); a "land" for a bomb that is not in the book is dropped.
-- Entries whose landing time is long past are forgotten, so the book can never grow forever.
function BurpGlue.buildCommands(
	book: Book,
	events: { BurpDirector.BurpEvent },
	now: number
): { Command }
	local out: { Command } = {}
	for _, ev in events do
		local kind = ev.kind
		if kind == "phase" then
			local phase = ev.phase
			local startsAt, endsAt = ev.startsAt, ev.endsAt
			if phase ~= nil and PHASES[phase] and finite(startsAt) and finite(endsAt) then
				local burpKind = ev.burpKind
				if burpKind ~= nil and not KINDS[burpKind] then
					burpKind = nil
				end
				table.insert(out, {
					kind = "phase",
					info = {
						phase = phase,
						kind = burpKind,
						startsAt = startsAt :: number,
						endsAt = endsAt :: number,
					},
					tint = BurpGlue.tintFor(phase, burpKind),
				})
			end
		elseif kind == "bombs" then
			local accepted: { Bomb } = {}
			for _, b in ev.bombs or {} do
				if
					validBomb(b)
					and book.bombs[b.id] == nil
					and book.count < BurpGlue.maxLiveBombs
				then
					book.bombs[b.id] = b
					book.count += 1
					table.insert(accepted, b)
				end
			end
			if #accepted > 0 then
				table.insert(out, { kind = "bombs", bombs = accepted })
			end
		elseif kind == "land" then
			local id = ev.bombId
			local bomb = if id ~= nil then book.bombs[id] else nil
			if bomb ~= nil then
				book.bombs[bomb.id] = nil
				book.count -= 1
				table.insert(out, { kind = "land", bomb = bomb })
			end
		elseif kind == "rain" then
			local fraction = clamp01(ev.fraction or 0)
			if fraction > 0 then
				table.insert(out, { kind = "rain", fraction = fraction })
			end
		elseif kind == "golden" then
			local cells = ev.cells
			local untilAt = ev.untilAt
			if finite(cells) and finite(untilAt) and (untilAt :: number) > now then
				local n = math.clamp(math.floor(cells :: number), 0, BurpGlue.maxGoldenCells)
				if n > 0 then
					table.insert(out, { kind = "golden", cells = n, untilAt = untilAt })
				end
			end
		elseif kind == "geysers" then
			local spots: { Spot } = {}
			for _, s in ev.spots or {} do
				if
					#spots < BurpGlue.maxGeyserSpots
					and type(s) == "table"
					and finite(s.x)
					and finite(s.z)
				then
					table.insert(spots, { x = s.x, z = s.z })
				end
			end
			table.insert(out, { kind = "geysers", spots = spots })
		elseif kind == "perfect" then
			local untilAt = ev.untilAt
			if finite(untilAt) and (untilAt :: number) > now then
				table.insert(out, { kind = "perfect", untilAt = untilAt })
			end
		end
	end
	-- forget bombs that should have landed long ago (director went to sleep, etc.)
	for id, b in book.bombs do
		if b.landsAt < now - 10 then
			book.bombs[id] = nil
			book.count -= 1
		end
	end
	return out
end

-- ===== burpDodged bookkeeping =====
-- One Round per volcano event. Everyone present when a bomb landed "took part"; whoever was not hit
-- by the time the event ends has dodged it.

export type Round = { landed: number, present: { [number]: boolean }, hit: { [number]: boolean } }

function BurpGlue.newRound(): Round
	return { landed = 0, present = {}, hit = {} }
end

function BurpGlue.roundReset(r: Round)
	r.landed = 0
	r.present = {}
	r.hit = {}
end

function BurpGlue.roundLand(r: Round, userIds: { number })
	r.landed += 1
	for _, id in userIds do
		r.present[id] = true
	end
end

function BurpGlue.roundHit(r: Round, userId: number)
	r.hit[userId] = true
end

-- userIds (ascending) who took part and were not hit, then the round starts over. Empty when no bomb
-- landed (ash storms, golden bursts and geysers never count as a dodge).
function BurpGlue.roundFinish(r: Round): { number }
	local out: { number } = {}
	if r.landed > 0 then
		for id in r.present do
			if not r.hit[id] then
				table.insert(out, id)
			end
		end
		table.sort(out)
	end
	BurpGlue.roundReset(r)
	return out
end

-- ===== sharing events between players =====

BurpGlue.stormPerPlayer = 0.02 -- each extra player adds this to the storm's share of cells ...
BurpGlue.stormMaxFraction = 0.6 -- ... up to this (before the island-size scale below)
-- The storm numbers were tuned on the first island (3004 cells). The island now has about 4x the
-- cells: the same share of cells would bring 4x the ash per player. sqrt(3004 / N) (about 0.5)
-- is the middle: a storm still dusts the whole island visibly, but brings about 2x the ash it
-- used to (kids are spread over 4x the ground), not 4x.
BurpGlue.STORM_REF_CELLS = 3004
BurpGlue.stormCellScale = math.min(1, math.sqrt(BurpGlue.STORM_REF_CELLS / math.max(1, Layout.N)))

-- Share of cells an Ash Storm pulse covers with `players` in the server: more friends sweep more,
-- so the storm brings more (the ash per player does not collapse as the server fills up).
function BurpGlue.stormFraction(base: number, players: number): number
	local b = if finite(base) then math.clamp(base, 0, 1) else 0
	local n = if finite(players)
		then math.clamp(math.floor(players), 1, Config.Game.MaxPlayers)
		else 1
	local share =
		math.min(math.max(b, BurpGlue.stormMaxFraction), b + BurpGlue.stormPerPlayer * (n - 1))
	return share * BurpGlue.stormCellScale
end

-- Highest zone id a profile has unlocked (zone 1 is always open).
function BurpGlue.bestZone(zones: { [string]: boolean }): number
	local best = 1
	if type(zones) ~= "table" then
		return best
	end
	for _, zone in Config.World.zones do
		if zones[tostring(zone.id)] == true and zone.id > best then
			best = zone.id
		end
	end
	return best
end

-- Splits `count` golden cells as evenly as possible over `players` (first players get the extra
-- ones). Always sums to the clamped count; never more than maxGoldenCells.
function BurpGlue.goldenShare(count: number, players: number): { number }
	local total = if finite(count)
		then math.clamp(math.floor(count), 0, BurpGlue.maxGoldenCells)
		else 0
	local n = if finite(players) then math.clamp(math.floor(players), 1, 64) else 1
	local out: { number } = {}
	local each, extra = total // n, total % n
	for i = 1, n do
		out[i] = each + (if i <= extra then 1 else 0)
	end
	return out
end

-- ===== geyser gems =====

-- Which rarity a gem is, from a 0..1 roll: mostly common, sometimes uncommon, rarely rare.
function BurpGlue.gemRarity(roll: number): string
	local r = clamp01(roll)
	if r < 0.7 then
		return "common"
	elseif r < 0.93 then
		return "uncommon"
	end
	return "rare"
end

-- Highest zone the player has unlocked that is not above the gem's zone (always >= 1). A player who
-- has not opened the Lava Heart cannot cash a Lava Heart gem at Lava Heart prices.
function BurpGlue.effectiveZone(gemZone: number, unlocked: { [string]: boolean }): number
	local top = 1
	if not finite(gemZone) then
		return top
	end
	for _, zone in Config.World.zones do
		if zone.id <= gemZone and zone.id > top and unlocked[tostring(zone.id)] == true then
			top = zone.id
		end
	end
	return top
end

-- Base coins (before the player's sell multiplier) of one gem: gemBaseCoins x zone value x rarity.
function BurpGlue.geyserCoins(
	gemZone: number,
	unlocked: { [string]: boolean },
	coinMult: number
): number
	local m = if finite(coinMult) then math.clamp(coinMult, 0, 100) else 1
	local value = Zones.valueOf(BurpGlue.effectiveZone(gemZone, unlocked))
	return math.max(1, math.floor(BurpGlue.gemBaseCoins * value * m + 0.5))
end

-- Is a player at (px, py, pz) close enough to take a gem at (gx, gy, gz)?
function BurpGlue.inPickupRange(
	px: number,
	py: number,
	pz: number,
	gx: number,
	gy: number,
	gz: number,
	radius: number?
): boolean
	if
		not (finite(px) and finite(py) and finite(pz) and finite(gx) and finite(gy) and finite(gz))
	then
		return false
	end
	local r = radius or BurpGlue.pickupRadius
	local dx, dz = px - gx, pz - gz
	return dx * dx + dz * dz <= r * r and math.abs(py - gy) <= BurpGlue.pickupHeight
end

-- `n` offsets around a vent: evenly spread angles (random start + a little jitter), radius rMin..rMax.
function BurpGlue.gemOffsets(rng: Rng, n: number, rMin: number, rMax: number): { Spot }
	local out: { Spot } = {}
	local count = if finite(n) then math.clamp(math.floor(n), 0, 20) else 0
	local base = rng:range(0, math.pi * 2)
	for k = 1, count do
		local a = base + (k - 1) * (math.pi * 2 / count) + rng:range(-0.3, 0.3)
		local r = rng:range(rMin, rMax)
		table.insert(out, { x = math.cos(a) * r, z = math.sin(a) * r })
	end
	return out
end

-- Moves each director spot onto the nearest vent nobody took yet (so gems pop out of real vents).
-- A spot with no vent left stays where it is.
function BurpGlue.snapSpots(spots: { Spot }, vents: { Spot }): { Spot }
	local out: { Spot } = {}
	local used: { [number]: boolean } = {}
	for _, s in spots do
		local best, bestD = 0, math.huge
		for k, v in vents do
			if not used[k] then
				local dx, dz = v.x - s.x, v.z - s.z
				local d = dx * dx + dz * dz
				if d < bestD then
					best, bestD = k, d
				end
			end
		end
		if best > 0 then
			used[best] = true
			table.insert(out, { x = vents[best].x, z = vents[best].z })
		else
			table.insert(out, { x = s.x, z = s.z })
		end
	end
	return out
end

-- ===== Finds Book =====

BurpGlue.maxRollsPerCall = 40 -- one Sweep can never trigger more find rolls than this

-- How many find rolls a "cleared N cells" report may cause: whole number, 0..maxRollsPerCall.
function BurpGlue.rollCount(cleared: number): number
	if not finite(cleared) then
		return 0
	end
	return math.clamp(math.floor(cleared), 0, BurpGlue.maxRollsPerCall)
end

-- FindRoller wants a bonus fraction; derived.luck is a multiplier (1 = no bonus).
function BurpGlue.luckBonus(derivedLuck: number): number
	if not finite(derivedLuck) then
		return 0
	end
	return math.max(0, derivedLuck - 1)
end

-- What a find pays: base coins x the player's sell multiplier, a whole number, at least 1 for a real find.
function BurpGlue.findCoins(baseCoins: number, sellMult: number): number
	if not finite(baseCoins) or baseCoins <= 0 then
		return 0
	end
	local m = if finite(sellMult) then math.max(sellMult, 0) else 1
	return math.max(1, math.floor(baseCoins * m + 0.5))
end

-- Counts one more of `id` in the saved finds table. Returns true when it is the first of its kind.
function BurpGlue.recordFind(finds: { [string]: number }, id: string): boolean
	local before = finds[id]
	local isNew = type(before) ~= "number" or not (before >= 1)
	finds[id] = if isNew then 1 else before + 1
	return isNew
end

-- Ids of the finds that belong to a set, in catalog order.
function BurpGlue.setMembers(findList: { { id: string, set: string } }, setId: string): { string }
	local out: { string } = {}
	for _, f in findList do
		if f.set == setId then
			table.insert(out, f.id)
		end
	end
	return out
end

-- Can this set be claimed? Returns (ok, reason). reason is "ok", "unknown" (no such set), "claimed",
-- "empty" (set without finds) or "incomplete" (some find never found). `setById` only needs the keys.
function BurpGlue.claimCheck(
	setId: string,
	finds: { [string]: number },
	claimed: { [string]: boolean },
	setById: { [string]: any },
	findList: { { id: string, set: string } }
): (boolean, string)
	if type(setId) ~= "string" or setById[setId] == nil then
		return false, "unknown"
	end
	if claimed[setId] == true then
		return false, "claimed"
	end
	local members = BurpGlue.setMembers(findList, setId)
	if #members == 0 then
		return false, "empty"
	end
	for _, id in members do
		local n = finds[id]
		if type(n) ~= "number" or not (n >= 1) then
			return false, "incomplete"
		end
	end
	return true, "ok"
end

-- Toast for a rare or better find; nil for common and uncommon (the Book popup is enough).
function BurpGlue.findToast(rarityId: string, name: string): Types.ToastInfo?
	if rarityId == "legendary" then
		return { text = `LEGENDARY find! {name}`, kind = "gold" }
	elseif rarityId == "rare" then
		return { text = `Rare find! {name}`, kind = "gold" }
	end
	return nil
end

-- "Set complete! +3% coins forever" for a reward fraction like 0.03.
function BurpGlue.setClaimText(reward: number): string
	local pct = if finite(reward) then math.floor(reward * 100 + 0.5) else 0
	return `Set complete! +{pct}% coins forever`
end

return BurpGlue
