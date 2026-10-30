--!strict
-- Words for the missions screen (piece 48). Pure, so Lune checks them. Tiny words: carter plays on a phone.
-- The goal lines ("Get 12 eliminations") are the same as the daily board, so they come from DailyText.

local DailyText = require("../Daily/DailyText")

local MissionText = {}

MissionText.goal = DailyText.line
MissionText.progress = DailyText.progress

-- Counts whole minutes upward, so "New in 0m" never shows before the moment.
local function split(seconds: number): (number, number, number)
	local mins = math.max(1, math.ceil(math.max(0, seconds) / 60))
	return mins // 1440, (mins % 1440) // 60, mins % 60
end

function MissionText.weekTimer(seconds: number): string
	local d, h, m = split(seconds)
	if d > 0 then
		return `New in {d}d {h}h`
	end
	if h > 0 then
		return `New in {h}h {m}m`
	end
	return `New in {m}m`
end

function MissionText.loginTimer(seconds: number): string
	local d, h, m = split(seconds)
	h += d * 24
	if h > 0 then
		return `Next in {h}h {m}m`
	end
	return `Next in {m}m`
end

function MissionText.day(step: number): string
	return `Day {step}`
end

function MissionText.reward(amount: number, coinName: string): string
	return `+{amount} {coinName}`
end

-- The strip after a claim. `just` is MissionsState.justClaimed.
function MissionText.claimed(just: string, amount: number, coinName: string): string
	local what = if just == "login"
		then "LOGIN"
		elseif just == "bonus" then "WEEK BONUS"
		else "CLAIMED"
	return `{what}! +{amount} {coinName}`
end

return MissionText
