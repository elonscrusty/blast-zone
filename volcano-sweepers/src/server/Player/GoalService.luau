--!strict
-- ClaimGoal: a goal is paid once, when its stat reached the target (rules in Shared/Player/GoalRules).
-- Also a small nudge: when a goal becomes ready the player gets a Toast, once per goal per visit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Goals = require(Shared.Catalog.Goals)
local GoalRules = require(Shared.Player.GoalRules)
local PurchaseRules = require(Shared.Player.PurchaseRules)

local Net = require(script.Parent.Parent.Core.Net)
local Profiles = require(script.Parent.Parent.Profile.Profiles)
local PlayerState = require(script.Parent.PlayerState)

local CHECK_SECONDS = 10

local GoalService = {}

local started = false
local announced: { [Player]: { [string]: boolean } } = {}

local function claim(player: Player, id: string)
	local state = PlayerState.get(player)
	if state == nil then
		return
	end
	local paid, why = GoalRules.claim(state.profile, id)
	if paid == nil then
		PlayerState.toast(player, why or "Can't claim that yet", "warn")
		return
	end
	PlayerState.touch(player, "coins", "runCoins", "lifetimeCoins", "sparks", "goalsClaimed")
	if paid.sparks > 0 then
		PlayerState.recompute(player) -- Sparks change the coin multiplier
	end
	local text = `{paid.name}! +{PurchaseRules.fmt(paid.coins)} coins`
	if paid.sparks > 0 then
		text ..= ` and +{paid.sparks} Sparks`
	end
	PlayerState.toast(player, text, "gold")
	Profiles.saveSoon(player)
end

local function announceReady()
	for _, state in PlayerState.all() do
		local mine = announced[state.player]
		if mine == nil then
			mine = {}
			announced[state.player] = mine
		end
		for _, goal in Goals.list do
			if not mine[goal.id] and GoalRules.status(goal, state.profile) == "ready" then
				mine[goal.id] = true
				PlayerState.toast(
					state.player,
					`Goal done: {goal.name}! Tap Goals to collect.`,
					"good"
				)
				break -- one hint per check, never a flood
			end
		end
	end
end

function GoalService.init()
	if started then
		return
	end
	started = true

	Net.onRequest("ClaimGoal", claim)

	Players.PlayerRemoving:Connect(function(player)
		announced[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			local ok, err = pcall(announceReady)
			if not ok then
				warn(`[Goals] check failed: {err}`)
			end
		end
	end)
end

return GoalService
