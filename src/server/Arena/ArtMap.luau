--!strict
-- Quick questions about the compiled layout for the art planner (piece 14): what kind of ground
-- is here, is something standing here, which solid is this. Pure maths, no Roblox types.
local Layout = require("./Layout")

local ArtMap = {}
ArtMap.__index = ArtMap

export type Map = typeof(setmetatable(
	{} :: {
		layout: Layout.Layout,
		solids: { Layout.Solid }, -- everything but the invisible boundary walls
		byId: { [string]: Layout.Solid },
	},
	ArtMap
))

local GROUND_RANK: { [string]: number } = {
	sidewalk = 0,
	lot = 1,
	park = 1,
	alley = 2,
	road = 3,
	floor = 4,
}

function ArtMap.new(layout: Layout.Layout): Map
	local solids: { Layout.Solid } = {}
	local byId: { [string]: Layout.Solid } = {}
	for _, s in layout.solids do
		if s.kind ~= "boundary" then
			table.insert(solids, s)
			byId[s.id] = s
		end
	end
	return setmetatable({ layout = layout, solids = solids, byId = byId }, ArtMap)
end

-- The ground kind on top at x, z (same layering as the graybox builder).
function ArtMap.groundKind(self: Map, x: number, z: number): string
	local best, rank = "sidewalk", -1
	for _, g in self.layout.ground do
		if x >= g.x0 and x <= g.x1 and z >= g.z0 and z <= g.z1 then
			local r = GROUND_RANK[g.kind] or 0
			if r > rank then
				best, rank = g.kind, r
			end
		end
	end
	return best
end

-- Is x, z inside (or within pad of) any solid?
function ArtMap.blocked(self: Map, x: number, z: number, pad: number): boolean
	for _, s in self.solids do
		if x >= s.x0 - pad and x <= s.x1 + pad and z >= s.z0 - pad and z <= s.z1 + pad then
			return true
		end
	end
	return false
end

-- Does the rectangle touch any solid (grown by pad)?
function ArtMap.rectHitsSolid(
	self: Map,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	pad: number
): boolean
	for _, s in self.solids do
		if x1 >= s.x0 - pad and x0 <= s.x1 + pad and z1 >= s.z0 - pad and z0 <= s.z1 + pad then
			return true
		end
	end
	return false
end

-- Is the whole rectangle one ground kind, with no solid in it?
function ArtMap.rectIsClear(
	self: Map,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	kind: string,
	pad: number
): boolean
	if self:rectHitsSolid(x0, z0, x1, z1, pad) then
		return false
	end
	for _, p in { { x0, z0 }, { x1, z0 }, { x0, z1 }, { x1, z1 }, { (x0 + x1) / 2, (z0 + z1) / 2 } } do
		if self:groundKind(p[1] :: number, p[2] :: number) ~= kind then
			return false
		end
	end
	return true
end

function ArtMap.ground(self: Map, kind: string): { Layout.GroundSpec }
	local out = {}
	for _, g in self.layout.ground do
		if g.kind == kind then
			table.insert(out, g)
		end
	end
	return out
end

function ArtMap.solidsWithPrefix(self: Map, prefix: string): { Layout.Solid }
	local out = {}
	for _, s in self.solids do
		if string.sub(s.id, 1, #prefix) == prefix then
			table.insert(out, s)
		end
	end
	return out
end

return ArtMap
