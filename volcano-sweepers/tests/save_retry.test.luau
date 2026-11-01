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

Harness.test("only real no-access errors stop at once", function()
	Harness.truthy(SaveRetry.isPermanent("403: Studio access to APIs is not allowed"))
	Harness.truthy(SaveRetry.isPermanent("403 no DataStore: x"))
	Harness.truthy(SaveRetry.isPermanent("HTTP 403 (Forbidden)"))
	Harness.truthy(SaveRetry.isPermanent("StudioAccessToApisNotAllowed"))
	Harness.eq(SaveRetry.isPermanent("502: request 4f403ab failed"), false)
	Harness.eq(SaveRetry.isPermanent("key profile_1403 throttled"), false)
	Harness.eq(SaveRetry.isPermanent(nil), false)
	local calls = 0
	local ok = SaveRetry.run(function()
		calls += 1
		error("503: request id 9403 busy")
	end, noWait)
	Harness.eq(ok, false)
	Harness.eq(calls, SaveRetry.TRIES, "a 403 inside other text is tried again")
end)
