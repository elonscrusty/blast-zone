--!strict
-- The bot's thinking, with no Roblox calls so Lune can test it. Each think gets a plain snapshot of
-- what the bot may know and returns what a player's controls would do: move, aim, fire, reload,
-- slide. The server then applies that through the same code paths players use, so bots follow the
-- same health, ammo, fire-rate and slide rules. Walls are respected because the bot only notices
-- someone when the snapshot's canSee says a shot could reach them.

local BotTuning = require("./BotTuning")

type Tuning = BotTuning.Tuning

export type Vec2 = { x: number, z: number }
export type Body = { id: string, pos: Vec2 }
export type Pickup = { id: string, pos: Vec2 }
export type Zone = { center: Vec2, radius: number }
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
}
export type View = {
	now: number,
	me: Self,
	others: { Body }, -- every other living participant; the brain filters by sight
	pickups: { Pickup },
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
		if d <= view.tuning.sightRange and view.canSee(view.me.pos, other.pos) then
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

local function nearestPickup(view: View): Pickup?
	local best: Pickup? = nil
	local bestDist = view.tuning.pickupRange
	for _, p in view.pickups do
		local d = dist(view.me.pos, p.pos)
		if d <= bestDist and view.canSee(view.me.pos, p.pos) then
			best, bestDist = p, d
		end
	end
	return best
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

function BotBrain.think(view: View, state: State): Intent
	local me = view.me
	local now = view.now
	checkStuck(view, state)

	local target = findTarget(view, state)
	if target then
		if target.id ~= state.targetId then
			state.targetId = target.id
			state.seenAt = now
		end
		state.lastSeen = now
		state.lastKnown = { x = target.pos.x, z = target.pos.z }
	elseif now - state.lastSeen > view.tuning.memoryTime then
		state.targetId = nil
		state.lastKnown = nil
	end

	local zone = view.zone
	local outside = zone ~= nil and dist(me.pos, zone.center) > zone.radius - view.tuning.zoneMargin

	local move: Vec2 = { x = 0, z = 0 }
	local mode = "roam"
	local fire = false
	local reload = false
	local slide = false
	local aim: Vec2 = state.aim

	local lowHealth = me.health <= me.maxHealth * view.tuning.fleeAtFraction

	if target then
		local toTarget = toward(me.pos, target.pos)
		local d = dist(me.pos, target.pos)
		aim = toTarget
		mode = "fight"
		if now >= state.strafeUntil then
			state.strafeSign = if view.rand() < 0.5 then 1 else -1
			state.strafeUntil = now
				+ between(view.rand, view.tuning.strafeMin, view.tuning.strafeMax)
		end
		local ideal = view.range * view.tuning.idealRangeFraction
		local radial = 0
		if d > ideal * 1.15 then
			radial = 1
		elseif d < view.tuning.closeRange then
			radial = -1
		end
		if lowHealth then
			mode = "flee"
			radial = -1
		end
		local side = { x = -toTarget.z * state.strafeSign, z = toTarget.x * state.strafeSign }
		move = unit(toTarget.x * radial + side.x * 0.9, toTarget.z * radial + side.z * 0.9)
		if outside and zone and not lowHealth then
			-- The zone wins over the fight: keep shooting while running in.
			move = toward(me.pos, zone.center)
			mode = "zone"
		end
		if lowHealth and me.slideReady and d < view.range then
			slide = true
		end
		-- Aim with a small random miss; shoot only after the reaction delay.
		local miss = math.rad(view.tuning.aimErrorDegrees) * (view.rand() * 2 - 1)
		aim = rotate(toTarget, miss)
		if
			me.canFire
			and not me.reloading
			and now - state.seenAt >= view.tuning.reactionTime
			and d <= view.range * 0.95
		then
			fire = true
		end
	elseif outside and zone then
		mode = "zone"
		move = toward(me.pos, zone.center)
	elseif state.lastKnown and now - state.lastSeen <= view.tuning.memoryTime then
		mode = "search"
		move = toward(me.pos, state.lastKnown)
	else
		local pickup = nearestPickup(view)
		if pickup then
			mode = "loot"
			move = toward(me.pos, pickup.pos)
		else
			move = roam(view, state)
		end
	end

	-- Reload when empty, or early when nobody is in sight.
	if not me.reloading and me.magazine > 0 then
		local empty = me.ammo <= 0
		local lowAndQuiet = not target and me.ammo < me.magazine * view.tuning.reloadBelowFraction
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
	}
end

return BotBrain
