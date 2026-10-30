--!strict
local Harness = require("./harness")
local Signal = require("../src/shared/Signal")

Harness.test("signal calls every listener", function()
	local s = Signal.new()
	local sum = 0
	s:connect(function(n: number)
		sum += n
	end)
	s:connect(function(n: number)
		sum += n * 10
	end)
	s:fire(2)
	Harness.eq(sum, 22)
end)

Harness.test("signal disconnect stops the listener", function()
	local s = Signal.new()
	local hits = 0
	local off = s:connect(function()
		hits += 1
	end)
	s:fire()
	off()
	s:fire()
	Harness.eq(hits, 1)
end)

Harness.test("signal listener may disconnect itself while firing", function()
	local s = Signal.new()
	local hits = 0
	local off
	off = s:connect(function()
		hits += 1
		off()
	end)
	s:connect(function()
		hits += 1
	end)
	s:fire()
	s:fire()
	Harness.eq(hits, 3)
end)
