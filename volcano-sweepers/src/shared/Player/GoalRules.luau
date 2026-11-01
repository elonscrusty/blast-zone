--!strict
-- Goal claiming rules. A goal is done when profile.stats[goal.stat] >= goal.target; its reward is
-- paid once (profile.goalsClaimed[id] flips to true in the same step as the payment).

local Types = require("../Types")
local Goals = require("../Catalog/Goals")
local Wallet = require("./Wallet")

local GoalRules = {}

export type Status = "locked" | "ready" | "claimed"

export type Paid = { id: string, name: string, coins: number, sparks: number }

function GoalRules.status(goal: Goals.Goal, profile: Types.Profile): Status
	if profile.goalsClaimed[goal.id] == true then
		return "claimed"
	end
	if Goals.isDone(goal, profile.stats) then
		return "ready"
	end
	return "locked"
end

-- How many goals can be claimed right now.
function GoalRules.readyCount(profile: Types.Profile): number
	local n = 0
	for _, goal in Goals.list do
		if GoalRules.status(goal, profile) == "ready" then
			n += 1
		end
	end
	return n
end

-- Claims goal `id`. Returns the payment, or nil and a short reason. Changes nothing on failure.
function GoalRules.claim(profile: Types.Profile, id: any): (Paid?, string?)
	if type(id) ~= "string" then
		return nil, "Unknown goal"
	end
	local goal = Goals.byId[id]
	if goal == nil then
		return nil, "Unknown goal"
	end
	local status = GoalRules.status(goal, profile)
	if status == "claimed" then
		return nil, "Already claimed!"
	elseif status == "locked" then
		return nil, "Keep going, you are not there yet!"
	end
	profile.goalsClaimed[goal.id] = true
	local coins, sparks = Wallet.earn(profile, goal.rewardCoins, goal.rewardSparks)
	return { id = goal.id, name = goal.name, coins = coins, sparks = sparks }, nil
end

return GoalRules
