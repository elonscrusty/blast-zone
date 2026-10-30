--!strict
-- One banner on screen at a time (carter: the first HUD was "way too cluttered"). Pure: the clock is
-- passed in. A stronger banner takes the screen at once, a weaker one waits in a short line, and a
-- banner that waited too long is dropped because it is old news.

local MomentRules = require("./MomentRules")

export type Config = {
	bannerSeconds: number,
	minGapSeconds: number,
	queueMax: number,
	staleSeconds: number,
}

type Waiting = { banner: MomentRules.Banner, at: number }

export type Queue = {
	cfg: Config,
	current: MomentRules.Banner?,
	startedAt: number,
	endsAt: number,
	nextAllowedAt: number, -- the quiet gap after the last banner
	waiting: { Waiting },
	fresh: boolean, -- a new banner just took the screen and the view has not heard yet
	seen: { [string]: number }, -- key -> when it was last shown or queued
}

local BannerQueue = {}

function BannerQueue.new(cfg: Config): Queue
	return {
		cfg = cfg,
		current = nil,
		startedAt = 0,
		endsAt = 0,
		nextAllowedAt = 0,
		waiting = {},
		fresh = false,
		seen = {},
	}
end

local function show(q: Queue, banner: MomentRules.Banner, now: number)
	q.current = banner
	q.startedAt = now
	q.endsAt = now + q.cfg.bannerSeconds
	q.fresh = true
end

-- Same news within one banner length is not shown twice.
local function isRepeat(q: Queue, key: string, now: number): boolean
	local at = q.seen[key]
	return at ~= nil and now - at < q.cfg.bannerSeconds + q.cfg.staleSeconds
end

local function trimWaiting(q: Queue)
	while #q.waiting > q.cfg.queueMax do
		-- drop the weakest, oldest first
		local worst = 1
		for i, w in q.waiting do
			local best = q.waiting[worst]
			if
				w.banner.priority < best.banner.priority
				or (w.banner.priority == best.banner.priority and w.at < best.at)
			then
				worst = i
			end
		end
		table.remove(q.waiting, worst)
	end
end

function BannerQueue.push(q: Queue, banner: MomentRules.Banner, now: number)
	if isRepeat(q, banner.key, now) then
		return
	end
	q.seen[banner.key] = now
	local current = q.current
	if current == nil then
		if now >= q.nextAllowedAt then
			show(q, banner, now)
			return
		end
	elseif banner.priority > current.priority then
		-- the stronger news takes the screen; what it pushed off is not shown again
		show(q, banner, now)
		return
	end
	table.insert(q.waiting, { banner = banner, at = now })
	trimWaiting(q)
end

-- Moves time forward. Returns the banner on screen (or nil) and whether it is a new one.
function BannerQueue.update(q: Queue, now: number): (MomentRules.Banner?, boolean)
	if q.current ~= nil and now >= q.endsAt then
		q.current = nil
		q.nextAllowedAt = q.endsAt + q.cfg.minGapSeconds
	end
	-- forget stale waiters
	for i = #q.waiting, 1, -1 do
		if now - q.waiting[i].at > q.cfg.staleSeconds then
			table.remove(q.waiting, i)
		end
	end
	if q.current == nil and now >= q.nextAllowedAt and #q.waiting > 0 then
		local best = 1
		for i, w in q.waiting do
			local b = q.waiting[best]
			if
				w.banner.priority > b.banner.priority
				or (w.banner.priority == b.banner.priority and w.at < b.at)
			then
				best = i
			end
		end
		local picked = table.remove(q.waiting, best) :: Waiting
		show(q, picked.banner, now)
	end
	local fresh = q.fresh
	q.fresh = false
	-- keep the memory of keys small
	for key, at in q.seen do
		if now - at > q.cfg.bannerSeconds + q.cfg.staleSeconds then
			q.seen[key] = nil
		end
	end
	return q.current, fresh
end

-- 0 at the start of the banner, 1 at its end (for slide-in and fade-out in the view).
function BannerQueue.progress(q: Queue, now: number): number
	if q.current == nil then
		return 1
	end
	local span = q.endsAt - q.startedAt
	if span <= 0 then
		return 1
	end
	return math.clamp((now - q.startedAt) / span, 0, 1)
end

function BannerQueue.clear(q: Queue)
	q.current = nil
	q.waiting = {}
	q.fresh = false
	q.seen = {}
	q.nextAllowedAt = 0
end

return BannerQueue
