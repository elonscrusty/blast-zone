--!strict
local Harness = require("./harness")
local roblox = require("@lune/roblox")
local Guard = require("../src/shared/Guard")

local V3 = roblox.Vector3

local function pack(...: any)
	return table.pack(...)
end

Harness.test("numbers must be finite and in range", function()
	local schema: { Guard.Field } = { { name = "n", kind = "number", min = 0, max = 10 } }
	Harness.eq((Guard.validate(schema, pack(5))), true)
	Harness.eq((Guard.validate(schema, pack(11))), false)
	Harness.eq((Guard.validate(schema, pack(0 / 0))), false)
	Harness.eq((Guard.validate(schema, pack(math.huge))), false)
	Harness.eq((Guard.validate(schema, pack("5"))), false)
end)

Harness.test("integers reject fractions", function()
	local schema: { Guard.Field } = { { name = "i", kind = "integer", min = 1, max = 3 } }
	Harness.eq((Guard.validate(schema, pack(2))), true)
	Harness.eq((Guard.validate(schema, pack(2.5))), false)
	Harness.eq((Guard.validate(schema, pack(0))), false)
end)

Harness.test("missing and extra arguments fail, optional may be nil", function()
	local schema: { Guard.Field } = {
		{ name = "a", kind = "boolean" },
		{ name = "b", kind = "boolean", optional = true },
	}
	Harness.eq((Guard.validate(schema, pack())), false)
	Harness.eq((Guard.validate(schema, pack(true))), true)
	Harness.eq((Guard.validate(schema, pack(true, false, true))), false)
end)

Harness.test("ids only allow safe characters", function()
	local schema: { Guard.Field } = { { name = "id", kind = "id" } }
	Harness.eq((Guard.validate(schema, pack("offer_12-a"))), true)
	Harness.eq((Guard.validate(schema, pack("a b"))), false)
	Harness.eq((Guard.validate(schema, pack(""))), false)
	Harness.eq((Guard.validate(schema, pack(string.rep("a", 100)))), false)
end)

Harness.test("unit vectors: NaN, zero and huge are refused; near-unit is normalised", function()
	local schema: { Guard.Field } = { { name = "dir", kind = "unit3" } }
	Harness.eq((Guard.validate(schema, pack(V3.new(0, 0, 1)))), true)
	Harness.eq((Guard.validate(schema, pack(V3.new(0, 0, 0)))), false)
	Harness.eq((Guard.validate(schema, pack(V3.new(0, 0, 50)))), false)
	Harness.eq((Guard.validate(schema, pack(V3.new(0 / 0, 0, 1)))), false)
	local ok, out = Guard.validate(schema, pack(V3.new(0, 0, 1.05)))
	Harness.eq(ok, true)
	Harness.near(out[1].Magnitude, 1, 1e-6)
end)

Harness.test("vector3 respects max length and rejects non-vectors", function()
	local schema: { Guard.Field } = { { name = "v", kind = "vector3", maxMagnitude = 2 } }
	Harness.eq((Guard.validate(schema, pack(V3.new(1, 0, 0)))), true)
	Harness.eq((Guard.validate(schema, pack(V3.new(5, 0, 0)))), false)
	Harness.eq((Guard.validate(schema, pack({ X = 1, Y = 0, Z = 0 }))), false)
end)

Harness.test("limiter allows a burst, then refills with time", function()
	local lim = Guard.newLimiter(2, 3)
	Harness.eq(lim:allow("a", 0), true)
	Harness.eq(lim:allow("a", 0), true)
	Harness.eq(lim:allow("a", 0), true)
	Harness.eq(lim:allow("a", 0), false)
	Harness.eq(lim:allow("b", 0), true, "other players have their own bucket")
	Harness.eq(lim:allow("a", 0.6), true)
	Harness.eq(lim:allow("a", 0.6), false)
	lim:forget("a")
	Harness.eq(lim:allow("a", 0.6), true)
end)
