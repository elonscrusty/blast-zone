--!strict
-- Piece 27: starts the move watch and closes the "reset to hide" trick. A player whose body dies
-- by any way other than the damage door (Reset button, a cheat killing its own body, falling out
-- of the world) while still in the fight is knocked out through the damage door, so the roster,
-- results and XP all agree. Remote checks themselves live in Core/Net + shared/Guard.

local Players = game:GetService("Players")

local Damage = require(script.Parent.Parent.Core.Damage)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)
local Participants = require(script.Parent.Parent.Core.Participants)
local SlideService = require(script.Parent.Parent.Movement.SlideService)
local MoveGuard = require(script.Parent.MoveGuard)

local AntiCheatSystem = {}
AntiCheatSystem.order = 40

local function onBodyDied(player: Player, character: Model)
	if player.Character ~= character then
		return -- an old body being swapped out, not this fight's body
	end
	local p = Participants:ofPlayer(player)
	if p == nil or not p.alive or not MatchContext:isCombat() then
		return
	end
	Damage:apply({
		matchId = MatchContext:getMatchId(),
		targetId = p.id,
		amount = 1e6,
		cause = "other",
		sourceId = nil,
	})
end

local function watchPlayer(player: Player)
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid ~= nil and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				onBodyDied(player, character)
			end)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character ~= nil then
		task.spawn(onCharacter, player.Character)
	end
end

function AntiCheatSystem.start()
	MoveGuard.start()
	SlideService.PlayerSlid:connect(function(id: string, distance: number)
		MoveGuard.allowSlide(id, distance)
	end)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return AntiCheatSystem
