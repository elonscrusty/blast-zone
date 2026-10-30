--!strict
-- Emotes on the server (piece 29). A client only ASKS to play one (EmoteRequest); EmoteRules decides:
-- the emote must exist, be unlocked (all are free unless Config.Emotes.trackUnlocks), and the player must not be fighting.
-- The server then marks the character (attributes Emote + EmoteAt) and every client draws it from there.
-- "win_A" / "win_B" / "win_C" picks the player's winner pose (Player attribute WinPose, any time).
-- An emote ends by itself after Config.Emotes.maxSeconds, when the player asks "stop", or when a match starts.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local EmoteRules = require(Shared.Character.EmoteRules)
local Ids = require(Shared.Ids)

local Server = script.Parent.Parent
local MatchContext = require(Server.Core.MatchContext)
local Net = require(Server.Core.Net)
local Participants = require(Server.Core.Participants)

local EmoteSystem = {}
EmoteSystem.order = 140

local tuning = Config.Emotes
local scheme: EmoteRules.Scheme =
	{ starterSet = tuning.starterSet, trackUnlocks = tuning.trackUnlocks }
local lastAt: { [Player]: number } = {}
local token: { [Player]: number } = {}

-- Piece 18's track progress, if that piece is in this build (only read when trackUnlocks is on).
local progressOf: ((Player) -> any)? = nil
local function findProgress()
	local folder = Server:FindFirstChild("Progression")
	local module = if folder then folder:FindFirstChild("ProgressionSystem") else nil
	if module == nil or not module:IsA("ModuleScript") then
		return
	end
	local ok, system = pcall(require, module)
	if ok and type(system) == "table" and type((system :: any).progressOf) == "function" then
		progressOf = (system :: any).progressOf
	end
end

local function tiersOf(player: Player): number
	local read = progressOf
	if not scheme.trackUnlocks or read == nil then
		return 0
	end
	local ok, progress = pcall(read, player)
	if not ok or type(progress) ~= "table" or type(progress.unlocked) ~= "table" then
		return 0
	end
	return EmoteRules.tiersOwned(progress.unlocked)
end

local function livingBody(player: Player): Model?
	local character = player.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	return character
end

local function clear(player: Player)
	token[player] = (token[player] or 0) + 1
	local character = player.Character
	if character ~= nil then
		character:SetAttribute(tuning.attribute, nil)
		character:SetAttribute(tuning.startedAttribute, nil)
	end
end

local function play(player: Player, emoteId: string)
	local body = livingBody(player)
	local now = os.clock()
	local inCombat = MatchContext:isCombat() and Participants:isAlive(Ids.player(player.UserId))
	local ok = EmoteRules.canPlay({
		emoteId = emoteId,
		scheme = scheme,
		tiersOwned = tiersOf(player),
		hasBody = body ~= nil,
		inCombat = inCombat,
		now = now,
		lastAt = lastAt[player],
		cooldown = tuning.cooldown,
	})
	if not ok or body == nil then
		return
	end
	lastAt[player] = now
	token[player] = (token[player] or 0) + 1
	local mine = token[player]
	body:SetAttribute(tuning.attribute, emoteId)
	body:SetAttribute(tuning.startedAttribute, Workspace:GetServerTimeNow())
	task.delay(tuning.maxSeconds, function()
		if token[player] == mine and player.Parent ~= nil then
			clear(player)
		end
	end)
end

function EmoteSystem.start()
	findProgress()

	Net.onRequest("EmoteRequest", function(player, emoteId: string)
		local winPose = EmoteRules.winPoseFrom(emoteId)
		if winPose ~= nil then
			player:SetAttribute(tuning.winPoseAttribute, winPose)
		elseif emoteId == EmoteRules.STOP then
			clear(player)
		else
			play(player, emoteId)
		end
	end)

	-- A match starting ends every emote (fighters spawn fresh anyway; this also covers anyone who stays put).
	MatchContext.PhaseChanged:connect(function(phase: string)
		if phase == "Spawning" or phase == "Active" then
			for _, player in Players:GetPlayers() do
				clear(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastAt[player] = nil
		token[player] = nil
	end)
end

return EmoteSystem
