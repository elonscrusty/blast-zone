--!strict
-- Trigger pulls, reloads and weapon switches. The server owns ammo, fire rate and every hit: the client
-- only says "I pulled the trigger aiming that way". Shots are flat (the vertical part of the aim is dropped),
-- start at the body, and are stopped by BlocksShots geometry, so nobody shoots through a nearby wall.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Damage = require(script.Parent.Parent.Core.Damage)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)
local Net = require(script.Parent.Parent.Core.Net)
local Participants = require(script.Parent.Parent.Core.Participants)
local SpawnShields = require(script.Parent.Parent.Core.SpawnShields)
local MoveGuard = require(script.Parent.Parent.AntiCheat.MoveGuard)
local SprintService = require(script.Parent.Parent.Movement.SprintService)
local Ballistics = require("./Ballistics")
local Combatants = require("./Combatants")
local ContainerLink = require("./ContainerLink")
local Shells = require("./Shells")
local ShotCaster = require("./ShotCaster")
local WeaponState = require("./WeaponState")
local WeaponCatalog = require("./WeaponCatalog")

local firearm = Config.Weapons.Firearm
local explosive = Config.Weapons.Explosive
local tuning = Config.Combat

local Firing = {}

local function weaponIdOf(id: string, slot: number): string
	return if slot == 2 then explosive.id else Combatants.primary(id)
end

-- The slot's weapon is usable only when its feature flag is on.
local function slotEnabled(slot: number): boolean
	return slot == 1 or (slot == 2 and Config.Features.explosiveWeapon)
end

function Firing.sendAmmo(id: string)
	local c = Combatants.get(id)
	local p = Participants:get(id)
	if c == nil or p == nil or p.player == nil then
		return
	end
	local slot = c.weapons.slot
	local endsAt = c.weapons.reloadEndsAt[slot]
	local serverNow = workspace:GetServerTimeNow()
	local weaponId = weaponIdOf(id, slot)
	local st = Combatants.slotStats(id, slot)
	Net.fire("AmmoState", p.player, {
		slot = slot,
		weaponId = weaponId,
		weaponName = if slot == 2
			then explosive.displayName
			else WeaponCatalog.displayName(Config, weaponId),
		fireInterval = st.fireInterval,
		reloadSeconds = st.reloadSeconds,
		muzzleOffset = if slot == 2
			then firearm.muzzleOffset
			else WeaponCatalog.def(Config, weaponId).muzzleOffset,
		ammo = c.weapons.ammo[slot],
		magazine = st.magazine,
		reloadEndsAt = if endsAt ~= nil then serverNow + (endsAt - os.clock()) else nil,
		serverNow = serverNow,
	})
end

-- Where the shot starts. The server's own idea of the body, nudged to the client's claim only when the
-- claim is close AND no wall lies between the two (a client cannot start a shot on the far side of a wall).
local function shotOrigin(root: BasePart, claimed: Vector3?, bodies: { Instance }): Vector3
	local mine = Vector3.new(root.Position.X, root.Position.Y + tuning.shotHeight, root.Position.Z)
	if claimed == nil then
		return mine
	end
	if not Ballistics.withinDrift(mine.X, mine.Z, claimed.X, claimed.Z, firearm.maxOriginDrift) then
		return mine
	end
	local theirs = Vector3.new(claimed.X, mine.Y, claimed.Z)
	if ShotCaster.lineBlocked(mine, theirs, bodies, nil) then
		return mine
	end
	return theirs
end

local function fireBullets(id: string, matchId: number, origin: Vector3, dx: number, dz: number)
	local stats = Combatants.gunStats(id)
	local gun = WeaponCatalog.def(Config, Combatants.primary(id))
	local bodies = Combatants.bodies()
	local targets = Combatants.targets(id, 0)
	for _, d in Ballistics.fan(dx, dz, stats.pellets, stats.spreadDegrees) do
		local wallDist, wallPart = ShotCaster.cast(origin, d.x, d.z, stats.range, bodies, nil)
		local hit = Ballistics.line(
			origin.X,
			origin.Z,
			d.x,
			d.z,
			stats.range,
			wallDist,
			targets,
			stats.pierce
		)
		local endPos = origin + Vector3.new(d.x, 0, d.z) * hit.endDist
		local kind = "none"
		-- Each body a bullet passes through takes less (Config.Powers.pierceFalloff).
		local amount = stats.damage
		for _, h in hit.hits do
			kind = "target"
			Damage:apply({
				matchId = matchId,
				targetId = h.id,
				amount = amount,
				cause = "bullet",
				sourceId = id,
				weaponId = gun.id,
				hitPosition = origin + Vector3.new(d.x, 0, d.z) * h.dist,
			})
			amount *= Config.Powers.pierceFalloff
		end
		if hit.endKind == "wall" then
			if kind == "none" then
				kind = "wall"
			end
			if wallPart ~= nil and ContainerLink.damage(wallPart, amount, id, matchId) then
				kind = "container"
			end
		end
		local muzzle = origin + Vector3.new(d.x, 0, d.z) * math.min(gun.muzzleOffset, hit.endDist)
		Net.fireAll("ShotFx", {
			shooterId = id,
			weaponId = gun.id,
			origin = muzzle,
			endPos = endPos,
			hitKind = kind,
		})
	end
end

-- One trigger pull. Returns whether a shot left the weapon, and why not.
function Firing.fire(id: string, claimedOrigin: Vector3?, dir: Vector3): (boolean, string?)
	if not MatchContext:isCombat() then
		return false, "not-combat"
	end
	if not Participants:isAlive(id) then
		return false, "eliminated"
	end
	local c = Combatants.ensure(id)
	local root = Combatants.root(id)
	if c == nil or root == nil then
		return false, "no-body"
	end
	if MoveGuard.isHeld(id) then
		return false, "move-check" -- the body just jumped further than it can: no shot from there
	end
	local dx, dz = Ballistics.flatten(dir.X, dir.Y, dir.Z)
	if dx == nil or dz == nil then
		return false, "bad-aim"
	end
	local slot = c.weapons.slot
	if not slotEnabled(slot) then
		return false, "disabled"
	end
	local result = c.weapons:tryFire(os.clock(), Combatants.slotStats(id, slot))
	if not result.ok then
		if result.startedReload then
			Firing.sendAmmo(id)
		end
		return false, result.reason
	end
	SprintService.noteFire(id) -- a shot breaks the run for a moment
	-- Shooting ends your own spawn shield: no attacking from behind it.
	if Config.SpawnShield.dropOnFire then
		SpawnShields:drop(id)
	end
	local origin = shotOrigin(root, claimedOrigin, Combatants.bodies())
	if slot == 2 then
		if not Shells.launch(id, c.matchId, origin, dx, dz) then
			return false, "too-many-shells"
		end
	else
		fireBullets(id, c.matchId, origin, dx, dz)
	end
	Firing.sendAmmo(id)
	return true, nil
end

function Firing.reload(id: string): (boolean, string?)
	if not MatchContext:isCombat() or not Participants:isAlive(id) then
		return false, "not-combat"
	end
	local c = Combatants.ensure(id)
	if c == nil then
		return false, "no-record"
	end
	local ok, why = c.weapons:startReload(os.clock(), Combatants.slotStats(id, c.weapons.slot))
	if ok then
		Firing.sendAmmo(id)
	end
	return ok, why
end

function Firing.switch(id: string, slot: number): (boolean, string?)
	if not MatchContext:isCombat() or not Participants:isAlive(id) then
		return false, "not-combat"
	end
	if not slotEnabled(slot) then
		return false, "disabled"
	end
	local c = Combatants.ensure(id)
	if c == nil then
		return false, "no-record"
	end
	local ok = c.weapons:equip(slot, os.clock(), tuning.switchSeconds)
	if ok then
		Firing.sendAmmo(id)
	end
	return ok, if ok then nil else "same-or-locked"
end

-- Every frame: finish reloads whose time is up, keep health attributes on respawned bodies.
local function statsOfSlot(id: string): (number) -> WeaponState.Stats
	return function(slot: number)
		return Combatants.slotStats(id, slot)
	end
end

function Firing.step()
	local now = os.clock()
	Combatants.forEach(function(c)
		-- A fighter with nothing reloading costs one table read here: no stats sheet, no list.
		if next(c.weapons.reloadEndsAt) ~= nil then
			local done = c.weapons:update(now, statsOfSlot(c.id))
			if #done > 0 then
				Firing.sendAmmo(c.id)
			end
		end
		if Combatants.model(c.id) ~= c.mirrored then
			Combatants.mirror(c.id)
		end
	end)
end

return Firing
