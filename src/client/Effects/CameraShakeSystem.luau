--!strict
-- Applies the shake meter to the camera. It runs just after the game camera has placed itself for the
-- frame (CameraSystem sets the whole CFrame every frame, so this never builds up).

local RunService = game:GetService("RunService")

local Shake = require("./Shake")

local CameraShakeSystem = {}
CameraShakeSystem.order = 60 -- after the camera (order 50)

local BIND_NAME = "BlastZoneCameraShake"

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local x, y, roll, fov = Shake.step(dt, os.clock())
	if x == 0 and y == 0 and roll == 0 and fov == 0 then
		return
	end
	camera.CFrame = camera.CFrame * CFrame.new(x, y, 0) * CFrame.Angles(0, 0, math.rad(roll))
	camera.FieldOfView += fov
end

function CameraShakeSystem.start()
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, step)
end

return CameraShakeSystem
