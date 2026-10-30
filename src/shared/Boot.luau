--!strict
-- Rules for finding "systems". Any ModuleScript whose name ends in "System", anywhere under the
-- server or client folder, is a system. It returns { order: number?, start: () -> () }.
-- Lower `order` starts first (default 100); ties go by name. One failing system never stops the rest.

local Boot = {}

Boot.SUFFIX = "System"
Boot.DEFAULT_ORDER = 100

function Boot.isSystemName(name: string): boolean
	return #name > #Boot.SUFFIX and string.sub(name, -#Boot.SUFFIX) == Boot.SUFFIX
end

export type Entry = { name: string, order: number? }

-- Returns the entries sorted into start order. Does not change the input.
function Boot.sort(entries: { Entry }): { Entry }
	local out = table.clone(entries)
	table.sort(out, function(a: Entry, b: Entry): boolean
		local ao: number = a.order or Boot.DEFAULT_ORDER
		local bo: number = b.order or Boot.DEFAULT_ORDER
		if ao ~= bo then
			return ao < bo
		end
		return a.name < b.name
	end)
	return out
end

return Boot
