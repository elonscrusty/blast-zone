--!strict
-- Chests on the server (gap 19). Connects Roblox to ChestService, which holds the rules:
--   * chests are earned only here: a finished match (MatchSystem.RewardGranted: place, win, free-chest meter), or
--     another server system calling ChestSystem.award. A client can only ASK to see its chests or to open one.
--   * opening takes one chest and pays the Scrap and looks in ONE change to the saved profile (piece 17), so a
--     double tap or a crash can never keep the chest and also pay it. The roll uses the server's own Random.
--   * the chests live in data.chests of the profile. Without the profile module they live in memory (status
--     "temporary") and the screen says "not saved".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChestMemoryStore = require(Shared.Chest.ChestMemoryStore)
local ChestRules = require(Shared.Chest.ChestRules)
local ChestService = require(Shared.Chest.ChestService)
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)

local Server = script.Parent.Parent
local Net = require(Server.Core.Net)

local ChestSystem = {}
ChestSystem.order = 75 -- after ProgressionSystem (60) and DailySystem (70)

local service: ChestService.Service? = nil

local function findModule(folderName: string, moduleName: string): any?
	local folder = Server:FindFirstChild(folderName)
	local module = if folder then folder:FindFirstChild(moduleName) else nil
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn(`[chest] {moduleName} failed to load: {result}`)
		return nil
	end
	return result
end

local function profileStore(Profiles: any): ChestService.Store
	local store = {} :: ChestService.Store
	function store.status(player: any): string
		return Profiles.status(player)
	end
	function store.read(player: any): ChestRules.State?
		local profile = Profiles.get(player)
		if profile == nil then
			return nil
		end
		-- A copy: the live table must not be kept or changed outside Profiles.update.
		local raw = profile.data.chests
		local copy = if type(raw) == "table" then table.clone(raw) else {}
		copy.owned = table.clone(if type(copy.owned) == "table" then copy.owned else {})
		return ChestRules.fill(copy)
	end
	function store.update(player: any, fn: ({ [string]: any }) -> boolean?): (boolean, string?)
		return Profiles.update(player, fn)
	end
	function store.grantOnce(
		player: any,
		key: string,
		fn: ({ [string]: any }) -> boolean?
	): (boolean, string?)
		return Profiles.grantOnce(player, key, fn)
	end
	function store.saveNow(player: any): boolean
		task.spawn(Profiles.saveNow, player) -- yields, so never inside a handler
		return true
	end
	return store
end

-- Another server system gives a chest (daily login days, missions, level gifts). Once per key; false + reason when
-- it did not give one ("duplicate" = it already did, "full" = the player holds the most allowed).
function ChestSystem.award(player: Player, kind: string, key: string): (boolean, string?)
	local s = service
	if s == nil then
		return false, "notStarted"
	end
	return s.award(player, kind, key)
end

function ChestSystem.start()
	local Profiles = findModule("Profile", "Profiles")
	local memory: ChestMemoryStore.Store? = nil
	local store: ChestService.Store
	if Profiles ~= nil then
		store = profileStore(Profiles)
	else
		warn("[chest] no profile module: chests are NOT saved (temporary)")
		local mem = ChestMemoryStore.new()
		memory = mem
		store = mem
	end

	local Progression = findModule("Progression", "ProgressionSystem")
	local rng = Random.new()
	local chests = ChestService.new({
		store = store,
		send = function(player: any, state)
			Net.fire("ChestState", player, state)
		end,
		random = function(): number
			return rng:NextNumber()
		end,
		maxStored = Config.Chest.maxStored,
		meterGoal = Config.Chest.meterGoal,
		maxGrant = Config.Progression.maxMatchGrant,
		changed = function(player: any)
			if Progression ~= nil then
				Progression.refresh(player) -- Scrap and looks changed in our own change
			end
		end,
	})
	service = chests

	-- A finished match: once per player per match (piece 05). Bots have no player and get nothing.
	local Match = require(Server.Match.MatchSystem)
	Match.RewardGranted:connect(
		function(
			participantId: string,
			_amount: number,
			place: number,
			matchId: number,
			won: boolean?
		)
			local userId = Ids.userIdOf(participantId)
			local player = if userId ~= nil then Players:GetPlayerByUserId(userId) else nil
			if player == nil then
				return
			end
			local key = if Profiles ~= nil
				then `{Profiles.matchReceiptKey(matchId)}:chest`
				else `{game.JobId}:{matchId}:chest`
			chests.onMatch(player, place, won == true, key)
		end
	)

	Net.onRequest("ChestRequest", function(player)
		chests.push(player)
	end)
	Net.onRequest("ChestOpenRequest", function(player, kind: string)
		chests.open(player, kind)
	end)

	if Profiles ~= nil then
		Profiles.Loaded:connect(function(player: Player)
			chests.push(player)
		end)
		Profiles.StatusChanged:connect(function(player: Player)
			chests.push(player)
		end)
	else
		Players.PlayerAdded:Connect(function(player)
			chests.push(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		task.spawn(chests.push, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		if memory ~= nil and memory.release ~= nil then
			memory.release(player)
		end
	end)
end

return ChestSystem
