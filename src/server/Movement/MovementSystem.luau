--!strict
-- Starts server movement: walk speed and no-jump settings on every player character, kept in step
-- with upgrades, plus the slide service.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ids = require(Shared.Ids)

local Core = script.Parent.Parent.Core
local EffectiveStats = require(Core.EffectiveStats)

local MovementSetup = require("./MovementSetup")
local SlideService = require("./SlideService")
local SprintService = require("./SprintService")
local VaultService = require("./VaultService")

local MovementSystem = {}
MovementSystem.order = 100

local humanoids: { [string]: Humanoid } = {} -- player id -> current humanoid

local function watchPlayer(player: Player)
	local id = Ids.player(player.UserId)
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoids[id] = humanoid
			MovementSetup.apply(humanoid, EffectiveStats:get(id).moveSpeed)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

function MovementSystem.start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		humanoids[Ids.player(player.UserId)] = nil
	end)
	-- An upgrade (or a match reset) changed someone's stats: update their walk speed.
	EffectiveStats.Changed:connect(function(id: string)
		local humanoid = humanoids[id]
		if humanoid and humanoid.Parent ~= nil then
			MovementSetup.setSpeed(humanoid, EffectiveStats:get(id).moveSpeed)
		end
	end)
	SlideService.start()
	SprintService.start()
	VaultService.start()
end

return MovementSystem
