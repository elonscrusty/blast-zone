--!strict
-- Each fighter's combat record: weapons and health. One per participant per match (a new match
-- stamp means a new record, so nothing leaks from the last match). Reads who exists from Core/Participants.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local EffectiveStats = require(script.Parent.Parent.Core.EffectiveStats)
local Net = require(script.Parent.Parent.Core.Net)
local Participants = require(script.Parent.Parent.Core.Participants)
local HealthBook = require("./HealthBook")
local WeaponState = require("./WeaponState")
local Ballistics = require("./Ballistics")

export type Combatant = {
	id: string,
	matchId: number,
	weapons: WeaponState.State,
	mirrored: Model?, -- the model whose attributes are up to date
}

local Combatants = {}

local book = HealthBook.new(Config.Health.max)
local byId: { [string]: Combatant } = {}
local botBodies: { [string]: Model } = {}

Combatants.book = book

function Combatants.registerBot(id: string, model: Model)
	botBodies[id] = model
end

function Combatants.model(id: string): Model?
	local bot: Model? = botBodies[id]
	if bot ~= nil and bot.Parent ~= nil then
		return bot
	end
	local p = Participants:get(id)
	if p ~= nil and p.player ~= nil then
		return p.player.Character
	end
	return nil
end

function Combatants.root(id: string): BasePart?
	local m = Combatants.model(id)
	local r = m and m:FindFirstChild("HumanoidRootPart")
	if r ~= nil and r:IsA("BasePart") then
		return r
	end
	return nil
end

-- Weapon numbers for one slot (1 = firearm, 2 = explosive), read fresh so upgrades count.
function Combatants.slotStats(id: string, slot: number): WeaponState.Stats
	local sheet = EffectiveStats:get(id)
	local w = if slot == 2 then sheet.explosive else sheet.firearm
	return { fireInterval = w.fireInterval, magazine = w.magazine, reloadSeconds = w.reloadSeconds }
end

function Combatants.get(id: string): Combatant?
	return byId[id]
end

local function playerOf(id: string): Player?
	local p = Participants:get(id)
	return if p ~= nil then p.player else nil
end

function Combatants.sendHealth(id: string)
	local player = playerOf(id)
	local hp = book:get(id)
	if player ~= nil and hp ~= nil then
		Net.fire("HealthState", player, { health = hp, max = Config.Health.max })
	end
end

-- Health, max and alive are copied onto the character so every client can draw health bars.
function Combatants.mirror(id: string)
	local c = byId[id]
	local m = Combatants.model(id)
	if c == nil or m == nil then
		return
	end
	m:SetAttribute("Health", book:get(id) or 0)
	m:SetAttribute("MaxHealth", Config.Health.max)
	m:SetAttribute("Alive", Participants:isAlive(id))
	c.mirrored = m
end

-- The record for a participant of the CURRENT enrolment, made on first use.
function Combatants.ensure(id: string): Combatant?
	local p = Participants:get(id)
	if p == nil then
		return nil
	end
	local c = byId[id]
	if c ~= nil and c.matchId == p.matchId then
		return c
	end
	local sheet = EffectiveStats:get(id)
	local fresh: Combatant = {
		id = id,
		matchId = p.matchId,
		weapons = WeaponState.new(
			{ sheet.firearm.magazine, sheet.explosive.magazine },
			Config.Combat.fireTolerance
		),
		mirrored = nil,
	}
	if not p.alive then
		fresh.weapons:lock()
	end
	byId[id] = fresh
	book:add(id)
	Combatants.mirror(id)
	Combatants.sendHealth(id)
	return fresh
end

function Combatants.drop(id: string)
	byId[id] = nil
	botBodies[id] = nil
	book:remove(id)
end

function Combatants.all(): { Combatant }
	local out = {}
	for _, c in byId do
		table.insert(out, c)
	end
	return out
end

-- The damage door's backend: health math only. The door checks match, phase and double eliminations.
function Combatants.applyDamage(req: any): any
	local c = Combatants.ensure(req.targetId)
	if c == nil then
		return {
			applied = false,
			reason = "no-record",
			dealt = 0,
			remaining = 0,
			eliminated = false,
		}
	end
	local dealt, remaining, dead = book:apply(req.targetId, req.amount, req.sourceId)
	return {
		applied = dealt > 0,
		reason = if dealt > 0 then nil else "no-health",
		dealt = dealt,
		remaining = remaining,
		eliminated = dead,
	}
end

-- Pickups call this. Never revives, never goes over the maximum.
function Combatants.heal(id: string, amount: number): number
	if not Participants:isAlive(id) then
		return 0
	end
	local gained = book:heal(id, amount)
	if gained > 0 then
		Combatants.mirror(id)
		Combatants.sendHealth(id)
	end
	return gained
end

function Combatants.health(id: string): number?
	return book:get(id)
end

-- Every living participant with a body, as flat circles. `exceptId` leaves one out (the shooter).
function Combatants.targets(exceptId: string?, padding: number): { Ballistics.Target }
	local out = {}
	for _, p in Participants:aliveList() do
		if p.id ~= exceptId then
			local root = Combatants.root(p.id)
			if root ~= nil then
				table.insert(out, {
					id = p.id,
					x = root.Position.X,
					z = root.Position.Z,
					r = Config.Combat.bodyRadius + padding,
				})
			end
		end
	end
	return out
end

-- Every participant's character: shots ignore bodies in the wall test (bodies are tested as circles).
function Combatants.bodies(): { Instance }
	local out: { Instance } = {}
	for _, p in Participants:list() do
		local m = Combatants.model(p.id)
		if m ~= nil then
			table.insert(out, m)
		end
	end
	return out
end

return Combatants
