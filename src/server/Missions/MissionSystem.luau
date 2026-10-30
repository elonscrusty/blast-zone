--!strict
-- Weekly missions, achievements and login days on the server (piece 48). Connects Roblox to MissionService:
--   * progress comes only from server events, the same ones the daily challenges count: RunXp awards
--     (eliminations, crates, orbs) and match results (matches, top 3, wins). Bots never count.
--   * a client can only ASK: MissionsRequest (show me the board) and MissionClaim (pay me this one).
--   * progress and claims are saved in data.missions of the profile (piece 17); Scrap is paid through piece 18
--     (ProgressionSystem.grant), once per key, so a repeated claim never pays twice.
-- If the profile module is missing, progress lives in memory (status "temporary").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DailyDefs = require(Shared.Daily.DailyDefs)
local Ids = require(Shared.Ids)
local MissionMemoryStore = require(Shared.Missions.MissionMemoryStore)
local MissionRules = require(Shared.Missions.MissionRules)
local MissionService = require(Shared.Missions.MissionService)

local Server = script.Parent.Parent
local Net = require(Server.Core.Net)
local RunXp = require(Server.Core.RunXp)

local MissionSystem = {}
MissionSystem.order = 72 -- after DailySystem (70)

local function findModule(folderName: string, moduleName: string): any?
	local folder = Server:FindFirstChild(folderName)
	local module = if folder then folder:FindFirstChild(moduleName) else nil
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn(`[missions] {moduleName} failed to load: {result}`)
		return nil
	end
	return result
end

local function profileStore(Profiles: any): MissionService.Store
	local store = {} :: MissionService.Store
	function store.status(player: any): string
		return Profiles.status(player)
	end
	function store.read(player: any): MissionRules.State?
		local profile = Profiles.get(player)
		if profile == nil then
			return nil
		end
		return MissionRules.fill(profile.data.missions) -- a copy: change it only through update
	end
	function store.update(player: any, fn: (MissionRules.State) -> boolean?): (boolean, string?)
		return Profiles.update(player, function(data: any)
			local state = MissionRules.fill(data.missions)
			local result = fn(state)
			if result == false then
				return false
			end
			data.missions = state
			return true
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

function MissionSystem.start()
	local Profiles = findModule("Profile", "Profiles")
	local memory: MissionService.Store? = nil
	local store: MissionService.Store
	if Profiles ~= nil then
		store = profileStore(Profiles)
	else
		warn("[missions] no profile module: mission progress is NOT saved (temporary)")
		local mem = MissionMemoryStore.new()
		memory = mem
		store = mem
	end

	local Progression = findModule("Progression", "ProgressionSystem")
	if Progression == nil then
		warn("[missions] no coin system: missions count but pay nothing")
	end

	local service = MissionService.new({
		store = store,
		pay = function(player: any, amount: number, key: string): (boolean, string?)
			if Progression == nil then
				return false, "noCoins"
			end
			return Progression.grant(player, amount, key)
		end,
		send = function(player: any, state)
			Net.fire("MissionsState", player, state)
		end,
		now = os.time,
		config = Config.Missions,
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

	Net.onRequest("MissionsRequest", function(player)
		service.push(player)
	end)

	-- The remote guard already checked the shape; the service checks everything else.
	Net.onRequest("MissionClaim", function(player, what: string, id: string?)
		service.claim(player, what, id)
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

return MissionSystem
