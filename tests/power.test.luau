--!strict
-- Video 3 gap #16: power rating (pure rules).
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local LevelRules = require("../src/shared/Level/LevelRules")
local PowerRules = require("../src/shared/Power/PowerRules")
local ProgressRules = require("../src/shared/Progression/ProgressRules")
local RemoteDefs = require("../src/shared/RemoteDefs")
local TrackDefs = require("../src/shared/Progression/TrackDefs")

local test, eq, truthy = Harness.test, Harness.eq, Harness.truthy

local function inputs(level: number, looks: number, wins: number, elims: number, matches: number)
	return { level = level, looks = looks, wins = wins, eliminations = elims, matches = matches }
end

local function partOf(rating: PowerRules.Rating, id: string): PowerRules.Part
	for _, part in rating.parts do
		if part.id == id then
			return part
		end
	end
	error("no part " .. id)
end

test("power: a brand new player is at 0 in band 1", function()
	local r = PowerRules.compute(inputs(1, 0, 0, 0, 0))
	eq(r.power, 0)
	eq(r.band, 1)
	eq(r.toNext, Config.Power.bands[2])
end)

test("power: each part adds its own points and they sum up", function()
	local c = Config.Power
	local r = PowerRules.compute(inputs(5, 2, 3, 10, 4))
	eq(partOf(r, "level").points, 4 * c.perLevel)
	eq(partOf(r, "looks").points, 2 * c.perUnit.looks)
	eq(partOf(r, "wins").points, 3 * c.perUnit.wins)
	eq(partOf(r, "eliminations").points, 10 * c.perUnit.eliminations)
	eq(partOf(r, "matches").points, 4 * c.perUnit.matches)
	local sum = 0
	for _, part in r.parts do
		sum += part.points
	end
	eq(r.power, sum)
end)

test("power: parts come in PART_IDS order", function()
	local r = PowerRules.compute(inputs(1, 0, 0, 0, 0))
	eq(#r.parts, #PowerRules.PART_IDS)
	for i, id in PowerRules.PART_IDS do
		eq(r.parts[i].id, id)
		truthy(PowerRules.LABELS[id] ~= nil, "label for " .. id)
	end
end)

test("power: every part is capped so no habit runs away", function()
	local r = PowerRules.compute(inputs(Config.Level.maxLevel, 999, 99999, 99999, 99999))
	for _, id in { "looks", "wins", "eliminations", "matches" } do
		local part = partOf(r, id)
		truthy(part.capped, id .. " capped")
		eq(part.points, Config.Power.caps[id] * Config.Power.perUnit[id])
	end
	eq(r.power, PowerRules.maxPower())
	-- a level above the top does not count either
	eq(
		PowerRules.compute(inputs(9999, 0, 0, 0, 0)).power,
		PowerRules.compute(inputs(50, 0, 0, 0, 0)).power
	)
end)

test("power: more of anything never lowers the number", function()
	local base = inputs(10, 3, 10, 40, 30)
	local before = PowerRules.compute(base).power
	for _, key in { "level", "looks", "wins", "eliminations", "matches" } do
		local more: any = table.clone(base)
		more[key] += 1
		truthy(PowerRules.compute(more).power >= before, key)
	end
end)

test("power: bands rise with the number, the top band has no next", function()
	local bands = Config.Power.bands
	eq(bands[1], 0, "first band starts at 0")
	for i = 2, #bands do
		truthy(bands[i] > bands[i - 1], "bands go up")
		eq(PowerRules.band(bands[i]), i)
		eq(PowerRules.band(bands[i] - 1), i - 1)
	end
	local top = PowerRules.band(PowerRules.maxPower())
	eq(top, #bands, "the cap reaches the top band")
	eq(PowerRules.compute(inputs(Config.Level.maxLevel, 99, 999, 999, 999)).toNext, nil)
end)

test("power: junk in gives a clean number, never an error", function()
	local r = PowerRules.compute({
		level = "x",
		looks = -4,
		wins = 0 / 0,
		eliminations = 2.9,
		matches = {},
	})
	eq(r.power, 1 * Config.Power.perUnit.eliminations * 2)
	eq(PowerRules.compute(nil).power, 0)
	eq(PowerRules.compute("nope").power, 0)
	local s = PowerRules.inputsFrom("x", 5)
	eq(s.level, 1)
	eq(s.wins, 0)
end)

test("power: inputs come from the saved tables", function()
	local p = ProgressRules.new()
	p.accountXp = LevelRules.costOf(1) + LevelRules.costOf(2) -- level 3
	p.unlocked[TrackDefs.tiers[1].id] = true
	p.unlocked[TrackDefs.gifts[1].id] = true
	p.unlocked["from_a_newer_game"] = true -- unknown id: not counted
	p.unlocked[TrackDefs.defaults[1].id] = true -- free look: not counted
	p.unlocked[TrackDefs.tiers[2].id] = false -- not owned
	local i = PowerRules.inputsFrom(p, { wins = 4, eliminations = 9, matches = 12 })
	eq(i.level, 3)
	eq(i.looks, 2)
	eq(i.wins, 4)
	eq(i.eliminations, 9)
	eq(i.matches, 12)
	-- no stats yet is fine
	eq(PowerRules.inputsFrom(p, nil).wins, 0)
	-- no progression yet is level 1 with no looks
	local none = PowerRules.inputsFrom(nil, { wins = 1 })
	eq(none.level, 1)
	eq(none.looks, 0)
end)

test("power: coins and Scrap spent do not count, only things earned", function()
	local p = ProgressRules.new()
	local a = PowerRules.compute(PowerRules.inputsFrom(p, nil)).power
	p.coins = 99999
	p.totalEarned = 99999
	eq(PowerRules.compute(PowerRules.inputsFrom(p, nil)).power, a)
end)

test("power: same() sees every change and nothing else", function()
	local a = PowerRules.compute(inputs(4, 1, 2, 3, 5))
	local b = PowerRules.compute(inputs(4, 1, 2, 3, 5))
	truthy(PowerRules.same(a, b))
	truthy(not PowerRules.same(a, PowerRules.compute(inputs(4, 1, 2, 3, 6))))
	truthy(not PowerRules.same(a, nil))
	truthy(PowerRules.same(nil, nil))
end)

test("power: the two remotes exist, the ask is limited, nothing is bought", function()
	local ask = RemoteDefs.byName.PowerRequest
	truthy(ask ~= nil and ask.direction == "toServer", "PowerRequest")
	truthy(ask.rate ~= nil and ask.rate.perSecond <= 2, "rate limited")
	truthy(#ask.schema == 0, "the client sends nothing the server must trust")
	local tell = RemoteDefs.byName.PowerUpdate
	truthy(tell ~= nil and tell.direction == "toClient", "PowerUpdate")
end)
