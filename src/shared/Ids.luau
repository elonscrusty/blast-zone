--!strict
-- Participant ids. Never use a bare UserId as an identity: bots have none, and ids must say what they are.

local Ids = {}

function Ids.player(userId: number): string
	return "p" .. tostring(math.floor(userId))
end

function Ids.bot(n: number): string
	return "b" .. tostring(math.floor(n))
end

function Ids.isBot(id: string): boolean
	return string.match(id, "^b%d+$") ~= nil
end

function Ids.isPlayer(id: string): boolean
	return string.match(id, "^p%-?%d+$") ~= nil
end

function Ids.isValid(id: any): boolean
	return type(id) == "string" and (Ids.isBot(id) or Ids.isPlayer(id))
end

function Ids.userIdOf(id: string): number?
	local digits = string.match(id, "^p(%-?%d+)$")
	if digits == nil then
		return nil
	end
	return tonumber(digits)
end

return Ids
