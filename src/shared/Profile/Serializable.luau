--!strict
-- Is this value safe to hand to a DataStore? Checked before every save so one bad number (NaN),
-- a function, or a mixed table can never make a save fail forever or poison a profile.
-- Pure Luau so Lune can test it.

local Serializable = {}

Serializable.MAX_DEPTH = 12
Serializable.MAX_NODES = 20000

local function isArray(t: { [any]: any }): boolean
	local n = 0
	for _ in t do
		n += 1
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	return true
end

-- Returns true, or false and a path/reason such as "progression.coins: not a finite number".
function Serializable.check(value: any): (boolean, string?)
	local nodes = 0
	local seen: { [any]: boolean } = {}

	local function walk(v: any, path: string, depth: number): string?
		nodes += 1
		if nodes > Serializable.MAX_NODES then
			return "too big"
		end
		local kind = type(v)
		if kind == "boolean" then
			return nil
		elseif kind == "number" then
			if v ~= v or v == math.huge or v == -math.huge then
				return path .. ": not a finite number"
			end
			return nil
		elseif kind == "string" then
			if utf8.len(v) == nil then
				return path .. ": not valid text"
			end
			return nil
		elseif kind == "table" then
			if depth > Serializable.MAX_DEPTH then
				return path .. ": too deep"
			end
			if seen[v] then
				return path .. ": table loops back"
			end
			seen[v] = true
			local array = isArray(v)
			for k, child in v do
				if array then
					if type(k) ~= "number" then
						return path .. ": mixed keys"
					end
				elseif type(k) ~= "string" then
					return path .. ": keys must be text"
				end
				local err = walk(child, path .. "." .. tostring(k), depth + 1)
				if err then
					return err
				end
			end
			seen[v] = nil
			return nil
		end
		return path .. ": a " .. kind .. " cannot be saved"
	end

	local err = walk(value, "data", 0)
	if err then
		return false, err
	end
	return true, nil
end

-- Deep copy of plain data (what a DataStore would hand back). Errors on a table loop.
function Serializable.copy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out: { [any]: any } = {}
	for k, v in value :: any do
		out[k] = Serializable.copy(v)
	end
	return out :: any
end

return Serializable
