--!strict
-- Checks for anything a client sends. Treat every argument as hostile.
--   Guard.validate(schema, packedArgs) -> true, cleanValues   or   false, reason
--   Guard.newLimiter(perSecond, burst) -> limiter:allow(key, now)
-- A schema is a list of fields, one per argument, in order. Extra or missing arguments fail.

export type Field = {
	name: string,
	kind: string, -- "number" | "integer" | "boolean" | "string" | "id" | "vector3" | "unit3"
	optional: boolean?,
	min: number?,
	max: number?,
	maxLen: number?, -- strings
	maxMagnitude: number?, -- vector3
}

local Guard = {}

local HUGE = 1e6

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -HUGE and n < HUGE
end

local function checkField(field: Field, v: any): (boolean, any)
	local kind = field.kind
	if kind == "number" or kind == "integer" then
		if not finite(v) then
			return false, "not a finite number"
		end
		if kind == "integer" and v ~= math.floor(v) then
			return false, "not an integer"
		end
		if field.min ~= nil and v < field.min then
			return false, "below min"
		end
		if field.max ~= nil and v > field.max then
			return false, "above max"
		end
		return true, v
	elseif kind == "boolean" then
		if type(v) ~= "boolean" then
			return false, "not a boolean"
		end
		return true, v
	elseif kind == "string" or kind == "id" then
		if type(v) ~= "string" then
			return false, "not a string"
		end
		if #v > (field.maxLen or 64) then
			return false, "too long"
		end
		if kind == "id" and (#v == 0 or string.match(v, "^[%w_:%-]+$") == nil) then
			return false, "bad id"
		end
		return true, v
	elseif kind == "vector3" or kind == "unit3" then
		if typeof(v) ~= "Vector3" then
			return false, "not a Vector3"
		end
		if not (finite(v.X) and finite(v.Y) and finite(v.Z)) then
			return false, "vector not finite"
		end
		local mag = v.Magnitude
		if kind == "unit3" then
			if mag < 0.9 or mag > 1.1 then
				return false, "not a unit vector"
			end
			return true, v.Unit
		end
		if field.maxMagnitude ~= nil and mag > field.maxMagnitude then
			return false, "vector too long"
		end
		return true, v
	end
	return false, "unknown kind " .. tostring(kind)
end

function Guard.validate(schema: { Field }, packed: { n: number? }): (boolean, any)
	local given = packed.n or #(packed :: any)
	if given > #schema then
		return false, "too many arguments"
	end
	local out = {}
	for i, field in schema do
		local v = (packed :: any)[i]
		if v == nil then
			if not field.optional then
				return false, "missing " .. field.name
			end
			out[i] = nil
		else
			local ok, clean = checkField(field, v)
			if not ok then
				return false, field.name .. ": " .. tostring(clean)
			end
			out[i] = clean
		end
	end
	return true, out
end

-- Token bucket per key. `now` is passed in (os.clock) so tests control time.
local Limiter = {}
Limiter.__index = Limiter

function Guard.newLimiter(perSecond: number, burst: number): any
	return setmetatable({ perSecond = perSecond, burst = burst, buckets = {} }, Limiter)
end

function Limiter.allow(self: any, key: any, now: number): boolean
	local b = self.buckets[key]
	if b == nil then
		b = { tokens = self.burst, at = now }
		self.buckets[key] = b
	end
	b.tokens = math.min(self.burst, b.tokens + (now - b.at) * self.perSecond)
	b.at = now
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end

function Limiter.forget(self: any, key: any)
	self.buckets[key] = nil
end

return Guard
