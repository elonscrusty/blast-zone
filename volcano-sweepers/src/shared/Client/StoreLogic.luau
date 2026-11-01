--!strict
-- Pure logic behind the client Store (client/Core/Store). No Roblox types, so Lune can test it.
--   * `new()` makes a store: a live `view` table, merge-by-top-level-key `apply`, `subscribe` with
--     the "also call once now" rule, `subscribeAll`, `onReady`.
--   * small helpers that read a view (backpack full, zone unlocked, swing interval, number format).
--
-- Merge rule: the server sends partial Views ({ [topLevelKey]: wholeNewValue }). Each key REPLACES
-- the old value (tables are not merged deeper: the server always sends a whole `derived`,
-- `settings`, `buffs` ...). A key whose new value is deeply equal to the old one is not a change, so
-- subscribers are not woken for nothing.

local Config = require("../Config")

export type Change = { key: string, new: any, old: any }

export type Store = {
	view: { [string]: any }, -- live table: never replaced, only written by apply
	ready: boolean, -- true after the first State payload was merged
	get: (key: string) -> any,
	apply: (patch: any) -> { Change },
	subscribe: (key: string, fn: (value: any, old: any) -> ()) -> () -> (),
	subscribeAll: (fn: (key: string, value: any, old: any) -> ()) -> () -> (),
	onReady: (fn: () -> ()) -> (),
}

local StoreLogic = {}

-- ===== deep equality (data only: numbers, strings, booleans, plain tables) =====

local function deepEqual(a: any, b: any, depth: number): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" or depth > 6 then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k], depth + 1) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function StoreLogic.deepEqual(a: any, b: any): boolean
	return deepEqual(a, b, 0)
end

-- ===== merge =====

-- Merge `patch` into `view` by top-level key. Returns what really changed. Non-string keys and NaN
-- numbers are ignored. A non-table patch changes nothing.
function StoreLogic.merge(view: { [string]: any }, patch: any): { Change }
	local changes: { Change } = {}
	if type(patch) ~= "table" then
		return changes
	end
	for key, value in patch do
		if type(key) == "string" and value == value then
			local old = view[key]
			if not deepEqual(old, value, 0) then
				view[key] = value
				table.insert(changes, { key = key, new = value, old = old })
			end
		end
	end
	return changes
end

-- ===== store object =====

type KeyListener = { fn: (value: any, old: any) -> (), alive: boolean }
type AllListener = { fn: (key: string, value: any, old: any) -> (), alive: boolean }

local function safeCall(fn: (...any) -> (), ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[Store] listener error: " .. tostring(err))
	end
end

function StoreLogic.new(): Store
	local view: { [string]: any } = {}
	local byKey: { [string]: { KeyListener } } = {}
	local all: { AllListener } = {}
	local readyWaiters: { () -> () } = {}

	local self: Store = {
		view = view,
		ready = false,
		get = function(key: string): any
			return view[key]
		end,
		apply = function(patch: any): { Change }
			return {}
		end,
		subscribe = function(key: string, fn: (value: any, old: any) -> ()): () -> ()
			return function() end
		end,
		subscribeAll = function(fn: (key: string, value: any, old: any) -> ()): () -> ()
			return function() end
		end,
		onReady = function(fn: () -> ()) end,
	}

	self.apply = function(patch: any): { Change }
		local changes = StoreLogic.merge(view, patch)
		if type(patch) == "table" then
			-- an empty first payload still means "the server talked to us"
			local firstReady = not self.ready
			self.ready = true
			for _, change in changes do
				local list = byKey[change.key]
				if list ~= nil then
					for _, l in table.clone(list) do
						if l.alive then
							safeCall(l.fn, change.new, change.old)
						end
					end
				end
				for _, l in table.clone(all) do
					if l.alive then
						safeCall(l.fn, change.key, change.new, change.old)
					end
				end
			end
			if firstReady then
				local waiters = readyWaiters
				readyWaiters = {}
				for _, fn in waiters do
					safeCall(fn)
				end
			end
		end
		return changes
	end

	self.subscribe = function(key: string, fn: (value: any, old: any) -> ()): () -> ()
		local entry: KeyListener = { fn = fn, alive = true }
		local list = byKey[key]
		if list == nil then
			list = {}
			byKey[key] = list
		end
		table.insert(list :: { KeyListener }, entry)
		local current = view[key]
		if current ~= nil then
			safeCall(fn, current, nil)
		end
		return function()
			if not entry.alive then
				return
			end
			entry.alive = false
			local l = byKey[key]
			if l ~= nil then
				local at = table.find(l, entry)
				if at ~= nil then
					table.remove(l, at)
				end
			end
		end
	end

	self.subscribeAll = function(fn: (key: string, value: any, old: any) -> ()): () -> ()
		local entry: AllListener = { fn = fn, alive = true }
		table.insert(all, entry)
		return function()
			if not entry.alive then
				return
			end
			entry.alive = false
			local at = table.find(all, entry)
			if at ~= nil then
				table.remove(all, at)
			end
		end
	end

	self.onReady = function(fn: () -> ())
		if self.ready then
			safeCall(fn)
		else
			table.insert(readyWaiters, fn)
		end
	end

	return self
end

-- ===== helpers that read a view (all tolerate a half-empty view) =====

local function num(v: any, fallback: number): number
	if type(v) == "number" and v == v and v > -1e15 and v < 1e15 then
		return v
	end
	return fallback
end

-- Seconds between swings the client should use: the server's derived interval, never below the
-- global floor.
function StoreLogic.sweepInterval(view: { [string]: any }): number
	local derived = view.derived
	local interval = 0.4
	if type(derived) == "table" then
		interval = num(derived.interval, 0.4)
	end
	return math.max(Config.Player.minInterval, interval)
end

-- True when the backpack cannot take more ash. Unknown capacity counts as "not full".
function StoreLogic.backpackFull(view: { [string]: any }): boolean
	local derived = view.derived
	if type(derived) ~= "table" then
		return false
	end
	local capacity = num(derived.capacity, 0)
	if capacity <= 0 then
		return false
	end
	return num(view.carried, 0) >= capacity
end

-- Backpack fill 0..1 (0 when unknown).
function StoreLogic.backpackFraction(view: { [string]: any }): number
	local derived = view.derived
	if type(derived) ~= "table" then
		return 0
	end
	local capacity = num(derived.capacity, 0)
	if capacity <= 0 then
		return 0
	end
	return math.clamp(num(view.carried, 0) / capacity, 0, 1)
end

-- Zone 1 is always open; others need view.zones[tostring(id)] == true.
function StoreLogic.zoneUnlocked(view: { [string]: any }, zoneId: number): boolean
	if zoneId == 1 then
		return true
	end
	local zones = view.zones
	if type(zones) ~= "table" then
		return false
	end
	return zones[tostring(zoneId)] == true
end

-- { [zoneId] = true } for every unlocked zone among 1..zoneCount.
function StoreLogic.unlockedSet(view: { [string]: any }, zoneCount: number): { [number]: boolean }
	local out: { [number]: boolean } = {}
	for id = 1, zoneCount do
		if StoreLogic.zoneUnlocked(view, id) then
			out[id] = true
		end
	end
	return out
end

-- A boolean setting; `default` when the settings table or the key is missing.
function StoreLogic.setting(view: { [string]: any }, key: string, default: boolean): boolean
	local settings = view.settings
	if type(settings) ~= "table" then
		return default
	end
	local v = settings[key]
	if type(v) ~= "boolean" then
		return default
	end
	return v
end

-- 1234 -> "1.2K", 3400000 -> "3.4M". Whole numbers below 1000. Never errors.
local SUFFIX = { "K", "M", "B", "T", "Qa" }
function StoreLogic.formatNumber(n: number): string
	if n ~= n then
		return "0"
	end
	if n < 0 then
		return "-" .. StoreLogic.formatNumber(-n)
	end
	if n < 1000 then
		return tostring(math.floor(n + 0.5))
	end
	local tier = 0
	local v = n
	while v >= 1000 and tier < #SUFFIX do
		v /= 1000
		tier += 1
	end
	local text = string.format("%.1f", v)
	if string.sub(text, -2) == ".0" then
		text = string.sub(text, 1, -3)
	end
	-- 999.95K rounds to "1000.0": step up a tier instead
	if tonumber(text) == 1000 and tier < #SUFFIX then
		return "1" .. SUFFIX[tier + 1]
	end
	return text .. SUFFIX[tier]
end

return StoreLogic
