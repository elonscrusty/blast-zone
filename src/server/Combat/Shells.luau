--!strict
-- The Arc Mortar's shells. Slow, so the server moves each one a little every frame (no physical part):
-- it flies flat, bursts on the first wall, the first body that is not the shooter's, or at the end of its range.
-- The blast hurts everyone in the radius with a clear line to the centre, the shooter at a reduced scale,
-- and breaks nearby supply containers.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Damage = require(script.Parent.Parent.Core.Damage)
local EffectiveStats = require(script.Parent.Parent.Core.EffectiveStats)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)
local Net = require(script.Parent.Parent.Core.Net)
local Participants = require(script.Parent.Parent.Core.Participants)
local Ballistics = require("./Ballistics")
local Combatants = require("./Combatants")
local ContainerLink = require("./ContainerLink")
local ShellFlight = require("./ShellFlight")
local ShotCaster = require("./ShotCaster")

local explosive = Config.Weapons.Explosive

type Live = {
	shell: ShellFlight.Shell,
	ownerId: string,
	matchId: number,
	y: number,
	damage: number,
	radius: number,
	aftershock: boolean, -- Config.Powers: a second, weaker blast follows
}

local live: { Live } = {}

local Shells = {}

function Shells.count(): number
	return #live
end

function Shells.clear()
	table.clear(live)
end

-- A disconnected shooter's shells are removed with them (Config.Policies.disconnectedAttacker).
function Shells.removeOwner(id: string)
	for i = #live, 1, -1 do
		if live[i].ownerId == id then
			table.remove(live, i)
		end
	end
end

-- Returns false when too many shells are already in the air.
function Shells.launch(
	ownerId: string,
	matchId: number,
	origin: Vector3,
	dx: number,
	dz: number
): boolean
	if #live >= Config.Combat.maxShells then
		return false
	end
	local stats = EffectiveStats:get(ownerId).explosive
	local bodies = Combatants.bodies()
	-- Where it will land if nobody walks into it: this is what the warning ring shows.
	local wall = ShotCaster.cast(origin, dx, dz, stats.range, bodies, nil)
	local flight = if wall ~= nil then math.max(0, wall - ShellFlight.WALL_BACKOFF) else stats.range
	local landing = origin + Vector3.new(dx, 0, dz) * flight
	local now = workspace:GetServerTimeNow()
	table.insert(live, {
		shell = {
			x = origin.X,
			z = origin.Z,
			dx = dx,
			dz = dz,
			speed = stats.projectileSpeed,
			remaining = stats.range,
		},
		ownerId = ownerId,
		matchId = matchId,
		y = origin.Y,
		damage = stats.damage,
		radius = stats.radius,
		aftershock = stats.aftershock >= 1,
	})
	local muzzle = origin
		+ Vector3.new(dx, 0, dz) * math.min(Config.Weapons.Firearm.muzzleOffset, flight)
	Net.fireAll("ShotFx", {
		shooterId = ownerId,
		weaponId = explosive.id,
		origin = muzzle,
		endPos = landing,
		hitKind = "none",
	})
	Net.fireAll("ExplosionFx", {
		pos = landing,
		radius = stats.radius,
		shooterId = ownerId,
		warnEndsAt = now + flight / math.max(stats.projectileSpeed, 1),
	})
	return true
end

local function detonate(s: Live, center: Vector3)
	Net.fireAll("ExplosionFx", { pos = center, radius = s.radius, shooterId = s.ownerId })
	local bodies = Combatants.bodies()
	local victims = Ballistics.blastVictims(
		center.X,
		center.Z,
		s.radius,
		explosive.falloffMin,
		Combatants.targets(nil, 0),
		function(t: Ballistics.Target): boolean
			local at = Vector3.new(t.x, s.y, t.z)
			return not ShotCaster.lineBlocked(center, at, bodies, nil)
		end
	)
	for _, v in victims do
		local amount = s.damage * v.factor
		if v.id == s.ownerId then
			if not Config.ShotRules.explosionsDamageOwner then
				continue
			end
			amount *= explosive.selfDamageScale
		end
		Damage:apply({
			matchId = s.matchId,
			targetId = v.id,
			amount = amount,
			cause = "explosion",
			sourceId = s.ownerId,
			weaponId = explosive.id,
			hitPosition = center,
		})
	end
	-- Supply containers inside the radius (a clear line to the centre is needed, like for bodies).
	for _, part in CollectionService:GetTagged(Config.Tags.SupplyContainer) do
		if part:IsA("BasePart") then
			local dist = (part.Position - center).Magnitude
			local factor =
				Ballistics.blastFactor(dist - part.Size.X / 2, s.radius, explosive.falloffMin)
			if factor > 0 then
				local model = part:FindFirstAncestorOfClass("Model")
				local at = Vector3.new(part.Position.X, s.y, part.Position.Z)
				if not ShotCaster.lineBlocked(center, at, bodies, model or part) then
					ContainerLink.damage(part, s.damage * factor, s.ownerId, s.matchId)
				end
			end
		end
	end
end

-- The same list without one fighter (a shell never touches its own shooter in flight).
local function without(list: { Ballistics.Target }, id: string): { Ballistics.Target }
	local out: { Ballistics.Target } = {}
	for _, t in list do
		if t.id ~= id then
			table.insert(out, t)
		end
	end
	return out
end

function Shells.step(dt: number)
	if #live == 0 then
		return
	end
	-- Bodies and positions are read once per frame, not once per shell.
	local bodies = Combatants.bodies()
	local everyone = Combatants.targets(nil, Config.Combat.shellContactPadding)
	for i = #live, 1, -1 do
		local s = live[i]
		local gone = not MatchContext:isCurrent(s.matchId)
			or not MatchContext:isCombat()
			or Participants:get(s.ownerId) == nil
		if gone then
			table.remove(live, i)
			continue
		end
		local targets = without(everyone, s.ownerId)
		local function wallDistance(
			x: number,
			z: number,
			dx: number,
			dz: number,
			dist: number
		): number?
			return (ShotCaster.cast(Vector3.new(x, s.y, z), dx, dz, dist, bodies, nil))
		end
		local left = math.min(dt, 0.25)
		local burst: ShellFlight.Burst? = nil
		while burst == nil and left > 1e-6 do
			local slice = math.min(left, Config.Combat.shellStepSeconds)
			burst = ShellFlight.step(s.shell, slice, wallDistance, targets)
			left -= slice
		end
		if burst ~= nil then
			table.remove(live, i)
			local center = Vector3.new(burst.x, s.y, burst.z)
			detonate(s, center)
			if s.aftershock then
				-- The second blast: same place, less damage, and only if the match is still the same one.
				local again = table.clone(s)
				again.damage = s.damage * Config.Powers.aftershockDamageShare
				again.aftershock = false
				task.delay(Config.Powers.aftershockDelaySeconds, function()
					if MatchContext:isCurrent(again.matchId) and MatchContext:isCombat() then
						detonate(again, center)
					end
				end)
			end
		end
	end
end

return Shells
