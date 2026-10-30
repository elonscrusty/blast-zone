--!strict
-- Pure rain rules (piece 38), tested in Lune. The server uses `pick`; the client uses `look`,
-- `amount` and `dropRate`. No Roblox services in here.

local Config = require("../Config")

export type Look = { dropsPerSecond: number, fogAdd: number, hazeAdd: number, speed: number }

local WeatherPlan = {}

WeatherPlan.CLEAR = "clear"

function WeatherPlan.isLevel(level: any): boolean
	return type(level) == "string" and (Config.Weather.look :: any)[level] ~= nil
end

-- Weighted pick. `roll` is a number in [0, 1). The level of the match just played (`last`) is
-- skipped so two matches in a row never look the same.
function WeatherPlan.pick(roll: number, last: string?): string
	local odds: { [string]: number } = Config.Weather.odds
	local total = 0
	for _, level in Config.Weather.levels do
		if level ~= last then
			total += odds[level] or 0
		end
	end
	local at = math.clamp(roll, 0, 0.999999) * total
	local picked = Config.Weather.levels[1]
	for _, level in Config.Weather.levels do
		if level ~= last then
			picked = level
			at -= odds[level] or 0
			if at < 0 then
				return level
			end
		end
	end
	return picked
end

function WeatherPlan.look(level: string): Look?
	return (Config.Weather.look :: any)[level]
end

-- 0 to 1: how much rain there is `elapsed` seconds after the weather changed. Rain fades in over
-- rampSeconds; going to "clear" fades out from where it was (`from`).
function WeatherPlan.amount(level: string, elapsed: number, from: number): number
	local ramp = math.max(Config.Weather.rampSeconds, 0.001)
	local k = math.clamp(elapsed / ramp, 0, 1)
	local target = if WeatherPlan.look(level) ~= nil then 1 else 0
	return from + (target - from) * k
end

-- Drops to make each second. Phones get phoneScale of them; never more than the live cap allows.
function WeatherPlan.dropRate(level: string, amountNow: number, isPhone: boolean): number
	local look = WeatherPlan.look(level)
	if look == nil then
		return 0
	end
	local scale = if isPhone then Config.Weather.phoneScale else 1
	local rate = look.dropsPerSecond * scale * math.clamp(amountNow, 0, 1)
	local cap = Config.Weather.maxLiveDrops / math.max(Config.Weather.dropSeconds, 0.001)
	return math.min(rate, cap)
end

-- Sky haze to add right now, for the Atmosphere.
function WeatherPlan.fogAdd(level: string, amountNow: number): (number, number)
	local look = WeatherPlan.look(level)
	if look == nil then
		return 0, 0
	end
	local a = math.clamp(amountNow, 0, 1)
	return look.fogAdd * a, look.hazeAdd * a
end

return WeatherPlan
