--!strict
-- Humanoid settings for the combat design: set speed, no jumping, no climbing, no turning by
-- walking (the body turns toward the aim instead).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MoveRules = require(Shared.Movement.MoveRules)

local MovementSetup = {}

local OFF_STATES = {
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
}

function MovementSetup.apply(humanoid: Humanoid, moveSpeed: number)
	local cfg = Config.Movement
	humanoid.WalkSpeed =
		MoveRules.clampSpeed(moveSpeed, cfg.walkSpeed, cfg.maxSpeedUpgradeMultiplier)
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
	humanoid.WalkSpeed =
		MoveRules.clampSpeed(moveSpeed, cfg.walkSpeed, cfg.maxSpeedUpgradeMultiplier)
end

return MovementSetup
