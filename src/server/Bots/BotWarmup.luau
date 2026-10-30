--!strict
-- Calm start: right after the fight begins bots see less far, react slower and miss more, then
-- slide to their full numbers. Pure, so Lune can test it.

local BotTuning = require("./BotTuning")

type Tuning = BotTuning.Tuning

local BotWarmup = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- 0 at the start of the fight, 1 once warm-up is over (or when there is no warm-up).
function BotWarmup.progress(tuning: Tuning, fightSeconds: number): number
	local total = tuning.warmupSeconds
	if total <= 0 then
		return 1
	end
	return math.clamp(fightSeconds / total, 0, 1)
end

-- A copy of `tuning` with sight, reaction and aim moved toward the calm values.
function BotWarmup.apply(tuning: Tuning, fightSeconds: number): Tuning
	local t = BotWarmup.progress(tuning, fightSeconds)
	if t >= 1 then
		return tuning
	end
	local out = table.clone(tuning)
	out.sightRange = lerp(tuning.warmupSightRange, tuning.sightRange, t)
	out.reactionTime = lerp(tuning.warmupReactionTime, tuning.reactionTime, t)
	out.aimErrorDegrees = lerp(tuning.warmupAimErrorDegrees, tuning.aimErrorDegrees, t)
	return out
end

return BotWarmup
