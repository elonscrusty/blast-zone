--!strict
-- Starts combat: binds the health math to the damage door, answers the three weapon requests,
-- and turns door events into feedback (health, hit confirms, incoming damage, elimination).

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local MatchPhase = require(Shared.MatchPhase)
local Damage = require(script.Parent.Parent.Core.Damage)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)
local Net = require(script.Parent.Parent.Core.Net)
local Participants = require(script.Parent.Parent.Core.Participants)
local Combatants = require("./Combatants")
local Firing = require("./Firing")
local Shells = require("./Shells")

local CombatSystem = {}
CombatSystem.order = 60

local function playerOf(id: string): Player?
	local p = Participants:get(id)
	return if p ~= nil then p.player else nil
end

local function nameOf(id: string?): string?
	if id == nil then
		return nil
	end
	local p = Participants:get(id)
	return if p ~= nil then p.displayName else nil
end

-- Flat direction from the victim toward the attacker (for the incoming-hit arrow), if both are known.
local function directionToSource(victimId: string, sourceId: string?, hitPosition: any): Vector3?
	local vroot = Combatants.root(victimId)
	if vroot == nil then
		return nil
	end
	local from: Vector3? = nil
	if typeof(hitPosition) == "Vector3" and sourceId ~= victimId then
		-- A blast: the arrow points at the centre.
		from = hitPosition
	elseif sourceId ~= nil then
		local sroot = Combatants.root(sourceId)
		from = if sroot ~= nil then sroot.Position else nil
	end
	if from == nil then
		return nil
	end
	local delta = Vector3.new(from.X - vroot.Position.X, 0, from.Z - vroot.Position.Z)
	if delta.Magnitude < 0.1 then
		return nil
	end
	return delta.Unit
end

local function onDamaged(e: any)
	local req, res = e.request, e.result
	Combatants.mirror(req.targetId)
	Combatants.sendHealth(req.targetId)
	local victim = playerOf(req.targetId)
	if victim ~= nil then
		Net.fire("DamageTaken", victim, {
			sourceId = req.sourceId,
			amount = res.dealt,
			cause = req.cause,
			fromDir = directionToSource(req.targetId, req.sourceId, req.hitPosition),
			weaponId = req.weaponId,
			health = res.remaining,
		})
	end
	local shooter = if req.sourceId ~= nil and req.sourceId ~= req.targetId
		then playerOf(req.sourceId)
		else nil
	if shooter ~= nil then
		Net.fire("HitConfirm", shooter, {
			targetId = req.targetId,
			amount = res.dealt,
			killed = res.eliminated,
			pos = req.hitPosition,
		})
	end
end

local function onEliminated(e: any)
	local id: string = e.victimId
	local c = Combatants.get(id)
	if c ~= nil then
		c.weapons:lock()
	end
	Combatants.mirror(id)
	local model = Combatants.model(id)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.Health = 0
	end
	local victim = playerOf(id)
	if victim ~= nil then
		local hitters = {}
		for _, h in Combatants.book:hitters(id) do
			table.insert(
				hitters,
				{ name = nameOf(h.sourceId) or "?", damage = math.floor(h.damage + 0.5) }
			)
		end
		Net.fire("DefeatSummary", victim, {
			killerId = e.killerId,
			killerName = nameOf(e.killerId),
			cause = e.cause,
			weaponId = e.weaponId,
			hitters = hitters,
		})
	end
end

function CombatSystem.start()
	Damage:bind(Combatants.applyDamage)
	Damage.Damaged:connect(onDamaged)
	Damage.Eliminated:connect(onEliminated)

	Net.onRequest(
		"FireRequest",
		function(player: Player, origin: Vector3, dir: Vector3, _seq: number)
			local p = Participants:ofPlayer(player)
			if p ~= nil then
				Firing.fire(p.id, origin, dir)
			end
		end
	)
	Net.onRequest("ReloadRequest", function(player: Player)
		local p = Participants:ofPlayer(player)
		if p ~= nil then
			Firing.reload(p.id)
		end
	end)
	Net.onRequest("SwitchWeaponRequest", function(player: Player, slot: number)
		local p = Participants:ofPlayer(player)
		if p ~= nil then
			Firing.switch(p.id, slot)
		end
	end)

	Participants.Enrolled:connect(function(p: any)
		Combatants.ensure(p.id)
		Firing.sendAmmo(p.id)
	end)
	Participants.Removed:connect(function(p: any)
		Combatants.drop(p.id)
		Shells.removeOwner(p.id)
	end)
	MatchContext.MatchStarted:connect(function()
		Shells.clear()
	end)
	MatchContext.PhaseChanged:connect(function(phase: string)
		-- Late shots and unfinished reloads must not change the finished match.
		if phase == "Finished" or phase == "Results" or phase == "Resetting" then
			Shells.clear()
			for _, c in Combatants.all() do
				c.weapons:lock()
			end
		end
		if not MatchPhase.hasParticipants(phase) then
			Shells.clear()
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		Firing.step()
		Shells.step(dt)
	end)
end

return CombatSystem
