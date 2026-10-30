--!strict
-- Piece 19: the lobby plaza and the loadout. Starts itself (any `*System` module does).
--   * builds Workspace.Lobby (LobbyBuilder) before players spawn, so piece 05 finds the LobbySpawn part
--   * keeps each player's loadout (outfit, gun skin, Slide sidegrade): the server checks every pick
--   * the OUTFIT slot is piece N11's three fighters: this sets the player's CharacterLook attribute (and
--     restyles a body already standing), and follows N11's own look buttons so the two never disagree
--   * tells other pieces what to read:
--       Player attributes  OutfitId, GunSkin, SlideVariant   (gun code may read GunSkin)
--       EffectiveStats modifier  applies the Slide sidegrade to the player's stat sheet
-- Picks can only change while you are out of the match (not on the roster).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local Loadout = require(Shared.Loadout)
local LoadoutStore = require(Shared.LoadoutStore)

local Core = script.Parent.Parent.Core
local EffectiveStats = require(Core.EffectiveStats)
local Net = require(Core.Net)
local Participants = require(Core.Participants)

local Adapters = require(script.Parent.LoadoutAdapters)
local LobbyBuilder = require(script.Parent.LobbyBuilder)

local LobbySystem = {}
LobbySystem.order = 20 -- after the arena (10), before match flow (50) sends anyone to the lobby

local store: any = nil

local function stateFor(player: Player): any
	local userId = player.UserId
	local unlocks = (Adapters.make() :: LoadoutStore.Deps).unlocks(userId)
	local selection = store:get(userId)
	return {
		selection = selection,
		unlocked = Loadout.unlockedIds(unlocks),
		level = unlocks.level,
		coins = Adapters.coins(player),
		saved = store:isSaved(userId),
	}
end

local function sendState(player: Player)
	if player.Parent == nil then
		return
	end
	Net.fire("LoadoutState", player, stateFor(player))
end

local function publishAttributes(player: Player)
	local selection = store:get(player.UserId)
	player:SetAttribute("OutfitId", selection.outfit)
	player:SetAttribute("GunSkin", selection.gun)
	player:SetAttribute("SlideVariant", selection.slide)
end

local function lookAttribute(): string
	return Config.Character.lookAttribute
end

-- Makes the player's fighter match their loadout. N11's styler reads the attribute at every spawn;
-- a body that is already standing is restyled now.
local function dress(player: Player)
	local item = Loadout.find("outfit", store:get(player.UserId).outfit)
	local fighter = if item then item.fighter else nil
	if fighter and player:GetAttribute(lookAttribute()) ~= fighter then
		player:SetAttribute(lookAttribute(), fighter)
		local character = player.Character
		local styler = Adapters.styler()
		if character and character.Parent and styler then
			styler.apply(character)
		end
	end
end

local function watchCharacter(player: Player)
	player.CharacterAdded:Connect(function()
		publishAttributes(player)
		dress(player) -- before N11 styles the new body, in case the attribute was lost
	end)
	-- N11's own look buttons change the attribute directly; take that as a loadout pick (or put it back).
	player:GetAttributeChangedSignal(lookAttribute()):Connect(function()
		local value = player:GetAttribute(lookAttribute())
		for _, item in Loadout.items.outfit do
			if item.fighter == value and store:get(player.UserId).outfit ~= item.id then
				local ok = store:equip(player.UserId, "outfit", item.id)
				if not ok then
					dress(player) -- still locked: put the saved fighter back
				end
				return
			end
		end
	end)
end

local function onPlayerAdded(player: Player)
	watchCharacter(player)
	publishAttributes(player)
	-- Saved picks arrive once the profile has loaded (piece 17). Show the screen what we have now, then again.
	task.spawn(function()
		local profiles = Adapters.profiles()
		if profiles and profiles.waitForLoad then
			pcall(profiles.waitForLoad, player, 15)
		end
		if player.Parent then
			publishAttributes(player)
			dress(player)
			sendState(player)
		end
	end)
	sendState(player)
end

function LobbySystem.start()
	LobbyBuilder.build()
	store = LoadoutStore.new(Adapters.make())

	-- Slide sidegrade: applied to a copy of the stat sheet, after upgrades (piece 08).
	EffectiveStats:addModifier(function(participantId: string, sheet: any)
		local userId = Ids.userIdOf(participantId)
		if userId then
			Loadout.applySlide(sheet, store:get(userId).slide)
		end
	end)

	store.Changed:connect(function(userId: number)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			publishAttributes(player)
			dress(player)
			EffectiveStats:invalidate(Ids.player(userId))
			sendState(player)
		end
	end)

	Net.onRequest("LoadoutSync", function(player: Player)
		sendState(player)
	end)

	Net.onRequest("LoadoutEquip", function(player: Player, slot: string, itemId: string)
		-- Not while you are part of a match: a Slide swap mid-fight would be a free edge.
		if Participants:get(Ids.player(player.UserId)) ~= nil then
			Net.fire(
				"Notice",
				player,
				{ text = "Pick your loadout between matches.", kind = "info" }
			)
			return
		end
		local ok, reason = store:equip(player.UserId, slot, itemId)
		if not ok then
			if reason == "locked" then
				Net.fire(
					"Notice",
					player,
					{ text = "Still locked. Earn it on the Rewards board.", kind = "info" }
				)
			end
			sendState(player) -- put the screen back in step with the server
		end
	end)

	-- Piece 17 and 18 may load later or change what is open: tell the screen.
	local profiles = Adapters.profiles()
	if profiles and profiles.Loaded then
		profiles.Loaded:connect(function(player: Player)
			publishAttributes(player)
			dress(player)
			sendState(player)
		end)
	end
	local progression = Adapters.progression()
	if progression and progression.Changed then
		progression.Changed:connect(function(player: Player)
			sendState(player)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		store:forget(player.UserId)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function LobbySystem.getStore(): any
	return store
end

return LobbySystem
