--!strict
-- Participants walk through each other (a body should not block a doorway). Call setup() once,
-- then apply(character) for every spawned character.
local PhysicsService = game:GetService("PhysicsService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local CollisionGroups = {}

local names = Config.CollisionGroups

function CollisionGroups.setup()
	for _, name in names do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(names.Participants, names.Participants, false)
	end)
	-- A body mid-hop touches nothing (piece 45).
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(names.Vaulting, "Default", false)
		PhysicsService:CollisionGroupSetCollidable(names.Vaulting, names.Participants, false)
		PhysicsService:CollisionGroupSetCollidable(names.Vaulting, names.Vaulting, false)
		PhysicsService:CollisionGroupSetCollidable(names.Vaulting, names.Projectiles, false)
	end)
end

function CollisionGroups.apply(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = names.Participants
		end
	end
end

return CollisionGroups
