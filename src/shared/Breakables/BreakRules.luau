--!strict
-- Street props that burst (piece 43), with no game objects in it so Lune can test it.
-- One book per arena: it knows each prop's health and which ones are already broken.
-- The server asks it "does this hit break the prop?"; it never touches a part itself.

export type Kind = { health: number, chunks: number }
export type Book = {
	kinds: { [string]: Kind },
	props: { [string]: { kind: string, health: number, max: number, broken: boolean } },
}
export type Box = { x0: number, z0: number, x1: number, z1: number, h: number }
export type Piece = {
	dx: number,
	dz: number,
	sx: number,
	sy: number,
	sz: number,
	ry: number,
	pick: number,
}

local BreakRules = {}

function BreakRules.new(kinds: { [string]: Kind }): Book
	return { kinds = kinds, props = {} }
end

-- Adds a prop. Returns false for a kind the book does not know or an id it already has.
function BreakRules.register(book: Book, id: string, kind: string): boolean
	local k = book.kinds[kind]
	if k == nil or book.props[id] ~= nil then
		return false
	end
	book.props[id] = { kind = kind, health = k.health, max = k.health, broken = false }
	return true
end

function BreakRules.has(book: Book, id: string): boolean
	return book.props[id] ~= nil
end

function BreakRules.isBroken(book: Book, id: string): boolean
	local p = book.props[id]
	return p ~= nil and p.broken
end

function BreakRules.health(book: Book, id: string): number?
	local p = book.props[id]
	return if p then p.health else nil
end

-- Takes health off a prop. Returns whether THIS hit broke it. A broken prop never breaks twice.
-- Bad numbers (nan, zero, negative, infinite) do nothing.
function BreakRules.damage(book: Book, id: string, amount: number): boolean
	local p = book.props[id]
	if p == nil or p.broken then
		return false
	end
	if amount ~= amount or amount <= 0 or amount == math.huge then
		return false
	end
	p.health = math.max(0, p.health - amount)
	if p.health <= 0 then
		p.broken = true
		return true
	end
	return false
end

-- Puts every prop back to full health (a new match on the same arena).
function BreakRules.reset(book: Book)
	for _, p in book.props do
		p.health = p.max
		p.broken = false
	end
end

function BreakRules.brokenCount(book: Book): number
	local n = 0
	for _, p in book.props do
		if p.broken then
			n += 1
		end
	end
	return n
end

-- A blast reaches a prop when its nearest edge is inside the radius. Returns the share of the
-- damage it gets (1 at the edge of the blast centre, falling to `minFactor` at the radius), or 0.
function BreakRules.blastFactor(distToEdge: number, radius: number, minFactor: number): number
	if distToEdge ~= distToEdge or radius <= 0 or distToEdge > radius then
		return 0
	end
	local d = math.max(0, distToEdge)
	return 1 - (1 - minFactor) * (d / radius)
end

-- Distance from a point to the nearest edge of a box on the ground (0 inside it).
function BreakRules.edgeDistance(x: number, z: number, box: Box): number
	local dx = math.max(box.x0 - x, 0, x - box.x1)
	local dz = math.max(box.z0 - z, 0, z - box.z1)
	return math.sqrt(dx * dx + dz * dz)
end

-- The blocks that stay behind: `pieces` small blocks spread over the box, same seed same pile.
-- `pick` is a number from 0 to 1 the caller maps to a colour. Sizes are inside [minSize, maxSize].
function BreakRules.rubble(
	box: Box,
	seed: number,
	pieces: number,
	minSize: number,
	maxSize: number
): { Piece }
	local state = (math.floor(math.abs(seed)) % 2147483646) + 1
	local function rnd(): number
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
	local w, d = box.x1 - box.x0, box.z1 - box.z0
	local out: { Piece } = {}
	for _ = 1, math.max(0, math.floor(pieces)) do
		local sx = minSize + rnd() * (maxSize - minSize)
		local sy = (minSize + rnd() * (maxSize - minSize)) * 0.7
		local sz = minSize + rnd() * (maxSize - minSize)
		table.insert(out, {
			dx = (rnd() - 0.5) * w * 0.9,
			dz = (rnd() - 0.5) * d * 0.9,
			sx = sx,
			sy = sy,
			sz = sz,
			ry = rnd() * 360,
			pick = rnd(),
		})
	end
	return out
end

-- A stable number for a prop id, so rubble looks the same on every run of a map.
function BreakRules.seedOf(id: string): number
	local h = 5381
	for i = 1, #id do
		h = (h * 33 + string.byte(id, i)) % 2147483629
	end
	return h
end

return BreakRules
