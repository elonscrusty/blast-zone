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
local Components = require(script.Parent.Parent.Ui.Components)
local ScreenMap = require(script.Parent.Parent.Ui.ScreenMap)

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

-- Bottom centre bar (design phone 780 x 360): [<]  WATCHING name  [>]. Only shown once you are out.

local function makeButton(parent: Instance, root: GuiObject, text: string, step: number)
	local button =
		Components.button(parent, root, if step < 0 then "SpectatePrev" else "SpectateNext", {
			text = text,
			style = "primary",
		})
	button.AnchorPoint = Vector2.new(if step < 0 then 0 else 1, 0.5)
	button.Position = UDim2.fromScale(if step < 0 then 0.02 else 0.98, 0.5)
	button.Size = UDim2.fromScale(0.2, 0.86)
	button.Activated:Connect(function()
		Net.send("SpectateCycle", step)
	end)
end

function SpectateClientSystem.start()
	local screen, root = Components.screen("Spectate", "Spectate")
	screen.Enabled = false

	local piece = Components.piece(root, "Bar", ScreenMap.spectate)
	local panel = Components.panel(piece, root, "Panel", "panel")
	panel.Size = UDim2.fromScale(1, 1)
	makeButton(panel, root, "<", -1)
	makeButton(panel, root, ">", 1)
	local label = Components.text(panel, root, "SpectateName", "body", {
		size = UDim2.fromScale(0.52, 0.7),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})

	Net.on("SpectateTarget", function(payload: { participantId: string?, name: string? })
		targetId = payload.participantId
		label.Text = if payload.name then `Watching {payload.name}` else ""
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
