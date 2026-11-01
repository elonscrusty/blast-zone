--!strict
-- ClaimDaily: the UTC day, the streak and the ladder come from Shared/Player/DailyRules. The payment
-- goes through Profiles.grantOnce with the day's receipt key, so a double tap, a retry or a second
-- server can never pay the same day twice (the receipt is saved in the same write as the coins).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DailyRules = require(Shared.Player.DailyRules)
local PurchaseRules = require(Shared.Player.PurchaseRules)

local Net = require(script.Parent.Parent.Core.Net)
local Profiles = require(script.Parent.Parent.Profile.Profiles)
local PlayerState = require(script.Parent.PlayerState)

local HINT_DELAY = 6 -- seconds after joining before the "gift waiting" hint

local DailyService = {}

local started = false

local function claim(player: Player)
	local state = PlayerState.get(player)
	if state == nil then
		return
	end
	local today = DailyRules.dayOf(os.time())
	local plan = DailyRules.plan(state.profile.daily, today)
	if not plan.canClaim then
		PlayerState.toast(player, plan.reason, "info")
		return
	end

	-- grantOnce runs the function on a copy and applies it only if it is valid; it does not yield.
	local out: { paid: DailyRules.Paid? } = { paid = nil }
	local ok, why = Profiles.grantOnce(player, Profiles.dailyKey(today), function(profile)
		out.paid = DailyRules.apply(profile, today)
		return out.paid ~= nil
	end)
	local paid = out.paid
	if not ok or paid == nil then
		if why == "duplicate" then
			PlayerState.toast(player, "You got today's gift! Come back tomorrow.", "info")
		else
			warn(`[Daily] claim for {player.Name} not paid: {tostring(why)}`)
			PlayerState.toast(player, "The gift box is stuck. Try again in a moment!", "warn")
		end
		return
	end

	PlayerState.touch(player, "coins", "runCoins", "lifetimeCoins", "sparks", "daily")
	PlayerState.recompute(player) -- Sparks change the coin multiplier
	local text = `Day {paid.ladderDay} gift! +{PurchaseRules.fmt(paid.coins)} coins`
	if paid.sparks > 0 then
		text ..= ` and +{paid.sparks} Sparks`
	end
	PlayerState.toast(player, text .. "!", "gold")
	task.spawn(function()
		Profiles.saveNow(player) -- the gift is safe on disk soon, even if the server closes
	end)
end

function DailyService.init()
	if started then
		return
	end
	started = true

	Net.onRequest("ClaimDaily", claim)

	PlayerState.onReady:connect(function(player: Player)
		task.delay(HINT_DELAY, function()
			if player.Parent ~= Players then
				return
			end
			local state = PlayerState.get(player)
			if
				state ~= nil
				and DailyRules.canClaim(state.profile.daily, DailyRules.dayOf(os.time()))
			then
				PlayerState.toast(player, "A daily gift is waiting for you!", "gold")
			end
		end)
	end)
end

return DailyService
