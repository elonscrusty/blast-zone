--!strict
local Harness = require("./harness")
local MapRotation = require("../src/server/Arena/MapRotation")
local Config = require("../src/shared/Config")

local known = { A = true, B = true, C = true, D = true, E = true, F = true }

Harness.test("map rotation: plays the list in order and loops", function()
	local r = MapRotation.new({ "C", "D" }, known, "C")
	Harness.eq(r:current(), "C")
	Harness.eq(r:peekNext(), "D")
	Harness.eq(r:advance(), "D")
	Harness.eq(r:current(), "D")
	Harness.eq(r:peekNext(), "C")
	Harness.eq(r:advance(), "C", "loops back")
	Harness.eq(r:advance(), "D")
end)

Harness.test("map rotation: one map stays put", function()
	local r = MapRotation.new({ "C" }, known, "C")
	Harness.eq(r:advance(), "C")
	Harness.eq(r:peekNext(), "C")
end)

Harness.test("map rotation: unknown ids are skipped, never built", function()
	local r = MapRotation.new({ "Z", "D", "nope" }, known, "C")
	Harness.eq(#r.order, 1)
	Harness.eq(r:current(), "D")
	Harness.eq(#r.dropped, 2)
	local empty = MapRotation.new({ "Z" }, known, "C")
	Harness.eq(empty:current(), "C", "falls back when nothing is real")
	local none = MapRotation.new({}, known, "C")
	Harness.eq(none:current(), "C")
end)

Harness.test("map rotation: config names real maps, starts on carter's map C", function()
	local rotation = Config.Arena.rotation
	Harness.truthy(#rotation >= 2, "at least two maps rotate")
	Harness.eq(rotation[1], Config.Arena.layout, "first map is the picked map")
	for _, id in rotation do
		Harness.truthy(known[id], `{id} is not a map`)
	end
	local r = MapRotation.new(rotation, known, Config.Arena.layout)
	Harness.eq(#r.dropped, 0)
end)
