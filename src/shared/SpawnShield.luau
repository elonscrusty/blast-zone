--!strict
-- Who is shielded right now, and until when. No Roblox calls, so Lune can test it.
-- The server gives the shield when the fight starts; the damage door asks isShielded() on every hit.

local SpawnShield = {}
SpawnShield.__index = SpawnShield

export type Book = typeof(setmetatable(
	{} :: {
		_clock: () -> number,
		_until: { [string]: number },
	},
	SpawnShield
))

function SpawnShield.new(clock: () -> number): Book
	return setmetatable({ _clock = clock, _until = {} }, SpawnShield)
end

function SpawnShield.give(self: Book, id: string, seconds: number)
	if seconds > 0 then
		self._until[id] = self._clock() + seconds
	end
end

function SpawnShield.isShielded(self: Book, id: string): boolean
	local t = self._until[id]
	if t == nil then
		return false
	end
	if self._clock() >= t then
		self._until[id] = nil
		return false
	end
	return true
end

-- Seconds left, 0 when not shielded.
function SpawnShield.remaining(self: Book, id: string): number
	if not self:isShielded(id) then
		return 0
	end
	return self._until[id] - self._clock()
end

-- Returns true if a shield was taken away.
function SpawnShield.drop(self: Book, id: string): boolean
	local had = self:isShielded(id)
	self._until[id] = nil
	return had
end

function SpawnShield.clear(self: Book)
	self._until = {}
end

-- Damage guard: drops hits on a shielded target.
function SpawnShield.guard(self: Book): (req: { targetId: string }) -> string?
	return function(req)
		if self:isShielded(req.targetId) then
			return "shielded"
		end
		return nil
	end
end

return SpawnShield
