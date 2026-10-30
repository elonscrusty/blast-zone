--!strict
-- Words for the pass screen (video 3 gap 20). Pure, so Lune checks them. Tiny words: carter plays on a phone.

local SeasonText = {}

function SeasonText.reward(kind: string, amount: number?, name: string?, coinName: string): string
	if kind == "scrap" then
		return `+{amount or 0} {coinName}`
	end
	return name or "Look"
end

function SeasonText.timer(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local d = s // 86400
	local h = (s % 86400) // 3600
	if d > 0 then
		return `Ends in {d}d {h}h`
	end
	local m = math.max(1, (s % 3600 + 59) // 60)
	if m == 60 then
		h += 1
		m = 0
	end
	if h > 0 then
		return `Ends in {h}h {m}m`
	end
	return `Ends in {m}m`
end

function SeasonText.tier(tier: number, maxTier: number): string
	return `TIER {tier}/{maxTier}`
end

function SeasonText.xp(intoTier: number, forNext: number?): string
	if forNext == nil then
		return "MAX"
	end
	return `{intoTier}/{forNext}`
end

local denied: { [string]: string } = {
	locked = "Not yet",
	needPass = "Paid row is locked",
	claimed = "Already taken",
	badTier = "Not found",
	badRow = "Not found",
	nothing = "Nothing to take",
}

function SeasonText.denied(reason: string?): string
	if reason == nil then
		return ""
	end
	return denied[reason] or "Try again"
end

return SeasonText
