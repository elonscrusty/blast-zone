--!strict
-- The Burp Director: a pure state machine that decides WHEN the volcano burps and WHAT happens.
-- It never touches the world. The server calls `step(now, ctx)` a few times a second and executes
-- the events it returns; it reports lava hits back with `reportHit`.
--
--   calm -> rumble -> event -> recover -> calm -> ...
--
-- Rules it keeps (tests enforce them):
--   * No players -> no burps. The director sleeps; when players come back the first-burp delay restarts.
--   * First rumble is at least `firstBurpDelay` (75 s) after the first player appears.
--   * Bombs aim near players (dodging matters) but never at the hub, and are shown for at least
--     `minTelegraph` seconds before they land.
--   * The perfect-dodge buff is only awarded when a lava-pops event landed bombs and nobody was hit.
--
-- Call order for the server glue, every tick (<= 0.5 s apart is plenty):
--   local events = director:step(now, ctx)
--   for each event in order: execute it. For {kind="land"} do the hit test against every player and
--   call director:reportHit(userId, now) for each player hit, BEFORE the next step.

local BurpTuning = require("./BurpTuning")
local Config = require("../Config")
local Rng = require("../Rng")
local Types = require("../Types")

type Rng = Rng.Rng
type Tuning = BurpTuning.Tuning
type Bomb = Types.Bomb

export type PlayerPos = { userId: number, x: number, z: number, zone: number }
export type Ctx = {
	playerPositions: { PlayerPos },
	cleanTotal: number, -- 0..1 island clean fraction
	playerCount: number,
}
export type Spot = { x: number, z: number }
export type BurpEvent = {
	kind: "phase" | "bombs" | "land" | "rain" | "golden" | "geysers" | "perfect",
	phase: Types.BurpPhase?, -- phase
	burpKind: Types.BurpKind?, -- phase (nil during calm)
	startsAt: number?, -- phase
	endsAt: number?, -- phase
	bombs: { Bomb }?, -- bombs
	bombId: number?, -- land
	fraction: number?, -- rain: share of cells that get +1..2 units
	cells: number?, -- golden: how many golden cells to place
	spots: { Spot }?, -- geysers
	untilAt: number?, -- golden / perfect: server time the effect ends ("until" is a Luau keyword)
}
export type State = {
	phase: Types.BurpPhase,
	burpKind: Types.BurpKind?,
	startsAt: number,
	endsAt: number,
	awake: boolean,
}

export type BurpDirector = {
	rng: Rng,
	tun: Tuning,
	awake: boolean,
	phase: Types.BurpPhase,
	burpKind: Types.BurpKind?,
	lastKind: Types.BurpKind?,
	phaseStart: number,
	phaseEnd: number,
	lastRumbleStart: number?,
	pulseAt: number?,
	spawnUntil: number,
	nextId: number,
	pending: { Bomb },
	pendHead: number,
	hit: boolean,
	landed: number,
	lastLandsAt: number?,
	hubX: number,
	hubZ: number,
	innerR: number,
	outerR: number,

	step: (self: BurpDirector, now: number, ctx: Ctx) -> { BurpEvent },
	reportHit: (self: BurpDirector, userId: number, now: number) -> (),
	hitTest: (self: BurpDirector, bomb: Bomb, x: number, z: number) -> boolean,
	getState: (self: BurpDirector) -> State,
	activeBombs: (self: BurpDirector) -> { Bomb },
}

local BurpDirector = {}

local TWO_PI = math.pi * 2
local KINDS: { Types.BurpKind } = { "pops", "ashStorm", "golden", "geysers" }

local function clamp01(v: number): number
	if v ~= v then
		return 0
	end
	return math.clamp(v, 0, 1)
end

local function zoneRing(zoneId: number): (number?, number?)
	for _, z in Config.World.zones do
		if z.id == zoneId then
			return z.inner, z.outer
		end
	end
	return nil, nil
end

local function kindDuration(tun: Tuning, kind: Types.BurpKind): number
	if kind == "pops" then
		return tun.popsDuration
	elseif kind == "ashStorm" then
		return tun.stormDuration
	elseif kind == "golden" then
		return tun.goldenDuration
	end
	return tun.geyserDuration
end

local function chooseKind(self: BurpDirector): Types.BurpKind
	local weights: { number } = {}
	local total = 0
	for k, kind in KINDS do
		local w = (self.tun.kindWeights :: any)[kind] or 0
		if kind == self.lastKind then
			w *= self.tun.repeatPenalty
		end
		weights[k] = w
		total += w
	end
	if total <= 0 then
		return "pops"
	end
	local r = self.rng:next() * total
	for k, w in weights do
		r -= w
		if r < 0 then
			return KINDS[k]
		end
	end
	return KINDS[#KINDS]
end

-- Random point in a zone's ring (uniform by area), kept off the ring edges.
local function ringPoint(self: BurpDirector, zoneId: number): (number?, number?)
	local inner, outer = zoneRing(zoneId)
	if inner == nil or outer == nil then
		return nil, nil
	end
	local lo, hi = inner + 3, outer - 3
	local r = math.sqrt(self.rng:range(lo * lo, hi * hi))
	local a = self.rng:range(0, TWO_PI)
	return r * math.cos(a), r * math.sin(a)
end

local function nearHub(self: BurpDirector, x: number, z: number): boolean
	local safe = Config.World.hub.clearRadius + self.tun.hubSafeMargin
	local dx, dz = x - self.hubX, z - self.hubZ
	return dx * dx + dz * dz <= safe * safe
end

-- Keep a point on the island (between the lava heart edge and the beach edge).
local function clampToIsland(self: BurpDirector, x: number, z: number): (number, number)
	local r = math.sqrt(x * x + z * z)
	if r < 1e-6 then
		return self.innerR + 1, 0
	end
	local target = math.clamp(r, self.innerR + 1, self.outerR - 2)
	if target == r then
		return x, z
	end
	return x * target / r, z * target / r
end

-- A spot near a random occupied zone's player or a random point in an occupied zone ring.
local function aimBomb(self: BurpDirector, players: { PlayerPos }): (number?, number?)
	for _ = 1, 6 do
		local rx, rz
		if self.rng:chance(self.tun.decoyFraction) then
			rx, rz = ringPoint(self, self.rng:pick(players).zone)
		end
		local x: number, z: number
		if rx ~= nil and rz ~= nil then
			x, z = rx, rz
		else
			local p = self.rng:pick(players)
			local a = self.rng:range(0, TWO_PI)
			local off = self.rng:range(0, self.tun.aimOffsetMax)
			x, z = p.x + math.cos(a) * off, p.z + math.sin(a) * off
		end
		x, z = clampToIsland(self, x, z)
		if not nearHub(self, x, z) then
			return x, z
		end
	end
	return nil, nil
end

local function playersFor(ctx: Ctx): number
	return math.max(ctx.playerCount, #ctx.playerPositions)
end

local function spawnWave(self: BurpDirector, t: number, now: number, ctx: Ctx): { Bomb }
	local out: { Bomb } = {}
	local players = ctx.playerPositions
	if #players == 0 then
		return out
	end
	local tun = self.tun
	local want = tun.bombsPerWaveBase + math.floor(playersFor(ctx) / tun.playersPerExtraBomb)
	want = math.min(want, tun.bombsPerWaveMax)
	want = math.min(want, tun.maxActiveBombs - (#self.pending - self.pendHead + 1))
	for _ = 1, want do
		local x, z = aimBomb(self, players)
		if x ~= nil and z ~= nil then
			self.nextId += 1
			local bomb: Bomb = {
				id = self.nextId,
				x = x,
				z = z,
				radius = tun.bombRadius,
				landsAt = math.max(t + tun.telegraph, now + tun.minTelegraph),
			}
			table.insert(self.pending, bomb)
			self.lastLandsAt = bomb.landsAt
			table.insert(out, bomb)
		end
	end
	return out
end

local function geyserSpots(self: BurpDirector, ctx: Ctx): { Spot }
	local tun = self.tun
	local count = tun.geyserSpotsBase + math.floor(playersFor(ctx) / tun.geyserPlayersPerExtraSpot)
	count = math.min(count, tun.geyserSpotsMax)
	local zones: { number } = {}
	for _, p in ctx.playerPositions do
		if (zoneRing(p.zone)) ~= nil then
			table.insert(zones, p.zone)
		end
	end
	if #zones == 0 then
		for _, z in Config.World.zones do
			table.insert(zones, z.id)
		end
	end
	local spots: { Spot } = {}
	for _ = 1, count do
		for _ = 1, 6 do
			local x, z = ringPoint(self, self.rng:pick(zones))
			if x ~= nil and z ~= nil and not nearHub(self, x, z) then
				table.insert(spots, { x = x, z = z })
				break
			end
		end
	end
	return spots
end

local function gapFor(self: BurpDirector, clean: number): number
	local tun = self.tun
	local gap = tun.gapMax - (tun.gapMax - tun.gapMin) * clamp01(clean)
	return gap * (1 + self.rng:range(-tun.gapJitter, tun.gapJitter))
end

local function emitPhase(events: { BurpEvent }, self: BurpDirector)
	table.insert(events, {
		kind = "phase",
		phase = self.phase,
		burpKind = self.burpKind,
		startsAt = self.phaseStart,
		endsAt = self.phaseEnd,
	})
end

local function sleep(self: BurpDirector, now: number, events: { BurpEvent })
	if not self.awake then
		return
	end
	self.awake = false
	self.pending = {}
	self.pendHead = 1
	self.pulseAt = nil
	local wasBusy = self.phase ~= "calm"
	self.phase = "calm"
	self.burpKind = nil
	self.phaseStart = now
	self.phaseEnd = now
	self.lastRumbleStart = nil
	if wasBusy then
		emitPhase(events, self)
	end
end

local function wake(self: BurpDirector, now: number, events: { BurpEvent })
	self.awake = true
	self.phase = "calm"
	self.burpKind = nil
	self.phaseStart = now
	self.phaseEnd = now + self.tun.firstBurpDelay + self.rng:range(0, self.tun.firstBurpJitter)
	self.lastRumbleStart = nil
	emitPhase(events, self)
end

-- When does the current phase want to end? The event phase waits for its last bomb to land.
local function phaseDueAt(self: BurpDirector): number
	if self.phase == "event" and self.lastLandsAt ~= nil then
		return math.max(self.phaseEnd, self.lastLandsAt + self.tun.perfectGrace)
	end
	return self.phaseEnd
end

local methods = {}

function methods.step(self: BurpDirector, now: number, ctx: Ctx): { BurpEvent }
	local events: { BurpEvent } = {}
	local tun = self.tun
	if ctx.playerCount <= 0 and #ctx.playerPositions == 0 then
		sleep(self, now, events)
		return events
	end
	if not self.awake then
		wake(self, now, events)
	end

	for _ = 1, 4000 do
		-- pick the earliest due thing; land beats pulse beats phase change when times tie
		local bestT = math.huge
		local what = ""
		local head = self.pending[self.pendHead]
		if head ~= nil and head.landsAt <= now then
			bestT, what = head.landsAt, "land"
		end
		local pulse = self.pulseAt
		if pulse ~= nil and pulse <= now and pulse < bestT then
			bestT, what = pulse, "pulse"
		end
		local due = phaseDueAt(self)
		if due <= now and due < bestT then
			bestT, what = due, "phase"
		end
		if what == "" then
			break
		end

		if what == "land" then
			local bomb = head :: Bomb
			self.pendHead += 1
			if self.pendHead > 32 then
				self.pending = table.move(self.pending, self.pendHead, #self.pending, 1, {})
				self.pendHead = 1
			end
			self.landed += 1
			table.insert(events, { kind = "land", bombId = bomb.id })
		elseif what == "pulse" then
			local kind = self.burpKind
			self.pulseAt = nil
			if kind == "pops" then
				-- a wave the server was too late to show (it would already have landed) is skipped
				local bombs = if bestT >= now - tun.telegraph
					then spawnWave(self, bestT, now, ctx)
					else {}
				if #bombs > 0 then
					table.insert(events, { kind = "bombs", bombs = bombs })
				end
				local nextAt = bestT
					+ tun.bombEvery
					+ self.rng:range(-tun.bombEveryJitter, tun.bombEveryJitter)
				if nextAt <= self.spawnUntil then
					self.pulseAt = nextAt
				end
			elseif kind == "ashStorm" then
				table.insert(events, { kind = "rain", fraction = tun.stormFraction })
				local nextAt = bestT + tun.stormPulseEvery
				if nextAt < self.phaseEnd then
					self.pulseAt = nextAt
				end
			elseif kind == "golden" then
				local cells = math.min(
					tun.goldenMaxCells,
					tun.goldenBaseCells + tun.goldenPerPlayer * playersFor(ctx)
				)
				table.insert(events, { kind = "golden", cells = cells, untilAt = self.phaseEnd })
			elseif kind == "geysers" then
				table.insert(events, { kind = "geysers", spots = geyserSpots(self, ctx) })
				local nextAt = bestT + tun.geyserWaveEvery
				if nextAt < self.phaseEnd then
					self.pulseAt = nextAt
				end
			end
		else
			-- phase change at time bestT
			if self.phase == "calm" then
				local kind = chooseKind(self)
				self.burpKind = kind
				self.phase = "rumble"
				self.phaseStart = bestT
				self.phaseEnd = bestT + tun.rumble
				self.lastRumbleStart = bestT
				self.hit = false
				self.landed = 0
				self.lastLandsAt = nil
			elseif self.phase == "rumble" then
				local kind = self.burpKind :: Types.BurpKind
				self.phase = "event"
				self.phaseStart = bestT
				self.phaseEnd = bestT + kindDuration(tun, kind)
				self.pulseAt = bestT
				self.spawnUntil = self.phaseEnd - tun.telegraph - tun.perfectGrace
			elseif self.phase == "event" then
				local kind = self.burpKind :: Types.BurpKind
				self.phase = "recover"
				self.phaseStart = bestT
				self.phaseEnd = bestT + tun.recover
				self.pulseAt = nil
				self.lastKind = kind
				emitPhase(events, self)
				if tun.perfectKinds[kind] and not self.hit and self.landed > 0 then
					table.insert(
						events,
						{ kind = "perfect", untilAt = bestT + tun.perfectBuffSeconds }
					)
				end
				continue
			else
				-- recover over: calm until the next gap is used up
				local last = self.lastRumbleStart or bestT
				local nextAt = math.max(bestT + tun.minCalm, last + gapFor(self, ctx.cleanTotal))
				self.phase = "calm"
				self.burpKind = nil
				self.phaseStart = bestT
				self.phaseEnd = nextAt
			end
			emitPhase(events, self)
		end
	end
	return events
end

function methods.reportHit(self: BurpDirector, _userId: number, _now: number)
	if self.awake and self.phase ~= "calm" then
		self.hit = true
	end
end

function methods.hitTest(self: BurpDirector, bomb: Bomb, x: number, z: number): boolean
	local reach = bomb.radius + self.tun.bodyRadius
	local dx, dz = x - bomb.x, z - bomb.z
	return dx * dx + dz * dz <= reach * reach
end

function methods.getState(self: BurpDirector): State
	return {
		phase = self.phase,
		burpKind = self.burpKind,
		startsAt = self.phaseStart,
		endsAt = self.phaseEnd,
		awake = self.awake,
	}
end

function methods.activeBombs(self: BurpDirector): { Bomb }
	local out: { Bomb } = {}
	for k = self.pendHead, #self.pending do
		table.insert(out, self.pending[k])
	end
	return out
end

-- `overrides` replaces any BurpTuning number (tests use it). kindWeights merges key by key.
function BurpDirector.new(rng: Rng, overrides: { [string]: any }?): BurpDirector
	local tun: any = table.clone(BurpTuning)
	tun.kindWeights = table.clone(BurpTuning.kindWeights)
	tun.perfectKinds = table.clone(BurpTuning.perfectKinds)
	if overrides then
		for k, v in overrides do
			if type(v) == "table" and type(tun[k]) == "table" then
				for k2, v2 in v do
					tun[k][k2] = v2
				end
			else
				tun[k] = v
			end
		end
	end
	local hub = Config.World.hub
	local a = math.rad(hub.angleDeg)
	local innerR, outerR = math.huge, 0
	for _, z in Config.World.zones do
		innerR = math.min(innerR, z.inner)
		outerR = math.max(outerR, z.outer)
	end
	local self = {
		rng = rng,
		tun = tun :: Tuning,
		awake = false,
		phase = "calm" :: Types.BurpPhase,
		burpKind = nil,
		lastKind = nil,
		phaseStart = 0,
		phaseEnd = 0,
		lastRumbleStart = nil,
		pulseAt = nil,
		spawnUntil = 0,
		nextId = 0,
		pending = {},
		pendHead = 1,
		hit = false,
		landed = 0,
		lastLandsAt = nil,
		hubX = hub.radius * math.cos(a),
		hubZ = hub.radius * math.sin(a),
		innerR = innerR,
		outerR = outerR,
	}
	return setmetatable(self, { __index = methods }) :: any
end

return BurpDirector
