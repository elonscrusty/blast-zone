--!strict
-- Camera shake and nudges. The default camera script rebuilds the camera CFrame every frame, so a
-- small OFFSET applied right after it (BindToRenderStep just after the Camera priority) never builds
-- up. Respects settings.shake (off = nothing moves).
--
--   CameraFx.shake(strength, duration)   a decaying shake. strength ~0.2 small .. 1 big
--   CameraFx.nudge(strength)             a tiny downward kick that settles in ~0.15 s (a sweep swing)
--   CameraFx.setRumble(strength, secs?)  a steady low rumble (0 stops it); stops by itself after secs
--                                        (default 12) in case the stop message is lost

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoreLogic = require(Shared.Client.StoreLogic)
local Store = require(script.Parent.Store)

local CameraFx = {}

local MAX_SHAKES = 8
local MAX_OFFSET = 1.2 -- studs, whatever stacks up
local METRES = 0.55 -- studs of sideways movement at strength 1
local ROLL_DEG = 0.7 -- degrees of roll at strength 1
local KICK_DECAY = 16 -- per second

type Shake = { strength: number, duration: number, t: number, seed: number }

local shakes: { Shake } = {}
local kick = 0
local rumble = 0
local rumbleUntil = 0
local seedCounter = 0

local function enabled(): boolean
	return StoreLogic.setting(Store.view(), "shake", true)
end

function CameraFx.shake(strength: number, duration: number)
	if not enabled() or strength ~= strength or duration ~= duration then
		return
	end
	local s = math.clamp(strength, 0, 2)
	local d = math.clamp(duration, 0.05, 6)
	if s <= 0 then
		return
	end
	seedCounter += 1
	if #shakes >= MAX_SHAKES then
		table.remove(shakes, 1)
	end
	table.insert(shakes, { strength = s, duration = d, t = 0, seed = seedCounter * 17.31 })
end

function CameraFx.nudge(strength: number)
	if not enabled() or strength ~= strength then
		return
	end
	kick = math.min(kick + math.clamp(strength, 0, 1) * 0.35, 0.5)
end

function CameraFx.setRumble(strength: number, seconds: number?)
	if strength ~= strength or strength <= 0 then
		rumble = 0
		return
	end
	rumble = math.clamp(strength, 0, 1)
	rumbleUntil = os.clock() + math.clamp(seconds or 12, 0.1, 30)
end

local clock = 0

local function onStep(dt: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	clock += dt
	if rumble > 0 and os.clock() > rumbleUntil then
		rumble = 0
	end
	if #shakes == 0 and kick < 0.001 and rumble <= 0 then
		return
	end
	if not enabled() then
		table.clear(shakes)
		kick = 0
		return
	end

	local ox, oy, roll = 0.0, 0.0, 0.0
	local i = 1
	while i <= #shakes do
		local s = shakes[i]
		s.t += dt
		if s.t >= s.duration then
			table.remove(shakes, i)
		else
			local fade = 1 - s.t / s.duration
			local amp = s.strength * fade * fade
			local f = clock * 24
			ox += math.noise(f, s.seed, 0.5) * 2 * amp * METRES
			oy += math.noise(s.seed, f, 1.5) * 2 * amp * METRES
			roll += math.noise(f, 3.5, s.seed) * 2 * amp * ROLL_DEG
			i += 1
		end
	end
	if rumble > 0 then
		local f = clock * 30
		ox += math.noise(f, 7.1, 0.3) * 2 * rumble * METRES * 0.5
		oy += math.noise(9.7, f, 0.3) * 2 * rumble * METRES * 0.5
	end
	if kick >= 0.001 then
		oy -= kick
		kick *= math.exp(-KICK_DECAY * dt)
	else
		kick = 0
	end

	ox = math.clamp(ox, -MAX_OFFSET, MAX_OFFSET)
	oy = math.clamp(oy, -MAX_OFFSET, MAX_OFFSET)
	camera.CFrame = camera.CFrame * CFrame.new(ox, oy, 0) * CFrame.Angles(0, 0, math.rad(roll))
end

RunService:BindToRenderStep("VSCameraFx", Enum.RenderPriority.Camera.Value + 1, onStep)

return CameraFx
