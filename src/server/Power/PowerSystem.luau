--!strict
-- Power rating on the server (video 3 gap #16). Reads what the player has earned (account level and looks from
-- progression, wins/eliminations/matches from the saved stats), asks PowerRules for the number, and tells that
-- player only. It writes nothing: no save, no stat, no combat rule. Nothing else may read the number to decide
-- damage, loot or who plays whom.
--   PowerSystem.getRating(player) -> PowerRules.Rating   (for other server pieces that only want to show it)
--   PowerSystem.Changed           Signal(player, rating)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ids = require(Shared.Ids)
local PowerRules = require(Shared.Power.PowerRules)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local ServerRoot = script.Parent.Parent
local Net = require(ServerRoot.Core.Net)
local MatchSystem = require(ServerRoot.Match.MatchSystem)
local ProgressionSystem = require(ServerRoot.Progression.ProgressionSystem)

local PowerSystem = {}
PowerSystem.order = 70 -- after Profiles (10), Match (50), Progression and Stats (60)
PowerSystem.Changed = Signal.new()

-- Piece 17's door, when it is in the build. Typed loosely so this file builds with or without it.
local Profiles: any = nil
do
	local folder = ServerRoot:FindFirstChild("Profile")
	local module = if folder then folder:FindFirstChild("Profiles") else nil
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			Profiles = result
		else
			warn(`[Power] Profiles did not load: {result}`)
		end
	end
end

local lastSent: { [Player]: PowerRules.Rating } = {}

function PowerSystem.getRating(player: Player): PowerRules.Rating
	local stats: any = nil
	if Profiles ~= nil then
		local profile = Profiles.get(player)
		if profile ~= nil then
			stats = profile.data.stats
		end
	end
	return PowerRules.compute(PowerRules.inputsFrom(ProgressionSystem.progressOf(player), stats))
end

local function payloadOf(rating: PowerRules.Rating): Types.PowerPayload
	return {
		power = rating.power,
		band = rating.band,
		toNext = rating.toNext,
		parts = rating.parts,
	}
end

-- `force` sends even when nothing changed (a client that just asked may have missed the last push).
local function refresh(player: Player, force: boolean)
	if player.Parent == nil then
		return
	end
	local rating = PowerSystem.getRating(player)
	if not force and PowerRules.same(lastSent[player], rating) then
		return
	end
	lastSent[player] = rating
	Net.fire("PowerUpdate", player, payloadOf(rating))
	PowerSystem.Changed:fire(player, rating)
end

function PowerSystem.start()
	local function onAdded(player: Player)
		refresh(player, false)
	end
	Players.PlayerAdded:Connect(onAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastSent[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onAdded, player)
	end

	ProgressionSystem.Changed:connect(function(player: Player)
		refresh(player, false)
	end)
	if Profiles ~= nil then
		Profiles.Loaded:connect(function(player: Player)
			refresh(player, false)
		end)
	end

	-- A match paying out is when wins, eliminations and matches change. Wait one beat so the stats piece has
	-- written its numbers first.
	MatchSystem.RewardGranted:connect(function(participantId: string)
		local userId = if Ids.isPlayer(participantId) then Ids.userIdOf(participantId) else nil
		local player = if userId then Players:GetPlayerByUserId(userId) else nil
		if player ~= nil then
			task.defer(refresh, player, false)
		end
	end)

	Net.onRequest("PowerRequest", function(player: Player)
		refresh(player, true)
	end)
end

return PowerSystem
