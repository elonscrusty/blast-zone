--!strict
-- Coins and the unlock track on the server (piece 18). Connects Roblox to ProgressService, which holds the rules:
--   * a finished match pays coins (MatchSystem.RewardGranted: once per player per match; the amount is decided by
--     the match, never by a client) into data.progression of the saved profile (piece 17).
--   * UnlockRequest / EquipRequest only ASK; ProgressService checks price, order and ownership.
--   * the chosen look is copied onto the Player as attributes so every client can draw it.
-- If the profile module is missing, coins live in memory (status "temporary") and the client says "not saved".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local MemoryStore = require(Shared.Progression.MemoryStore)
local ProgressRules = require(Shared.Progression.ProgressRules)
local ProgressService = require(Shared.Progression.ProgressService)

local Server = script.Parent.Parent
local Net = require(Server.Core.Net)

local ProgressionSystem = {}
ProgressionSystem.order = 60

local service: ProgressService.Service
local memory: ProgressService.Store? = nil

-- The real profile (piece 17), if it is in this build.
local function findProfiles(): any?
	local folder = Server:FindFirstChild("Profile")
	local module = if folder then folder:FindFirstChild("Profiles") else nil
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, profiles = pcall(require, module)
	if not ok then
		warn(`[progression] Profiles failed to load: {profiles}`)
		return nil
	end
	return profiles
end

local function profileStore(Profiles: any): ProgressService.Store
	local function progressionOf(data: any): ProgressRules.Progression
		if type(data.progression) ~= "table" then
			data.progression = {}
		end
		return ProgressRules.fill(data.progression)
	end
	local store = {} :: ProgressService.Store
	function store.status(player: any): string
		return Profiles.status(player)
	end
	function store.read(player: any): ProgressRules.Progression?
		local profile = Profiles.get(player)
		if profile == nil then
			return nil
		end
		-- A copy: the live table must not be kept or changed outside Profiles.update.
		local copy = table.clone(profile.data.progression or {})
		copy.unlocked = table.clone(copy.unlocked or {})
		copy.equipped = table.clone(copy.equipped or {})
		copy.grantedKeys = table.clone(copy.grantedKeys or {})
		return ProgressRules.fill(copy)
	end
	function store.update(
		player: any,
		fn: (ProgressRules.Progression) -> boolean?
	): (boolean, string?)
		return Profiles.update(player, function(data: any)
			return fn(progressionOf(data))
		end)
	end
	function store.grantOnce(
		player: any,
		key: string,
		fn: (ProgressRules.Progression) -> boolean?
	): (boolean, string?)
		return Profiles.grantOnce(player, key, function(data: any)
			return fn(progressionOf(data))
		end)
	end
	function store.saveNow(player: any): boolean
		task.spawn(Profiles.saveNow, player) -- yields, so never inside a handler
		return true
	end
	return store
end

local function playerOf(participantId: string): Player?
	local userId = Ids.userIdOf(participantId)
	if userId == nil then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

function ProgressionSystem.start()
	local Profiles = findProfiles()
	local store: ProgressService.Store
	if Profiles ~= nil then
		store = profileStore(Profiles)
	else
		warn("[progression] no profile module: coins are NOT saved (temporary)")
		local mem = MemoryStore.new()
		memory = mem
		store = mem
	end

	local attributes = Config.Progression.attributes
	service = ProgressService.new({
		store = store,
		maxGrant = Config.Progression.maxMatchGrant,
		receiptKey = function(matchId: number): string
			if Profiles ~= nil then
				return Profiles.matchReceiptKey(matchId)
			end
			return `{game.JobId}:{matchId}`
		end,
		send = function(player: any, state)
			Net.fire("ProgressState", player, state)
		end,
		applyLook = function(player: any, trailId: string, tracerId: string)
			(player :: Player):SetAttribute(attributes.trail, trailId);
			(player :: Player):SetAttribute(attributes.tracer, tracerId)
		end,
	})

	-- A match paid someone: this is the only way coins are earned.
	local Match = require(Server.Match.MatchSystem)
	Match.RewardGranted:connect(
		function(participantId: string, amount: number, _place: number, matchId: number)
			local player = playerOf(participantId)
			if player ~= nil then
				service.onReward(player, amount, matchId)
			end
		end
	)

	Net.onRequest("ProgressRequest", function(player)
		service.push(player)
	end)
	Net.onRequest("UnlockRequest", function(player, itemId: string)
		service.unlock(player, itemId)
	end)
	Net.onRequest("EquipRequest", function(player, itemId: string)
		service.equip(player, itemId)
	end)

	-- Tell each player their state when their saved data arrives (or changes status), and when they join.
	if Profiles ~= nil then
		Profiles.Loaded:connect(function(player: Player)
			service.push(player)
		end)
		Profiles.StatusChanged:connect(function(player: Player)
			service.push(player)
		end)
	else
		Players.PlayerAdded:Connect(function(player)
			service.push(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		task.spawn(service.push, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		if memory ~= nil and memory.release ~= nil then
			memory.release(player)
		end
	end)
end

return ProgressionSystem
