--!strict
-- The player's side of combat: reads the controls piece's aim and fire state, asks the server to fire,
-- turns the body toward the aim, and draws what the server reports (tracers, blasts, damage numbers).
-- The client only asks. Reload and weapon switching are sent by the controls piece itself.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Parent.Core.Net)
local CombatFx = require("./CombatFx")
local CosmeticLook = require(script.Parent.Parent.Progression.CosmeticLook)
local Fx = require(script.Parent.Parent.Effects.Fx)
local GunModels = require("./GunModels")
local HealthBars = require("./HealthBars")
local Shake = require(script.Parent.Parent.Effects.Shake)

local CombatClientSystem = {}
CombatClientSystem.order = 120

local firearm = Config.Weapons.Firearm
local explosive = Config.Weapons.Explosive
local localPlayer = Players.LocalPlayer

type Controls = {
	isFiring: () -> boolean,
	getAimWorld: () -> Vector3?, -- unit direction on the ground, nil when there is no aim input
}

-- What the server last told us about our weapons.
local slot = 1
local ammo = firearm.magazine
local reloadEndsAt: number? = nil

local seq = 0
local nextSendAt = 0
local lastDir: Vector3? = nil
local lastAimAt = 0
local controls: Controls? = nil
local lastPhase = ""
local combatLive = true -- until the match piece says otherwise (lobby and results are not combat)

local function root(): BasePart?
	local ch = localPlayer.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	if r ~= nil and r:IsA("BasePart") then
		return r
	end
	return nil
end

local function isMine(shooterId: string?): boolean
	return shooterId ~= nil and shooterId == ("p" .. tostring(localPlayer.UserId))
end

-- Where we are aiming right now, or the last aim we had (so a tap still shoots somewhere sensible).
local function currentDir(): Vector3?
	local c = controls
	if c ~= nil then
		local aim = c.getAimWorld()
		if aim ~= nil then
			local flat = Vector3.new(aim.X, 0, aim.Z)
			if flat.Magnitude > 0.1 then
				lastDir = flat.Unit
				lastAimAt = os.clock()
				return lastDir
			end
		end
	end
	if lastDir ~= nil then
		return lastDir
	end
	local r = root()
	if r ~= nil then
		local look = r.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.1 then
			return flat.Unit
		end
	end
	return nil
end

local function intervalOf(s: number): number
	return if s == 2 then explosive.fireInterval else firearm.fireInterval
end

local function canSend(now: number): boolean
	if now < nextSendAt then
		return false
	end
	if reloadEndsAt ~= nil and workspace:GetServerTimeNow() < reloadEndsAt then
		return false
	end
	return true
end

local function trySend(dir: Vector3)
	local r = root()
	if
		r == nil
		or not combatLive
		or r:GetAttribute("Alive") == false
		or (r.Parent ~= nil and r.Parent:GetAttribute("Alive") == false)
	then
		return
	end
	local now = os.clock()
	if not canSend(now) then
		return
	end
	nextSendAt = now + intervalOf(slot)
	seq += 1
	local origin = r.Position + Vector3.new(0, Config.Combat.shotHeight, 0)
	Net.send("FireRequest", origin, dir, seq)
	-- Instant feedback; the server's answer (ammo, tracer, hit) follows.
	CombatFx.muzzleFlash(origin + dir * firearm.muzzleOffset, dir, true)
	ammo = math.max(0, ammo - 1)
end

-- Turn the body toward the aim without taking over movement: a torque-only constraint, no CFrame writes.
local function setupFacing(character: Model)
	local r = character:WaitForChild("HumanoidRootPart", 5)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if r == nil or not r:IsA("BasePart") then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "CombatAimAttachment"
	att.Parent = r
	local align = Instance.new("AlignOrientation")
	align.Name = "CombatAim"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.MaxTorque = 100000
	align.Responsiveness = 50
	align.Enabled = false
	align.Parent = r
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if align.Parent == nil then
			conn:Disconnect()
			return
		end
		local dir = lastDir
		local aiming = dir ~= nil and os.clock() - lastAimAt < 0.6
		if aiming and dir ~= nil then
			align.CFrame = CFrame.lookAt(Vector3.zero, dir)
			if humanoid ~= nil then
				humanoid.AutoRotate = false
			end
		elseif humanoid ~= nil then
			humanoid.AutoRotate = true
		end
		align.Enabled = aiming
	end)
end

function CombatClientSystem.start()
	task.spawn(function()
		local folder = script.Parent.Parent:WaitForChild("Controls", 15)
		local module = folder and folder:WaitForChild("Controls", 15)
		if module ~= nil and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok then
				controls = result
			else
				warn("[Combat] could not load Controls: " .. tostring(result))
			end
		else
			warn("[Combat] Controls not found: aiming and firing are off")
		end
	end)

	HealthBars.start()
	GunModels.start()

	RunService.RenderStepped:Connect(function()
		local c = controls
		local dir = currentDir()
		if c ~= nil and dir ~= nil and c.isFiring() then
			trySend(dir)
		end
	end)

	if localPlayer.Character ~= nil then
		task.spawn(setupFacing, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(function(character)
		task.spawn(setupFacing, character)
	end)

	Net.on("MatchState", function(m: any)
		combatLive = m.phase == "Active" or m.phase == "FinalPressure"
		-- A new round starts clean: no old rings, numbers or shells left over.
		if m.phase ~= lastPhase and (m.phase == "Waiting" or m.phase == "Countdown") then
			CombatFx.clear()
		end
		lastPhase = m.phase
	end)

	Net.on("AmmoState", function(s: any)
		slot = s.slot
		ammo = s.ammo
		reloadEndsAt = s.reloadEndsAt
	end)

	Net.on("ShotFx", function(s: any)
		local mortar = s.weaponId == explosive.id
		if mortar then
			CombatFx.shell(s.shooterId, s.origin, s.endPos, explosive.projectileSpeed)
		else
			CombatFx.tracer(s.origin, s.endPos, CosmeticLook.tracerColor(s.shooterId))
			if s.hitKind ~= "none" then
				local travel = s.endPos - s.origin
				local dir = if travel.Magnitude > 0.01 then travel.Unit else nil
				CombatFx.impact(s.endPos, s.hitKind, dir, false)
			end
		end
		if not isMine(s.shooterId) and not mortar then
			local aim = s.endPos - s.origin
			if aim.Magnitude > 0.01 then
				CombatFx.muzzleFlash(s.origin, aim.Unit, false)
			end
		end
	end)

	Net.on("ExplosionFx", function(e: any)
		if e.warnEndsAt ~= nil then
			local left = math.max(0, e.warnEndsAt - workspace:GetServerTimeNow())
			CombatFx.warnRing(e.shooterId or "?", e.pos, e.radius, left)
		else
			CombatFx.burst(e.shooterId, e.pos, e.radius)
		end
	end)

	Net.on("HitConfirm", function(h: any)
		local model = if typeof(h.targetId) == "string" then HealthBars.modelOf(h.targetId) else nil
		if model ~= nil then
			Fx.hitFlash(model)
		end
		if typeof(h.pos) == "Vector3" then
			CombatFx.damageNumber(h.pos, h.amount, h.killed, false)
			if h.amount >= Config.Effects.numbers.bigAmount and not h.killed then
				CombatFx.impact(h.pos, "target", nil, true)
			end
			if h.killed then
				Fx.kill(h.pos, true)
			end
		end
	end)

	Net.on("DamageTaken", function(d: any)
		local r = root()
		if r ~= nil then
			CombatFx.damageNumber(r.Position, d.amount, false, true)
		end
		Shake.add("hurt")
	end)
end

return CombatClientSystem
