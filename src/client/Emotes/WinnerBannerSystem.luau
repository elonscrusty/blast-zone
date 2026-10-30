--!strict
-- The winner pose on the results screen (piece 29). The results screen (Big Banner, piece 05) covers the world,
-- so this shows a copy of the winner's own body in a small 3D window in the free bottom-left corner, doing the
-- winner pose that player picked (A Gun to the Sky, B Fist Pump, C Arms Crossed). Cosmetic only: it reads the Results event and the winner's body, nothing more.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Look = require(script.Parent.Parent.Ui.Look)
local Emotes = require(Shared.Character.Emotes)
local MatchPhase = require(Shared.MatchPhase)
local Pose = require(Shared.Character.Pose)
local Net = require(script.Parent.Parent.Core.Net)
local CharacterRig = require(script.Parent.Parent.Character.CharacterRig)
local WinPose = require(script.Parent.WinPose)
local UiLayers = require(script.Parent.Parent.Ui.UiLayers)

local WinnerBannerSystem = {}
WinnerBannerSystem.order = 215

local tuning = Config.Emotes
local GOLD = Look.color("accent")
local NAVY = Look.color("outline")
local WHITE = Look.color("panel")

local function findBody(participantId: string): Model?
	for _, d in Workspace:GetDescendants() do
		if
			d:IsA("Model")
			and d:GetAttribute(Config.Attributes.ParticipantId) == participantId
			and d:FindFirstChildOfClass("Humanoid") ~= nil
		then
			return d
		end
	end
	return nil
end

-- A still copy of a body: no scripts, no sounds, nothing that moves by itself.
local function copyOf(model: Model): Model?
	local was = model.Archivable
	model.Archivable = true
	local ok, cloned = pcall(function(): Model?
		return model:Clone()
	end)
	model.Archivable = was
	local copy: Model? = if ok then cloned else nil
	if copy == nil then
		return nil
	end
	for _, d in copy:GetDescendants() do
		if
			d:IsA("Script")
			or d:IsA("LocalScript")
			or d:IsA("Sound")
			or d:IsA("ParticleEmitter")
		then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
		end
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	return copy
end

function WinnerBannerSystem.start()
	if not tuning.bannerWinner then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "WinnerPose"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = UiLayers.MatchFlowExtra -- above the results screen; the claim strip shares the layer in its own band
	gui.Enabled = false

	-- Bottom-left corner: the results column ends at y 74% and the claim strip spans x 18-82%, so this is free.
	local frame = Instance.new("ViewportFrame")
	frame.Name = "Winner"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.fromScale(0.01, 0.985)
	frame.Size = UDim2.fromScale(0.16, 0.25)
	frame.BackgroundColor3 = GOLD
	frame.BackgroundTransparency = 0
	frame.Ambient = Color3.fromHSV(0, 0, 0.667)
	frame.LightColor = Color3.fromHSV(0, 0, 1)
	frame.LightDirection = Vector3.new(-1, -2, -1)
	frame.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 0.8
	aspect.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = WHITE
	edge.Thickness = 4
	edge.Parent = frame

	local tag = Instance.new("TextLabel")
	tag.Name = "Tag"
	tag.AnchorPoint = Vector2.new(0.5, 0.5)
	tag.Position = UDim2.fromScale(0.5, 0)
	tag.Size = UDim2.fromScale(0.86, 0.16)
	tag.Rotation = -3
	tag.BackgroundColor3 = NAVY
	tag.TextColor3 = GOLD
	tag.Font = Look.font("display")
	tag.TextScaled = true
	tag.Text = "WINNER"
	tag.ZIndex = 2
	tag.Parent = frame

	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = frame
	frame.CurrentCamera = camera

	local world: WorldModel? = nil
	local joints: CharacterRig.Joints? = nil
	local pose = Pose.zero()
	local shownFor: number? = nil -- matchId on show
	local startedAt = 0
	local winSet = "A"

	local function hide()
		gui.Enabled = false
		shownFor = nil
		joints = nil
		if world ~= nil then
			world:Destroy()
			world = nil
		end
	end

	local function show(matchId: number, winnerId: string)
		hide()
		local body = findBody(winnerId)
		local copy = if body ~= nil then copyOf(body) else nil
		if copy == nil then
			return
		end
		local w = Instance.new("WorldModel")
		w.Parent = frame
		copy:PivotTo(CFrame.new())
		copy.Parent = w
		world = w
		joints = CharacterRig.find(copy)
		-- Frame the whole body from the front (bodies face -Z), a little from the side and above.
		local box, size = copy:GetBoundingBox()
		local height = math.max(size.Y, 4)
		local distance = (height * 0.62) / math.tan(math.rad(camera.FieldOfView / 2))
		local centre = box.Position + Vector3.new(0, height * 0.12, 0)
		camera.CFrame =
			CFrame.lookAt(centre + Vector3.new(distance * 0.35, height * 0.15, -distance), centre)
		pose = Pose.zero()
		startedAt = os.clock()
		shownFor = matchId
		winSet = WinPose.of(winnerId)
		gui.Enabled = true
	end

	Net.on("Results", function(p: any)
		if type(p) ~= "table" or type(p.matchId) ~= "number" then
			return
		end
		if type(p.winnerId) == "string" and p.draw ~= true and p.outcome ~= "abandoned" then
			show(p.matchId, p.winnerId)
		else
			hide()
		end
	end)
	Net.on("MatchState", function(p: any)
		if type(p) ~= "table" then
			return
		end
		local stays = (p.phase == MatchPhase.Finished or p.phase == MatchPhase.Results)
			and p.matchId == shownFor
		if shownFor ~= nil and not stays then
			hide()
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local j = joints
		if j == nil or not gui.Enabled then
			return
		end
		local target = Emotes.win(winSet, os.clock() - startedAt)
		Pose.blend(pose, target, dt, Config.Character.smoothing)
		CharacterRig.apply(j, pose)
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return WinnerBannerSystem
