--!strict
-- What this player knows about their coins and unlocks. Only the server writes it (ProgressState); the screens
-- here read it and ask (UnlockRequest / EquipRequest). Never trust or compute coin totals on the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ProgressRules = require(Shared.Progression.ProgressRules)
local Signal = require(Shared.Signal)
local TrackDefs = require(Shared.Progression.TrackDefs)
local Types = require(Shared.Types)
local Net = require(script.Parent.Parent.Core.Net)

local ProgressClient = {}
ProgressClient.Changed = Signal.new() -- (state)

local current: Types.ProgressState? = nil
local started = false

function ProgressClient.get(): Types.ProgressState?
	return current
end

-- The saved-style table the shared rules expect, rebuilt from the last state (look-only use: prices, next tier).
function ProgressClient.asProgression(): ProgressRules.Progression?
	local s = current
	if s == nil then
		return nil
	end
	local p = ProgressRules.new()
	p.coins = s.coins
	p.totalEarned = s.totalEarned
	for _, id in s.unlocked do
		p.unlocked[id] = true
	end
	for slot, id in s.equipped do
		p.equipped[slot] = id
	end
	return p
end

function ProgressClient.owns(itemId: string): boolean
	local p = ProgressClient.asProgression()
	return p ~= nil and ProgressRules.owns(p, itemId)
end

function ProgressClient.nextTier(): TrackDefs.Item?
	local p = ProgressClient.asProgression()
	return if p then ProgressRules.nextTier(p) else TrackDefs.tiers[1]
end

function ProgressClient.ensureStarted()
	if started then
		return
	end
	started = true
	Net.on("ProgressState", function(state: Types.ProgressState)
		current = state
		ProgressClient.Changed:fire(state)
	end)
	-- The server pushes on join, but this script may not have been listening yet: ask once.
	task.delay(1, function()
		if current == nil then
			Net.send("ProgressRequest")
		end
	end)
end

function ProgressClient.unlock(itemId: string)
	Net.send("UnlockRequest", itemId)
end

function ProgressClient.equip(itemId: string)
	Net.send("EquipRequest", itemId)
end

return ProgressClient
