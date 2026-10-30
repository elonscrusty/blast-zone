--!strict
-- The bot's thinking, with no Roblox calls so Lune can test it. Each think gets a plain snapshot of
-- what the bot may know and returns what a player's controls would do: move, aim, fire, reload,
-- slide. The server then applies that through the same code paths players use, so bots follow the
-- same health, ammo, fire-rate and slide rules. Walls are respected because the bot only notices
-- someone when the snapshot's canSee says a shot could reach them.

local BotGuns = require("./BotGuns")
local BotTuning = require("./BotTuning")

type Tuning = BotTuning.Tuning

export type Vec2 = { x: number, z: number }
export type Body = { id: string, pos: Vec2, shielded: boolean? } -- shielded: spawn shield, not worth shooting
export type Pickup = { id: string, pos: Vec2 }
export type Zone = { center: Vec2, radius: number, shrinking: boolean? }
export type GunDrop = { id: string, gunId: string, pos: Vec2 } -- a found gun lying on the ground
export type Self = {
	id: string,
	pos: Vec2,
	health: number,
	maxHealth: number,
	ammo: number,
	magazine: number,
	reloading: boolean,
	canFire: boolean, -- the server would accept a shot right now
	slideReady: boolean,
	gunId: string?, -- the gun in hand (nil = the pistol)
}
export type View = {
	now: number,
	me: Self,
	others: { Body }, -- every other living participant; the brain filters by sight
	pickups: { Pickup },
	gunDrops: { GunDrop }?,
	zone: Zone?,
	range: number, -- weapon range
	canSee: (Vec2, Vec2) -> boolean,
	rand: () -> number, -- [0, 1)
	tuning: Tuning,
}
export type State = {
	targetId: string?,
	seenAt: number,
	lastSeen: number,
	lastKnown: Vec2?,
	strafeSign: number,
	strafeUntil: number,
	goal: Vec2?,
	goalUntil: number,
	lastPos: Vec2?,
	lastCheck: number,
	sideUntil: number,
	sideSign: number,
	lastMove: Vec2,
	aim: Vec2,
	cover: Vec2?, -- the spot it is ducking behind
	coverUntil: number,
	coverRetryAt: number, -- no new cover search before this
	zoneRun: boolean, -- heading back into the zone (stays on until well inside)
}
export type Intent = {
	moveX: number,
	moveZ: number,
	aimX: number,
	aimZ: number,
	fire: boolean,
	reload: boolean,
	slide: boolean,
	mode: string,
	grabGunId: string?, -- a found gun close enough to swap for: the drop's id
}

local BotBrain = {}

function BotBrain.newState(): State
	return {
		targetId = nil,
		seenAt = 0,
		lastSeen = -1e9,
		lastKnown = nil,
		strafeSign = 1,
		strafeUntil = 0,
		goal = nil,
		goalUntil = 0,
		lastPos = nil,
		lastCheck = 0,
		sideUntil = 0,
		sideSign = 1,
		lastMove = { x = 0, z = 0 },
		aim = { x = 0, z = 1 },
		cover = nil,
		coverUntil = 0,
		coverRetryAt = 0,
		zoneRun = false,
	}
end

local function dist(a: Vec2, b: Vec2): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

local function unit(x: number, z: number): Vec2
	local len = math.sqrt(x * x + z * z)
	if len < 1e-6 then
		return { x = 0, z = 0 }
	end
	return { x = x / len, z = z / len }
end

local function rotate(v: Vec2, radians: number): Vec2
	local c, s = math.cos(radians), math.sin(radians)
	return { x = v.x * c - v.z * s, z = v.x * s + v.z * c }
end

local function toward(from: Vec2, to: Vec2): Vec2
	return unit(to.x - from.x, to.z - from.z)
end

local function between(rand: () -> number, lo: number, hi: number): number
	return lo + (hi - lo) * rand()
end

-- Nearest living participant that is close enough and in the clear. Keeps the old target while it
-- is still visible so the bot does not flip between two enemies.
local function findTarget(view: View, state: State): Body?
	local best: Body? = nil
	local bestDist = math.huge
	local sticky: Body? = nil
	for _, other in view.others do
		local d = dist(view.me.pos, other.pos)
		if
			not other.shielded
			and d <= view.tuning.sightRange
			and view.canSee(view.me.pos, other.pos)
		then
			if other.id == state.targetId then
				sticky = other
			end
			if d < bestDist then
				best, bestDist = other, d
			end
		end
	end
	return sticky or best
end

-- True when `pos` is inside the safe circle with room to spare (no zone = everywhere).
local function insideZone(view: View, pos: Vec2): boolean
	local zone = view.zone
	return zone == nil or dist(pos, zone.center) <= zone.radius - view.tuning.zoneMargin
end

local function nearestPickup(view: View): Pickup?
	local best: Pickup? = nil
	local bestDist = view.tuning.pickupRange
	for _, p in view.pickups do
		local d = dist(view.me.pos, p.pos)
		if d <= bestDist and insideZone(view, p.pos) and view.canSee(view.me.pos, p.pos) then
			best, bestDist = p, d
		end
	end
	return best
end

-- The nearest found gun worth swapping for: an upgrade, in the zone, close, in a clear line.
local function nearestWantedGun(view: View): GunDrop?
	local drops = view.gunDrops
	if not drops or not view.tuning.seekGuns then
		return nil
	end
	local best: GunDrop? = nil
	local bestDist = view.tuning.gunSeekRange
	for _, drop in drops do
		local d = dist(view.me.pos, drop.pos)
		if
			d <= bestDist
			and BotGuns.wants(view.me.gunId, drop.gunId)
			and insideZone(view, drop.pos)
			and view.canSee(view.me.pos, drop.pos)
		then
			best, bestDist = drop, d
		end
	end
	return best
end

-- A spot close by that the threat cannot see, so the bot can reload or catch its breath there. It
-- looks in a ring around itself, nearest ring first, and prefers the spot farthest from the threat.
-- Costs a few ray checks, so the caller only asks once in a while.
local COVER_DIRECTIONS = 8
local function findCover(view: View, threat: Vec2): Vec2?
	local me = view.me.pos
	for ring = 1, 2 do
		local reach = view.tuning.coverProbe * ring
		local best: Vec2? = nil
		local bestFar = -1
		for i = 0, COVER_DIRECTIONS - 1 do
			local angle = i / COVER_DIRECTIONS * math.pi * 2
			local spot = { x = me.x + math.cos(angle) * reach, z = me.z + math.sin(angle) * reach }
			if
				insideZone(view, spot)
				and view.canSee(me, spot) -- the walk there is open
				and not view.canSee(threat, spot) -- the threat cannot see it
			then
				local far = dist(spot, threat)
				if far > bestFar then
					best, bestFar = spot, far
				end
			end
		end
		if best then
			return best
		end
	end
	return nil
end

local function newGoal(view: View): Vec2
	local zone = view.zone
	if zone then
		local angle = view.rand() * math.pi * 2
		local r = zone.radius * 0.8 * math.sqrt(view.rand())
		return { x = zone.center.x + math.cos(angle) * r, z = zone.center.z + math.sin(angle) * r }
	end
	local angle = view.rand() * math.pi * 2
	return {
		x = view.me.pos.x + math.cos(angle) * view.tuning.roamDistance,
		z = view.me.pos.z + math.sin(angle) * view.tuning.roamDistance,
	}
end

-- Walks toward the roam goal; picks a new one when it arrives, runs out of time, or is stuck.
local function roam(view: View, state: State): Vec2
	local goal = state.goal
	if
		not goal
		or view.now >= state.goalUntil
		or dist(view.me.pos, goal) < view.tuning.goalReached
	then
		goal = newGoal(view)
		state.goal = goal
		state.goalUntil = view.now + view.tuning.goalTime
	end
	return toward(view.me.pos, goal)
end

-- If the bot barely moved while it wanted to, it hit something: drop the goal and sidestep.
local function checkStuck(view: View, state: State)
	local last = state.lastPos
	if not last then
		state.lastPos = { x = view.me.pos.x, z = view.me.pos.z }
		state.lastCheck = view.now
		return
	end
	if view.now - state.lastCheck < view.tuning.stuckCheck then
		return
	end
	local wantedToMove = state.lastMove.x ~= 0 or state.lastMove.z ~= 0
	if wantedToMove and dist(view.me.pos, last) < view.tuning.stuckDistance then
		state.goal = nil
		state.strafeSign = -state.strafeSign
		state.sideSign = if view.rand() < 0.5 then 1 else -1
		state.sideUntil = view.now + view.tuning.sidestepTime
	end
	state.lastPos = { x = view.me.pos.x, z = view.me.pos.z }
	state.lastCheck = view.now
end

-- Heads back into the zone stay on until the bot is this far inside the margin, so it does not
-- jitter on the edge.
local ZONE_RUN_EXTRA = 6

function BotBrain.think(view: View, state: State): Intent
	local me = view.me
	local now = view.now
	local tuning = view.tuning
	checkStuck(view, state)

	local target = findTarget(view, state)
	if target then
		if target.id ~= state.targetId then
			state.targetId = target.id
			state.seenAt = now
		end
		state.lastSeen = now
		state.lastKnown = { x = target.pos.x, z = target.pos.z }
	elseif now - state.lastSeen > tuning.memoryTime then
		state.targetId = nil
		state.lastKnown = nil
	end

	-- The zone wall. A closing zone and a sharper tier both make the bot leave earlier.
	local zone = view.zone
	local outsideBy = 0 -- studs past the edge of the safe circle (negative = inside)
	local outside = false
	if zone then
		local margin = tuning.zoneMargin
			+ tuning.zoneExtra
			+ (if zone.shrinking then tuning.zoneLookahead else 0)
		local fromCenter = dist(me.pos, zone.center)
		outsideBy = fromCenter - zone.radius
		if fromCenter > zone.radius - margin then
			state.zoneRun = true
		elseif fromCenter < zone.radius - margin - ZONE_RUN_EXTRA then
			state.zoneRun = false
		end
		outside = state.zoneRun
	else
		state.zoneRun = false
	end

	local move: Vec2 = { x = 0, z = 0 }
	local mode = "roam"
	local fire = false
	local reload = false
	local slide = false
	local aim: Vec2 = state.aim

	local lowHealth = me.health <= me.maxHealth * tuning.fleeAtFraction

	-- Cover: reload, or catch a breath, behind something the threat cannot see through.
	local needCover = tuning.coverSkill > 0 and (me.reloading or me.ammo <= 0 or lowHealth)
	if state.cover and not needCover then
		state.cover = nil -- done reloading: step back out
	elseif state.cover and now >= state.coverUntil then
		state.cover = nil
		state.coverRetryAt = now + tuning.coverRetry
	end
	local threat: Vec2? = if target then target.pos else state.lastKnown
	if
		needCover
		and not outside
		and state.cover == nil
		and threat
		and now >= state.coverRetryAt
	then
		-- Rolled once per try; a bot that says no waits before it thinks about it again.
		state.coverRetryAt = now + tuning.coverRetry
		if view.rand() < tuning.coverSkill then
			local spot = findCover(view, threat)
			if spot then
				state.cover = spot
				state.coverUntil = now + tuning.coverHold
			end
		end
	end
	local cover = state.cover
	local atCover = cover ~= nil and dist(me.pos, cover) <= tuning.coverReached

	-- A found gun that is an upgrade. Asking for the swap is a separate, tiny move.
	local gun = nearestWantedGun(view)
	local grabGunId: string? = nil
	if gun and dist(me.pos, gun.pos) <= tuning.gunGrabRange then
		grabGunId = gun.id
	end

	if target then
		local toTarget = toward(me.pos, target.pos)
		local d = dist(me.pos, target.pos)
		aim = toTarget
		mode = "fight"
		if now >= state.strafeUntil then
			state.strafeSign = if view.rand() < 0.5 then 1 else -1
			state.strafeUntil = now + between(view.rand, tuning.strafeMin, tuning.strafeMax)
		end
		-- Each gun has its own habits: the shotgun rushes in, the long rifle keeps away.
		local profile = BotGuns.profile(me.gunId)
		local ideal = view.range * (profile.idealFraction or tuning.idealRangeFraction)
		local closeRange = profile.closeRange or tuning.closeRange
		local fireLimit = view.range * (profile.fireFraction or 0.95)
		local radial = 0
		if d > ideal * 1.15 then
			radial = 1
		elseif d < closeRange then
			radial = -1
		end
		if lowHealth then
			mode = "flee"
			radial = -1
		end
		local side = { x = -toTarget.z * state.strafeSign, z = toTarget.x * state.strafeSign }
		move = unit(toTarget.x * radial + side.x * 0.9, toTarget.z * radial + side.z * 0.9)
		if cover then
			mode = "cover"
			move = if atCover then { x = 0, z = 0 } else toward(me.pos, cover)
		end
		if lowHealth and not cover and me.slideReady and d < view.range then
			slide = true
		end
		-- Aim with a small random miss; shoot only after the reaction delay.
		local miss = math.rad(tuning.aimErrorDegrees) * (view.rand() * 2 - 1)
		aim = rotate(toTarget, miss)
		if
			me.canFire
			and not me.reloading
			and now - state.seenAt >= tuning.reactionTime
			and d <= fireLimit
		then
			fire = true
		end
		if outside and zone then
			-- The zone wins over everything else: keep shooting while running in.
			move = toward(me.pos, zone.center)
			mode = "zone"
			slide = false
		end
	elseif outside and zone then
		mode = "zone"
		move = toward(me.pos, zone.center)
	elseif cover then
		mode = "cover"
		move = if atCover then { x = 0, z = 0 } else toward(me.pos, cover)
	elseif state.lastKnown and now - state.lastSeen <= tuning.memoryTime then
		mode = "search"
		move = toward(me.pos, state.lastKnown)
	elseif gun then
		mode = "gun"
		move = toward(me.pos, gun.pos)
	else
		local pickup = nearestPickup(view)
		if pickup then
			mode = "loot"
			move = toward(me.pos, pickup.pos)
		else
			move = roam(view, state)
		end
	end

	-- Far outside the wall: dash back in (same slide a player has).
	if outside and zone and me.slideReady and outsideBy > tuning.zoneSlideDistance then
		slide = true
	end

	-- Reload when empty, or early when nobody is in sight.
	if not me.reloading and me.magazine > 0 then
		local empty = me.ammo <= 0
		local lowAndQuiet = not target and me.ammo < me.magazine * tuning.reloadBelowFraction
		reload = empty or lowAndQuiet
	end

	-- Stuck: step sideways for a moment.
	if now < state.sideUntil and (move.x ~= 0 or move.z ~= 0) then
		move = { x = -move.z * state.sideSign, z = move.x * state.sideSign }
	end

	if move.x ~= 0 or move.z ~= 0 then
		state.aim = if target then aim else move
	elseif target then
		state.aim = aim
	end
	state.lastMove = move

	return {
		moveX = move.x,
		moveZ = move.z,
		aimX = state.aim.x,
		aimZ = state.aim.z,
		fire = fire,
		reload = reload,
		slide = slide,
		mode = mode,
		grabGunId = grabGunId,
	}
end

return BotBrain
