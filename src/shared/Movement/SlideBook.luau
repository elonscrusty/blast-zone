--!strict
-- Slide bookkeeping per participant: cooldown, whether a slide is running, and a token that tells
-- a delayed check whether it still belongs to the slide it was made for. Plain numbers (the clock
-- is passed in) so Lune can test it. Server only.

local SlideRules = require("./SlideRules")

type Entry = { readyAt: number, activeUntil: number, token: number }

local SlideBook = {}
SlideBook.__index = SlideBook

function SlideBook.new(): any
	return setmetatable({ _entries = {} :: { [string]: Entry }, _nextToken = 0 }, SlideBook)
end

function SlideBook.readyAt(self: any, id: string): number
	local e: Entry? = self._entries[id]
	return if e then e.readyAt else 0
end

function SlideBook.isActive(self: any, id: string, now: number): boolean
	local e: Entry? = self._entries[id]
	return e ~= nil and now < e.activeUntil
end

function SlideBook.isReady(self: any, id: string, now: number): boolean
	local e: Entry? = self._entries[id]
	return e == nil or (now >= e.readyAt and now >= e.activeUntil)
end

-- Why a slide may not start now, or nil when it may. Does not change anything.
function SlideBook.check(
	self: any,
	id: string,
	now: number,
	alive: boolean,
	gateOpen: boolean
): string?
	local e: Entry? = self._entries[id]
	return SlideRules.blockedReason({
		now = now,
		readyAt = if e then e.readyAt else 0,
		activeUntil = if e then e.activeUntil else 0,
		alive = alive,
		gateOpen = gateOpen,
	})
end

-- Starts the cooldown and the slide window. Returns the token for this slide.
function SlideBook.commit(
	self: any,
	id: string,
	now: number,
	duration: number,
	cooldown: number
): number
	self._nextToken += 1
	self._entries[id] = {
		readyAt = now + cooldown,
		activeUntil = now + duration,
		token = self._nextToken,
	}
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
