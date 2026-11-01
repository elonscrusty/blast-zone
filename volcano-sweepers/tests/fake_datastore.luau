--!strict
-- A pretend DataStore for tests. Behaves like UpdateAsync: the transform sees a COPY of the
-- stored value and returns the new one (or nil to cancel). Values are copied on the way in and
-- out, like the real thing, so a test cannot cheat by sharing tables. Can be told to fail.

local Serializable = require("../src/shared/Profile/Serializable")

local Fake = {}
Fake.__index = Fake

export type FakeStore = typeof(setmetatable(
	{} :: {
		values: { [string]: any },
		failures: number,
		failMessage: string,
		calls: number,
		writes: number,
		log: { string },
	},
	Fake
))

function Fake.new(): FakeStore
	return setmetatable({
		values = {},
		failures = 0,
		failMessage = "503 service unavailable",
		calls = 0,
		writes = 0,
		log = {},
	}, Fake)
end

-- The next `n` calls throw `message`.
function Fake.failNext(self: FakeStore, n: number, message: string?)
	self.failures = n
	if message then
		self.failMessage = message
	end
end

function Fake.update(self: FakeStore, key: string, transform: (any) -> (any, { number }?)): any
	self.calls += 1
	if self.failures > 0 then
		self.failures -= 1
		error(self.failMessage)
	end
	local old = Serializable.copy(self.values[key])
	local new = transform(old)
	if new == nil then
		return self.values[key]
	end
	local ok, why = Serializable.check(new)
	if not ok then
		error("fake DataStore refused the value: " .. tostring(why))
	end
	self.values[key] = Serializable.copy(new)
	self.writes += 1
	return Serializable.copy(new)
end

function Fake.raw(self: FakeStore, key: string): any
	return Serializable.copy(self.values[key])
end

function Fake.setRaw(self: FakeStore, key: string, value: any)
	self.values[key] = Serializable.copy(value)
end

return Fake
