--!strict
-- Gets every fighter's body ready: dressed in its look, no Roblox walk cycle, and a defeated fighter stays
-- in one piece (the death pose is drawn on the client) instead of falling apart.
-- Players and bots are found the same way: a Model with a ParticipantId attribute and a Humanoid.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local CharacterStyler = require(script.Parent.CharacterStyler)

local CharacterSetupSystem = {}
CharacterSetupSystem.order = 90

local prepared: { [Model]: boolean } = {}

local function prepare(model: Model)
	if prepared[model] then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	prepared[model] = true
	humanoid.BreakJointsOnDeath = false
	humanoid.Died:Connect(function()
		-- Held still where it fell; the client draws the fall.
		local root = model:FindFirstChild("HumanoidRootPart")
		if root ~= nil and root:IsA("BasePart") then
			root.Anchored = true
		end
	end)
	-- The stock walk/idle script would fight the drawn poses.
	local animate = model:FindFirstChild("Animate")
	if animate ~= nil then
		animate:Destroy()
	end
	CharacterStyler.apply(model)
	local player = Players:GetPlayerFromCharacter(model)
	if player ~= nil then
		-- The player's own avatar finishes loading after the body appears; dress it again over that.
		player.CharacterAppearanceLoaded:Connect(function(character: Model)
			if character == model then
				CharacterStyler.apply(model)
			end
		end)
	end
	model.AncestryChanged:Once(function(_, parent)
		if parent == nil then
			prepared[model] = nil
		end
	end)
end

local function consider(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local attribute = Config.Attributes.ParticipantId
	if inst:GetAttribute(attribute) ~= nil then
		prepare(inst)
	else
		inst:GetAttributeChangedSignal(attribute):Once(function()
			prepare(inst)
		end)
	end
end

function CharacterSetupSystem.start()
	for _, d in Workspace:GetDescendants() do
		consider(d)
	end
	Workspace.DescendantAdded:Connect(consider)
end

return CharacterSetupSystem
