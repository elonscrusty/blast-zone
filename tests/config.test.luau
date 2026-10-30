--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local RemoteDefs = require("../src/shared/RemoteDefs")

Harness.test("game name is set in one place", function()
	Harness.eq(Config.Game.Name, "Circuit District")
end)

Harness.test("zone stages only get smaller, later and meaner", function()
	local z = Config.Zone
	local radius, at, dps = z.initialRadius, 0, 0
	for i, s in z.stages do
		Harness.truthy(s.warnAt < s.closeAt, `stage {i}: warn before closing`)
		Harness.truthy(s.closeAt > at, `stage {i}: starts after the last one`)
		Harness.truthy(s.targetRadius < radius, `stage {i}: smaller than before`)
		Harness.truthy(s.damagePerSecond > dps, `stage {i}: hurts more`)
		radius, at, dps = s.targetRadius, s.closeAt + s.closeSeconds, s.damagePerSecond
	end
	local sd = z.suddenDeath
	Harness.truthy(sd.startsAt >= at, "sudden death after the last stage closes")
	Harness.truthy(sd.targetRadius < radius, "sudden death shrinks further")
	Harness.truthy(sd.damagePerSecond > dps, "sudden death hurts most")
	Harness.near(
		z.stages[1].warnAt,
		math.floor(35 * Config.Arena.scale + 0.5),
		0,
		"first warning at 35 s, stretched with the map"
	)
end)

Harness.test("first zone covers the whole arena", function()
	local half = Config.Arena.size / 2
	Harness.truthy(Config.Zone.initialRadius >= math.sqrt(2) * half)
end)

Harness.test("fire rate and interval agree", function()
	local f = Config.Weapons.Firearm
	Harness.near(f.fireRate * f.fireInterval, 1, 1e-9)
end)

Harness.test("first three levels give about three offers in a good match", function()
	local sum = 0
	for _, c in Config.Xp.levelCosts do
		sum += c
	end
	Harness.truthy(sum >= 80 and sum <= 150, "three level-ups cost a sensible amount")
end)

Harness.test("bots get no hidden advantage", function()
	Harness.eq(Config.Bots.hiddenStatAdvantage, false)
end)

Harness.test("spawns outnumber the biggest match", function()
	Harness.truthy(Config.Arena.minSpawns >= Config.Match.maxParticipants)
end)

Harness.test("remote names are unique; asks have schema and rate; tells do not", function()
	local seen: { [string]: boolean } = {}
	for _, d in RemoteDefs.list do
		Harness.truthy(not seen[d.name], "duplicate " .. d.name)
		seen[d.name] = true
		if d.direction == "toServer" then
			Harness.truthy(d.schema ~= nil and d.rate ~= nil, d.name .. " needs schema and rate")
		else
			Harness.truthy(d.schema == nil, d.name .. " is toClient")
		end
	end
	Harness.truthy(RemoteDefs.byName["FireRequest"] ~= nil)
end)
