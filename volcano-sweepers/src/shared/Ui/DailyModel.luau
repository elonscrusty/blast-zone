--!strict
-- The Daily Reward panel as plain data. Pure: `now` (unix seconds, UTC) is a parameter, so tests
-- can walk across UTC midnight. The SERVER decides every claim; this only previews what the rules
-- (Player/DailyRules, the same code the server runs) would say right now.
--   DailyModel.build(daily, now) -> View        daily = { lastDay, streak } (missing = never claimed)
--   DailyModel.waitText(seconds) -> "Next gift in 5h 12m"
--   DailyModel.tileRects(width) -> { rects, height }   where the 7 tiles sit for a given width

local Daily = require("../Catalog/Daily")
local DailyRules = require("../Player/DailyRules")
local Format = require("./Format")

local DailyModel = {}

export type TileState = "claimed" | "today" | "next" | "later"

export type Tile = {
	day: number, -- 1..7
	label: string, -- "Day 3"
	coins: number,
	sparks: number,
	rewardText: string, -- "350"  (coins, short)
	sparksText: string, -- "+3 ✨" or ""
	icon: string,
	special: boolean, -- day 7
	state: TileState,
	stateText: string, -- "✔", "TODAY!", "TOMORROW", ""
}

export type View = {
	today: number, -- UTC day number
	canClaim: boolean,
	reason: string, -- why not, "" when canClaim
	streak: number, -- the streak to show right now
	streakText: string,
	giftText: string, -- "Today's gift: 💰 350"
	noteText: string, -- "" or a gentle note ("A day was missed...")
	countdownText: string, -- "Next gift in 5h 12m" / "Your gift is ready!"
	secondsToNext: number, -- seconds until the next UTC day
	buttonText: string,
	tiles: { Tile },
	todayDay: number?, -- ladder day being offered (1..7) when canClaim
	nextDay: number?, -- ladder day of the next gift when already claimed
	badge: boolean,
}

local function whole(v: any): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return math.max(0, math.floor(v))
end

local function ladderDay(streak: number): number
	return (streak - 1) % Daily.days + 1
end

-- "Next gift in 5h 12m". Rounds minutes UP so it never says 0m while time is left.
function DailyModel.waitText(seconds: number): string
	local s = if seconds ~= seconds or seconds < 0 then 0 else math.floor(seconds)
	if s < 60 then
		return `Next gift in {math.max(1, s)}s`
	end
	local minutes = math.ceil(s / 60)
	local h = minutes // 60
	local m = minutes % 60
	if h > 0 then
		return `Next gift in {h}h {m}m`
	end
	return `Next gift in {m}m`
end

local function giftLine(coins: number, sparks: number): string
	local text = `💰 {Format.compact(coins)}`
	if sparks > 0 then
		text ..= `  ✨ {sparks}`
	end
	return text
end

function DailyModel.build(daily: any, now: number): View
	local last = 0
	local streak = 0
	if type(daily) == "table" then
		last = whole((daily :: { [string]: any }).lastDay)
		streak = whole((daily :: { [string]: any }).streak)
	end
	local today = DailyRules.dayOf(now)
	local plan = DailyRules.plan({ lastDay = last, streak = streak }, today)
	local canClaim = plan.canClaim

	-- how many tiles of the 7-day ladder are already ticked, and which one glows
	local claimedUpTo: number
	local todayDay: number? = nil
	local nextDay: number? = nil
	if canClaim then
		todayDay = plan.reward.day
		claimedUpTo = plan.reward.day - 1
	else
		claimedUpTo = if streak >= 1 then ladderDay(streak) else 0
		nextDay = (claimedUpTo % Daily.days) + 1
	end

	local tiles: { Tile } = {}
	for _, reward in Daily.ladder do
		local state: TileState
		if todayDay ~= nil and reward.day == todayDay then
			state = "today"
		elseif reward.day <= claimedUpTo then
			state = "claimed"
		elseif nextDay ~= nil and reward.day == nextDay then
			state = "next"
		else
			state = "later"
		end
		local special = reward.day == Daily.days
		table.insert(tiles, {
			day = reward.day,
			label = `Day {reward.day}`,
			coins = reward.coins,
			sparks = reward.sparks,
			rewardText = Format.compact(reward.coins),
			sparksText = if reward.sparks > 0 then `+{reward.sparks} ✨` else "",
			icon = if special then "🎁" else "💰",
			special = special,
			state = state,
			stateText = if state == "claimed"
				then "✔"
				elseif state == "today" then "TODAY!"
				elseif state == "next" then "TOMORROW"
				else "",
		})
	end

	-- a missed day sends the streak back to the start, but only when the player claims
	local shownStreak = if canClaim and plan.reset then 0 else streak
	local streakText: string
	if shownStreak <= 0 then
		streakText = "Start your streak today!"
	elseif shownStreak == 1 then
		streakText = "🔥 1 day in a row"
	else
		streakText = `🔥 {shownStreak} days in a row`
	end

	local noteText = ""
	if canClaim and plan.reset and streak > 0 then
		noteText = "You missed a day, so we start again at Day 1."
	elseif not canClaim and nextDay == 1 and claimedUpTo == Daily.days then
		noteText = "Wow, a whole week! A new week starts tomorrow."
	end

	local secondsToNext = DailyRules.secondsToNextDay(now)
	local countdown: string
	if canClaim then
		countdown = "Your gift is ready!"
	elseif today <= 0 or last > today then
		countdown = plan.reason
	else
		countdown = DailyModel.waitText(secondsToNext)
	end

	return {
		today = today,
		canClaim = canClaim,
		reason = plan.reason,
		streak = shownStreak,
		streakText = streakText,
		giftText = if canClaim
			then `Today's gift: {giftLine(plan.reward.coins, plan.reward.sparks)}`
			else "You got today's gift!",
		noteText = noteText,
		countdownText = countdown,
		secondsToNext = secondsToNext,
		buttonText = if canClaim then "CLAIM GIFT!" else "Come back tomorrow",
		tiles = tiles,
		todayDay = todayDay,
		nextDay = nextDay,
		badge = canClaim,
	}
end

export type Rect = { x: number, y: number, w: number, h: number }

local TILE_H = 86
local TILE_GAP = 6
local TILE_MIN_W = 62

-- Where the 7 tiles go in a box `width` wide (virtual px).
--   wide enough:   one row of 7
--   phone upright: 4 on top; below them days 5 and 6 and a double-wide day 7 (the big prize)
--   very narrow:   3 per row, day 7 full width at the bottom
function DailyModel.tileRects(width: number): { rects: { Rect }, height: number }
	local w = if width ~= width or width < 1 then 1 else width
	local g = TILE_GAP
	local h = TILE_H
	local rects: { Rect } = {}
	if (w - 6 * g) / 7 >= TILE_MIN_W then
		local cell = (w - 6 * g) / 7
		for i = 0, 6 do
			table.insert(rects, { x = i * (cell + g), y = 0, w = cell, h = h })
		end
		return { rects = rects, height = h }
	elseif (w - 3 * g) / 4 >= TILE_MIN_W then
		local cell = (w - 3 * g) / 4
		for i = 0, 3 do
			table.insert(rects, { x = i * (cell + g), y = 0, w = cell, h = h })
		end
		for i = 0, 1 do
			table.insert(rects, { x = i * (cell + g), y = h + g, w = cell, h = h })
		end
		table.insert(rects, { x = 2 * (cell + g), y = h + g, w = 2 * cell + g, h = h })
		return { rects = rects, height = 2 * h + g }
	end
	local cell = (w - 2 * g) / 3
	for i = 0, 5 do
		table.insert(rects, {
			x = (i % 3) * (cell + g),
			y = (i // 3) * (h + g),
			w = cell,
			h = h,
		})
	end
	table.insert(rects, { x = 0, y = 2 * (h + g), w = w, h = h })
	return { rects = rects, height = 3 * h + 2 * g }
end

return DailyModel
