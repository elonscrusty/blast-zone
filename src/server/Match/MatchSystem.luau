--!strict
-- Match flow on the server: waiting, countdown, spawns, survivors, results, spectating, reset (brief §7, §11, §16).
-- This file only connects Roblox things (players, remotes, tagged parts) to MatchController, which holds the rules.
--
-- For other pieces:
--   MatchSystem.requestBots(n)       piece 09: ask for n bots in Waiting/Countdown. Returns how many were accepted.
--   MatchSystem.SpawnAssigned        Signal(participant, point, lookAt): fired at Spawning for everyone, bots included.
--   MatchSystem.RewardGranted        Signal(participantId, amount, place, matchId): once per player per match.
--   MatchSystem.queuePlayer(player)  piece 26: queue a player for the next match, same as pressing PLAY.
--   MatchSystem.isQueued(player)     piece 26: true when the player pressed PLAY / PLAY AGAIN (or was queued).
-- Phase and matchId live in Core/MatchContext; the roster in Core/Participants; hurting goes through Core/Damage.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local MatchPhase = require(Shared.MatchPhase)
local Signal = require(Shared.Signal)

local Core = script.Parent.Parent:WaitForChild("Core")
local CollisionGroups = require(Core.CollisionGroups)
local Damage = require(Core.Damage)
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)
local Participants = require(Core.Participants)

local MoveGuard = require(script.Parent.Parent.AntiCheat.MoveGuard)
local MatchController = require(script.Parent.MatchController)
local MatchRules = require(script.Parent.MatchRules)

local LOBBY_TAG = "LobbySpawn" -- optional: parts the arena piece tags where waiting players stand
local TICK_SECONDS = 0.1

local MatchSystem = {}
MatchSystem.order = 50 -- before the pieces that listen to the roster
MatchSystem.SpawnAssigned = Signal.new()
MatchSystem.RewardGranted = Signal.new()

local playerById: { [string]: Player } = {}
local lastState: any = nil
local controller: MatchController.Controller

local function serverTime(clockTime: number): number
	return workspace:GetServerTimeNow() + (clockTime - os.clock())
end

local function toVector(p: MatchController.Point): Vector3
	return Vector3.new(p.x, p.y, p.z)
end

local function lobbyPosition(): Vector3?
	local parts = CollectionService:GetTagged(LOBBY_TAG)
	for _, inst in parts do
		if inst:IsA("BasePart") then
			return inst.Position + Vector3.new(0, inst.Size.Y / 2 + 3, 0)
		end
	end
	return nil
end

-- Loads a fresh character (or reuses none) and optionally stands it somewhere.
local function loadCharacter(player: Player, at: CFrame?)
	if player.Parent == nil then
		return
	end
	player:LoadCharacter()
	if at then
		MoveGuard.place(player, at) -- tells the move watch this jump is the server's own
	end
end

local function sendLobbyCharacter(player: Player)
	local spot = lobbyPosition()
	loadCharacter(player, if spot then CFrame.new(spot) else nil)
	local character = player.Character
	if character then
		character:SetAttribute(Config.Attributes.ParticipantId, nil)
	end
end

local world: MatchController.World = {
	getSpawnPoints = function()
		local points: { MatchController.Point } = {}
		for _, inst in CollectionService:GetTagged(Config.Tags.Spawn) do
			if inst:IsA("BasePart") then
				local pos = inst.Position + Vector3.new(0, inst.Size.Y / 2 + 3, 0)
				table.insert(points, { x = pos.X, y = pos.Y, z = pos.Z })
			end
		end
		return points
	end,

	getCenter = function()
		return { x = Config.Arena.centerX, y = 3, z = Config.Arena.centerZ }
	end,

	place = function(participant, point, lookAt)
		MatchSystem.SpawnAssigned:fire(participant, point, lookAt) -- bots: piece 09 builds the rig now
		if participant.kind ~= "player" then
			return
		end
		local player = playerById[participant.id]
		if not player then
			return
		end
		task.spawn(function()
			local pos = toVector(point)
			local face = Vector3.new(lookAt.x, pos.Y, lookAt.z)
			loadCharacter(
				player,
				CFrame.lookAt(
					pos,
					if (face - pos).Magnitude > 0.1 then face else pos + Vector3.zAxis
				)
			)
			local character = player.Character
			if character then
				character:SetAttribute(Config.Attributes.ParticipantId, participant.id)
				character:SetAttribute(Config.Attributes.IsBot, false)
				CollisionGroups.apply(character)
			end
		end)
	end,

	cleanup = function(participants)
		-- Bots clear their own rigs (piece 09). Players go back to the lobby with a fresh character.
		for _, p in participants do
			local player = playerById[p.id]
			if player then
				task.spawn(sendLobbyCharacter, player)
			end
		end
	end,

	publish = function(state)
		lastState = state
		Net.fireAll("MatchState", state)
	end,

	announce = function(kind, text)
		Net.fireAll("Announce", { kind = kind, text = text })
	end,

	sendEliminated = function(payload)
		Net.fireAll("Eliminated", payload)
	end,

	sendResults = function(id, payload)
		local player = playerById[id]
		if player then
			Net.fire("Results", player, payload)
		end
	end,

	sendSpectate = function(id, targetId, targetName)
		local player = playerById[id]
		if player then
			Net.fire("SpectateTarget", player, { participantId = targetId, name = targetName })
		end
	end,

	grantReward = function(id, amount, place, matchId)
		local player = playerById[id]
		if player then
			-- In-game Credits only for now (Config.Rewards.persist = false). Saving comes later and must use SaveRetry.
			player:SetAttribute("Credits", (player:GetAttribute("Credits") or 0) + amount)
		end
		MatchSystem.RewardGranted:fire(id, amount, place, matchId)
	end,

	toServerTime = serverTime,

	log = function(message)
		print(`[match] {message}`)
	end,
}

function MatchSystem.requestBots(count: number): number
	return controller.requestBots(count)
end

local function idOf(player: Player): string
	return Ids.player(player.UserId)
end

function MatchSystem.queuePlayer(player: Player): boolean
	local id = idOf(player)
	controller.setReady(id, true)
	return controller.isReady(id)
end

function MatchSystem.isQueued(player: Player): boolean
	return controller ~= nil and controller.isReady(idOf(player))
end

local function onPlayerAdded(player: Player)
	local id = idOf(player)
	playerById[id] = player
	controller.addHuman(player, player.UserId, player.DisplayName)
	task.spawn(sendLobbyCharacter, player)
	-- The client may not be listening yet: send the current state again a little later.
	for _, delaySeconds in { 1.5, 5 } do
		task.delay(delaySeconds, function()
			if player.Parent and lastState then
				Net.fire("MatchState", player, lastState)
			end
		end)
	end
end

local function onPlayerRemoving(player: Player)
	local id = idOf(player)
	controller.removeHuman(id)
	playerById[id] = nil
end

function MatchSystem.start()
	Players.CharacterAutoLoads = false -- the match decides when and where characters appear

	controller = MatchController.new({
		config = Config,
		rules = MatchRules,
		ctx = MatchContext,
		registry = Participants,
		phases = MatchPhase,
		ids = Ids,
		clock = os.clock,
		world = world,
	})

	Damage.Eliminated:connect(function(event)
		controller.onEliminated(event)
	end)

	-- Requests: Net already rate-limited and shape-checked them. The controller checks phase and who is asking.
	Net.onRequest("PlayRequest", function(player)
		controller.setReady(idOf(player), true)
	end)
	Net.onRequest("ReplayRequest", function(player)
		controller.setReady(idOf(player), true)
	end)
	Net.onRequest("ReturnToLobbyRequest", function(player)
		controller.setReady(idOf(player), false)
	end)
	Net.onRequest("ClaimResults", function(player, matchId: number)
		controller.claimResults(idOf(player), matchId)
	end)
	Net.onRequest("SpectateCycle", function(player, step: number)
		controller.cycleSpectate(idOf(player), step)
	end)

	-- Piece 06: the zone's last warning starts Final pressure. Optional, so the match still runs without a zone.
	local zoneFolder = script.Parent.Parent:FindFirstChild("Zone")
	local zoneModule = if zoneFolder then zoneFolder:FindFirstChild("ZoneSystem") else nil
	if zoneModule and zoneModule:IsA("ModuleScript") then
		local ok, zone = pcall(require, zoneModule)
		if ok and zone.FinalPressure then
			zone.FinalPressure:connect(function(matchId: number)
				controller.enterFinalPressure(matchId)
			end)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < TICK_SECONDS then
			return
		end
		elapsed = 0
		local ok, err = pcall(controller.update)
		if not ok then
			warn(`[match] update failed: {err}`)
		end
	end)
end

return MatchSystem
