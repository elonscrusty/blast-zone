--!strict
-- The top-bar counters on the server (piece G17). Connects Roblox to WalletService, which holds the rules:
--   * stars are earned only from server events: a finished match (MatchSystem.RewardGranted), once per match.
--     Bots have no wallet. A client can only ASK to see the list (WalletRequest).
--   * the saved counters live in data.wallet of the profile (piece 17). Scrap is read from piece 18, never written here.
--   * a shop or chest piece spends through WalletSystem.spend; nothing else lowers a balance.
-- If the profile module is missing, balances live in memory (status "temporary").
--
-- For other server pieces:
--   WalletSystem.grant(player, id, amount, key)  -> ok, reason?   once per key (key: letters, digits, _ : . -, 100 max)
--   WalletSystem.spend(player, id, amount)       -> ok, reason?   all or nothing; reason "tooPoor" | "badAmount" | ...
--   WalletSystem.balance(player, id)             -> number?       nil until the profile is loaded (saved counters only)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ids = require(Shared.Ids)
local WalletMemoryStore = require(Shared.Wallet.WalletMemoryStore)
local WalletRules = require(Shared.Wallet.WalletRules)
local WalletService = require(Shared.Wallet.WalletService)

local Server = script.Parent.Parent
local Net = require(Server.Core.Net)

local WalletSystem = {}
WalletSystem.order = 65 -- after ProgressionSystem (60), before DailySystem (70)

local service: WalletService.Service? = nil

local function findModule(folderName: string, moduleName: string): any?
	local folder = Server:FindFirstChild(folderName)
	local module = if folder then folder:FindFirstChild(moduleName) else nil
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn(`[wallet] {moduleName} failed to load: {result}`)
		return nil
	end
	return result
end

local function copyWallet(raw: any): WalletRules.Wallet
	local w: WalletRules.Wallet = {}
	if type(raw) == "table" then
		for key, value in raw do
			if type(key) == "string" and type(value) == "number" then
				w[key] = value
			end
		end
	end
	return WalletRules.fill(w)
end

local function profileStore(Profiles: any): WalletService.Store
	local store = {} :: WalletService.Store
	function store.status(player: any): string
		return Profiles.status(player)
	end
	function store.read(player: any): WalletRules.Wallet?
		local profile = Profiles.get(player)
		if profile == nil then
			return nil
		end
		return copyWallet(profile.data.wallet) -- a copy: change it only through update
	end
	local function inProfile(fn: (WalletRules.Wallet) -> boolean?): ({ [string]: any }) -> boolean?
		return function(data: { [string]: any }): boolean?
			if type(data.wallet) ~= "table" then
				data.wallet = {}
			end
			return fn(WalletRules.fill(data.wallet))
		end
	end
	function store.update(player: any, fn: (WalletRules.Wallet) -> boolean?): (boolean, string?)
		return Profiles.update(player, inProfile(fn))
	end
	function store.grantOnce(
		player: any,
		key: string,
		fn: (WalletRules.Wallet) -> boolean?
	): (boolean, string?)
		return Profiles.grantOnce(player, key, inProfile(fn))
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
		return nil -- bots
	end
	return Players:GetPlayerByUserId(userId)
end

function WalletSystem.grant(
	player: Player,
	id: string,
	amount: number,
	key: string
): (boolean, string?)
	local s = service
	if s == nil then
		return false, "notStarted"
	end
	return s.grant(player, id, amount, key)
end

function WalletSystem.spend(player: Player, id: string, amount: number): (boolean, string?)
	local s = service
	if s == nil then
		return false, "notStarted"
	end
	return s.spend(player, id, amount)
end

function WalletSystem.balance(player: Player, id: string): number?
	local s = service
	return if s then s.balance(player, id) else nil
end

function WalletSystem.start()
	local Profiles = findModule("Profile", "Profiles")
	local memory: WalletService.Store? = nil
	local store: WalletService.Store
	if Profiles ~= nil then
		store = profileStore(Profiles)
	else
		warn("[wallet] no profile module: stars are NOT saved (temporary)")
		local mem = WalletMemoryStore.new()
		memory = mem
		store = mem
	end

	local Progression = findModule("Progression", "ProgressionSystem")
	if Progression == nil then
		warn("[wallet] no coin system: the bar shows 0 Scrap")
	end

	local svc = WalletService.new({
		store = store,
		scrap = function(player: any): number?
			if Progression == nil then
				return nil
			end
			return Progression.getCoins(player)
		end,
		send = function(player: any, state)
			Net.fire("WalletState", player, state)
		end,
	})
	service = svc

	-- A finished match: once per player per match (piece 05). `won` is false for a shared first place.
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
				then Profiles.matchReceiptKey(matchId)
				else `{game.JobId}:{matchId}`
			svc.onMatch(player, place, won == true, key)
		end
	)

	Net.onRequest("WalletRequest", function(player)
		svc.push(player)
	end)

	-- Scrap moved (match reward, daily, track unlock): redraw the bar.
	if Progression ~= nil then
		Progression.Changed:connect(function(player: Player)
			svc.push(player)
		end)
	end
	if Profiles ~= nil then
		Profiles.Loaded:connect(function(player: Player)
			svc.push(player)
		end)
		Profiles.StatusChanged:connect(function(player: Player)
			svc.push(player)
		end)
	else
		Players.PlayerAdded:Connect(function(player)
			svc.push(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		task.spawn(svc.push, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		if memory ~= nil and memory.release ~= nil then
			memory.release(player)
		end
	end)
end

return WalletSystem
