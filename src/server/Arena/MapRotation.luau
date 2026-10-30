--!strict
-- Which map is next. A plain list of layout ids played in order, looping back to the start.
-- Ids that are not real layouts are dropped (with a note), so a typo never breaks the server.
-- Pure: no Roblox types, so Lune can test it.

local MapRotation = {}
MapRotation.__index = MapRotation

export type MapRotation = {
	order: { string },
	index: number,
	dropped: { string },
	current: (self: MapRotation) -> string,
	advance: (self: MapRotation) -> string,
	peekNext: (self: MapRotation) -> string,
	select: (self: MapRotation, id: string) -> boolean,
}

-- `list` is the wanted order, `known` says which ids exist, `fallback` is used when nothing in
-- the list is real.
function MapRotation.new(list: { string }, known: { [string]: any }, fallback: string): MapRotation
	local order: { string } = {}
	local dropped: { string } = {}
	for _, id in list do
		if known[id] ~= nil then
			table.insert(order, id)
		else
			table.insert(dropped, id)
		end
	end
	if #order == 0 then
		table.insert(order, fallback)
	end
	local self = setmetatable({ order = order, index = 1, dropped = dropped }, MapRotation)
	return (self :: any) :: MapRotation
end

function MapRotation.current(self: MapRotation): string
	return self.order[self.index]
end

function MapRotation.peekNext(self: MapRotation): string
	return self.order[self.index % #self.order + 1]
end

-- Moves to the next map and returns it. One map in the list means it stays.
function MapRotation.advance(self: MapRotation): string
	self.index = self.index % #self.order + 1
	return self.order[self.index]
end

-- Jumps to a map in the list (a vote winner). Rotation carries on from there. Unknown ids do nothing.
function MapRotation.select(self: MapRotation, id: string): boolean
	local i = table.find(self.order, id)
	if not i then
		return false
	end
	self.index = i
	return true
end

return MapRotation
