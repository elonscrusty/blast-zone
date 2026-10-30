--!strict
-- Slide bookkeeping per participant: cooldown, whether a slide is running, and a token that tells
-- a delayed check whether it still belongs to the slide it was made for. Plain numbers (the clock
-- is passed in) so Lune can test it. Server only.

local SlideRules = require("./SlideRules")

type Entry = {
	charges: number, -- slides ready right now (as of `rechargeAt` bookkeeping; see refresh)
	max: number,
	rechargeAt: number, -- when the next charge comes back (meaningless while charges == max)
	cooldown: number,
	activeUntil: number,
	token: number,
}

local SlideBook = {}
SlideBook.__index = SlideBook

function SlideBook.new(): any
	return setmetatable({ _entries = {} :: { [string]: Entry }, _nextToken = 0 }, SlideBook)
end

-- Gives back every charge whose time has come.
local function refresh(e: Entry, now: number)
	while e.charges < e.max and now >= e.rechargeAt do
		e.charges += 1
		e.rechargeAt += e.cooldown
	end
	if e.charges >= e.max then
		e.charges = e.max
	end
end

-- When the next slide is available: 0 while a charge is ready, else when the next one returns.
function SlideBook.readyAt(self: any, id: string): number
	local e: Entry? = self._entries[id]
	if e == nil or e.charges > 0 then
		return 0
	end
	return e.rechargeAt
end

-- Charges ready at `now` and the most there can be (an unknown fighter has `defaultMax`).
function SlideBook.charges(
	self: any,
	id: string,
	now: number,
	defaultMax: number?
): (number, number)
	local e: Entry? = self._entries[id]
	if e == nil then
		local m = defaultMax or 1
		return m, m
	end
	refresh(e, now)
	return e.charges, e.max
end

function SlideBook.isActive(self: any, id: string, now: number): boolean
	local e: Entry? = self._entries[id]
	return e ~= nil and now < e.activeUntil
end

function SlideBook.isReady(self: any, id: string, now: number): boolean
	local e: Entry? = self._entries[id]
	if e == nil then
		return true
	end
	refresh(e, now)
	return e.charges > 0 and now >= e.activeUntil
end

-- Why a slide may not start now, or nil when it may. Does not change anything the fighter can see.
function SlideBook.check(
	self: any,
	id: string,
	now: number,
	alive: boolean,
	gateOpen: boolean
): string?
	local e: Entry? = self._entries[id]
	if e ~= nil then
		refresh(e, now)
	end
	return SlideRules.blockedReason({
		now = now,
		readyAt = if e ~= nil and e.charges <= 0 then e.rechargeAt else 0,
		activeUntil = if e then e.activeUntil else 0,
		alive = alive,
		gateOpen = gateOpen,
	})
end

-- Uses a charge and opens the slide window. Returns the token for this slide. `maxCharges` (default 1)
-- is how many a fighter holds when full; each takes `cooldown` seconds to come back, one at a time.
function SlideBook.commit(
	self: any,
	id: string,
	now: number,
	duration: number,
	cooldown: number,
	maxCharges: number?
): number
	self._nextToken += 1
	local max = math.max(1, math.floor(maxCharges or 1))
	local e: Entry? = self._entries[id]
	if e == nil or e.max ~= max then
		e = {
			charges = max,
			max = max,
			rechargeAt = now,
			cooldown = cooldown,
			activeUntil = 0,
			token = 0,
		}
	end
	local entry = e :: Entry
	entry.cooldown = cooldown
	refresh(entry, now)
	if entry.charges >= entry.max then
		entry.rechargeAt = now + cooldown -- the clock starts when the bag stops being full
	end
	entry.charges = math.max(0, entry.charges - 1)
	entry.activeUntil = now + duration
	entry.token = self._nextToken
	self._entries[id] = entry
	return self._nextToken
end

function SlideBook.isCurrent(self: any, id: string, token: number): boolean
	local e: Entry? = self._entries[id]
	return e ~= nil and e.token == token
end

-- The slide stops now (death, reset). The cooldown stays, so dying cannot refresh it.
function SlideBook.cancel(self: any, id: string, now: number)
	local e: Entry? = self._entries[id]
	if e then
		e.activeUntil = now
		self._nextToken += 1
		e.token = self._nextToken
	end
end

-- Forget one participant (leaves, new character).
function SlideBook.reset(self: any, id: string)
	self._entries[id] = nil
end

-- Forget everyone (new match, reset).
function SlideBook.clear(self: any)
	self._entries = {}
end

return SlideBook
