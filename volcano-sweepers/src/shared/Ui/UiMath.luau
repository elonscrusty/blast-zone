--!strict
-- Pure UI maths: scale from screen size, the HUD layout rectangles, bar fill, count-up easing,
-- zone-from-position, banner text. Everything is in "virtual pixels": the size the UI is drawn at
-- BEFORE the UIScale is applied. The client builds one root frame of virtual size and one UIScale
-- (see client/Ui/Components.screen), so layout code never thinks about real screen sizes.
--
-- Layout is computed here (not inside Roblox glue) so tests can prove nothing overlaps on a
-- phone in landscape, a phone in portrait, a tablet and a PC.

local UiMath = {}

export type Rect = { x: number, y: number, w: number, h: number }

export type LayoutOpts = {
	top: number, -- virtual px reserved at the top for the Roblox top bar
	touch: boolean, -- true on touch devices (leave room for the default jump button)
	offline: boolean?, -- true when the "Guest mode" badge shows (only then is room kept for it)
	menuCount: number?, -- ignored (kept so old callers still work): the menu is ONE launcher button
}

export type Layout = {
	mode: string, -- "wide" (landscape / desktop) or "tall" (portrait)
	coins: Rect,
	pack: Rect,
	clean: Rect,
	buffs: Rect,
	banner: Rect,
	toasts: Rect, -- h = 0 when there is no room at all
	toastMax: number, -- how many toasts fit (0..3)
	offline: Rect, -- w = 0 unless opts.offline
	menu: Rect, -- the ONE menu launcher button (opens the big tile menu)
	sweep: Rect,
	sell: Rect,
	auto: Rect,
	jump: Rect, -- area the default Roblox jump button may use (not ours; kept clear)
	play: Rect, -- where the character and the ground at its feet are (no opaque HUD here)
}

-- Sizes in virtual px. Everything touchable is >= touch (44); main buttons use `button` (48).
UiMath.K = {
	touch = 44,
	button = 48, -- every main action button (BUY, CLAIM, AUTO, the MENU launcher)
	closeButton = 48,
	claimW = 104, -- width of the small price / claim buttons on cards
	titleBar = 54,
	titleBarShort = 44, -- panels shorter than `shortPanel` get the slimmer title bar
	shortPanel = 340,
	margin = 8,
	topPad = 4, -- under the top bar inset
	stackGap = 4,
	coinsW = 148,
	coinsH = 34,
	packH = 24,
	cleanH = 38,
	chipH = 26,
	chipMinW = 64, -- a chip never gets narrower than this (icon + "4:59" at 11 px)
	chipMaxW = 108,
	chipGap = 4,
	chipIconW = 28, -- left part of a chip taken by the emoji
	chipPadR = 6,
	bannerH = 44,
	toastH = 36, -- room for two short lines
	toastGap = 4,
	toastCap = 3,
	toastW = 260, -- widest a toast gets
	toastMinW = 170, -- narrower than this and toasts go under the banner instead
	offlineH = 20,
	offlineW = 170,
	sweepSize = 84,
	sellSize = 76,
	autoH = 48,
	bottomPad = 12,
	jumpReserve = 100,
	menuSize = 48,
	centerMaxW = 300,
	textMin = 11, -- the smallest any text may shrink to (at UI scale 1)
}

local MIN_SCALE = 1.0
local MAX_SCALE = 1.5
local REF = 360 -- the shorter side of a normal phone, in px: scale 1 there

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

function UiMath.scaleFor(width: number, height: number): number
	if width ~= width or height ~= height or width <= 0 or height <= 0 then
		return 1
	end
	return math.clamp(math.min(width, height) / REF, MIN_SCALE, MAX_SCALE)
end

function UiMath.clamp01(v: number): number
	if v ~= v then
		return 0
	end
	return math.clamp(v, 0, 1)
end

-- Fill share (0..1) for a progress bar. Anything weird becomes 0.
function UiMath.barFill(fraction: number): number
	return UiMath.clamp01(fraction)
end

-- Smooth count-up: move `current` toward `target`. rate ~ 6 means 90% of the way in ~0.4 s.
-- Snaps when within half a unit (or 0.2% of a big target) so the shown number lands exactly
-- on the target and a huge jump still finishes in about a second.
function UiMath.approach(current: number, target: number, dt: number, rate: number): number
	if current ~= current or target ~= target then
		return 0
	end
	if dt <= 0 then
		return current
	end
	local k = 1 - math.exp(-math.max(0, rate) * dt)
	local nextValue = current + (target - current) * k
	if math.abs(target - nextValue) < math.max(0.5, math.abs(target) * 0.002) then
		return target
	end
	return nextValue
end

-- Width of each buff chip when `count` chips share `total` px.
function UiMath.chipWidth(total: number, count: number, maxW: number, gap: number): number
	if count <= 0 then
		return maxW
	end
	local each = (total - gap * (count - 1)) / count
	return math.max(0, math.min(maxW, math.floor(each)))
end

-- Rough width (virtual px) of one line of bold game text: about 0.62 x size per character.
-- Counts characters, not bytes, so "4:59" and "✨" are measured the same way the eye sees them.
function UiMath.textWidth(text: string, size: number): number
	local ok, n = pcall(utf8.len, text)
	local chars = if ok and type(n) == "number" then n else #text
	return chars * size * 0.62
end

export type ChipPlan = {
	count: number, -- chips shown (the rest wait their turn; never more than fit)
	w: number, -- width of each chip
	labelW: number, -- room for the text inside a chip (after the emoji)
	full: boolean, -- true: "x2 4:59", false: just "4:59"
	textSize: number, -- the size the text fits at
}

-- How buff chips share a row `total` px wide. Chips never shrink under K.chipMinW; when even
-- that is too tight the extra chips are left out (the longest-running ones show first anyway).
-- A chip shows its word ("x2") only when that still fits at a readable size.
function UiMath.chipPlan(total: number, count: number, sample: string, timeSample: string): ChipPlan
	local k = UiMath.K
	local n = math.max(0, math.floor(count))
	local fitCount = math.max(1, math.floor((total + k.chipGap) / (k.chipMinW + k.chipGap)))
	n = math.min(n, fitCount)
	local w = if n > 0 then UiMath.chipWidth(total, n, k.chipMaxW, k.chipGap) else k.chipMaxW
	local labelW = w - k.chipIconW - k.chipPadR
	local full = false
	local size = k.textMin
	for _, s in { 14, 13, 12 } do
		if UiMath.textWidth(sample, s) <= labelW then
			full, size = true, s
			break
		end
	end
	if not full then
		for _, s in { 14, 13, 12, 11 } do
			if UiMath.textWidth(timeSample, s) <= labelW then
				size = s
				break
			end
		end
	end
	return { count = n, w = w, labelW = labelW, full = full, textSize = size }
end

-- Title bar height for a panel of this height (slimmer on short landscape phones).
function UiMath.titleBarFor(panelH: number): number
	local k = UiMath.K
	return if panelH < k.shortPanel then k.titleBarShort else k.titleBar
end

-- Which zone id (1..5) a ground position belongs to, from the ring radii in Config.World.zones.
-- Past the beach's outer edge counts as zone 1; inside the volcano ring counts as the last zone.
function UiMath.zoneAt(
	x: number,
	z: number,
	zones: { { id: number, outer: number, inner: number } }
): number
	local r = math.sqrt(x * x + z * z)
	if r ~= r then
		return 1
	end
	local last = 1
	for _, zone in zones do
		if r <= zone.outer and r > zone.inner then
			return zone.id
		end
		last = zone.id
	end
	if #zones > 0 and r > zones[1].outer then
		return zones[1].id
	end
	return last
end

-- True when (x, z) is within `range` studs (flat distance) of any point.
function UiMath.nearAny(
	points: { { x: number, z: number } },
	x: number,
	z: number,
	range: number
): boolean
	for _, p in points do
		local dx, dz = p.x - x, p.z - z
		if dx * dx + dz * dz <= range * range then
			return true
		end
	end
	return false
end

-- Can the daily reward be claimed? lastDay = whole UTC days since epoch of the last claim
-- (0 = never). The server still decides; this only lights the dot. Pass SERVER time
-- (workspace:GetServerTimeNow()), never the device clock.
function UiMath.dailyReady(lastDay: number, nowUnix: number): boolean
	if nowUnix ~= nowUnix then
		return false
	end
	return math.floor(nowUnix / 86400) > lastDay
end

function UiMath.secondsLeft(endsAt: number, now: number): number
	local left = endsAt - now
	if left ~= left or left < 0 then
		return 0
	end
	return left
end

-- ===== Burp banner =====
export type BannerSpec = {
	text: string,
	tone: string, -- "rumble" | "pops" | "ash" | "gold" | "gems"
	fraction: number, -- 1 -> 0 as the phase runs out (timer bar)
	secondsLeft: number, -- whole seconds, for the big number
	showCount: boolean, -- show the number (rumble countdown)
}

local EVENT_TEXT: { [string]: { string } } = {
	pops = { "DODGE THE LAVA!", "pops" },
	ashStorm = { "ASH STORM — sweep more!", "ash" },
	golden = { "GOLDEN BURP — grab the gold!", "gold" },
	geysers = { "GEYSERS — grab the gems!", "gems" },
}

-- What the banner should say for a BurpInfo, or nil when it should be hidden (calm / recover).
function UiMath.banner(
	info: { phase: string, kind: string?, startsAt: number, endsAt: number },
	now: number
): BannerSpec?
	local phase = info.phase
	if phase ~= "rumble" and phase ~= "event" then
		return nil
	end
	local total = math.max(0.001, info.endsAt - info.startsAt)
	local left = UiMath.secondsLeft(info.endsAt, now)
	local fraction = UiMath.clamp01(left / total)
	local whole = math.ceil(left - 1e-9)
	if phase == "rumble" then
		return {
			text = "RUMBLE! Get ready!",
			tone = "rumble",
			fraction = fraction,
			secondsLeft = math.max(0, whole),
			showCount = true,
		}
	end
	local entry = if info.kind then EVENT_TEXT[info.kind] else nil
	return {
		text = if entry then entry[1] else "VOLCANO BURP!",
		tone = if entry then entry[2] else "rumble",
		fraction = fraction,
		secondsLeft = math.max(0, whole),
		showCount = false,
	}
end

-- ===== Rectangles =====
function UiMath.intersects(a: Rect, b: Rect): boolean
	if a.w <= 0 or a.h <= 0 or b.w <= 0 or b.h <= 0 then
		return false
	end
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Where the character and the ground at its feet usually are on screen. The default camera looks
-- at the head, so the body, its feet and any lava target circles sit in the middle of the lower
-- half. Nothing opaque from the HUD may sit here (toasts, banner).
function UiMath.playRect(vw: number, vh: number): Rect
	local halfW = math.max(60, vw * 0.15)
	return rect(vw / 2 - halfW, vh * 0.5, 2 * halfW, vh * 0.35)
end

-- Every HUD rectangle for a virtual screen of vw x vh.
--   Left:   coins, backpack bar, then ONE 48 px MENU button (it opens the tile menu). The rest of
--           the left side stays empty for the movement thumbstick.
--   Right:  SWEEP (thumb), AUTO above it, SELL beside it (landscape) or above AUTO (portrait).
--   Top:    clean bar, buff chips and the volcano banner (landscape: a centre column; portrait:
--           right of the coins, then full width).
--   Toasts: landscape: the empty top-right corner; portrait: under the banner. Never over the
--           character (playRect) and never over the thumb buttons.
function UiMath.layout(vw: number, vh: number, opts: LayoutOpts): Layout
	local k = UiMath.K
	local m = k.margin
	local top = opts.top + k.topPad
	local wide = vw >= vh
	local showOffline = opts.offline == true

	-- Left stack: coins, the backpack bar, the menu launcher.
	local coins = rect(m, top, k.coinsW, k.coinsH)
	local pack = rect(m, coins.y + coins.h + k.stackGap, k.coinsW, k.packH)
	local menu = rect(m, pack.y + pack.h + 6, k.menuSize, k.menuSize)

	-- Bottom right: SWEEP (the thumb button) next to where Roblox puts its jump button.
	local rightEdge = vw - (if opts.touch then k.jumpReserve + 8 else m)
	local sweep =
		rect(rightEdge - k.sweepSize, vh - k.bottomPad - k.sweepSize, k.sweepSize, k.sweepSize)
	local auto = rect(sweep.x, sweep.y - 6 - k.autoH, k.sweepSize, k.autoH)
	local sell: Rect
	if wide then
		sell =
			rect(sweep.x - 10 - k.sellSize, vh - k.bottomPad - k.sellSize, k.sellSize, k.sellSize)
	else
		sell = rect(sweep.x + sweep.w - k.sellSize, auto.y - 6 - k.sellSize, k.sellSize, k.sellSize)
	end
	local jump = if opts.touch
		then rect(vw - k.jumpReserve, vh - k.jumpReserve, k.jumpReserve, k.jumpReserve)
		else rect(vw, vh, 0, 0)
	local play = UiMath.playRect(vw, vh)

	local function stack(
		x: number,
		y: number,
		w: number,
		bottom: number,
		cap: number
	): (Rect, number)
		local fit = math.floor((bottom - y + k.toastGap) / (k.toastH + k.toastGap))
		local count = math.clamp(fit, 0, cap)
		local h = if count > 0 then count * k.toastH + (count - 1) * k.toastGap else 0
		return rect(x, y, w, h), count
	end

	local clean: Rect, buffs: Rect, banner: Rect, offline: Rect, toasts: Rect
	local toastMax = 0
	if wide then
		-- Centre column between the left stack and the SWEEP column.
		local leftLimit = coins.x + coins.w + m
		local rightLimit = sweep.x - m
		local colW = math.max(120, math.min(k.centerMaxW, rightLimit - leftLimit))
		local colX =
			math.clamp(vw / 2 - colW / 2, leftLimit, math.max(leftLimit, rightLimit - colW))
		clean = rect(colX, top, colW, k.cleanH)
		buffs = rect(colX, clean.y + clean.h + 4, colW, k.chipH)
		banner = rect(colX, buffs.y + buffs.h + 4, colW, k.bannerH)
		offline = if showOffline
			then rect(
				leftLimit,
				vh - m - k.offlineH,
				math.max(100, math.min(k.offlineW, sell.x - m - leftLimit)),
				k.offlineH
			)
			else rect(leftLimit, vh - m - k.offlineH, 0, 0)
		-- toasts: the top-right corner, right of the centre column and above AUTO
		local rx = clean.x + clean.w + m
		local rw = (vw - m) - rx
		if rw >= k.toastMinW then
			local w = math.min(k.toastW, rw)
			toasts, toastMax = stack(vw - m - w, top, w, auto.y - m, k.toastCap)
		else
			toasts, toastMax =
				stack(banner.x, banner.y + banner.h + 4, banner.w, math.min(sell.y, play.y) - 4, 2)
		end
	else
		-- Portrait: clean bar right of the coins; buff chips right of the menu button; the banner
		-- and the toasts use the full width under them.
		local cx = coins.x + coins.w + m
		clean = rect(cx, top, vw - cx - m, k.cleanH)
		local chipX = menu.x + menu.w + m
		buffs = rect(chipX, menu.y + (menu.h - k.chipH) / 2, vw - chipX - m, k.chipH)
		banner = rect(m, menu.y + menu.h + 6, vw - 2 * m, k.bannerH)
		offline = if showOffline
			then rect(
				m,
				vh - m - k.offlineH,
				math.max(100, math.min(k.offlineW, sweep.x - 2 * m)),
				k.offlineH
			)
			else rect(m, vh - m - k.offlineH, 0, 0)
		toasts, toastMax = stack(
			banner.x,
			banner.y + banner.h + 4,
			banner.w,
			math.min(sell.y - m, play.y - 4),
			k.toastCap
		)
	end

	return {
		mode = if wide then "wide" else "tall",
		coins = coins,
		pack = pack,
		clean = clean,
		buffs = buffs,
		banner = banner,
		toasts = toasts,
		toastMax = toastMax,
		offline = offline,
		menu = menu,
		sweep = sweep,
		sell = sell,
		auto = auto,
		jump = jump,
		play = play,
	}
end

-- Where a modal panel sits: centred under the top bar, with a margin all round.
function UiMath.panelRect(vw: number, vh: number, top: number): Rect
	local margin = 12
	local wide = vw >= vh
	local w = math.min(vw - 2 * margin, if wide then 680 else 520)
	local availH = vh - top - margin
	local h = math.min(availH - margin, if wide then 520 else 700)
	h = math.max(h, 120)
	return rect((vw - w) / 2, top + margin + (availH - margin - h) / 2, w, h)
end

return UiMath
