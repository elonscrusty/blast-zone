--!strict
-- Runs the bots' thinking on a timer and hands each result to the game through `World`. No Roblox
-- calls here, so Lune can test it with a fake world. The real world sends move, fire, reload and
-- slide through the same server code players use, so every rule (ammo, fire rate, cooldowns,
-- walls) applies to bots too.

local BotBrain = require("./BotBrain")
local BotTuning = require("./BotTuning")
local BotWarmup = require("./BotWarmup")

export type World = {
	now: () -> number,
	isActive: () -> boolean, -- a match is running (bots stand still otherwise)
	fightSeconds: (() -> number)?, -- seconds since the fight began (calm start); nil = always sharp
	selfState: (id: string) -> BotBrain.Self?, -- nil = eliminated or gone
	others: (id: string) -> { BotBrain.Body }, -- every other living participant
	pickups: () -> { BotBrain.Pickup },
	zone: () -> BotBrain.Zone?,
	weaponRange: (id: string) -> number,
	canSee: (BotBrain.Vec2, BotBrain.Vec2) -> boolean, -- same test that blocks shots
	move: (id: string, x: number, z: number) -> (),
	fire: (id: string, aimX: number, aimZ: number) -> (),
	reload: (id: string) -> (),
	slide: (id: string, dirX: number, dirZ: number) -> (),
}

type Entry = {
	state: BotBrain.State,
	nextThink: number,
	last: BotBrain.Intent?,
	stopped: boolean,
}

local BotRunner = {}
BotRunner.__index = BotRunner

export type Runner = typeof(setmetatable(
	{} :: {
		world: World,
		tuning: BotTuning.Tuning,
		rand: () -> number,
		onError: (string, string) -> (),
		bots: { [string]: Entry },
	},
	BotRunner
))

function BotRunner.new(
	world: World,
	tuning: BotTuning.Tuning,
	rand: () -> number,
	onError: ((string, string) -> ())?
): Runner
	return setmetatable({
		world = world,
		tuning = tuning,
		rand = rand,
		onError = onError or function() end,
		bots = {},
	}, BotRunner)
end

function BotRunner.add(self: Runner, id: string)
	if self.bots[id] then
		return
	end
	-- Spread the first thinks so bots do not all think on the same frame.
	self.bots[id] = {
		state = BotBrain.newState(),
		nextThink = self.world.now() + self.rand() * self.tuning.thinkInterval,
		last = nil,
		stopped = true,
	}
end

function BotRunner.remove(self: Runner, id: string)
	if self.bots[id] then
		self.world.move(id, 0, 0)
		self.bots[id] = nil
	end
end

function BotRunner.clear(self: Runner)
	for id in self.bots do
		self:remove(id)
	end
end

function BotRunner.count(self: Runner): number
	local n = 0
	for _ in self.bots do
		n += 1
	end
	return n
end

local function stop(world: World, id: string, entry: Entry)
	if not entry.stopped then
		world.move(id, 0, 0)
		entry.stopped = true
		entry.last = nil
	end
end

-- Call every frame (Heartbeat).
function BotRunner.step(self: Runner)
	local world = self.world
	local now = world.now()
	local active = world.isActive()
	-- Removing while looping a table is allowed in Luau, but gather first to stay clear of surprises.
	local ids = {}
	for id in self.bots do
		table.insert(ids, id)
	end
	for _, id in ids do
		local entry = self.bots[id]
		if not entry then
			continue
		end
		if not active then
			stop(world, id, entry)
			continue
		end
		local me = world.selfState(id)
		if not me then
			-- Eliminated or gone: a bot cannot act, so it is dropped here.
			self:remove(id)
			continue
		end
		if now >= entry.nextThink then
			entry.nextThink = now + self.tuning.thinkInterval
			-- Building the snapshot talks to the game, so it sits inside the pcall too.
			local ok, result = pcall(function(): BotBrain.Intent
				local fightSeconds = world.fightSeconds
				local tuning = if fightSeconds
					then BotWarmup.apply(self.tuning, fightSeconds())
					else self.tuning
				local view: BotBrain.View = {
					now = now,
					me = me,
					others = world.others(id),
					pickups = world.pickups(),
					zone = world.zone(),
					range = world.weaponRange(id),
					canSee = world.canSee,
					rand = self.rand,
					tuning = tuning,
				}
				return BotBrain.think(view, entry.state)
			end)
			if ok then
				local intent = result :: BotBrain.Intent
				entry.last = intent
				entry.stopped = false
				if intent.slide then
					world.slide(id, intent.moveX, intent.moveZ)
				end
				if intent.reload then
					world.reload(id)
				end
				if intent.fire then
					world.fire(id, intent.aimX, intent.aimZ)
				end
			else
				self.onError(id, tostring(result))
				entry.last = nil
			end
		end
		-- Humanoid movement should be refreshed every frame, not only when the bot thinks.
		local last = entry.last
		if last then
			world.move(id, last.moveX, last.moveZ)
		else
			stop(world, id, entry)
		end
	end
end

return BotRunner
