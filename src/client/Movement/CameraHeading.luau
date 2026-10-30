--!strict
-- Which way the camera is turned right now (degrees; see CameraRules.offset). CameraSystem turns
-- it from the player's input; walking, sliding and the minimap read it so "up the screen" always
-- means the way the camera looks. It starts at Config.Camera.yawDegrees.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CameraRules = require(Shared.Movement.CameraRules)

local CameraHeading = {}

local yaw = Config.Camera.yawDegrees

function CameraHeading.get(): number
	return yaw
end

-- Turn the view to the right by `degrees` (negative = left).
function CameraHeading.turnRight(degrees: number)
	yaw = CameraRules.turnedYaw(yaw, degrees)
end

-- Back to the starting heading.
function CameraHeading.reset()
	yaw = Config.Camera.yawDegrees
end

return CameraHeading
