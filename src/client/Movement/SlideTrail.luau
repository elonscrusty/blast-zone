--!strict
-- The slide's streak: a short cyan trail behind the body while it slides, plus dust puffs and white
-- speed lines from Effects/Fx. Cosmetic only. At most one trail per character, and it cleans itself up
-- (and goes away with the character).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CosmeticLook = require(script.Parent.Parent.Progression.CosmeticLook)
local Fx = require(script.Parent.Parent.Effects.Fx)

local SlideTrail = {}

local NAME = "BlastZoneSlideTrail"

function SlideTrail.play(character: Model, duration: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local old = root:FindFirstChild(NAME)
	if old then
		old:Destroy()
	end

	local holder = Instance.new("Folder")
	holder.Name = NAME
	holder.Parent = root

	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 1.4, 0)
	top.Parent = holder
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -2.2, 0)
	bottom.Parent = holder

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = Config.Slide.trailFadeSeconds
	trail.Color = ColorSequence.new(CosmeticLook.trailColor(character)) -- the owner's chosen trail (piece 18)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.LightEmission = 0.5
	trail.FaceCamera = true
	trail.Parent = holder

	task.delay(duration, function()
		trail.Enabled = false -- stops growing, the tail fades on its own
	end)
	Debris:AddItem(holder, duration + Config.Slide.trailFadeSeconds + 0.2)
	Fx.slide(character, duration, character == Players.LocalPlayer.Character)
end

return SlideTrail
