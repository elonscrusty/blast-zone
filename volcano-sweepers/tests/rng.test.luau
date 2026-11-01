--!strict
local Harness = require("./harness")
local Rng = require("../src/shared/Rng")

Harness.test("rng same seed same numbers", function()
	local a, b = Rng.new(5), Rng.new(5)
	for _ = 1, 20 do
		Harness.eq(a:next(), b:next())
	end
end)

Harness.test("rng stays in range and spreads", function()
	local r = Rng.new(99)
	local sum = 0
	for _ = 1, 4000 do
		local v = r:next()
		Harness.truthy(v >= 0 and v < 1, "range")
		sum += v
	end
	Harness.near(sum / 4000, 0.5, 0.03, "mean")
	for _ = 1, 500 do
		local i = r:int(3, 6)
		Harness.truthy(i >= 3 and i <= 6 and i == math.floor(i), "int")
	end
end)
