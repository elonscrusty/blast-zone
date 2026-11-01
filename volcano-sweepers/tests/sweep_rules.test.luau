--!strict
local Harness = require("./harness")
local AshGrid = require("../src/shared/Ash/AshGrid")
local Config = require("../src/shared/Config")
local Layout = require("../src/shared/Ash/Layout")
local SweepRules = require("../src/shared/Sweep/SweepRules")

-- a spot in the middle of Fern Forest (zone 2), away from the hub
local PX, PZ = 0, -165

Harness.test("sweep rate: swings at the tool interval are always accepted", function()
	local b = SweepRules.newBucket(100)
	local now = 100
	for _ = 1, 200 do
		now += 0.38
		Harness.truthy(SweepRules.allowSwing(b, now, 0.38), "honest swing")
	end
end)

Harness.test("sweep rate: a burst of 2 passes, the 3rd is dropped, then it recovers", function()
	local b = SweepRules.newBucket(50)
	Harness.eq(SweepRules.allowSwing(b, 50, 0.4), true)
	Harness.eq(SweepRules.allowSwing(b, 50, 0.4), true)
	Harness.eq(SweepRules.allowSwing(b, 50, 0.4), false)
	Harness.eq(SweepRules.allowSwing(b, 50.1, 0.4), false)
	-- one token needs interval x 0.8 = 0.32 s
	Harness.eq(SweepRules.allowSwing(b, 50.33, 0.4), true)
	Harness.eq(SweepRules.allowSwing(b, 50.34, 0.4), false)
end)

Harness.test("sweep rate: spamming cannot beat interval x 0.8 on average", function()
	local b = SweepRules.newBucket(0)
	local accepted = 0
	local now = 0
	for _ = 1, 1000 do -- 10 s of attempts every 10 ms
		now += 0.01
		if SweepRules.allowSwing(b, now, 0.38) then
			accepted += 1
		end
	end
	-- burst 2 + 10 s / 0.304 s = about 34.9
	Harness.truthy(accepted <= 36, `too many accepted: {accepted}`)
	Harness.truthy(accepted >= 30, `too few accepted: {accepted}`)
end)

Harness.test("sweep rate: rejected swings spend nothing and tokens never pass the burst", function()
	local b = SweepRules.newBucket(0)
	-- a long idle time still only banks BURST swings
	Harness.eq(SweepRules.allowSwing(b, 1000, 0.5), true)
	Harness.eq(SweepRules.allowSwing(b, 1000, 0.5), true)
	Harness.eq(SweepRules.allowSwing(b, 1000, 0.5), false)
	Harness.near(b.tokens, 0, 1e-6)
end)

Harness.test("sweep rate: interval is clamped and bad data is strict", function()
	-- tiny interval cannot go below the global minimum
	Harness.near(SweepRules.minGap(0.001), Config.Player.minInterval * 0.8)
	Harness.near(SweepRules.minGap(0.4), 0.32)
	Harness.near(SweepRules.minGap(0 / 0), 0.8)
	Harness.near(SweepRules.minGap(-3), 0.8)
	Harness.near(SweepRules.minGap(math.huge), 0.8)
end)

Harness.test("sweep rate: a clock that goes backwards mints no tokens", function()
	local b = SweepRules.newBucket(100)
	Harness.eq(SweepRules.allowSwing(b, 100, 0.4), true)
	Harness.eq(SweepRules.allowSwing(b, 100, 0.4), true)
	Harness.eq(SweepRules.allowSwing(b, 90, 0.4), false)
	Harness.eq(SweepRules.allowSwing(b, 100.1, 0.4), false)
end)

Harness.test("direction: Y is ignored and the result has length 1", function()
	local dx, dz, ok = SweepRules.flattenDir(3, 5, 4)
	Harness.eq(ok, true)
	Harness.near(dx, 0.6)
	Harness.near(dz, 0.8)
	local ex, ez, ok2 = SweepRules.flattenDir(0, -0.5, -0.8)
	Harness.eq(ok2, true)
	Harness.near(ex, 0)
	Harness.near(ez, -1)
end)

Harness.test("direction: straight up / down / non-finite are rejected", function()
	local _, _, up = SweepRules.flattenDir(0, 1, 0)
	Harness.eq(up, false)
	local _, _, down = SweepRules.flattenDir(0.001, -1, 0.001)
	Harness.eq(down, false)
	local _, _, nan = SweepRules.flattenDir(0 / 0, 0, 1)
	Harness.eq(nan, false)
	local _, _, inf = SweepRules.flattenDir(1, 0, math.huge)
	Harness.eq(inf, false)
end)

Harness.test("zones: allow-mask comes from the profile map; zone 1 is always open", function()
	local out: { [number]: boolean } = {}
	local n = SweepRules.buildAllowed({ ["1"] = true, ["3"] = true, ["4"] = false }, out)
	Harness.eq(n, 2)
	Harness.eq(out[1], true)
	Harness.eq(out[2], false)
	Harness.eq(out[3], true)
	Harness.eq(out[4], false)
	Harness.eq(out[5], false)
	-- even a broken profile cannot lock the free zone
	local n2 = SweepRules.buildAllowed({}, out)
	Harness.eq(n2, 1)
	Harness.eq(out[1], true)
	Harness.eq(out[3], false, "the same table is cleared and refilled")
end)

Harness.test("zones: odd keys in the profile are ignored", function()
	local out: { [number]: boolean } = {}
	local zones: any = { ["1"] = true, ["9"] = true, ["abc"] = true, [2] = true, ["2"] = "yes" }
	SweepRules.buildAllowed(zones, out)
	Harness.eq(out[2], false, "'yes' is not true")
	Harness.eq(out[9], nil)
	Harness.eq(out[1], true)
end)

Harness.test("locked ash: found only when an unallowed zone still has ash in the cone", function()
	local g = AshGrid.new("full")
	local L = g.layout
	local dx, dz = 0, 1
	local cells = g:queryCone(PX, PZ, dx, dz, 12, 90)
	Harness.truthy(#cells > 0, "cone has cells")
	local allowed: { [number]: boolean } = {}
	SweepRules.buildAllowed({ ["1"] = true }, allowed)
	Harness.eq(L.zoneAt(PX, PZ), 2)
	Harness.eq(SweepRules.hasLockedAsh(cells, g.levels, L.zone, allowed), true)
	SweepRules.buildAllowed({ ["1"] = true, ["2"] = true }, allowed)
	Harness.eq(SweepRules.hasLockedAsh(cells, g.levels, L.zone, allowed), false)
	-- empty locked cells are not "locked ash"
	SweepRules.buildAllowed({ ["1"] = true }, allowed)
	for _, j in cells do
		g:set(j, 0)
	end
	Harness.eq(SweepRules.hasLockedAsh(cells, g.levels, L.zone, allowed), false)
end)

Harness.test("sweeping honours the allow-mask built from the profile", function()
	local Rng = require("../src/shared/Rng")
	local g = AshGrid.new("full")
	local allowed: { [number]: boolean } = {}
	SweepRules.buildAllowed({ ["1"] = true }, allowed)
	local tool = { reach = 9, arcDeg = 110, power = 1 }
	local r = g:sweep(PX, PZ, 0, 1, tool, allowed, 100, Rng.new(1), 0, nil)
	Harness.eq(r.removedUnits, 0, "zone 2 is locked")
	SweepRules.buildAllowed({ ["1"] = true, ["2"] = true }, allowed)
	local r2 = g:sweep(PX, PZ, 0, 1, tool, allowed, 100, Rng.new(1), 0, nil)
	Harness.truthy(r2.removedUnits > 0, "zone 2 is open")
end)

Harness.test("count by zone: counts cleared cells per zone and resets the table", function()
	local zoneOf = { 1, 1, 2, 5, 2, 1 }
	local out: { [number]: number } = { [3] = 99 }
	local total = SweepRules.countByZone({ 1, 3, 4, 5 }, zoneOf, out)
	Harness.eq(total, 4)
	Harness.eq(out[1], 1)
	Harness.eq(out[2], 2)
	Harness.eq(out[3], 0, "stale counts are cleared")
	Harness.eq(out[5], 1)
	Harness.eq(SweepRules.countByZone({}, zoneOf, out), 0)
	Harness.eq(out[2], 0)
end)

Harness.test("allowEvery: throttles per key", function()
	local last: { [any]: number } = {}
	Harness.eq(SweepRules.allowEvery(last, "a", 10, 3), true)
	Harness.eq(SweepRules.allowEvery(last, "a", 11, 3), false)
	Harness.eq(SweepRules.allowEvery(last, "b", 11, 3), true)
	Harness.eq(SweepRules.allowEvery(last, "a", 13.01, 3), true)
	Harness.eq(SweepRules.allowEvery(last, "a", 14, 3), false)
end)

Harness.test("sell range: flat distance check and hub fallback from Config", function()
	Harness.eq(SweepRules.withinRange2D(0, 0, 10, 10, 16), true)
	Harness.eq(SweepRules.withinRange2D(0, 0, 12, 12, 16), false)
	Harness.eq(SweepRules.withinRange2D(16, 0, 0, 0, 16), true, "edge counts")
	local hx, hz = SweepRules.hubXZ(Config.World)
	Harness.near(hx, Layout.hubX, 1e-9)
	Harness.near(hz, Layout.hubZ, 1e-9)
	Harness.near(math.sqrt(hx * hx + hz * hz), Config.World.hub.radius, 1e-6)
end)

return {}
