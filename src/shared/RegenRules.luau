--!strict
-- Pure maths for health that comes back on its own (feel pass 2). A fighter who has not been hurt
-- for `delaySeconds` gets `perSecond` health back. Any drop in health (a shot, a blast, the zone)
-- starts the wait again. Only whole health points are given, so the bar never shows 73.4.
-- The server feeds it each fighter's health on a steady tick; it says how much to give back.

export type Config = {
	enabled: boolean,
	delaySeconds: number,
	perSecond: number,
	maxStepSeconds: number?, -- one tick never counts more time than this (a server hitch cannot heal in one lump)
}

type Entry = { lastHealth: number, hurtAt: number, lastAt: number, carry: number }

local RegenRules = {}
RegenRules.__index = RegenRules

function RegenRules.new(cfg: Config)
	return setmetatable({ _cfg = cfg, _entries = {} :: { [string]: Entry } }, RegenRules)
end

-- One tick for one fighter. `now` is any steadily rising clock (os.clock). Returns whole health to give.
function RegenRules.step(self: any, id: string, health: number, max: number, now: number): number
	local cfg: Config = self._cfg
	local entries: { [string]: Entry } = self._entries
	local e = entries[id]
	if e == nil then
		-- First sight of a fighter counts as "not hurt yet": a full bar has nothing to regrow anyway.
		entries[id] = { lastHealth = health, hurtAt = -math.huge, lastAt = now, carry = 0 }
		return 0
	end
	local dt = math.clamp(now - e.lastAt, 0, cfg.maxStepSeconds or math.huge)
	e.lastAt = now
	if health < e.lastHealth then
		e.hurtAt = now
		e.carry = 0
	end
	e.lastHealth = health
	if not cfg.enabled or health <= 0 or health >= max then
		e.carry = 0
		return 0
	end
	if now - e.hurtAt < cfg.delaySeconds then
		return 0
	end
	e.carry += cfg.perSecond * dt
	local whole = math.floor(e.carry)
	if whole <= 0 then
		return 0
	end
	e.carry -= whole
	return math.min(whole, math.floor(max - health))
end

-- The server calls this with the health a fighter really has after the heal went through.
function RegenRules.applied(self: any, id: string, healthAfter: number)
	local e: Entry? = self._entries[id]
	if e ~= nil then
		e.lastHealth = healthAfter
	end
end

function RegenRules.reset(self: any, id: string)
	self._entries[id] = nil
end

function RegenRules.clear(self: any)
	table.clear(self._entries)
end

return RegenRules
