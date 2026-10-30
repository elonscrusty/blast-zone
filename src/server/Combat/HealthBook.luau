--!strict
-- Health numbers and "who hit me" for one match. Pure. This is the backend the damage door calls;
-- it never fires events (the door does) and never decides if damage is allowed (the door does).

local HealthBook = {}
HealthBook.__index = HealthBook

type Entry = { health: number, max: number, hitters: { [string]: number }, order: { string } }

export type Book = typeof(setmetatable(
	{} :: { max: number, entries: { [string]: Entry } },
	HealthBook
))

function HealthBook.new(maxHealth: number): Book
	return setmetatable({ max = maxHealth, entries = {} }, HealthBook)
end

function HealthBook.add(self: Book, id: string)
	self.entries[id] = { health = self.max, max = self.max, hitters = {}, order = {} }
end

function HealthBook.has(self: Book, id: string): boolean
	return self.entries[id] ~= nil
end

function HealthBook.get(self: Book, id: string): number?
	local e = self.entries[id]
	return e and e.health
end

function HealthBook.max_(self: Book, id: string): number?
	local e = self.entries[id]
	return e and e.max
end

function HealthBook.remove(self: Book, id: string)
	self.entries[id] = nil
end

-- Takes health off. Returns dealt (never more than what was left), remaining, and whether this hit finished them.
-- A target already at 0 takes nothing, so a second finishing blow can never report eliminated.
function HealthBook.apply(
	self: Book,
	id: string,
	amount: number,
	sourceId: string?
): (number, number, boolean)
	local e = self.entries[id]
	if e == nil or e.health <= 0 or amount ~= amount or amount <= 0 then
		return 0, if e then e.health else 0, false
	end
	local dealt = math.min(amount, e.health)
	e.health -= dealt
	if sourceId ~= nil and sourceId ~= id then
		if e.hitters[sourceId] == nil then
			table.insert(e.order, sourceId)
			e.hitters[sourceId] = 0
		end
		e.hitters[sourceId] += dealt
	end
	return dealt, e.health, e.health <= 0
end

-- Healing never revives and never goes over the maximum.
function HealthBook.heal(self: Book, id: string, amount: number): number
	local e = self.entries[id]
	if e == nil or e.health <= 0 or amount ~= amount or amount <= 0 then
		return 0
	end
	local gained = math.min(amount, e.max - e.health)
	e.health += gained
	return gained
end

-- Everyone who hurt `id`, most damage first (for "who hit you" on the defeat card).
function HealthBook.hitters(self: Book, id: string): { { sourceId: string, damage: number } }
	local e = self.entries[id]
	local out = {}
	if e == nil then
		return out
	end
	for _, sourceId in e.order do
		table.insert(out, { sourceId = sourceId, damage = e.hitters[sourceId] })
	end
	table.sort(out, function(a, b)
		return a.damage > b.damage
	end)
	return out
end

return HealthBook
