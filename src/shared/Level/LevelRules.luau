--!strict
-- Pure rules for the account level (piece 34). The saved numbers live in the progression table (accountXp,
-- claimedLevels). Run XP from a match goes in through addXp; the level and every gift come out of it, in one
-- change, so a repeat can never pay a gift twice. No Roblox: Lune tests it.

local Config = require("../Config")
local LevelDefs = require("./LevelDefs")
local ProgressRules = require("../Progression/ProgressRules")
local TrackDefs = require("../Progression/TrackDefs")

local LevelRules = {}

export type Info = {
	level: number,
	intoLevel: number, -- XP earned toward the next level
	forNext: number?, -- XP the next level needs (nil at the top)
}

export type Reward = { level: number, kind: string, amount: number?, itemId: string? }

export type Result = {
	ok: boolean,
	reason: string?,
	fromLevel: number,
	toLevel: number,
	rewards: { Reward },
}

-- XP needed to leave this level.
function LevelRules.costOf(level: number): number
	return Config.Level.firstCost + Config.Level.costStep * (level - 1)
end

function LevelRules.info(accountXp: number): Info
	local level = 1
	local left = accountXp
	while level < Config.Level.maxLevel do
		local cost = LevelRules.costOf(level)
		if left < cost then
			return { level = level, intoLevel = left, forNext = cost }
		end
		left -= cost
		level += 1
	end
	return { level = level, intoLevel = 0, forNext = nil }
end

function LevelRules.levelOf(p: ProgressRules.Progression): number
	return LevelRules.info(p.accountXp).level
end

local function refuse(reason: string, level: number): Result
	return { ok = false, reason = reason, fromLevel = level, toLevel = level, rewards = {} }
end

-- Adds a match's run XP and hands out every gift for the levels reached that was not given yet. All or nothing:
-- a refusal leaves the table as it was. `maxGrant` is a sanity cap so a bug upstream cannot mint levels.
function LevelRules.addXp(p: ProgressRules.Progression, amount: number, maxGrant: number): Result
	local before = LevelRules.levelOf(p)
	if
		type(amount) ~= "number"
		or amount ~= amount
		or amount < 0
		or amount ~= math.floor(amount)
	then
		return refuse("badAmount", before)
	end
	if amount > maxGrant then
		return refuse("tooMuch", before)
	end
	if p.accountXp + amount >= 1e9 then
		return refuse("full", before)
	end
	p.accountXp += amount
	local after = LevelRules.levelOf(p)
	local rewards: { Reward } = {}
	for _, g in LevelDefs.gifts do
		local key = tostring(g.level)
		if g.level <= after and not p.claimedLevels[key] then
			p.claimedLevels[key] = true
			if g.kind == "scrap" then
				local pay = math.min(g.amount or 0, 1e9 - 1 - p.coins)
				if pay > 0 then
					p.coins += pay
					p.totalEarned += pay
				end
				table.insert(rewards, { level = g.level, kind = "scrap", amount = pay })
			elseif g.itemId ~= nil and TrackDefs.get(g.itemId) ~= nil then
				p.unlocked[g.itemId] = true
				table.insert(rewards, { level = g.level, kind = "item", itemId = g.itemId })
			end
		end
	end
	return { ok = true, reason = nil, fromLevel = before, toLevel = after, rewards = rewards }
end

return LevelRules
