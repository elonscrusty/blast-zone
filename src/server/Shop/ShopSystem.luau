--!strict
-- The Scrap Shop on the server (video 3 gap 18). Connects Roblox to ShopService, which holds the rules:
--   * what is on sale depends only on the day number (same on every server); the price is the shop's, not a client's.
--   * BuyRequest only ASKS; ProgressService.buy checks stock, ownership and Scrap, and changes everything or nothing.
--   * "has this player opened today's shop" is saved in data.shop of the profile (piece 17).
-- If the profile module is missing the "new" mark lives in memory and the shop says "temporary".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ShopService = require(Shared.Shop.ShopService)

local Server = script.Parent.Parent
local Net = require(Server.Core.Net)
local ProgressionSystem = require(Server.Progression.ProgressionSystem)

local ShopSystem = {}
ShopSystem.order = 65 -- after ProgressionSystem (60)

local function findProfiles(): any?
	local folder = Server:FindFirstChild("Profile")
	local module = if folder then folder:FindFirstChild("Profiles") else nil
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, profiles = pcall(require, module)
	if not ok then
		warn(`[shop] Profiles failed to load: {profiles}`)
		return nil
	end
	return profiles
end

function ShopSystem.start()
	local Profiles = findProfiles()
	local seenInMemory: { [Player]: number } = {}

	local function seenDay(player: any): number?
		if Profiles == nil then
			return seenInMemory[player]
		end
		local profile = Profiles.get(player)
		local shop = if profile then profile.data.shop else nil
		if type(shop) == "table" and type(shop.seenDay) == "number" then
			return shop.seenDay
		end
		return nil
	end

	local function setSeenDay(player: any, day: number)
		if Profiles == nil then
			seenInMemory[player] = day
			return
		end
		Profiles.update(player, function(data: any)
			if type(data.shop) ~= "table" then
				data.shop = {}
			end
			data.shop.seenDay = day
			return true
		end)
		Profiles.saveSoon(player)
	end

	local service = ShopService.new({
		buy = function(player: any, itemId: string, day: number): (boolean, string?)
			return ProgressionSystem.buy(player, itemId, day)
		end,
		status = function(player: any): string
			if Profiles ~= nil then
				return Profiles.status(player)
			end
			return "temporary"
		end,
		seenDay = seenDay,
		setSeenDay = setSeenDay,
		send = function(player: any, state)
			Net.fire("ShopState", player, state)
		end,
		now = os.time,
		resetHour = Config.Daily.resetHourUtc,
	})

	Net.onRequest("ShopRequest", function(player)
		service.push(player)
	end)
	Net.onRequest("ShopSeenRequest", function(player)
		service.markSeen(player)
	end)
	Net.onRequest("BuyRequest", function(player, itemId: string)
		service.buy(player, itemId)
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
		seenInMemory[player] = nil
	end)
end

return ShopSystem
