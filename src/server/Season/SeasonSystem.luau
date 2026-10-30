--!strict
-- The season pass on the server (video 3 gap 20). Connects Roblox to SeasonService, which holds the rules:
--   * season XP comes only from the server: the run XP a finished match gives a real player (LevelSystem.XpEarned,
--     once per match). A client can only ASK to see its pass or to take a reward it has reached.
--   * the pass is saved in data.season of the profile (piece 17); Scrap and looks are given through piece 18
--     (ProgressionSystem.grant / giveItem), once per season, tier and row.
--   * the paid row opens only through SeasonSystem.unlockPaid. Nothing sells it yet (Config.Season.forSale).
-- If the profile module is missing, the pass lives in memory (status "temporary").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SeasonMemoryStore = require(Shared.Season.SeasonMemoryStore)
local SeasonRules = require(Shared.Season.SeasonRules)
local SeasonService = require(Shared.Season.SeasonService)

local Server = script.Parent.Parent
local Net = require(Server.Core.Net)

local SeasonSystem = {}
SeasonSystem.order = 75 -- after LevelSystem (65) and ProgressionSystem (60)

local service: SeasonService.Service? = nil

local function findModule(folderName: string, moduleName: string): any?
	local folder = Server:FindFirstChild(folderName)
	local module = if folder then folder:FindFirstChild(moduleName) else nil
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn(`[season] {moduleName} failed to load: {result}`)
		return nil
	end
	return result
end

local function copyState(raw: any): SeasonRules.State
	local s = type(raw) == "table" and raw or {}
	return SeasonRules.fill({
		season = s.season,
		xp = s.xp,
		paid = s.paid,
		claimed = table.clone(type(s.claimed) == "table" and s.claimed or {}),
		keys = table.clone(type(s.keys) == "table" and s.keys or {}),
	})
end

local function profileStore(Profiles: any): SeasonService.Store
	local store = {} :: SeasonService.Store
	function store.status(player: any): string
		return Profiles.status(player)
	end
	function store.read(player: any): SeasonRules.State?
		local profile = Profiles.get(player)
		if profile == nil then
			return nil
		end
		return copyState(profile.data.season) -- a copy: change it only through update
	end
	function store.update(player: any, fn: (SeasonRules.State) -> boolean?): (boolean, string?)
		return Profiles.update(player, function(data: any)
			if type(data.season) ~= "table" then
				data.season = {}
			end
			return fn(SeasonRules.fill(data.season))
		end)
	end
	return store
end

-- Opens the paid row for a player. For the buy step to call once a purchase is confirmed; nothing else may.
function SeasonSystem.unlockPaid(player: Player): boolean
	local s = service
	return s ~= nil and s.unlockPaid(player)
end

function SeasonSystem.start()
	local Profiles = findModule("Profile", "Profiles")
	local memory: SeasonService.Store? = nil
	local store: SeasonService.Store
	if Profiles ~= nil then
		store = profileStore(Profiles)
	else
		warn("[season] no profile module: the pass is NOT saved (temporary)")
		local mem = SeasonMemoryStore.new()
		memory = mem
		store = mem
	end

	local Progression = findModule("Progression", "ProgressionSystem")
	if Progression == nil then
		warn("[season] no coin system: rewards cannot be given")
	end

	local created = SeasonService.new({
		store = store,
		pay = function(player: any, amount: number, key: string): (boolean, string?)
			if Progression == nil then
				return false, "noCoins"
			end
			return Progression.grant(player, amount, key)
		end,
		giveItem = function(
			player: any,
			itemId: string,
			key: string,
			dupScrap: number
		): (boolean, string?)
			if Progression == nil then
				return false, "noCoins"
			end
			return Progression.giveItem(player, itemId, key, dupScrap)
		end,
		send = function(player: any, state)
			Net.fire("SeasonState", player, state)
		end,
		now = os.time,
	})
	service = created

	-- A finished match told us this player's run XP (once per match; bots never get here).
	local Level = require(Server.Progression.LevelSystem)
	Level.XpEarned:connect(function(player: Player, xp: number, matchId: number)
		local key = if Profiles ~= nil
			then Profiles.matchReceiptKey(matchId)
			else `{game.JobId}:{matchId}`
		created.onXp(player, xp, key)
	end)

	Net.onRequest("SeasonRequest", function(player)
		created.push(player)
	end)
	Net.onRequest("SeasonClaimRequest", function(player, tier: number, row: string)
		created.claim(player, tier, row)
	end)

	if Profiles ~= nil then
		Profiles.Loaded:connect(function(player: Player)
			created.push(player)
		end)
	else
		Players.PlayerAdded:Connect(function(player)
			created.push(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		task.spawn(created.push, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		if memory ~= nil and memory.release ~= nil then
			memory.release(player)
		end
	end)
end

return SeasonSystem
