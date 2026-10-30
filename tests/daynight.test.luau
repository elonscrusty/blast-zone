--!strict
-- Piece 14: the day-to-night maths. Pure, so Lune can check the clock, the glide and the glow.
local Harness = require("./harness")
local DayNight = require("../src/shared/DayNight")
local Config = require("../src/shared/Config")

local ZONE = Config.Zone
local ART = Config.Art.dayNight

Harness.test("daynight: t=0 is day, t=1 is night, out-of-range is clamped", function()
	Harness.eq(DayNight.look(0).clockTime, DayNight.looks.day.clockTime)
	Harness.eq(DayNight.look(1).clockTime, DayNight.looks.night.clockTime)
	Harness.eq(DayNight.look(-5).glow, DayNight.looks.day.glow)
	Harness.eq(DayNight.look(9).glow, DayNight.looks.night.glow)
	Harness.eq(DayNight.look(0 / 0).glow, DayNight.looks.day.glow, "NaN falls back to day")
end)

Harness.test("daynight: the sky and the neon never jump or go backwards", function()
	local last = DayNight.look(0)
	for i = 1, 200 do
		local l = DayNight.look(i / 200)
		Harness.truthy(l.glow >= last.glow - 1e-9, "glow only rises")
		Harness.truthy(math.abs(l.glow - last.glow) < 0.05, "glow moves in small steps")
		Harness.truthy(l.brightness <= last.brightness + 1e-9, "light only falls")
		Harness.truthy(math.abs(l.clockTime - last.clockTime) < 0.2, "clock moves in small steps")
		last = l
	end
end)

Harness.test("daynight: night stays bright enough to see crates and shots", function()
	local n = DayNight.looks.night
	Harness.truthy(n.brightness >= 1, "ground light kept")
	Harness.truthy(n.ambient[3] >= 120 or n.outdoorAmbient[3] >= 150, "ambient is not black")
end)

Harness.test("daynight: sunset sits in the middle", function()
	local l = DayNight.look(DayNight.SUNSET_AT)
	Harness.eq(l.clockTime, DayNight.looks.sunset.clockTime)
end)

Harness.test("daynight: the match clock reaches night exactly at sudden death", function()
	local start = 1000
	Harness.near(DayNight.progress(start, start, ZONE), 0)
	Harness.near(DayNight.progress(start, start + ZONE.suddenDeath.startsAt, ZONE), 1)
	Harness.near(DayNight.progress(start, start + ZONE.suddenDeath.startsAt / 2, ZONE), 0.5)
	Harness.eq(DayNight.progress(start, start + 9999, ZONE), 1, "stays night")
	Harness.eq(DayNight.progress(start, start - 50, ZONE), 0, "before the start is day")
end)

Harness.test("daynight: every ZoneState gives the same match start (late joiners agree)", function()
	local start = 5000
	local first = DayNight.matchStart({ startedAt = start, stage = 0 }, ZONE)
	Harness.near(first, start)
	for i, stage in ZONE.stages do
		Harness.near(
			DayNight.matchStart({ startedAt = start + stage.closeAt, stage = i }, ZONE),
			start,
			1e-9,
			`stage {i}`
		)
	end
	Harness.near(
		DayNight.matchStart({ startedAt = start + ZONE.suddenDeath.startsAt, stage = 99 }, ZONE),
		start
	)
end)

Harness.test("daynight: outside a match it is day, and the sky glides home", function()
	Harness.eq(DayNight.targetT(false, 100, 150, ZONE, ART.lobbyT), ART.lobbyT)
	Harness.eq(DayNight.targetT(true, nil, 150, ZONE, ART.lobbyT), ART.lobbyT, "no stamp yet")
	Harness.truthy(DayNight.targetT(true, 100, 150, ZONE, ART.lobbyT) > 0)
	local t = 1
	local seconds = 0
	while t > 0 and seconds < 100 do
		t = DayNight.follow(t, 0, 0.1, ART.maxChangePerSecond)
		seconds += 0.1
	end
	Harness.truthy(
		seconds <= 1 / ART.maxChangePerSecond + 0.2,
		"back to day within about 4 seconds"
	)
	Harness.eq(DayNight.follow(0.5, 0.5, 1, 1), 0.5)
	Harness.eq(DayNight.follow(0, 1, -1, 1), 0, "negative dt does nothing")
end)

Harness.test("daynight: neon steps and windows come on one by one", function()
	local steps = ART.glowSteps
	Harness.eq(DayNight.glowLevel(0, steps), 0)
	Harness.eq(DayNight.glowLevel(1, steps), steps)
	Harness.eq(DayNight.glowLevel(2, steps), steps, "clamped")
	Harness.truthy(DayNight.windowLit(0.5, 0.4))
	Harness.truthy(not DayNight.windowLit(0.3, 0.4))
	Harness.eq(DayNight.blend(-1), 0)
	Harness.eq(DayNight.blend(3), 1)
	local lit = 0
	for i = 0, 99 do
		if DayNight.windowLit(DayNight.looks.day.glow, i / 100) then
			lit += 1
		end
	end
	Harness.truthy(lit < 20, "few windows are lit by day")
end)
