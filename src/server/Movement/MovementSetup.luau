--!strict
-- Humanoid settings for the combat design: set speed, no jumping, no climbing, no turning by
-- walking (the body turns toward the aim instead).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local LobbyLayout = require(Shared.LobbyLayout)
local MoveRules = require(Shared.Movement.MoveRules)

local MovementSetup = {}

local OFF_STATES = {
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
}

-- The plaza between matches is walked faster than the arena (see MoveRules.walkSpeed). Whether a body is on
-- the plaza is decided by where it stands, so it is right in every phase (wait, countdown, reset, a late join).
local PLAZA_SLACK = 12 -- studs of margin around the plaza

local function inPlaza(humanoid: Humanoid): boolean
	local root = humanoid.RootPart
	if root == nil then
		return false
	end
	return LobbyLayout.contains(root.Position.X, root.Position.Z, PLAZA_SLACK)
end

function MovementSetup.apply(humanoid: Humanoid, moveSpeed: number)
	local cfg = Config.Movement
	humanoid.WalkSpeed = MoveRules.walkSpeed(inPlaza(humanoid), moveSpeed, cfg)
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
	humanoid.WalkSpeed = MoveRules.walkSpeed(inPlaza(humanoid), moveSpeed, Config.Movement)
end

-- Speed for this moment: the upgraded run speed, times the sprint boost while sprinting (piece 45).
-- The sprint boost has its own hard cap so upgrade stacks cannot push it past it. The sprint tick runs for
-- everyone every step (also on the plaza), so it uses the same plaza rule as apply and setSpeed.
function MovementSetup.setSprintSpeed(humanoid: Humanoid, moveSpeed: number, running: boolean)
	humanoid.WalkSpeed = MoveRules.sprintWalkSpeed(
		inPlaza(humanoid),
		moveSpeed,
		running,
		Config.Movement,
		Config.Sprint.speedMultiplier
	)
end

return MovementSetup
