--!strict
-- Which roofs and walls should look see-through for the local player. Pure maths (no Roblox
-- calls) so Lune can test it. This only decides how things LOOK on one screen. It never touches
-- collision, shots or line of sight, and it never runs on the server.
--
-- Rules (proposed, tune in Config.Arena.fade):
--   * Standing inside a building: its roof disappears, and its outer walls that sit between the
--     camera and you turn mostly see-through. You see the whole room.
--   * Anything else (a tall block, another building) that sits on the line from the camera to
--     your head turns partly see-through, so a big foreground object never hides you.
--   * Other people standing inside a building you are not in are hidden from you (see
--     `hidesOccupant`), so fading a roof or wall can never show you someone behind a wall.

local Visibility = {}

export type Box = {
	id: string,
	kind: string, -- "roof" | "wall" | "mass"
	building: string?,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
}

export type Footprint = { id: string, x0: number, z0: number, x1: number, z1: number }

export type Fade = {
	insideRoof: number,
	insideWall: number,
	outsideBlocker: number,
	playerPad: number,
	headHeight: number,
}

local WALL = 2 -- wall thickness; the room starts this far in from the footprint edge

-- The building whose room (inside the walls) contains x, z. Standing in a doorway counts as outside.
function Visibility.insideBuilding(buildings: { Footprint }, x: number, z: number): string?
	for _, b in buildings do
		if x > b.x0 + WALL and x < b.x1 - WALL and z > b.z0 + WALL and z < b.z1 - WALL then
			return b.id
		end
	end
	return nil
end

-- Another participant at x, z should be hidden when they are in a room you are not in.
function Visibility.hidesOccupant(
	buildings: { Footprint },
	myBuilding: string?,
	x: number,
	z: number
): boolean
	local theirs = Visibility.insideBuilding(buildings, x, z)
	return theirs ~= nil and theirs ~= myBuilding
end

-- Does the straight line a -> b pass through the box grown by `pad` sideways?
function Visibility.lineHitsBox(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	box: Box,
	pad: number
): boolean
	local t0, t1 = 0, 1
	local function slab(p: number, d: number, lo: number, hi: number): boolean
		if math.abs(d) < 1e-9 then
			return p >= lo and p <= hi
		end
		local ta, tb = (lo - p) / d, (hi - p) / d
		if ta > tb then
			ta, tb = tb, ta
		end
		t0, t1 = math.max(t0, ta), math.min(t1, tb)
		return t0 <= t1
	end
	return slab(ax, bx - ax, box.x0 - pad, box.x1 + pad)
		and slab(ay, by - ay, box.y0, box.y1)
		and slab(az, bz - az, box.z0 - pad, box.z1 + pad)
end

-- Fills `out` (cleared first) with target transparency per box id. Boxes not listed stay solid.
-- (px, pz) is where the local player stands; (cx, cy, cz) is the camera.
function Visibility.compute(
	boxes: { Box },
	buildings: { Footprint },
	px: number,
	pz: number,
	cx: number,
	cy: number,
	cz: number,
	fade: Fade,
	out: { [string]: number }
): string?
	table.clear(out)
	local inside = Visibility.insideBuilding(buildings, px, pz)
	local hy = fade.headHeight
	for _, b in boxes do
		local mine = inside ~= nil and b.building == inside
		if b.kind == "roof" and mine then
			out[b.id] = fade.insideRoof
		elseif Visibility.lineHitsBox(cx, cy, cz, px, hy, pz, b, fade.playerPad) then
			out[b.id] = if mine then fade.insideWall else fade.outsideBlocker
		end
	end
	return inside
end

return Visibility
