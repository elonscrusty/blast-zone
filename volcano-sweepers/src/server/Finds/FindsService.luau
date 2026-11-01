--!strict
-- The Finds Book on the server: hidden treasure found while sweeping, set rewards, geyser gems.
-- The rules live in shared/Finds/FindRoller + shared/Burp/BurpGlue (tested in Lune); this file only
-- connects them to PlayerState, the profile and the remotes.
--
--   FindsService.init()                                  once (Main calls it after SweepService)
--   FindsService.onCleared(player, zoneId, clearedCount) SweepService calls this after each swing that
--                                                        took cells to bare ground. Rolls once per
--                                                        cleared cell, rationed per player by
--                                                        FindRoller.takeRolls (~1.5 a second).
--   FindsService.grantGeyserGem(player, coins) -> paid   GeyserService calls this for a picked-up gem.
--                                                        `coins` is BEFORE the sell multiplier.
--
-- Remotes used: FindFound (FindInfo), Toast, ClaimSet (client asks; the server checks everything).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BurpGlue = require(Shared.Burp.BurpGlue)
local FindRoller = require(Shared.Finds.FindRoller)
local Finds = require(Shared.Catalog.Finds)
local Rng = require(Shared.Rng)
local Types = require(Shared.Types)
local Zones = require(Shared.Catalog.Zones)

local Net = require(script.Parent.Parent.Core.Net)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)
local Profiles = require(script.Parent.Parent.Profile.Profiles)

local MAX_GEM_COINS = 5e7 -- one gem can never pay more than this before multipliers
local GEM_TOAST_WINDOW = 0.6 -- seconds: a handful of gems grabbed together make one toast

local FindsService = {}

local started = false
local rng = Rng.new(os.time() + math.floor(os.clock() * 1000))
local gemPending: { [Player]: number } = {}
local budgets: { [Player]: FindRoller.Budget } = {}

local function toast(player: Player, text: string, kind: "info" | "good" | "warn" | "gold")
	local info: Types.ToastInfo = { text = text, kind = kind }
	Net.fire("Toast", player, info)
end

-- Rolls for hidden finds once per cleared cell.
function FindsService.onCleared(player: Player, zoneId: number, clearedCount: number)
	local state = PlayerState.get(player)
	if state == nil then
		return
	end
	if type(zoneId) ~= "number" or Zones.byId[zoneId] == nil then
		return
	end
	local now = os.clock()
	local budget = budgets[player]
	if budget == nil then
		budget = FindRoller.newBudget(now)
		budgets[player] = budget
	end
	local rolls =
		FindRoller.takeRolls(budget :: FindRoller.Budget, now, BurpGlue.rollCount(clearedCount))
	if rolls == 0 then
		return
	end
	local profile = state.profile
	local luck = BurpGlue.luckBonus(state.derived.luck)
	local sellMult = state.derived.sellMult
	local setList = Finds.list :: { { id: string, set: string } }
	local setById = Finds.setById :: { [string]: any }

	for _ = 1, rolls do
		local found = FindRoller.roll(rng, luck, zoneId, Finds.list :: any, Finds.rarities :: any)
		local def = if found ~= nil then Finds.byId[found.id] else nil
		if def ~= nil then
			local isNew = BurpGlue.recordFind(profile.finds, def.id)
			local coins = BurpGlue.findCoins(def.coins, sellMult)
			PlayerState.addCoins(player, coins)
			PlayerState.addStat(player, "findsTotal", 1)
			PlayerState.touch(player, "finds")
			local info: Types.FindInfo = {
				id = def.id,
				rarity = def.rarity,
				isNew = isNew,
				coins = coins,
			}
			Net.fire("FindFound", player, info)
			local t = BurpGlue.findToast(def.rarity, def.name)
			if t ~= nil then
				Net.fire("Toast", player, t)
			end
			if isNew then
				local complete = BurpGlue.claimCheck(
					def.set,
					profile.finds,
					profile.setsClaimed,
					setById,
					setList
				)
				if complete then
					local set = Finds.setById[def.set]
					toast(player, `{set.name} complete! Open the Book to claim it.`, "gold")
				end
			end
		end
	end
end

-- A gem from a geyser: pays `coins` x the player's coin multiplier. Returns the coins paid.
function FindsService.grantGeyserGem(player: Player, coins: number): number
	local state = PlayerState.get(player)
	if state == nil or not BurpGlue.finite(coins) or coins <= 0 then
		return 0
	end
	local paid = BurpGlue.findCoins(math.min(coins, MAX_GEM_COINS), state.derived.sellMult)
	if paid <= 0 then
		return 0
	end
	PlayerState.addCoins(player, paid)
	local pending = gemPending[player]
	if pending ~= nil then
		gemPending[player] = pending + paid
	else
		gemPending[player] = paid
		task.delay(GEM_TOAST_WINDOW, function()
			local sum = gemPending[player]
			gemPending[player] = nil
			if sum ~= nil and player.Parent ~= nil then
				toast(player, `Gem! +{math.floor(sum)} coins`, "gold")
			end
		end)
	end
	return paid
end

local function onClaimSet(player: Player, id: string)
	local state = PlayerState.get(player)
	if state == nil then
		return
	end
	local profile = state.profile
	local ok, why = BurpGlue.claimCheck(
		id,
		profile.finds,
		profile.setsClaimed,
		Finds.setById :: { [string]: any },
		Finds.list :: { { id: string, set: string } }
	)
	if not ok then
		if why == "incomplete" then
			toast(player, "Find every treasure in the set first!", "warn")
		elseif why == "claimed" then
			toast(player, "You already took this reward.", "info")
		end
		return
	end
	local set = Finds.setById[id]
	profile.setsClaimed[id] = true
	PlayerState.recompute(player) -- sellMult now includes the set bonus
	PlayerState.touch(player, "setsClaimed", "derived")
	Profiles.saveSoon(player)
	toast(player, BurpGlue.setClaimText(set.reward), "gold")
end

function FindsService.init()
	if started then
		return
	end
	started = true
	Net.onRequest("ClaimSet", function(player: Player, ...: any)
		local id = ...
		if type(id) == "string" then
			onClaimSet(player, id)
		end
	end)
	PlayerState.onLeaving:connect(function(player: Player)
		gemPending[player] = nil
		budgets[player] = nil
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		gemPending[player] = nil
		budgets[player] = nil
	end)
end

return FindsService
