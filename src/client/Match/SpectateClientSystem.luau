--!strict
-- Spectating on the client. The SERVER picks who you watch (MatchSystem sends SpectateTarget, and only to people
-- who are out or not playing). This file follows that target and gives two buttons (and Q / E) to cycle.
-- Other camera code can read the LocalPlayer attribute "SpectateTargetId" (nil when not spectating).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local Net = require(script.Parent.Parent.Core.Net)

local SpectateClientSystem = {}
SpectateClientSystem.order = 200

local player = Players.LocalPlayer
local targetId: string? = nil

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

local function ownHumanoid(): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function follow()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local humanoid: Humanoid? = nil
	if targetId then
		local character = characterOf(targetId)
		humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	end
	camera.CameraSubject = humanoid or ownHumanoid()
end

local function makeButton(parent: Instance, text: string, x: number, step: number)
	local button = Instance.new("TextButton")
	button.Name = if step < 0 then "SpectatePrev" else "SpectateNext"
	button.Text = text
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, x, 0, 12)
	button.Size =
		UDim2.fromOffset(Config.Settings.minTouchTarget + 16, Config.Settings.minTouchTarget)
	button.BackgroundColor3 = Color3.fromHex(Config.Palette.Navy)
	button.BackgroundTransparency = 0.15
	button.TextColor3 = Color3.fromHex(Config.Palette.Cyan)
	button.TextScaled = true
	button.Font = Enum.Font.GothamBold
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	button.Activated:Connect(function()
		Net.send("SpectateCycle", step)
	end)
end

function SpectateClientSystem.start()
	local screen = Instance.new("ScreenGui")
	screen.Name = "Spectate"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")
	makeButton(screen, "<", -48, -1)
	makeButton(screen, ">", 48, 1)

	Net.on("SpectateTarget", function(payload: { participantId: string? })
		targetId = payload.participantId
		player:SetAttribute("SpectateTargetId", targetId)
		screen.Enabled = targetId ~= nil
		follow()
	end)

	-- The target's character can appear late or be replaced, so keep checking while spectating.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if targetId then
				follow()
			end
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or targetId == nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q then
			Net.send("SpectateCycle", -1)
		elseif input.KeyCode == Enum.KeyCode.E then
			Net.send("SpectateCycle", 1)
		end
	end)
end

return SpectateClientSystem
