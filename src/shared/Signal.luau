--!strict
-- Minimal signal. A listener that errors is reported but cannot stop the other listeners.

export type Connection = { disconnect: (self: Connection) -> (), connected: boolean }

export type Signal<T... = ...any> = {
	connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	fire: (self: Signal<T...>, T...) -> (),
	listenerCount: (self: Signal<T...>) -> number,
}

local Signal = {}
Signal.__index = Signal

function Signal.new(): any
	return setmetatable({ _listeners = {} }, Signal)
end

function Signal.connect(self: any, fn: (...any) -> ()): Connection
	local entry = { fn = fn }
	table.insert(self._listeners, entry)
	local conn: any = { connected = true }
	function conn.disconnect(c: any)
		if not c.connected then
			return
		end
		c.connected = false
		local i = table.find(self._listeners, entry)
		if i then
			table.remove(self._listeners, i)
		end
	end
	return conn
end

function Signal.fire(self: any, ...: any)
	local copy = table.clone(self._listeners)
	for _, entry in copy do
		local ok, err = pcall(entry.fn, ...)
		if not ok then
			warn("[Signal] listener error: " .. tostring(err))
		end
	end
end

function Signal.listenerCount(self: any): number
	return #self._listeners
end

return Signal
