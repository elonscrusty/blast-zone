--!strict
-- Daily challenges on the server (piece 25). Connects Roblox to DailyService, which holds the rules:
--   * progress comes only from server events: RunXp awards (eliminations, crates, orbs) and match results
--     (MatchSystem.RewardGranted: matches, top 3, wins). Bots never count. A client can only ASK to see the board.
--   * progress is saved in data.daily of the profile (piece 17); coins are paid through piece 18
--     (ProgressionSystem.grant), once per day and challenge.
-- If the profile module is missing, progress lives in memory (status "temporary").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DailyDefs = require(Shared.Daily.DailyDefs)
local DailyMemoryStore = require(Shared.Daily.DailyMemoryStore)
local DailyRules = require(Shared.Daily.DailyRules)
local DailyService = require(Shared.Daily.DailyService)
local Ids = require(Shared.Ids)

local Server = script.Parent.Parent
local Net = require(Server.Core.Net)
local RunXp = require(Server.Core.RunXp)

local DailySystem = {}
DailySystem.order = 70 -- after ProgressionSystem (60)

local function findModule(folderName: string, moduleName: string): any?
	local folder = Server:FindFirstChild(folderName)
	local module = if folder then folder:FindFirstChild(moduleName) else nil
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn(`[daily] {moduleName} failed to load: {result}`)
		return nil
	end
	return result
end

local function copyState(raw: any): DailyRules.State
	local s = type(raw) == "table" and raw or {}
	return DailyRules.fill({
		day = s.day,
		progress = table.clone(type(s.progress) == "table" and s.progress or {}),
		paid = table.clone(type(s.paid) == "table" and s.paid or {}),
	})
end

local function profileStore(Profiles: any): DailyService.Store
	local store = {} :: DailyService.Store
	function store.status(player: any): string
		return Profiles.status(player)
	end
	function store.read(player: any): DailyRules.State?
		local profile = Profiles.get(player)
		if profile == nil then
			return nil
		end
		return copyState(profile.data.daily) -- a copy: change it only through update
	end
	function store.update(player: any, fn: (DailyRules.State) -> boolean?): (boolean, string?)
		return Profiles.update(player, function(data: any)
			if type(data.daily) ~= "table" then
				data.daily = {}
			end
			return fn(DailyRules.fill(data.daily))
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

function DailySystem.start()
	local Profiles = findModule("Profile", "Profiles")
	local memory: DailyService.Store? = nil
	local store: DailyService.Store
	if Profiles ~= nil then
		store = profileStore(Profiles)
	else
		warn("[daily] no profile module: daily progress is NOT saved (temporary)")
		local mem = DailyMemoryStore.new()
		memory = mem
		store = mem
	end

	local Progression = findModule("Progression", "ProgressionSystem")
	if Progression == nil then
		warn("[daily] no coin system: challenges count but pay nothing")
	end

	local service = DailyService.new({
		store = store,
		pay = function(player: any, amount: number, key: string): (boolean, string?)
			if Progression == nil then
				return false, "noCoins"
			end
			return Progression.grant(player, amount, key)
		end,
		send = function(player: any, state)
			Net.fire("DailyState", player, state)
		end,
		now = os.time,
		rewards = Config.Daily.rewards,
		resetHour = Config.Daily.resetHourUtc,
	})

	-- Eliminations, crates and orbs: RunXp only awards these inside a real match, for the right participant.
	RunXp.Awarded:connect(function(participantId: string, reason: string)
		local kind = DailyDefs.kindForXpReason[reason]
		local player = playerOf(participantId)
		if kind ~= nil and player ~= nil then
			service.count(player, kind, 1)
		end
	end)

	-- A finished match: once per player per match (piece 05).
	local Match = require(Server.Match.MatchSystem)
	Match.RewardGranted:connect(
		function(
			participantId: string,
			_amount: number,
			place: number,
			_matchId: number,
			won: boolean?
		)
			local player = playerOf(participantId)
			if player == nil then
				return
			end
			service.count(player, "matches", 1)
			if place >= 1 and place <= 3 then
				service.count(player, "top3", 1)
			end
			if won == true then -- a draw shares place 1 but is not a win
				service.count(player, "wins", 1)
			end
		end
	)

	Net.onRequest("DailyRequest", function(player)
		service.push(player)
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
		if memory ~= nil and memory.release ~= nil then
			memory.release(player)
		end
	end)
end

return DailySystem
