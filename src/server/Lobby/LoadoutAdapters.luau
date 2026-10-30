--!strict
-- Connects the loadout to the other pieces without hard-wiring to them:
--   piece 17  Profile/Profiles  : saves data.loadout (slot -> item id)
--   piece 18  Progression/ProgressionSystem : the player's reward level (0..6) and coins
--   piece N11 Character/CharacterStyler : puts the chosen fighter look on a standing body
-- Either one may be missing (they land in their own PRs). Then picks last this visit only and only
-- free items are open. Nothing here is trusted from a client.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loadout = require(Shared.Loadout)
local LoadoutStore = require(Shared.LoadoutStore)

local Adapters = {}

local function optionalModule(folderName: string, moduleName: string): any?
	local folder = script.Parent.Parent:FindFirstChild(folderName)
	local module = if folder then folder:FindFirstChild(moduleName) else nil
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			return result
		end
		warn(`[lobby] could not load {folderName}.{moduleName}: {result}`)
	end
	return nil
end

-- Resolved late, because the other pieces start in their own order.
local profilesModule: any? = nil
local progressionModule: any? = nil
local stylerModule: any? = nil
local looked = false
local function resolve()
	if looked then
		return
	end
	looked = true
	profilesModule = optionalModule("Profile", "Profiles")
	progressionModule = optionalModule("Progression", "ProgressionSystem")
	stylerModule = optionalModule("Character", "CharacterStyler")
end

function Adapters.profiles(): any?
	resolve()
	return profilesModule
end

function Adapters.progression(): any?
	resolve()
	return progressionModule
end

function Adapters.styler(): any?
	resolve()
	return stylerModule
end

local function playerOf(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

function Adapters.make(): LoadoutStore.Deps
	return {
		read = function(userId: number): { [string]: any }?
			local profiles = Adapters.profiles()
			local player = playerOf(userId)
			if not profiles or not player then
				return nil
			end
			local profile = profiles.get(player)
			if not profile or type(profile.data) ~= "table" then
				return nil
			end
			local saved = profile.data.loadout
			if type(saved) ~= "table" then
				return nil
			end
			local copy: { [string]: any } = {}
			for _, slot in Loadout.slots do
				local id = saved[slot]
				if type(id) == "string" then
					copy[slot] = id
				end
			end
			return copy
		end,

		write = function(userId: number, slot: string, id: string): boolean
			local profiles = Adapters.profiles()
			local player = playerOf(userId)
			if not profiles or not player then
				return false
			end
			local ok = profiles.update(player, function(data: any)
				if type(data.loadout) ~= "table" then
					data.loadout = {}
				end
				data.loadout[slot] = id
				return true
			end)
			return ok == true
		end,

		unlocks = function(userId: number): Loadout.Unlocks
			local progression = Adapters.progression()
			local player = playerOf(userId)
			local level = 0
			if progression and player then
				local ok, value = pcall(progression.getLevel, player)
				if ok and type(value) == "number" then
					level = value
				end
			end
			return { level = level }
		end,

		saved = function(userId: number): boolean
			local profiles = Adapters.profiles()
			local player = playerOf(userId)
			if not profiles or not player then
				return false
			end
			return profiles.status(player) == "ready"
		end,
	}
end

-- Scrap (coins) for the screen. nil until the saved data is loaded or when piece 18 is absent.
function Adapters.coins(player: Player): number?
	local progression = Adapters.progression()
	if not progression then
		return nil
	end
	local ok, value = pcall(progression.getCoins, player)
	if ok and type(value) == "number" then
		return value
	end
	return nil
end

return Adapters
