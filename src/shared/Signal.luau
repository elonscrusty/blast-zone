--!strict
-- A tiny event. `connect` returns a function that undoes it. Pure Luau so Lune can test it.

export type Signal<T...> = {
	connect: (self: Signal<T...>, fn: (T...) -> ()) -> () -> (),
	fire: (self: Signal<T...>, T...) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	return setmetatable({ _fns = {} }, Signal) :: any
end

function Signal.connect(self: any, fn: (...any) -> ()): () -> ()
	local fns = self._fns
	table.insert(fns, fn)
	return function()
		local i = table.find(fns, fn)
		if i then
			table.remove(fns, i)
		end
	end
end

function Signal.fire(self: any, ...: any)
	-- Copy first so a listener can disconnect itself while we are firing.
	local copy = table.clone(self._fns)
	for _, fn in copy do
		fn(...)
	end
end

return Signal
