--!strict
-- Draws the safe zone for this player: the world ring (Neon Wall), and the red edges plus an
-- arrow when standing outside. Warning text and the timer chip are piece 10's HUD. It only reads
-- what the server sent (ZoneState) and the match phase (MatchState); the server alone decides damage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchPhase = require(Shared.MatchPhase)

local Net = require(script.Parent.Parent.Core.Net)
local ZoneBoundary = require(script.Parent.ZoneBoundary)
local ZoneHud = require(script.Parent.ZoneHud)
local ZoneView = require(script.Parent.ZoneView)

local ZoneClientSystem = {}
ZoneClientSystem.order = 200

local GROUND_Y = 0 -- floor height; the arena builder (piece 04) keeps the floor top at 0

local function localRoot(): (BasePart?, boolean)
	local character = Players.LocalPlayer.Character
	-- A lobby body (out of the match, watching someone) is not in the fight: no red edges for it.
	if character == nil or character:GetAttribute(Config.Attributes.ParticipantId) == nil then
		return nil, false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0
	if root ~= nil and root:IsA("BasePart") then
		return root, alive
	end
	return nil, false
end

function ZoneClientSystem.start()
	local boundary = ZoneBoundary.new()
	local hud = ZoneHud.new()

	Net.on("ZoneState", function(state)
		ZoneView.setState(state)
	end)
	Net.on("MatchState", function(state)
		ZoneView.setLive(MatchPhase.isCombat(state.phase), state.matchId)
	end)
	Net.send("ZoneStateRequest") -- we may have joined mid-match

	RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		local view = ZoneView.get(now)
		if view == nil then
			boundary:hide()
			hud:setVisible(false)
			return
		end
		hud:setVisible(true)
		boundary:update(
			view.centerX,
			view.centerZ,
			GROUND_Y,
			view.radius,
			view.targetRadius,
			view.phase == "Warning",
			now
		)

		local root, alive = localRoot()
		local outside = false
		local heading = 0
		if root ~= nil and alive then
			local pos = root.Position
			outside = view.damagePerSecond > 0 and not ZoneView.isInside(view, pos.X, pos.Z)
			if outside then
				-- angle from the way the camera looks to the direction of the circle centre
				local camera = workspace.CurrentCamera
				local look = camera.CFrame.LookVector
				local right = camera.CFrame.RightVector
				local toX, toZ = view.centerX - pos.X, view.centerZ - pos.Z
				local forward = look.X * toX + look.Z * toZ
				local side = right.X * toX + right.Z * toZ
				heading = math.deg(math.atan2(side, forward))
			end
		end
		hud:setOutside(outside, heading, now)
	end)
end

return ZoneClientSystem
