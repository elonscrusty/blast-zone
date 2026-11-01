--!strict
-- The Goals list as plain data. Pure. Order: goals you can claim first, then goals still to do
-- (closest to done first), then claimed goals at the bottom (shown small).
--   GoalsModel.build(source) -> View
--   GoalsModel.badge(source) -> boolean         true when at least one goal can be claimed
-- `source` is the store view or a profile: it needs `stats` and `goalsClaimed` (missing = empty).

local Goals = require("../Catalog/Goals")
local Format = require("./Format")

local GoalsModel = {}

export type Source = { [string]: any }

export type Status = "ready" | "locked" | "claimed"

export type Card = {
	id: string,
	name: string,
	icon: string,
	status: Status,
	desc: string, -- "Sweep 200 ash"
	progress: number, -- clamped to target
	target: number,
	fraction: number, -- 0..1
	progressText: string, -- "120/200"
	rewardCoins: number,
	rewardSparks: number,
	rewardText: string, -- "💰 300  ✨ 2"
	rewardShort: string, -- "300 coins, 2 Sparks" (plain words)
}

export type View = {
	cards: { Card }, -- display order
	readyCount: number,
	claimedCount: number,
	total: number,
	headerText: string,
	allDone: boolean,
	badge: boolean,
}

local ICONS: { [string]: string } = {
	ashSwept = "🧹",
	sellCount = "💰",
	findsTotal = "💎",
	cleared = "✨",
	burpHits = "🌋",
	burpDodged = "🏃",
	playSeconds = "⏰",
}

local function stat(stats: any, key: string): number
	if type(stats) ~= "table" then
		return 0
	end
	local v = (stats :: { [string]: any })[key]
	if type(v) ~= "number" or v ~= v or v < 0 then
		return 0
	end
	return v
end

local function plural(n: number, one: string, many: string): string
	return if n == 1 then one else many
end

local function timeWords(seconds: number): string
	if seconds >= 3600 then
		local h = math.floor(seconds / 3600)
		return `{h} {plural(h, "hour", "hours")}`
	end
	local m = math.max(1, math.floor(seconds / 60))
	return `{m} {plural(m, "minute", "minutes")}`
end

-- What the goal asks for, in short kid words.
function GoalsModel.describe(goal: Goals.Goal): string
	local n = Format.compact(goal.target)
	local t = goal.stat
	if t == "ashSwept" then
		return `Sweep {n} ash`
	elseif t == "sellCount" then
		return `Sell {n} {plural(goal.target, "time", "times")}`
	elseif t == "findsTotal" then
		return `Find {n} {plural(goal.target, "treasure", "treasures")}`
	elseif t == "cleared" then
		return `Sweep {n} spots down to bare ground`
	elseif t == "burpHits" then
		return `Get bounced by lava {n} {plural(goal.target, "time", "times")}`
	elseif t == "burpDodged" then
		return `Dodge {n} volcano {plural(goal.target, "burp", "burps")}`
	elseif t == "playSeconds" then
		return `Play for {timeWords(goal.target)}`
	end
	return goal.name
end

local function progressText(goal: Goals.Goal, value: number): string
	if goal.stat == "playSeconds" then
		-- minutes read easier than seconds
		return `{Format.compact(math.floor(value / 60))}/{Format.compact(
			math.floor(goal.target / 60)
		)} min`
	end
	return Format.pair(math.floor(value), goal.target)
end

local function rewardTexts(goal: Goals.Goal): (string, string)
	local icon: { string } = {}
	local words: { string } = {}
	if goal.rewardCoins > 0 then
		table.insert(icon, `💰 {Format.compact(goal.rewardCoins)}`)
		table.insert(words, `{Format.compact(goal.rewardCoins)} coins`)
	end
	if goal.rewardSparks > 0 then
		table.insert(icon, `✨ {goal.rewardSparks}`)
		table.insert(words, `{goal.rewardSparks} {plural(goal.rewardSparks, "Spark", "Sparks")}`)
	end
	return table.concat(icon, "  "), table.concat(words, ", ")
end

function GoalsModel.build(source: Source): View
	local stats = source.stats
	local claimedMap = source.goalsClaimed
	local ready: { Card } = {}
	local locked: { Card } = {}
	local claimed: { Card } = {}

	for _, goal in Goals.list do
		local value = stat(stats, goal.stat)
		local done = value >= goal.target
		local isClaimed = type(claimedMap) == "table"
			and (claimedMap :: { [string]: any })[goal.id] == true
		local status: Status = if isClaimed then "claimed" elseif done then "ready" else "locked"
		local rewardText, rewardShort = rewardTexts(goal)
		local card: Card = {
			id = goal.id,
			name = goal.name,
			icon = ICONS[goal.stat] or "🎯",
			status = status,
			desc = GoalsModel.describe(goal),
			progress = math.min(value, goal.target),
			target = goal.target,
			fraction = if goal.target > 0 then math.clamp(value / goal.target, 0, 1) else 1,
			progressText = progressText(goal, math.min(value, goal.target)),
			rewardCoins = goal.rewardCoins,
			rewardSparks = goal.rewardSparks,
			rewardText = rewardText,
			rewardShort = rewardShort,
		}
		if status == "ready" then
			table.insert(ready, card)
		elseif status == "locked" then
			table.insert(locked, card)
		else
			table.insert(claimed, card)
		end
	end

	-- closest to done first; table.sort is not stable, so ties fall back to the catalog position
	local position: { [string]: number } = {}
	for i, goal in Goals.list do
		position[goal.id] = i
	end
	table.sort(locked, function(a: Card, b: Card)
		if a.fraction ~= b.fraction then
			return a.fraction > b.fraction
		end
		return position[a.id] < position[b.id]
	end)

	local cards: { Card } = {}
	for _, list in { ready, locked, claimed } do
		for _, card in list do
			table.insert(cards, card)
		end
	end

	local total = #Goals.list
	local header: string
	if #ready > 0 then
		header = `{#ready} {plural(#ready, "reward is", "rewards are")} ready!`
	elseif #claimed >= total then
		header = "All goals done! Wow!"
	else
		header = `Goals done: {#claimed} / {total}`
	end
	return {
		cards = cards,
		readyCount = #ready,
		claimedCount = #claimed,
		total = total,
		headerText = header,
		allDone = #claimed >= total,
		badge = #ready > 0,
	}
end

function GoalsModel.badge(source: Source): boolean
	return GoalsModel.build(source).badge
end

return GoalsModel
