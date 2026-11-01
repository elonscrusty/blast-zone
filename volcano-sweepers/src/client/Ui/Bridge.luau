--!strict
-- The UI's safe door to the client core (Core/Store, Net, Controls, Sfx, Haptics). Each module is
-- required lazily inside a pcall: if one is missing or broken the UI keeps working and simply does
-- nothing for that feature. Nothing in here ever throws.
--
--   Bridge.view()                     live store table (empty table when there is no store)
--   Bridge.subscribe(key, fn)         -> disconnect fn, or nil if the store is not there yet
--   Bridge.storeReady()               -> boolean
--   Bridge.onStoreReady(fn)           runs fn once the store is ready (false if no store)
--   Bridge.send(name, ...)            Net.send
--   Bridge.listen(name, fn)           -> disconnect fn (Net.on)
--   Bridge.controls()                 -> Controls module or nil
--   Bridge.play(name)                 Sfx.play (silent without ids)
--   Bridge.tap(strength)              Haptics.tap

local Bridge = {}

local cache: { [string]: any } = {}
local failedAt: { [string]: number } = {}
local RETRY_SECONDS = 3

local function clientRoot(): Instance?
	-- script = Client.Ui.Bridge  ->  parent.parent = the Client folder
	local ui = script.Parent
	return if ui then ui.Parent else nil
end

local function load(folder: string, name: string): any?
	local key = folder .. "/" .. name
	local hit = cache[key]
	if hit ~= nil then
		return hit
	end
	local last = failedAt[key]
	if last ~= nil and os.clock() - last < RETRY_SECONDS then
		return nil
	end
	local root = clientRoot()
	local dir = if root then root:FindFirstChild(folder) else nil
	local mod = if dir then dir:FindFirstChild(name) else nil
	if mod == nil or not mod:IsA("ModuleScript") then
		failedAt[key] = os.clock()
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		failedAt[key] = os.clock()
		warn(`[Ui] could not load {key}: {result}`)
		return nil
	end
	cache[key] = result
	return result
end

local function call(folder: string, name: string, method: string, ...: any): any
	local mod = load(folder, name)
	if mod == nil then
		return nil
	end
	local fn = mod[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(`[Ui] {name}.{method} failed: {result}`)
		return nil
	end
	return result
end

local EMPTY: { [string]: any } = {}

function Bridge.view(): { [string]: any }
	local v = call("Core", "Store", "view")
	if type(v) == "table" then
		return v
	end
	return EMPTY
end

function Bridge.subscribe(key: string, fn: (value: any, old: any) -> ()): (() -> ())?
	local store = load("Core", "Store")
	if store == nil then
		return nil
	end
	local ok, disconnect = pcall(store.subscribe, key, fn)
	if ok and type(disconnect) == "function" then
		return disconnect
	end
	return nil
end

function Bridge.storeReady(): boolean
	local store = load("Core", "Store")
	return store ~= nil and store.ready == true
end

function Bridge.onStoreReady(fn: () -> ()): boolean
	local store = load("Core", "Store")
	if store == nil then
		return false
	end
	local ok = pcall(store.onReady, fn)
	return ok
end

function Bridge.send(name: string, ...: any)
	call("Core", "Net", "send", name, ...)
end

function Bridge.listen(name: string, fn: (any) -> ()): (() -> ())?
	local net = load("Core", "Net")
	if net == nil then
		return nil
	end
	local ok, conn = pcall(net.on, name, fn)
	if not ok or conn == nil then
		return nil
	end
	return function()
		pcall(function()
			conn:Disconnect()
		end)
	end
end

function Bridge.controls(): any?
	return load("Core", "Controls")
end

function Bridge.play(name: string)
	call("Core", "Sfx", "play", name)
end

function Bridge.tap(strength: number)
	call("Core", "Haptics", "tap", strength)
end

return Bridge
