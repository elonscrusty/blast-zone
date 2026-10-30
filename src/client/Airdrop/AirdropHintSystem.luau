--!strict
-- A small strip while an airdrop is on its way or shut: the words, seconds until it lands, an arrow and
-- how far away it is. Logic only: the look comes from Ui/Components and Ui/Tokens (Claude Design owns
-- it), the layer from UiLayers. Takes no taps. The drop itself is AirdropClientSystem's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AirdropRules = require(Shared.Airdrop.AirdropRules)
local Config = require(Shared.Config)

local AirdropClient = require(script.Parent.AirdropClient)
local Components = require(script.Parent.Parent.Ui.Components)

local AirdropHintSystem = {}
AirdropHintSystem.order = 330

local cfg = Config.Airdrop

local gui: ScreenGui? = nil
local label: TextLabel? = nil
local since = 0

local function ensure(): (ScreenGui, TextLabel)
	if gui ~= nil and label ~= nil and gui.Parent ~= nil then
		return gui, label
	end
	local screen, root = Components.screen("AirdropHint", "Moments")
	screen.Enabled = false
	local text = Components.text(root, root, "Hint", "title", {
		color = "accent",
		anchor = Vector2.new(0.5, 0),
		position = UDim2.fromScale(0.5, 0.2),
		size = UDim2.fromScale(0.6, 0.05),
	})
	gui, label = screen, text
	return screen, text
end

local function flatLook(): (number, number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return 0, 0
	end
	local look = camera.CFrame.LookVector
	return look.X, look.Z
end

local function bodyPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root ~= nil and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function refresh()
	local drop = AirdropClient.nextToOpen()
	if drop == nil then
		if gui ~= nil then
			gui.Enabled = false
		end
		return
	end
	local screen, text = ensure()
	local now = Workspace:GetServerTimeNow()
	local words = cfg.hintText
	local line: string
	if AirdropRules.stage(now, drop.landsAt, drop.opensAt) == "falling" then
		line = `{words.incoming} {math.max(0, math.ceil(drop.landsAt - now))}`
	else
		line = words.landed
	end
	local at = bodyPosition()
	if at ~= nil then
		local lx, lz = flatLook()
		local dx, dz = drop.pos.X - at.X, drop.pos.Z - at.Z
		local arrow = AirdropRules.arrow(dx, dz, lx, lz)
		line ..= ` {arrow} {AirdropRules.distanceText(math.sqrt(dx * dx + dz * dz))}`
	end
	text.Text = line
	screen.Enabled = true
end

function AirdropHintSystem.start()
	if not cfg.enabled then
		return
	end
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since >= cfg.hintRefreshSeconds then
			since = 0
			refresh()
		end
	end)
end

return AirdropHintSystem
