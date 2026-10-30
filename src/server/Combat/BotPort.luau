--!strict
-- The door bots use. A bot shoots through exactly the same rules as a player: same ammo, fire rate,
-- reload, wall blocking and damage door. Bots are keyed by ParticipantId ("b1").
--   registerBotBody(id, model)  -- once, after the bot is enrolled and its R15 rig exists
--   fire(id, dirX, dirZ) -> boolean          one trigger pull aimed that way
--   reload(id) -> boolean ; switchSlot(id, slot) -> boolean
--   state(id) -> { health, maxHealth, ammo, magazine, reloading, canFire, slot }? (nil when dead or unknown)
--   shotParams() -> RaycastParams           an Include list of every shot-stopping part, so a plain Raycast
--                                           with it sees exactly what shots see (rebuilt on each call)
--   gunDrops() -> { { dropId, gunId, x, z } }   found guns lying on the ground
--   claimGun(id, dropId)                      ask for a swap (same checks as a player's button)
--   isLineClear(from, to) -> boolean         true when no shot-stopping wall lies between (use for eyesight)

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)
local Participants = require(script.Parent.Parent.Core.Participants)
local Combatants = require("./Combatants")
local Firing = require("./Firing")
local WeaponDrops = require("./WeaponDrops")
local ShotCaster = require("./ShotCaster")

export type BotState = {
	health: number,
	maxHealth: number,
	ammo: number,
	magazine: number,
	reloading: boolean,
	canFire: boolean,
	slot: number,
	gunId: string, -- the slot 1 gun in hand
	range: number, -- how far that gun reaches, upgrades counted
}

local BotPort = {}

function BotPort.registerBotBody(id: string, model: Model)
	Combatants.registerBot(id, model)
	Combatants.ensure(id)
	Combatants.mirror(id)
end

function BotPort.fire(id: string, dirX: number, dirZ: number): boolean
	local ok = Firing.fire(id, nil, Vector3.new(dirX, 0, dirZ))
	return ok
end

function BotPort.reload(id: string): boolean
	local ok = Firing.reload(id)
	return ok
end

function BotPort.switchSlot(id: string, slot: number): boolean
	local ok = Firing.switch(id, slot)
	return ok
end

function BotPort.state(id: string): BotState?
	if not Participants:isAlive(id) then
		return nil
	end
	local c = Combatants.ensure(id)
	local hp = Combatants.health(id)
	if c == nil or hp == nil then
		return nil
	end
	local slot = c.weapons.slot
	return {
		health = hp,
		maxHealth = Combatants.maxHealth(id),
		ammo = c.weapons.ammo[slot],
		magazine = Combatants.slotStats(id, slot).magazine,
		reloading = c.weapons.reloadEndsAt[slot] ~= nil,
		canFire = MatchContext:isCombat() and c.weapons:canFire(os.clock()),
		slot = slot,
		gunId = Combatants.primary(id),
		range = Combatants.gunStats(id).range,
	}
end

function BotPort.gunDrops(): { WeaponDrops.GunOnGround }
	return WeaponDrops.list()
end

function BotPort.claimGun(id: string, dropId: string)
	WeaponDrops.claimFor(id, dropId)
end

function BotPort.shotParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = CollectionService:GetTagged(Config.Tags.BlocksShots)
	return params
end

function BotPort.isLineClear(from: Vector3, to: Vector3): boolean
	return not ShotCaster.lineBlocked(from, to, Combatants.bodies(), nil)
end

return BotPort
