--!strict
-- Words for the daily board (piece 25). Pure, so Lune checks them. Tiny words: carter plays on a phone.

local DailyText = {}

local words: { [string]: { string } } = {
	-- kind = { one, many } with %d for the number
	elims = { "Get %d elimination", "Get %d eliminations" },
	crates = { "Open %d crate", "Open %d crates" },
	orbs = { "Grab %d XP orb", "Grab %d XP orbs" },
	matches = { "Play %d match", "Play %d matches" },
	top3 = { "Finish top 3 in %d match", "Finish top 3 in %d matches" },
	wins = { "Win %d match", "Win %d matches" },
}

function DailyText.line(kind: string, goal: number): string
	local w = words[kind]
	if w == nil then
		return ""
	end
	return string.format(if goal == 1 then w[1] else w[2], goal)
end

function DailyText.progress(progress: number, goal: number): string
	return `{math.min(progress, goal)}/{goal}`
end

function DailyText.timer(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = s // 3600
	local m = math.max(1, (s % 3600 + 59) // 60)
	if m == 60 then
		h += 1
		m = 0
	end
	if h > 0 then
		return `New in {h}h {m}m`
	end
	return `New in {m}m`
end

return DailyText
