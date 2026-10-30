--!strict
-- Only one full panel (settings, track, loadout, shop...) is open at a time. A panel calls
-- `opened` when it shows and `closed` when it hides; opening a second one closes the first.
-- Pure Luau so Lune can check it.

local ModalGate = {}

local current: string? = nil
local closers: { [string]: () -> () } = {}

-- `close` hides the panel; the gate calls it when another panel opens.
function ModalGate.opened(name: string, close: () -> ())
	closers[name] = close
	local other = current
	current = name
	if other and other ~= name then
		local closeOther = closers[other]
		if closeOther then
			closeOther()
		end
		current = name -- the other panel's `closed` call must not clear this one
	end
end

function ModalGate.closed(name: string)
	if current == name then
		current = nil
	end
end

function ModalGate.current(): string?
	return current
end

function ModalGate.closeAll()
	local name = current
	if name then
		current = nil
		local close = closers[name]
		if close then
			close()
		end
	end
end

return ModalGate
