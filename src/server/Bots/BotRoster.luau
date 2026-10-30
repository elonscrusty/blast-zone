--!strict
-- Auto-fill rules: a player alone in the waiting area gets a short count, then bots top the match up.
-- Pure, so Lune can test it. Bots are always labeled (by the roster name prefix) and never counted
-- as people.

local BotTuning = require("./BotTuning")

type Tuning = BotTuning.Tuning

local BotRoster = {}

-- How many bots to ask for so the match reaches `fillTo` participants (never past the maximum).
function BotRoster.botsToAdd(tuning: Tuning, humans: number, bots: number): number
	local target = math.min(tuning.fillTo, tuning.maxParticipants)
	return math.max(0, target - humans - bots)
end

-- How many people the fill rules count. Once someone has pressed Play, only people who pressed Play
-- count: a friend idling in the lobby must not hold a lone queued player there forever. Before anyone
-- pressed Play, everyone in the server counts, so bots can be ready the moment a lone player taps.
function BotRoster.lobbyHumans(inServer: number, queued: number): number
	if queued > 0 then
		return queued
	end
	return inServer
end

export type Fill = {
	since: number?,
	filled: boolean,
}

-- `alone` is true while fewer than `aloneBelow` people are here (the client shows the "Alone?" banner then).
export type FillResult = {
	action: "none" | "countdown" | "fill",
	secondsLeft: number,
	alone: boolean,
}

function BotRoster.newFill(): Fill
	return { since = nil, filled = false }
end

-- Call about once a second. `waiting` = the match is in Waiting or Countdown and has not started.
-- Fills once per wait. Nobody around (0 humans) never counts as "alone".
-- A part-full lobby (fewer people than `fillTo`) is topped up too, after the shorter `topUpDelay`,
-- so a match with two or three friends still starts with a full arena.
function BotRoster.updateFill(
	tuning: Tuning,
	fill: Fill,
	now: number,
	waiting: boolean,
	humans: number
): FillResult
	if not waiting then
		fill.since = nil
		fill.filled = false
		return { action = "none", secondsLeft = 0, alone = false }
	end
	if humans >= tuning.fillTo or humans < 1 then
		fill.since = nil
		return { action = "none", secondsLeft = 0, alone = false }
	end
	local alone = humans < tuning.aloneBelow
	if fill.filled then
		return { action = "none", secondsLeft = 0, alone = alone }
	end
	local since = fill.since or now
	fill.since = since
	local delay = if alone then tuning.autoFillDelay else tuning.topUpDelay
	local left = delay - (now - since)
	if left <= 0 then
		fill.filled = true
		return { action = "fill", secondsLeft = 0, alone = alone }
	end
	return { action = "countdown", secondsLeft = math.ceil(left), alone = alone }
end

-- "Add bots now" tap. Same rules as the count: only while waiting alone, with a cooldown.
function BotRoster.checkAddNow(
	tuning: Tuning,
	waiting: boolean,
	humans: number,
	now: number,
	lastAt: number?
): (boolean, string)
	if not waiting then
		return false, "busy"
	end
	if humans >= tuning.aloneBelow or humans < 1 then
		return false, "not alone"
	end
	if lastAt and now - lastAt < tuning.tapGap then
		return false, "slow down"
	end
	return true, "ok"
end

return BotRoster
