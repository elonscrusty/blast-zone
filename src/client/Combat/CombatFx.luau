--!strict
-- What shots and blasts look like. Cosmetic only: nothing here decides a hit. The looks themselves
-- (stars, clouds, confetti, rings, numbers, streaks) live in Effects/Fx, which pools and caps them;
-- this file is the combat side of that, plus the mortar shell in the air.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Fx = require(script.Parent.Parent.Effects.Fx)

local GOLD = Color3.fromHex(Config.Palette.RewardGold)

local CombatFx = {}

local shells: { [string]: BasePart? } = {}

local function newShell(at: Vector3): BasePart
	local folder = Workspace:FindFirstChild(Config.Workspace.EffectsFolder) or Workspace
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = GOLD
	p.Size =
		Vector3.new(Config.Effects.shellStuds, Config.Effects.shellStuds, Config.Effects.shellStuds)
	p.CFrame = CFrame.new(at)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = folder
	return p
end

-- The streak a shot draws from the barrel to where it ended. shooterColor: their chosen shot look (piece 18).
function CombatFx.tracer(from: Vector3, to: Vector3, weaponId: string, shooterColor: Color3?)
	-- Shape tells the guns apart: thin shotgun pellets, a thick rifle line, the rest in between.
	local widthScale = if weaponId == "longline"
		then 1.7
		elseif weaponId == "breaker" or weaponId == "hornet" then 0.65
		else 1
	Fx.tracer(from, to, shooterColor, widthScale)
end

-- `mine` is a shot you fired yourself (the camera gives it a tiny kick).
function CombatFx.muzzleFlash(at: Vector3, dir: Vector3, mine: boolean)
	Fx.muzzle(at, dir, mine)
end

-- Where a shot ended. `hitKind` is what the server says it hit: "target", "wall", "container" or "none".
function CombatFx.impact(at: Vector3, hitKind: string, travelDir: Vector3?, big: boolean)
	Fx.impact(at, travelDir, hitKind, big)
end

-- A floating "-10". Capped and pooled by Fx: the oldest number goes first.
function CombatFx.damageNumber(at: Vector3, amount: number, killed: boolean, mine: boolean)
	local kind = "hit"
	if mine then
		kind = "mine"
	elseif killed then
		kind = "kill"
	elseif amount >= Config.Effects.numbers.bigAmount then
		kind = "big"
	end
	local text = "-" .. tostring(math.floor(amount + 0.5))
	Fx.number(at + Vector3.new(0, 3, 0), text, kind)
end

-- A shell in the air, drawn from its start to where it is expected to land.
function CombatFx.shell(shooterId: string, from: Vector3, to: Vector3, speed: number)
	local old = shells[shooterId]
	if old ~= nil then
		old:Destroy()
	end
	local ball = newShell(from)
	shells[shooterId] = ball
	local seconds = math.max(0.05, (to - from).Magnitude / math.max(speed, 1))
	TweenService:Create(ball, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Position = to })
		:Play()
	Debris:AddItem(ball, seconds + 1.5) -- a burst on a body ends it sooner (see burst)
end

-- The warning ring: where the blast will be and how big it is.
function CombatFx.warnRing(shooterId: string, at: Vector3, radius: number, secondsToLand: number)
	Fx.blastWarn(shooterId, at, radius, secondsToLand)
end

-- The blast itself. Also removes that shooter's shell and warning ring.
function CombatFx.burst(shooterId: string?, at: Vector3, radius: number)
	if shooterId ~= nil then
		local s = shells[shooterId]
		if s ~= nil then
			s:Destroy()
			shells[shooterId] = nil
		end
		Fx.warnClear(shooterId)
	end
	Fx.blast(at, radius)
end

function CombatFx.clear()
	for _, s in shells do
		if s ~= nil then
			s:Destroy()
		end
	end
	table.clear(shells)
	Fx.clear()
end

return CombatFx
