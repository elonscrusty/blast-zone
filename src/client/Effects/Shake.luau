--!strict
-- The one camera-shake meter for this player. Effects add to it by name (`Shake.add("kill")`); the
-- camera step reads it. Everything is multiplied by the player's Camera shake setting, so 0 means no
-- shake and no field-of-view kick at all.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ShakeMath = require("./ShakeMath")
local Settings = require(script.Parent.Parent.Settings.Settings)

local Shake = {}

local state = ShakeMath.new()

-- `scale` is for distance falloff (1 = full, 0 = none). A name that is not in the config adds nothing.
function Shake.add(name: string, scale: number?)
	local setting = Settings.number("cameraShake")
	local s = (scale or 1) * setting
	local trauma = (Config.Effects.trauma :: { [string]: number })[name]
	if trauma ~= nil then
		ShakeMath.addTrauma(state, trauma, s)
	end
	local fov = (Config.Effects.fovKick :: { [string]: number })[name]
	if fov ~= nil then
		ShakeMath.addFov(state, fov, s, Config.Effects.fovKick.maxDegrees)
	end
end

-- For a world event (a blast): full shake when it is near you, none when it is far. Distance is measured
-- on the ground from your character, or from where the camera looks when you have none.
function Shake.addAt(name: string, at: Vector3)
	local fall = Config.Effects.falloff
	local from: Vector3? = nil
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root ~= nil and root:IsA("BasePart") then
		from = root.Position
	elseif workspace.CurrentCamera ~= nil then
		from = workspace.CurrentCamera.Focus.Position
	end
	if from == nil then
		return
	end
	local flat = Vector3.new(from.X - at.X, 0, from.Z - at.Z)
	Shake.add(name, ShakeMath.distanceScale(flat.Magnitude, fall.fullStuds, fall.noneStuds))
end

-- Called once per frame by CameraShakeSystem: moves the meter along and gives back the camera nudge.
function Shake.step(dt: number, now: number): (number, number, number, number)
	ShakeMath.step(
		state,
		dt,
		Config.Effects.shake.decayPerSecond,
		Config.Effects.fovKick.decayPerSecond
	)
	local x, y, roll = ShakeMath.sample(state, now, Config.Effects.shake)
	return x, y, roll, state.fov
end

function Shake.reset()
	state.trauma = 0
	state.fov = 0
end

return Shake
