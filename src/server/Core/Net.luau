--!strict
-- Server door for remotes. Every client request passes through here: rate limit, then argument
-- check, then your handler. Handlers still must check match state, ownership and cooldowns.
--   Net.onRequest("FireRequest", function(player, origin, dir, seq) ... end)
--   Net.fire("Notice", player, payload) / Net.fireAll(...) / Net.fireMany(name, players, ...)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Guard = require(Shared.Guard)
local RemoteDefs = require(Shared.RemoteDefs)
local Remotes = require(Shared.Remotes)

local Net = {}

local limiters: { [string]: any } = {}
local started = false
local lastWarn: { [string]: number } = {}

local function warnThrottled(player: Player, name: string, why: string)
	local key = tostring(player.UserId) .. ":" .. name
	local now = os.clock()
	if (lastWarn[key] or -10) + 5 < now then
		lastWarn[key] = now
		warn(`[Net] {player.Name} -> {name}: {why}`)
	end
end

function Net.init()
	if started then
		return
	end
	started = true
	Remotes.build()
	-- Server-to-client remotes: a client firing one back gets nothing, and the server does not
	-- keep a queue of its junk (an unheard RemoteEvent stores what it is sent).
	for _, def in RemoteDefs.list do
		if def.direction == "toClient" then
			Remotes.get(def.name).OnServerEvent:Connect(function() end)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		for _, limiter in limiters do
			limiter:forget(player.UserId)
		end
		local prefix = tostring(player.UserId)
		for key in lastWarn do
			if string.sub(key, 1, #prefix + 1) == prefix .. ":" then
				lastWarn[key] = nil
			end
		end
	end)
end

function Net.onRequest(name: string, handler: (player: Player, ...any) -> ()): RBXScriptConnection
	local def = RemoteDefs.byName[name]
	assert(
		def ~= nil and def.direction == "toServer",
		"Net.onRequest: '" .. name .. "' is not a toServer remote"
	)
	local schema = def.schema :: { Guard.Field }
	local rate = def.rate :: { perSecond: number, burst: number }
	local limiter = limiters[name] or Guard.newLimiter(rate.perSecond, rate.burst)
	limiters[name] = limiter
	local ev = Remotes.get(name)
	return ev.OnServerEvent:Connect(function(player: Player, ...)
		if not limiter:allow(player.UserId, os.clock()) then
			return
		end
		local ok, clean = Guard.validate(schema, table.pack(...))
		if not ok then
			warnThrottled(player, name, tostring(clean))
			return
		end
		local pcallOk, err = pcall(handler, player, table.unpack(clean, 1, #schema))
		if not pcallOk then
			warn(`[Net] handler for {name} failed: {err}`)
		end
	end)
end

local function checkToClient(name: string)
	local def = RemoteDefs.byName[name]
	assert(
		def ~= nil and def.direction == "toClient",
		"Net.fire: '" .. name .. "' is not a toClient remote"
	)
end

function Net.fire(name: string, player: Player, ...: any)
	checkToClient(name)
	Remotes.get(name):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	checkToClient(name)
	Remotes.get(name):FireAllClients(...)
end

function Net.fireMany(name: string, targets: { Player }, ...: any)
	checkToClient(name)
	local ev = Remotes.get(name)
	for _, player in targets do
		ev:FireClient(player, ...)
	end
end

return Net
