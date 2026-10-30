--!strict
-- The bench on the server (video 3 gap 14). Connects Roblox to BenchService, which holds the rules:
--   * parts drop only from a finished match (MatchSystem.RewardGranted), once per player per match, for real
--     players only (bots have no bench). A client can only ASK to see its bench, merge, or build.
--   * the bench is saved in data.bench of the profile (piece 17). Gear built here is looks only: no stats.
-- If the profile module is missing, the bench lives in memory (status "temporary").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BenchMemoryStore = require(Shared.Bench.BenchMemoryStore)
local BenchRules = require(Shared.Bench.BenchRules)
local BenchService = require(Shared.Bench.BenchService)
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)

local Server = script.Parent.Parent
local Net = require(Server.Core.Net)

local BenchSystem = {}
BenchSystem.order = 72 -- after DailySystem (70)

local function findModule(folderName: string, moduleName: string): any?
	local folder = Server:FindFirstChild(folderName)
	local module = if folder then folder:FindFirstChild(moduleName) else nil
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn(`[bench] {moduleName} failed to load: {result}`)
		return nil
	end
	return result
end

local function profileStore(Profiles: any): BenchService.Store
	local store = {} :: BenchService.Store
	function store.status(player: any): string
		return Profiles.status(player)
	end
	function store.read(player: any): BenchRules.State?
		local profile = Profiles.get(player)
		if profile == nil then
			return nil
		end
		return BenchRules.fill(profile.data.bench) -- a copy: change it only through update
	end
	local function wrap(data: any, fn: (BenchRules.State) -> boolean?): boolean?
		local state = BenchRules.fill(data.bench)
		local result = fn(state)
		if result ~= false then
			data.bench = state
		end
		return result
	end
	function store.update(player: any, fn: (BenchRules.State) -> boolean?): (boolean, string?)
		return Profiles.update(player, function(data: any)
			return wrap(data, fn)
		end)
	end
	function store.grantOnce(
		player: any,
		key: string,
		fn: (BenchRules.State) -> boolean?
	): (boolean, string?)
		return Profiles.grantOnce(player, key, function(data: any)
			return wrap(data, fn)
		end)
	end
	return store
end

local function playerOf(participantId: string): Player?
	local userId = Ids.userIdOf(participantId)
	if userId == nil then
		return nil -- bots
	end
	return Players:GetPlayerByUserId(userId)
end

function BenchSystem.start()
	local Profiles = findModule("Profile", "Profiles")
	local memory: BenchMemoryStore.MemoryStore? = nil
	local store: BenchService.Store
	if Profiles ~= nil then
		store = profileStore(Profiles)
	else
		warn("[bench] no profile module: the bench is NOT saved (temporary)")
		local mem = BenchMemoryStore.new()
		memory = mem
		store = mem
	end

	local rng = Random.new()
	local service = BenchService.new({
		store = store,
		send = function(player: any, state)
			Net.fire("BenchState", player, state)
		end,
		rng = function(max: number): number
			return rng:NextInteger(1, max)
		end,
		drops = Config.Bench.drops,
		fieldSize = Config.Bench.fieldSize,
	})

	-- A finished match: once per player per match (piece 05).
	local Match = require(Server.Match.MatchSystem)
	Match.RewardGranted:connect(
		function(
			participantId: string,
			_amount: number,
			place: number,
			matchId: number,
			won: boolean?
		)
			local player = playerOf(participantId)
			if player == nil then
				return
			end
			local key = if Profiles ~= nil
				then Profiles.matchReceiptKey(matchId) .. ":bench"
				else `m:temp:{matchId}:bench`
			service.drop(player, key, place, won)
		end
	)

	Net.onRequest("BenchRequest", function(player)
		service.push(player)
	end)
	Net.onRequest("BenchMerge", function(player, kind: any, tier: any)
		service.merge(player, kind, tier)
	end)
	Net.onRequest("BenchBuild", function(player, blueprintId: any)
		service.build(player, blueprintId)
	end)

	if Profiles ~= nil then
		Profiles.Loaded:connect(function(player: Player)
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
		if memory ~= nil then
			memory.release(player)
		end
	end)
end

return BenchSystem
