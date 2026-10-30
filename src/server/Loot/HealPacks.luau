--!strict
-- Heal packs a fighter carries (piece 42). Server only. A pack is taken from the street through
-- PickupSystem (same claim rules as XP orbs) and used on a button: UseHealRequest, or the bot sweep
-- in LootSystem. Every check is here: combat phase, alive, has a pack, not full health, cooldown.
-- The only thing the client gets is LootState, so it can draw the count.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local LootRules = require(Shared.Loot.LootRules)

local Core = script.Parent.Parent.Core
local MatchContext = require(Core.MatchContext)
local Net = require(Core.Net)
local Participants = require(Core.Participants)

local Combatants = require(script.Parent.Parent.Combat.Combatants)

local heal = Config.Loot.heal

local HealPacks = {}

local counts: { [string]: number } = {}
local readyAt: { [string]: number } = {} -- os.clock

-- Tell the owner how many packs they have. `event` is "picked", "used" or "denied" (with a `reason`)
-- for the client's little effect; nil is a plain refresh (late join, new match).
function HealPacks.push(id: string, event: string?, reason: string?)
	local p = Participants:get(id)
	if p == nil or p.player == nil then
		return
	end
	local wait = math.max(0, (readyAt[id] or 0) - os.clock())
	Net.fire("LootState", p.player, {
		healPacks = counts[id] or 0,
		max = heal.carryMax,
		readyAt = Workspace:GetServerTimeNow() + wait,
		serverNow = Workspace:GetServerTimeNow(),
		event = event,
		reason = reason,
	})
end

function HealPacks.count(id: string): number
	return counts[id] or 0
end

-- A pack picked up. False if the bag is full or the fighter cannot carry (out, wrong phase).
function HealPacks.add(id: string): boolean
	if not MatchContext:isCombat() or not Participants:isAlive(id) then
		return false
	end
	local n, taken = LootRules.addPack(counts[id] or 0, heal.carryMax)
	if not taken then
		return false
	end
	counts[id] = n
	HealPacks.push(id, "picked")
	return true
end

-- Uses one pack. Returns true, or false and the reason (see LootRules.canUse; "phase" outside combat).
function HealPacks.use(id: string): (boolean, string?)
	if not MatchContext:isCombat() then
		return false, "phase"
	end
	if not Participants:isAlive(id) then
		return false, "down"
	end
	local health = Combatants.health(id)
	local max = Combatants.book:max_(id)
	if health == nil or max == nil then
		return false, "down"
	end
	local now = os.clock()
	local ok, why = LootRules.canUse(counts[id] or 0, health, max, now, readyAt[id] or 0)
	if not ok then
		if why ~= "cooling" then
			HealPacks.push(id, "denied", why)
		end
		return false, why
	end
	local gained = Combatants.heal(id, heal.amount)
	if gained <= 0 then
		return false, "full"
	end
	counts[id] = (counts[id] or 1) - 1
	readyAt[id] = now + heal.useCooldownSeconds
	HealPacks.push(id, "used")
	return true, nil
end

-- A fighter who falls loses their packs. Returns how many they had.
function HealPacks.take(id: string): number
	local n = counts[id] or 0
	counts[id] = nil
	readyAt[id] = nil
	return n
end

function HealPacks.carriers(): { string }
	local out = {}
	for id, n in counts do
		if n > 0 then
			table.insert(out, id)
		end
	end
	return out
end

function HealPacks.clear()
	table.clear(counts)
	table.clear(readyAt)
end

return HealPacks
