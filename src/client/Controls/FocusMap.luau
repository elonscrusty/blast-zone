--!strict
-- Which button the gamepad cursor sits on, and where each direction takes it. Pure numbers so
-- Lune can test the rules:
--   * the first button is the same every time (highest priority, then top-left)
--   * a direction only moves to a button that lies that way; with none, the cursor stays put
--   * a menu on top (a modal) hides everything under it

export type Item = {
	id: string,
	x: number, -- screen pixels, top-left
	y: number,
	w: number,
	h: number,
	priority: number?, -- higher is picked first when focus starts (PLAY over SETTINGS)
}

export type Direction = "left" | "right" | "up" | "down"

export type Links = { left: string, right: string, up: string, down: string }

export type Scope = {
	name: string,
	modal: boolean, -- true: while it has buttons, only its buttons can be focused
	items: { Item },
}

local FocusMap = {}

-- Off-axis distance counts double so a button straight across beats one far off to the side.
local CROSS_WEIGHT = 2

local function centre(item: Item): (number, number)
	return item.x + item.w / 2, item.y + item.h / 2
end

local function valid(item: Item): boolean
	return item.w > 0 and item.h > 0 and item.x == item.x and item.y == item.y
end

local function firstBefore(a: Item, b: Item): boolean
	local pa, pb = a.priority or 0, b.priority or 0
	if pa ~= pb then
		return pa > pb
	end
	local ax, ay = centre(a)
	local bx, by = centre(b)
	-- A little tolerance so two buttons in one row compare left to right.
	if math.abs(ay - by) > 8 then
		return ay < by
	end
	if ax ~= bx then
		return ax < bx
	end
	return a.id < b.id
end

-- The button focus starts on. nil when there is nothing to focus.
function FocusMap.first(items: { Item }): string?
	local best: Item? = nil
	for _, item in items do
		if valid(item) and (best == nil or firstBefore(item, best)) then
			best = item
		end
	end
	return if best then best.id else nil
end

-- Where a direction takes the cursor from `fromId`. nil when nothing lies that way.
function FocusMap.neighbor(items: { Item }, fromId: string, dir: Direction): string?
	local from: Item? = nil
	for _, item in items do
		if item.id == fromId then
			from = item
			break
		end
	end
	if from == nil then
		return nil
	end
	local fx, fy = centre(from)
	local best: string? = nil
	local bestScore = math.huge
	for _, item in items do
		if item.id ~= fromId and valid(item) then
			local cx, cy = centre(item)
			local dx, dy = cx - fx, cy - fy -- screen y points down
			local along, across
			if dir == "left" then
				along, across = -dx, dy
			elseif dir == "right" then
				along, across = dx, dy
			elseif dir == "up" then
				along, across = -dy, dx
			else
				along, across = dy, dx
			end
			if along > 0 then
				local score = along + CROSS_WEIGHT * math.abs(across)
				if score < bestScore or (score == bestScore and best ~= nil and item.id < best) then
					bestScore = score
					best = item.id
				end
			end
		end
	end
	return best
end

-- Every button's four neighbours. With nothing that way a direction points back at the button
-- itself, which keeps the cursor where it is instead of jumping somewhere unexpected.
function FocusMap.links(items: { Item }): { [string]: Links }
	local out: { [string]: Links } = {}
	for _, item in items do
		if valid(item) then
			out[item.id] = {
				left = FocusMap.neighbor(items, item.id, "left") or item.id,
				right = FocusMap.neighbor(items, item.id, "right") or item.id,
				up = FocusMap.neighbor(items, item.id, "up") or item.id,
				down = FocusMap.neighbor(items, item.id, "down") or item.id,
			}
		end
	end
	return out
end

-- The buttons that may take focus right now: a menu on top owns it all, otherwise everything.
function FocusMap.active(scopes: { Scope }): { Item }
	local out: { Item } = {}
	for _, scope in scopes do
		if scope.modal and #scope.items > 0 then
			return table.clone(scope.items)
		end
	end
	for _, scope in scopes do
		for _, item in scope.items do
			table.insert(out, item)
		end
	end
	return out
end

-- Is a menu on top?
function FocusMap.hasModal(scopes: { Scope }): boolean
	for _, scope in scopes do
		if scope.modal and #scope.items > 0 then
			return true
		end
	end
	return false
end

-- Keep the cursor where it is if that button is still on offer, else start from the first.
function FocusMap.settle(items: { Item }, currentId: string?): string?
	if currentId ~= nil then
		for _, item in items do
			if item.id == currentId and valid(item) then
				return currentId
			end
		end
	end
	return FocusMap.first(items)
end

return FocusMap
