--!strict
local Harness = require("./harness")
local RemoteNames = require("../src/shared/RemoteNames")

Harness.test("every client remote has a rate limit", function()
	for name, spec in RemoteNames do
		if spec.dir == "c2s" then
			Harness.truthy(spec.perSecond ~= nil and spec.perSecond > 0, `{name} needs perSecond`)
		end
	end
end)

Harness.test("server remotes have no rate limit", function()
	for name, spec in RemoteNames do
		if spec.dir == "s2c" then
			Harness.eq(spec.perSecond, nil, `{name} is s2c`)
		end
	end
end)

Harness.test("a function remote is always client to server", function()
	for name, spec in RemoteNames do
		if spec.kind == "func" then
			Harness.eq(spec.dir, "c2s", name)
		end
	end
end)
