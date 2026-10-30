--!strict
-- Pure kill-streak maths (piece 36). The server feeds it kills; it says what each kill earns.
-- One book per match. Times are any steadily rising clock (os.clock).

export type Tier = {
	at: number,
	heal: number,
	speedMultiplier: number,
	speedSeconds: number,
	text: string,
}

export type Config = { windowSeconds: number, tiers: { Tier } }

export type Reward = { streak: number, tier: Tier }

local StreakRules = {}
StreakRules.__index = StreakRules

type Entry = { count: number, lastAt: number }

function StreakRules.new(cfg: Config)
	return setmetatable({ _cfg = cfg, _entries = {} :: { [string]: Entry } }, StreakRules)
end

-- A kill by killerId at time `now`. Returns the new streak and the tier it unlocked, if any.
function StreakRules.recordKill(self: any, killerId: string, now: number): (number, Reward?)
	local entries: { [string]: Entry } = self._entries
	local e = entries[killerId]
	if e ~= nil and now - e.lastAt <= self._cfg.windowSeconds then
		e.count += 1
		e.lastAt = now
	else
		e = { count = 1, lastAt = now }
		entries[killerId] = e
	end
	local count = (e :: Entry).count
	for _, tier in self._cfg.tiers do
		if tier.at == count then
			return count, { streak = count, tier = tier }
		end
	end
	return count, nil
end

function StreakRules.get(self: any, id: string): number
	local e = self._entries[id]
	return if e ~= nil then e.count else 0
end

-- Dying ends a streak.
function StreakRules.reset(self: any, id: string)
	self._entries[id] = nil
end

function StreakRules.clear(self: any)
	self._entries = {}
end

return StreakRules
