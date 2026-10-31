--!strict
-- Humanoid settings for the combat design: set speed, no jumping, no climbing, no turning by
-- walking (the body turns toward the aim instead).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MoveRules = require(Shared.Movement.MoveRules)
local SprintRules = require(Shared.Movement.SprintRules)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)

local MovementSetup = {}

local OFF_STATES = {
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
}

-- Plaza walks are brisker than arena runs (see MoveRules.lobbyScale).
local function lobbyScale(): number
	local cfg = Config.Movement
	return MoveRules.lobbyScale(MatchContext:getPhase(), cfg.walkSpeed, cfg.lobbyWalkSpeed)
end

function MovementSetup.apply(humanoid: Humanoid, moveSpeed: number)
	local cfg = Config.Movement
	local k = lobbyScale()
	humanoid.WalkSpeed =
		MoveRules.clampSpeed(moveSpeed * k, cfg.walkSpeed * k, cfg.maxSpeedUpgradeMultiplier)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoJumpEnabled = false
	humanoid.AutoRotate = false
	humanoid.MaxSlopeAngle = cfg.maxSlopeAngle
	for _, state in OFF_STATES do
		pcall(function()
			humanoid:SetStateEnabled(state, false)
		end)
	end
end

-- Only the speed: used when an upgrade changes it mid-match.
function MovementSetup.setSpeed(humanoid: Humanoid, moveSpeed: number)
	local cfg = Config.Movement
	local k = lobbyScale()
	humanoid.WalkSpeed =
		MoveRules.clampSpeed(moveSpeed * k, cfg.walkSpeed * k, cfg.maxSpeedUpgradeMultiplier)
end

-- Speed for this moment: the upgraded run speed, times the sprint boost while sprinting (piece 45).
-- The sprint boost has its own hard cap so upgrade stacks cannot push it past it.
function MovementSetup.setSprintSpeed(humanoid: Humanoid, moveSpeed: number, running: boolean)
	local cfg = Config.Movement
	local normal = MoveRules.clampSpeed(moveSpeed, cfg.walkSpeed, cfg.maxSpeedUpgradeMultiplier)
	local cap = cfg.walkSpeed * cfg.maxSpeedUpgradeMultiplier * Config.Sprint.speedMultiplier
	humanoid.WalkSpeed = SprintRules.speed(normal, running, Config.Sprint.speedMultiplier, cap)
end

return MovementSetup
