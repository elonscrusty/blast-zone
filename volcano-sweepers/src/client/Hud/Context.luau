--!strict
-- What every HUD widget shares: the store, the remotes, a timer loop and one cleanup list, so a
-- widget never owns a stray connection. Hud.destroy() runs ctx.destroy() and everything goes away.
--
--   ctx.view()                    the live store table (never nil)
--   ctx.watch({keys}, fn)         run fn whenever any key changes (and once the store is there)
--   ctx.listen(remote, fn)        Net.on with automatic cleanup
--   ctx.every(seconds, fn)        timer on one Heartbeat connection; 0 = every frame; fn(dt)
--   ctx.connect(conn)             keep an RBXScriptConnection for cleanup
--   ctx.onCleanup(fn)             run fn at destroy
--   ctx.serverNow()               workspace:GetServerTimeNow()
--   ctx.toast(text, kind?)        show a toast (wired up by Hud)

local RunService = game:GetService("RunService")

local Bridge = require(script.Parent.Parent.Ui.Bridge)

export type Context = {
	view: () -> { [string]: any },
	watch: (keys: { string }, fn: () -> ()) -> (),
	listen: (remote: string, fn: (any) -> ()) -> (),
	every: (seconds: number, fn: (dt: number) -> ()) -> (),
	connect: (conn: RBXScriptConnection) -> (),
	onCleanup: (fn: () -> ()) -> (),
	serverNow: () -> number,
	toast: (text: string, kind: string?) -> (),
	toastImpl: ((text: string, kind: string?) -> ())?,
	destroy: () -> (),
}

type Timer = { period: number, acc: number, fn: (dt: number) -> (), failed: boolean }
type PendingWatch = { key: string, fn: () -> () }
type PendingListen = { remote: string, fn: (any) -> () }

local Context = {}

function Context.new(): Context
	local cleanups: { () -> () } = {}
	local timers: { Timer } = {}
	local pendingWatch: { PendingWatch } = {}
	local pendingListen: { PendingListen } = {}
	local beat: RBXScriptConnection? = nil
	local retryAcc = 0
	local destroyed = false

	local self: Context

	local function safe(fn: () -> ())
		local ok, err = pcall(fn)
		if not ok then
			warn(`[Hud] {err}`)
		end
	end

	local function attachWatch(key: string, fn: () -> ()): boolean
		local disconnect = Bridge.subscribe(key, function()
			safe(fn)
		end)
		if disconnect then
			table.insert(cleanups, disconnect)
			return true
		end
		return false
	end

	local function attachListen(remote: string, fn: (any) -> ()): boolean
		local disconnect = Bridge.listen(remote, function(payload: any)
			safe(function()
				fn(payload)
			end)
		end)
		if disconnect then
			table.insert(cleanups, disconnect)
			return true
		end
		return false
	end

	local function ensureBeat()
		if beat ~= nil then
			return
		end
		beat = RunService.Heartbeat:Connect(function(dt: number)
			for _, t in timers do
				t.acc += dt
				if t.acc >= t.period then
					local elapsed = t.acc
					t.acc = 0
					local ok, err = pcall(t.fn, elapsed)
					if not ok and not t.failed then
						t.failed = true -- warn once, keep running
						warn(`[Hud] timer error: {err}`)
					end
				end
			end
			if #pendingWatch > 0 or #pendingListen > 0 then
				retryAcc += dt
				if retryAcc >= 0.5 then
					retryAcc = 0
					for i = #pendingWatch, 1, -1 do
						local p = pendingWatch[i]
						if attachWatch(p.key, p.fn) then
							table.remove(pendingWatch, i)
							safe(p.fn)
						end
					end
					for i = #pendingListen, 1, -1 do
						local p = pendingListen[i]
						if attachListen(p.remote, p.fn) then
							table.remove(pendingListen, i)
						end
					end
				end
			end
		end)
	end

	self = {
		view = function()
			return Bridge.view()
		end,
		watch = function(keys: { string }, fn: () -> ())
			for _, key in keys do
				if not attachWatch(key, fn) then
					table.insert(pendingWatch, { key = key, fn = fn })
				end
			end
			ensureBeat()
		end,
		listen = function(remote: string, fn: (any) -> ())
			if not attachListen(remote, fn) then
				table.insert(pendingListen, { remote = remote, fn = fn })
			end
			ensureBeat()
		end,
		every = function(seconds: number, fn: (dt: number) -> ())
			table.insert(
				timers,
				{ period = math.max(0, seconds), acc = 0, fn = fn, failed = false }
			)
			ensureBeat()
		end,
		connect = function(conn: RBXScriptConnection)
			table.insert(cleanups, function()
				conn:Disconnect()
			end)
		end,
		onCleanup = function(fn: () -> ())
			table.insert(cleanups, fn)
		end,
		serverNow = function(): number
			return workspace:GetServerTimeNow()
		end,
		toast = function(text: string, kind: string?)
			local impl = self.toastImpl
			if impl then
				impl(text, kind)
			end
		end,
		toastImpl = nil,
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			if beat then
				beat:Disconnect()
				beat = nil
			end
			table.clear(timers)
			table.clear(pendingWatch)
			table.clear(pendingListen)
			for _, fn in cleanups do
				safe(fn)
			end
			table.clear(cleanups)
		end,
	}
	return self
end

return Context
