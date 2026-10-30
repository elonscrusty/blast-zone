--!strict
-- The elevated, angled camera. It follows the player from a fixed heading (it never turns during
-- play), glides with a very short delay, and pulls back a little on narrow screens so a phone held
-- upright still shows threats at the sides. Spectating: piece 05 sets the LocalPlayer attribute
-- SpectateTargetId (and points Camera.CameraSubject there); this camera follows either.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local CameraRules = require(Shared.Movement.CameraRules)

local CameraSystem = {}
CameraSystem.order = 50

local BIND_NAME = "BlastZoneCamera"
local player = Players.LocalPlayer

local focus: Vector3? = nil
local lastRoot: BasePart? = nil
local lastFrame = os.clock()

-- Only bodies still in the world: a respawn leaves the old character (and a stale CameraSubject) behind.
local function rootOfModel(model: Instance?): BasePart?
	local root = if model then model:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") and root:IsDescendantOf(workspace) then
		return root
	end
	return nil
end

-- The body of a participant by id: a player's character, or a bot's model.
local function characterOf(id: string): Model?
	local userId = Ids.userIdOf(id)
	if userId then
		local other = Players:GetPlayerByUserId(userId)
		return if other then other.Character else nil
	end
	for _, inst in workspace:GetChildren() do
		if inst:IsA("Model") and inst:GetAttribute(Config.Attributes.ParticipantId) == id then
			return inst
		end
	end
	return nil
end

-- Who the camera looks at: the spectate target when piece 05 names one (LocalPlayer attribute
-- SpectateTargetId), else whatever the camera subject is, else the player's own character.
local function subjectRoot(camera: Camera): BasePart?
	local spectateId = player:GetAttribute("SpectateTargetId")
	if type(spectateId) == "string" and Ids.isValid(spectateId) then
		local root = rootOfModel(characterOf(spectateId))
		if root then
			return root
		end
	end
	local subject = camera.CameraSubject
	if subject and subject:IsA("Humanoid") then
		local root = rootOfModel(subject.Parent)
		if root then
			return root
		end
	elseif subject and subject:IsA("BasePart") and subject:IsDescendantOf(workspace) then
		return subject
	end
	return rootOfModel(player.Character)
end

local function step()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local now = os.clock()
	local dt = math.min(now - lastFrame, 0.1)
	lastFrame = now

	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	camera.FieldOfView = Config.Camera.fieldOfView

	local root = subjectRoot(camera)
	if root == nil then
		return
	end
	local target = root.Position
	local cfg = Config.Camera
	-- Jump straight there for a new subject (respawn, spectate swap) or a long hop (teleport).
	if focus == nil or root ~= lastRoot or (target - focus).Magnitude > cfg.snapDistance then
		focus = target
	else
		focus = focus:Lerp(target, CameraRules.followAlpha(dt, cfg.followSmoothingSeconds))
	end
	lastRoot = root

	local spectating = type(player:GetAttribute("SpectateTargetId")) == "string"
	local pitch, baseDistance = CameraRules.viewFor(cfg, Config.Spectate, spectating)
	local view = camera.ViewportSize
	local aspect = if view.Y > 0 then view.X / view.Y else 1.78
	local distance = CameraRules.distanceForAspect(
		baseDistance,
		aspect,
		cfg.narrowAspect,
		cfg.narrowAspectFloor,
		cfg.maxWiden
	)
	local dx, dy, dz = CameraRules.offset(pitch, distance, cfg.yawDegrees)
	local at = focus :: Vector3
	camera.CFrame = CFrame.lookAt(at + Vector3.new(dx, dy, dz), at)
	camera.Focus = CFrame.new(at) -- roof fading reads the focus to know which building we are in
end

function CameraSystem.start()
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraSystem
