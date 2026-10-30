--!strict
-- Run XP ledger. Pure: Config.Xp goes in, nothing else is touched. One instance per server (Core/RunXp).
-- Piece 07 calls award(); piece 08 hears LevelUp and spends pending offers with takeOffer().

local Signal = require("./Signal")

export type XpConfig = {
	rewards: { [string]: number },
	levelCosts: { number },
	costStepAfter: number,
	maxOffersPerMatch: number,
}

export type State = {
	level: number,
	xp: number,
	xpToNext: number,
	totalXp: number,
	pendingOffers: number,
	offersGranted: number,
}

local RunXp = {}
RunXp.__index = RunXp

function RunXp.new(cfg: XpConfig): any
	return setmetatable({
		_cfg = cfg,
		_state = {} :: { [string]: State },
		Changed = Signal.new(), -- (participantId, State)
		LevelUp = Signal.new(), -- (participantId, newLevel, pendingOffers)
		Awarded = Signal.new(), -- (participantId, reason): after an award counted (daily challenges listen)
	}, RunXp)
end

function RunXp.costForLevel(self: any, level: number): number
	local costs = self._cfg.levelCosts
	if level <= #costs then
		return costs[level]
	end
	return costs[#costs] + self._cfg.costStepAfter * (level - #costs)
end

function RunXp.reset(self: any, id: string)
	self._state[id] = {
		level = 1,
		xp = 0,
		xpToNext = self:costForLevel(1),
		totalXp = 0,
		pendingOffers = 0,
		offersGranted = 0,
	}
	self.Changed:fire(id, self._state[id])
end

function RunXp.resetAll(self: any)
	self._state = {}
end

-- A participant left the match for good: their ledger entry goes with them.
function RunXp.forget(self: any, id: string)
	self._state[id] = nil
end

function RunXp.get(self: any, id: string): State?
	return self._state[id]
end

function RunXp.amountFor(self: any, reason: string): number
	local n = self._cfg.rewards[reason]
	if n == nil then
		error("RunXp: unknown reason " .. tostring(reason), 2)
	end
	return n
end

-- Adds XP for a named reason (never a client number). Returns the new state, or nil if unknown id.
function RunXp.award(self: any, id: string, reason: string): State?
	local st: State? = self._state[id]
	if st == nil then
		return nil
	end
	local amount = self:amountFor(reason)
	st.xp += amount
	st.totalXp += amount
	while st.xp >= st.xpToNext do
		st.xp -= st.xpToNext
		st.level += 1
		st.xpToNext = self:costForLevel(st.level)
		if st.offersGranted < self._cfg.maxOffersPerMatch then
			st.offersGranted += 1
			st.pendingOffers += 1
		end
		self.LevelUp:fire(id, st.level, st.pendingOffers)
	end
	self.Changed:fire(id, st)
	self.Awarded:fire(id, reason)
	return st
end

-- Piece 08 calls this when it shows or resolves an offer. False if none is waiting.
function RunXp.takeOffer(self: any, id: string): boolean
	local st: State? = self._state[id]
	if st == nil or st.pendingOffers <= 0 then
		return false
	end
	st.pendingOffers -= 1
	self.Changed:fire(id, st)
	return true
end

return RunXp
