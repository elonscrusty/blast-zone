--!strict
-- The words on the results screen, decided from the Results payload. Pure, so Lune can test them.
-- Tone picks the colors: "win" cyan, "lose" coral, "draw" pavement.

export type Words = {
	title: string,
	sub: string,
	tone: string,
	place: number?,
	kills: number,
	time: string,
	reward: number,
	winnerName: string?,
}

local ResultsText = {}

function ResultsText.ordinal(n: number): string
	local last2 = n % 100
	local last = n % 10
	local suffix = "th"
	if last2 < 11 or last2 > 13 then
		if last == 1 then
			suffix = "st"
		elseif last == 2 then
			suffix = "nd"
		elseif last == 3 then
			suffix = "rd"
		end
	end
	return `{n}{suffix}`
end

function ResultsText.formatTime(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

local function nameOf(payload: any, id: string?): string?
	if id == nil then
		return nil
	end
	for _, row in payload.rows do
		if row.participantId == id then
			return row.displayName
		end
	end
	return nil
end

-- `payload` is a ResultsPayload (see Types.luau). `you` is nil for someone who only watched.
function ResultsText.describe(payload: any): Words
	local you = payload.you
	local winnerName = nameOf(payload, payload.winnerId)
	local words: Words = {
		title = "MATCH OVER",
		sub = if winnerName then `{winnerName} won` else "Nobody won",
		tone = "draw",
		place = nil,
		kills = 0,
		time = "0:00",
		reward = 0,
		winnerName = winnerName,
	}
	if you == nil then
		return words
	end
	words.place = you.placement
	words.kills = you.eliminations
	words.time = ResultsText.formatTime(you.survivedSeconds)
	words.reward = you.reward
	local ord = ResultsText.ordinal(you.placement)
	local outcome = payload.outcome or (if payload.draw then "draw" else "win")
	if outcome == "abandoned" then
		words.title = "NO WINNER"
		words.sub = `The last player left · {ord} place`
		words.tone = "draw"
	elseif outcome == "draw" then
		if you.placement == 1 then
			words.title = "DRAW!"
			words.sub = "You share 1st place"
			words.tone = "draw"
		else
			words.title = "NICE TRY!"
			words.sub = `{ord} place`
			words.tone = "lose"
		end
	elseif you.placement == 1 then
		words.title = "YOU WIN!"
		words.sub = "1st place · Last one standing!"
		words.tone = "win"
	else
		words.title = "NICE TRY!"
		words.sub = if winnerName then `{ord} place · {winnerName} won` else `{ord} place`
		words.tone = "lose"
	end
	return words
end

local CAUSES: { [string]: string } = {
	zone = "the closing zone",
	blast = "a blast",
	bullet = "a shot",
}

-- The line under ELIMINATED, from an Eliminated payload about the local player.
function ResultsText.defeatLine(payload: any, localId: string): string?
	if payload.victimId ~= localId then
		return nil
	end
	local place = ResultsText.ordinal(payload.placement)
	if payload.killerId and payload.killerName then
		return `by {payload.killerName} · {place} place`
	end
	local cause = CAUSES[payload.cause] or "the arena"
	return `by {cause} · {place} place`
end

return ResultsText
