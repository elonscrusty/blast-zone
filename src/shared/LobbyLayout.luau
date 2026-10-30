--!strict
-- Where everything is in the lobby (carter's pick: plaza A "Crosswalk Plaza", locked at 260 x 182 studs).
-- Pure numbers, no Roblox services. The server builds parts from it, the client uses stationAt() to know
-- which pad you stand on, and the tests check the walks stay short.
--
-- Coordinates are studs from the lobby's top-left corner: x goes right, z goes toward the camera (down the
-- screen). Walking "up" the screen (smaller z) is toward the PLAY gate, like walking toward the arena.
-- Boxes are { x, z, width, depth, height } with x,z the top-left corner.

export type Box = { number }
export type Pad = { x: number, z: number, radius: number }

export type Station = {
	id: string, -- "loadout" | "play" | "settings" | "rewards"
	label: string,
	color: string, -- hex, from the palette
	pad: Pad,
	box: Box?, -- the building or board
	pillars: { Box }?, -- PLAY gate
	beam: Box?, -- PLAY gate crossbar: { x, z, width, depth, topHeight, thickness }
}

export type Decor = {
	kind: string, -- "planter" | "crate" | "wall" | "tower" | "fountain" | "tree" | "lamp"
	box: Box?,
	x: number?,
	z: number?,
}

local K = 1.3 -- the size carter locked, on top of the 200 x 140 plaza he first called big enough to try

local function scaled(list: { number }): { number }
	local out = {}
	for i, n in list do
		out[i] = math.floor(n * K * 10 + 0.5) / 10
	end
	return out
end

local WIDTH, DEPTH = 200 * K, 140 * K
local PAD_DRAW_RADIUS = 6 * 2.6 -- how big the glowing disc looks
local PAD_TRIGGER_SHARE = 0.6 -- you must stand well inside the disc

local function pad(x: number, z: number): Pad
	return { x = x * K, z = z * K, radius = PAD_DRAW_RADIUS }
end

local LobbyLayout = {}

LobbyLayout.width = WIDTH
LobbyLayout.depth = DEPTH
LobbyLayout.wallHeight = 14 -- invisible walls that keep people on the plaza
LobbyLayout.spawn = { x = 100 * K, z = 108 * K }
LobbyLayout.padTriggerShare = PAD_TRIGGER_SHARE

-- Far from the arena (which sits around 0,0), and high enough that nothing else is near.
LobbyLayout.origin = { x = 1000, y = 0, z = 0 } -- world position of the plaza's centre

-- Where the top-wins board stands (the leaderboard piece finds the part tagged `LeaderboardSpot`).
-- Back wall, right of the PLAY gate. The part faces the camera (+z). x,z = centre of its base.
LobbyLayout.leaderboardSpot = { x = 195, z = 5, width = 36, height = 22 }

LobbyLayout.stations = {
	{
		id = "loadout",
		label = "LOADOUT",
		color = "#36D9E8",
		pad = pad(38, 62),
		box = scaled({ 10, 8, 56, 36, 24 }),
	},
	{
		id = "play",
		label = "PLAY",
		color = "#FFC44D",
		pad = pad(100, 30),
		pillars = { scaled({ 70, 0, 8, 8, 32 }), scaled({ 122, 0, 8, 8, 32 }) },
		beam = scaled({ 70, 0, 60, 8, 32, 10 }),
	},
	{
		id = "settings",
		label = "SETTINGS",
		color = "#F15B64",
		pad = pad(169, 46),
		box = scaled({ 156, 16, 26, 16, 16 }),
	},
	{
		id = "rewards",
		label = "REWARDS",
		color = "#8B5FBF",
		pad = pad(168, 114),
		box = scaled({ 148, 92, 40, 6, 24 }),
	},
} :: { Station }

LobbyLayout.decor = {
	{ kind = "planter", box = scaled({ 14, 96, 28, 10, 5 }) },
	{ kind = "planter", box = scaled({ 46, 118, 28, 10, 5 }) },
	{ kind = "crate", box = scaled({ 124, 116, 8, 8, 8 }) },
	{ kind = "crate", box = scaled({ 135, 124, 8, 8, 8 }) },
	{ kind = "wall", box = scaled({ 0, 70, 10, 30, 16 }) },
	{ kind = "tower", box = scaled({ 190, 52, 10, 28, 18 }) },
	{ kind = "fountain", x = 100 * K, z = 74 * K },
	{ kind = "tree", x = 86 * K, z = 40 * K },
	{ kind = "tree", x = 114 * K, z = 40 * K },
	{ kind = "tree", x = 24 * K, z = 128 * K },
	{ kind = "tree", x = 176 * K, z = 130 * K },
	{ kind = "tree", x = 70 * K, z = 88 * K },
	{ kind = "tree", x = 130 * K, z = 90 * K },
	{ kind = "lamp", x = 60 * K, z = 24 * K },
	{ kind = "lamp", x = 140 * K, z = 24 * K },
	{ kind = "lamp", x = 60 * K, z = 100 * K },
	{ kind = "lamp", x = 140 * K, z = 100 * K },
} :: { Decor }

function LobbyLayout.station(id: string): Station?
	for _, s in LobbyLayout.stations do
		if s.id == id then
			return s
		end
	end
	return nil
end

-- Plaza coordinates -> world coordinates (x, z). The plaza is centred on `origin`.
function LobbyLayout.toWorld(x: number, z: number): (number, number)
	return LobbyLayout.origin.x + (x - WIDTH / 2), LobbyLayout.origin.z + (z - DEPTH / 2)
end

-- World coordinates -> plaza coordinates.
function LobbyLayout.fromWorld(wx: number, wz: number): (number, number)
	return wx - LobbyLayout.origin.x + WIDTH / 2, wz - LobbyLayout.origin.z + DEPTH / 2
end

-- Is this world position inside the plaza (a little slack for the edge)?
function LobbyLayout.contains(wx: number, wz: number, slack: number?): boolean
	local x, z = LobbyLayout.fromWorld(wx, wz)
	local s = slack or 0
	return x >= -s and x <= WIDTH + s and z >= -s and z <= DEPTH + s
end

-- Which station's pad (if any) is a world position standing on?
function LobbyLayout.stationAt(wx: number, wz: number): string?
	local x, z = LobbyLayout.fromWorld(wx, wz)
	local best: string? = nil
	local bestDist = math.huge
	for _, s in LobbyLayout.stations do
		local d = math.sqrt((x - s.pad.x) ^ 2 + (z - s.pad.z) ^ 2)
		if d <= s.pad.radius * PAD_TRIGGER_SHARE and d < bestDist then
			best, bestDist = s.id, d
		end
	end
	return best
end

-- Straight-line seconds to walk between two plaza points at this speed.
function LobbyLayout.walkSeconds(
	ax: number,
	az: number,
	bx: number,
	bz: number,
	speed: number
): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) / speed
end

return LobbyLayout
