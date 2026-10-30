--!strict
local Harness = require("./harness")
local SaveRetry = require("../src/shared/SaveRetry")

local function noWait(_: number) end

Harness.test("save works first try", function()
	local ok, result = SaveRetry.run(function()
		return 5
	end, noWait)
	Harness.eq(ok, true)
	Harness.eq(result, 5)
end)

Harness.test("save tries again, then works", function()
	local calls = 0
	local waits = {}
	local ok = SaveRetry.run(function()
		calls += 1
		if calls < 3 then
			error("busy")
		end
		return true
	end, function(s: number)
		table.insert(waits, s)
	end)
	Harness.eq(ok, true)
	Harness.eq(calls, 3)
	Harness.eq(waits[1], 2, "first wait")
	Harness.eq(waits[2], 4, "second wait")
end)

Harness.test("save gives up after all tries", function()
	local calls = 0
	local ok, _, err = SaveRetry.run(function()
		calls += 1
		error("down")
	end, noWait)
	Harness.eq(ok, false)
	Harness.eq(calls, SaveRetry.TRIES)
	Harness.truthy(err and string.find(err, "down", 1, true), "error text kept")
end)

Harness.test("403 stops at once", function()
	local calls = 0
	local ok = SaveRetry.run(function()
		calls += 1
		error("HTTP 403 (Forbidden)")
	end, noWait)
	Harness.eq(ok, false)
	Harness.eq(calls, 1)
end)
