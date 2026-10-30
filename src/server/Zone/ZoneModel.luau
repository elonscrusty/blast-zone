--!strict
-- Shrinking safe zone rules (brief §15). Pure Luau (no Roblox services) so Lune can test it.
-- All numbers come from Config.Zone: this file has none of its own. The server owns the zone;
-- clients get a ZoneState message at every change and draw from that.

local ZoneModel = {}

export type ParticipantId = string

export type StageConfig = {
	warnAt: number,
	closeAt: number,
	closeSeconds: number,
	targetRadius: number,
	damagePerSecond: number,
}

export type SuddenDeathConfig = {
	startsAt: number,
	closeSeconds: number,
	targetRadius: number,
	damagePerSecond: number,
}

export type Config = {
	centerX: number,
	centerZ: number,
	initialRadius: number,
	tickSeconds: number,
	edgeTolerance: number,
	stages: { StageConfig },
	suddenDeath: SuddenDeathConfig,
}

-- Stage number sent to clients while sudden death is closing (same as Types.ZoneState.stage).
ZoneModel.SUDDEN_DEATH_STAGE = 99

export type Segment = {
	index: number,
	stage: number,
	warnAt: number, -- same as closeAt when there is no warning (sudden death)
	closeAt: number,
	endAt: number,
	fromRadius: number,
	toRadius: number,
	damagePerSecond: number,
	previousDamagePerSecond: number,
}

export type Timeline = {
	config: Config,
	segments: { Segment },
	finalPressureAt: number,
}

export type Phase = "Holding" | "Warning" | "Closing"

export type Sample = {
	phase: Phase,
	segment: number, -- index into Timeline.segments, 0 before the first warning
	stage: number, -- 0 before the first warning, 99 for sudden death
	centerX: number,
	centerZ: number,
	radius: number,
	fromRadius: number,
	toRadius: number,
	startedAt: number, -- when this circle began (or will begin) closing, seconds after Active
	endsAt: number, -- when it stops closing
	warningEndsAt: number?, -- set only during a warning
	outsideDamagePerSecond: number,
	secondsToNext: number, -- to the next warning, closing start or closing end
	finalPressure: boolean,
	suddenDeath: boolean,
	elapsed: number,
}

local function check(ok: boolean, message: string)
	if not ok then
		error("Config.Zone: " .. message, 3)
	end
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Checks the config and returns the timeline (absolute times, seconds after Active starts).
function ZoneModel.build(config: Config): Timeline
	check(finite(config.centerX) and finite(config.centerZ), "centerX and centerZ must be numbers")
	check(
		finite(config.initialRadius) and config.initialRadius > 0,
		"initialRadius must be above 0"
	)
	check(finite(config.tickSeconds) and config.tickSeconds > 0, "tickSeconds must be above 0")
	check(
		finite(config.edgeTolerance) and config.edgeTolerance >= 0,
		"edgeTolerance must be 0 or more"
	)
	check(#config.stages >= 1, "needs at least one stage")

	local segments: { Segment } = {}
	local radius = config.initialRadius
	local dps = 0
	local clock = 0
	for i, s in config.stages do
		check(
			finite(s.warnAt) and finite(s.closeAt) and finite(s.closeSeconds),
			`stage {i} times must be numbers`
		)
		check(s.warnAt >= clock, `stage {i} warns before the last one has finished closing`)
		check(s.closeAt > s.warnAt, `stage {i} must warn before it closes`)
		check(s.closeSeconds > 0, `stage {i} closeSeconds must be above 0`)
		check(
			finite(s.targetRadius) and s.targetRadius > 0 and s.targetRadius < radius,
			`stage {i} must shrink the circle`
		)
		check(
			finite(s.damagePerSecond) and s.damagePerSecond >= 0,
			`stage {i} damagePerSecond must be 0 or more`
		)
		table.insert(segments, {
			index = i,
			stage = i,
			warnAt = s.warnAt,
			closeAt = s.closeAt,
			endAt = s.closeAt + s.closeSeconds,
			fromRadius = radius,
			toRadius = s.targetRadius,
			damagePerSecond = s.damagePerSecond,
			previousDamagePerSecond = dps,
		})
		clock = s.closeAt + s.closeSeconds
		radius = s.targetRadius
		dps = s.damagePerSecond
	end

	local sd = config.suddenDeath
	check(
		finite(sd.startsAt) and sd.startsAt >= clock,
		"sudden death must start after the last stage has closed"
	)
	check(
		finite(sd.closeSeconds) and sd.closeSeconds > 0,
		"suddenDeath.closeSeconds must be above 0"
	)
	check(
		finite(sd.targetRadius) and sd.targetRadius > 0 and sd.targetRadius < radius,
		"sudden death must shrink the circle"
	)
	check(
		finite(sd.damagePerSecond) and sd.damagePerSecond >= dps,
		"sudden death must hurt at least as much as the last stage"
	)
	table.insert(segments, {
		index = #segments + 1,
		stage = ZoneModel.SUDDEN_DEATH_STAGE,
		warnAt = sd.startsAt,
		closeAt = sd.startsAt,
		endAt = sd.startsAt + sd.closeSeconds,
		fromRadius = radius,
		toRadius = sd.targetRadius,
		damagePerSecond = sd.damagePerSecond,
		previousDamagePerSecond = dps,
	})

	return {
		config = config,
		segments = segments,
		finalPressureAt = segments[#config.stages].warnAt,
	}
end

-- The circle `t` seconds after Active started.
function ZoneModel.sample(timeline: Timeline, t: number): Sample
	local config = timeline.config
	local elapsed = math.max(t, 0)
	local segments = timeline.segments

	local function make(
		phase: Phase,
		seg: number,
		stage: number,
		radius: number,
		from: number,
		to: number,
		startedAt: number,
		endsAt: number,
		warningEndsAt: number?,
		dps: number,
		nextAt: number
	): Sample
		return {
			phase = phase,
			segment = seg,
			stage = stage,
			centerX = config.centerX,
			centerZ = config.centerZ,
			radius = radius,
			fromRadius = from,
			toRadius = to,
			startedAt = startedAt,
			endsAt = endsAt,
			warningEndsAt = warningEndsAt,
			outsideDamagePerSecond = dps,
			secondsToNext = math.max(nextAt - elapsed, 0),
			finalPressure = elapsed >= timeline.finalPressureAt,
			suddenDeath = stage == ZoneModel.SUDDEN_DEATH_STAGE,
			elapsed = elapsed,
		}
	end

	local prevStage, prevSeg = 0, 0
	local prevRadius = config.initialRadius
	local prevDps = 0
	local prevEnd = 0
	for _, seg in segments do
		if elapsed < seg.warnAt then
			return make(
				"Holding",
				prevSeg,
				prevStage,
				prevRadius,
				prevRadius,
				prevRadius,
				prevEnd,
				prevEnd,
				nil,
				prevDps,
				seg.warnAt
			)
		elseif elapsed < seg.closeAt then
			return make(
				"Warning",
				seg.index,
				seg.stage,
				seg.fromRadius,
				seg.fromRadius,
				seg.toRadius,
				seg.closeAt,
				seg.endAt,
				seg.closeAt,
				seg.previousDamagePerSecond,
				seg.closeAt
			)
		elseif elapsed < seg.endAt then
			local k = (elapsed - seg.closeAt) / (seg.endAt - seg.closeAt)
			local radius = seg.fromRadius + (seg.toRadius - seg.fromRadius) * k
			return make(
				"Closing",
				seg.index,
				seg.stage,
				radius,
				seg.fromRadius,
				seg.toRadius,
				seg.closeAt,
				seg.endAt,
				nil,
				seg.damagePerSecond,
				seg.endAt
			)
		end
		prevStage, prevSeg = seg.stage, seg.index
		prevRadius, prevDps, prevEnd = seg.toRadius, seg.damagePerSecond, seg.endAt
	end
	return make(
		"Holding",
		prevSeg,
		prevStage,
		prevRadius,
		prevRadius,
		prevRadius,
		prevEnd,
		prevEnd,
		nil,
		prevDps,
		prevEnd
	)
end

-- True when the point is on the safe side. Exactly on the line is safe, and `edgeTolerance`
-- studs past it are safe too (it covers lag between the server position and the screen).
-- A NaN position is never safe.
function ZoneModel.isInside(sample: Sample, x: number, z: number, tolerance: number): boolean
	local dx = x - sample.centerX
	local dz = z - sample.centerZ
	local limit = sample.radius + tolerance
	return dx * dx + dz * dz <= limit * limit
end

-- For bots: the nearest spot inside the circle, `margin` studs in from the line. Returns the
-- point itself when it is already inside.
function ZoneModel.nearestSafePoint(
	sample: Sample,
	x: number,
	z: number,
	margin: number
): (number, number)
	local dx = x - sample.centerX
	local dz = z - sample.centerZ
	local limit = math.max(sample.radius - margin, 0)
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist <= limit or dist == 0 then
		return x, z
	end
	local k = limit / dist
	return sample.centerX + dx * k, sample.centerZ + dz * k
end

-- ---------------------------------------------------------------------------------------------
-- Runner: the loop that hands out damage and events. Everything outside is passed in.
-- ---------------------------------------------------------------------------------------------

export type Target = { id: ParticipantId, x: number, z: number }

export type EventKind =
	"WarningStarted"
	| "ClosingStarted"
	| "ClosingEnded"
	| "FinalPressure"
	| "SuddenDeath"

export type Event = {
	kind: EventKind,
	matchId: number,
	stage: number,
	elapsed: number,
}

-- Same fields as Types.ZoneState.
export type StatePayload = {
	matchId: number,
	centerX: number,
	centerZ: number,
	fromRadius: number,
	toRadius: number,
	startedAt: number,
	endsAt: number,
	warningEndsAt: number?,
	damagePerSecond: number,
	stage: number,
}

export type Deps = {
	config: Config,
	now: () -> number, -- server time (workspace:GetServerTimeNow)
	-- Living participants and where they stand (ground plane).
	getTargets: () -> { Target },
	-- Piece 01 Damage:apply with cause = "zone". The runner never touches health itself.
	applyDamage: (id: ParticipantId, amount: number, stage: number) -> (),
	-- Sends a ZoneState to every client.
	publish: (state: StatePayload) -> (),
	onEvent: ((event: Event) -> ())?,
}

type RunnerFields = {
	deps: Deps,
	timeline: Timeline,
	running: boolean,
	matchId: number,
	startTime: number,
	nextTickAt: number,
	lastKey: number,
	finalAnnounced: boolean,
}

local Runner = {}
Runner.__index = Runner

export type Runner = typeof(setmetatable({} :: RunnerFields, Runner))

function ZoneModel.newRunner(deps: Deps): Runner
	local self: RunnerFields = {
		deps = deps,
		timeline = ZoneModel.build(deps.config),
		running = false,
		matchId = 0,
		startTime = 0,
		nextTickAt = 0,
		lastKey = 0,
		finalAnnounced = false,
	}
	return setmetatable(self, Runner)
end

-- What clients need to draw `sample` (times turned into server time).
function ZoneModel.toState(sample: Sample, matchId: number, startTime: number): StatePayload
	return {
		matchId = matchId,
		centerX = sample.centerX,
		centerZ = sample.centerZ,
		fromRadius = sample.fromRadius,
		toRadius = sample.toRadius,
		startedAt = startTime + sample.startedAt,
		endsAt = startTime + sample.endsAt,
		warningEndsAt = if sample.warningEndsAt then startTime + sample.warningEndsAt else nil,
		damagePerSecond = sample.outsideDamagePerSecond,
		stage = sample.stage,
	}
end

local function elapsedNow(self: Runner): number
	return math.max(self.deps.now() - self.startTime, 0)
end

local function emit(self: Runner, kind: EventKind, sample: Sample)
	local onEvent = self.deps.onEvent
	if onEvent then
		onEvent({
			kind = kind,
			matchId = self.matchId,
			stage = sample.stage,
			elapsed = sample.elapsed,
		})
	end
end

local function publish(self: Runner, sample: Sample)
	self.deps.publish(ZoneModel.toState(sample, self.matchId, self.startTime))
end

-- Begins the zone for a match. Call when the match turns Active (the clock starts here).
-- Starting again replaces the old zone: nothing carries over between matches.
function Runner.start(self: Runner, matchId: number)
	self.running = true
	self.matchId = matchId
	self.startTime = self.deps.now()
	self.nextTickAt = self.deps.config.tickSeconds
	self.lastKey = 0
	self.finalAnnounced = false
	publish(self, ZoneModel.sample(self.timeline, 0))
end

-- Ends the zone. After this nothing is damaged. (Clients hide the ring from the match phase.)
function Runner.stop(self: Runner)
	self.running = false
end

function Runner.isRunning(self: Runner): boolean
	return self.running
end

function Runner.getSample(self: Runner): Sample?
	if not self.running then
		return nil
	end
	return ZoneModel.sample(self.timeline, elapsedNow(self))
end

-- The message for the circle right now, for a client that joins or asks again.
function Runner.getState(self: Runner): StatePayload?
	local sample = self:getSample()
	if sample == nil then
		return nil
	end
	return ZoneModel.toState(sample, self.matchId, self.startTime)
end

local function announce(self: Runner, sample: Sample)
	if sample.finalPressure and not self.finalAnnounced then
		self.finalAnnounced = true
		emit(self, "FinalPressure", sample)
	end
	if sample.segment == 0 then
		return
	end
	local key
	if sample.phase == "Warning" then
		key = sample.segment * 10 + 1
	elseif sample.phase == "Closing" then
		key = sample.segment * 10 + 2
	else
		key = sample.segment * 10 + 3
	end
	if key <= self.lastKey then
		return
	end
	self.lastKey = key
	if sample.phase == "Warning" then
		emit(self, "WarningStarted", sample)
		publish(self, sample)
	elseif sample.phase == "Closing" then
		if sample.suddenDeath then
			emit(self, "SuddenDeath", sample)
		else
			emit(self, "ClosingStarted", sample)
		end
		publish(self, sample)
	else
		emit(self, "ClosingEnded", sample)
	end
end

local function damageTick(self: Runner, sample: Sample)
	local config = self.deps.config
	local amount = sample.outsideDamagePerSecond * config.tickSeconds
	if amount <= 0 then
		return
	end
	for _, target in self.deps.getTargets() do
		if not ZoneModel.isInside(sample, target.x, target.z, config.edgeTolerance) then
			self.deps.applyDamage(target.id, amount, sample.stage)
		end
	end
end

-- Call often (about every 0.1 s). Hands out events, ZoneState messages and damage. After a long
-- server hitch it does not pay out the damage ticks it missed.
function Runner.step(self: Runner)
	if not self.running then
		return
	end
	local t = elapsedNow(self)
	local sample = ZoneModel.sample(self.timeline, t)
	announce(self, sample)
	if t >= self.nextTickAt then
		self.nextTickAt = t + self.deps.config.tickSeconds
		damageTick(self, sample)
	end
end

return ZoneModel
