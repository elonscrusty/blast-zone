--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local RemoteDefs = require("../src/shared/RemoteDefs")
local WeatherPlan = require("../src/shared/Weather/WeatherPlan")

local cfg: any = Config.Weather

Harness.test("every level has odds and a look", function()
	for _, level in cfg.levels do
		Harness.truthy(cfg.odds[level] > 0, `{level}: odds`)
		Harness.truthy(WeatherPlan.look(level) ~= nil, `{level}: look`)
		Harness.truthy(WeatherPlan.isLevel(level))
	end
	Harness.truthy(not WeatherPlan.isLevel("clear"))
	Harness.truthy(not WeatherPlan.isLevel(5))
end)

Harness.test("heavier rain has more drops, more fog, faster fall", function()
	local last: any = nil
	for _, level in cfg.levels do
		local look: any = WeatherPlan.look(level)
		if last ~= nil then
			Harness.truthy(look.dropsPerSecond > last.dropsPerSecond, `{level}: drops`)
			Harness.truthy(look.fogAdd > last.fogAdd, `{level}: fog`)
			Harness.truthy(look.speed > last.speed, `{level}: speed`)
		end
		last = look
	end
end)

Harness.test("pick follows the odds and never repeats the last level", function()
	local counts: { [string]: number } = { light = 0, steady = 0, heavy = 0 }
	for i = 0, 9999 do
		local level = WeatherPlan.pick(i / 10000, nil)
		counts[level] += 1
	end
	Harness.near(counts.light, 3000, 2)
	Harness.near(counts.steady, 4500, 2)
	Harness.near(counts.heavy, 2500, 2)
	for _, last in cfg.levels do
		for i = 0, 999 do
			Harness.truthy(WeatherPlan.pick(i / 1000, last) ~= last, `repeated {last}`)
		end
	end
end)

Harness.test("pick survives odd rolls", function()
	Harness.truthy(WeatherPlan.isLevel(WeatherPlan.pick(0, nil)))
	Harness.truthy(WeatherPlan.isLevel(WeatherPlan.pick(1, nil)))
	Harness.truthy(WeatherPlan.isLevel(WeatherPlan.pick(-3, "light")))
	Harness.truthy(WeatherPlan.isLevel(WeatherPlan.pick(99, "heavy")))
end)

Harness.test("rain fades in and out over rampSeconds", function()
	Harness.near(WeatherPlan.amount("steady", 0, 0), 0)
	Harness.near(WeatherPlan.amount("steady", cfg.rampSeconds / 2, 0), 0.5)
	Harness.near(WeatherPlan.amount("steady", cfg.rampSeconds * 3, 0), 1)
	Harness.near(WeatherPlan.amount("clear", 0, 1), 1)
	Harness.near(WeatherPlan.amount("clear", cfg.rampSeconds / 2, 1), 0.5)
	Harness.near(WeatherPlan.amount("clear", cfg.rampSeconds, 1), 0)
	Harness.near(
		WeatherPlan.amount("heavy", cfg.rampSeconds / 2, 0.5),
		0.75,
		1e-6,
		"change from half rain"
	)
end)

Harness.test("phones get fewer drops and nobody goes over the cap", function()
	for _, level in cfg.levels do
		local pc = WeatherPlan.dropRate(level, 1, false)
		local phone = WeatherPlan.dropRate(level, 1, true)
		Harness.truthy(
			phone < pc or pc * cfg.dropSeconds >= cfg.maxLiveDrops,
			`{level}: phone lighter`
		)
		Harness.truthy(pc * cfg.dropSeconds <= cfg.maxLiveDrops + 1e-6, `{level}: pc cap`)
		Harness.truthy(phone * cfg.dropSeconds <= cfg.maxLiveDrops + 1e-6, `{level}: phone cap`)
		Harness.near(WeatherPlan.dropRate(level, 0, false), 0)
	end
	Harness.near(WeatherPlan.dropRate("clear", 1, false), 0)
	Harness.truthy(
		WeatherPlan.dropRate("heavy", 5, false) <= cfg.maxLiveDrops / cfg.dropSeconds + 1e-6,
		"amount over 1"
	)
	Harness.truthy(
		WeatherPlan.dropRate("heavy", 1, true) * cfg.dropSeconds
			<= 0.5 * cfg.look.heavy.dropsPerSecond * cfg.dropSeconds + 1e-6
	)
end)

Harness.test("haze grows with rain and is zero when clear", function()
	local f0, h0 = WeatherPlan.fogAdd("clear", 1)
	Harness.eq(f0, 0)
	Harness.eq(h0, 0)
	local fHalf = WeatherPlan.fogAdd("steady", 0.5)
	local fFull = WeatherPlan.fogAdd("steady", 1)
	Harness.near(fFull, cfg.look.steady.fogAdd)
	Harness.near(fHalf, cfg.look.steady.fogAdd / 2)
end)

Harness.test("weather remotes: the server tells, a client may only ask", function()
	local state = RemoteDefs.byName.WeatherState :: any
	local ask = RemoteDefs.byName.WeatherRequest :: any
	Harness.eq(state.direction, "toClient")
	Harness.eq(ask.direction, "toServer")
	Harness.truthy(ask.rate ~= nil and ask.rate.perSecond <= 2, "rate limited")
	Harness.eq(#ask.schema, 0, "takes no arguments")
end)
