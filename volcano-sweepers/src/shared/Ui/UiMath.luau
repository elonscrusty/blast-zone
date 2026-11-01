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
	menuCount: number, -- how many menu buttons
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
	offline: Rect,
	menu: Rect,
	menuCols: number,
	menuRows: number,
	menuScroll: boolean, -- true when the buttons do not all fit and the menu scrolls
	sweep: Rect,
	sell: Rect,
	auto: Rect,
	jump: Rect, -- area the default Roblox jump button may use (not ours; kept clear)
}

-- Sizes in virtual px. Everything touchable is >= touch (44).
UiMath.K = {
	touch = 44,
	margin = 8,
	topPad = 4, -- under the top bar inset
	stackGap = 4,
	coinsW = 148,
	coinsH = 34,
	packH = 24,
	cleanH = 38,
	chipH = 26,
	bannerH = 44,
	toastH = 32,
	toastGap = 4,
	toastCap = 3,
	offlineH = 20,
	offlineW = 170,
	sweepSize = 84,
	sellSize = 76,
	autoH = 44,
	bottomPad = 12,
	jumpReserve = 100,
	menuGap = 4,
	menuPad = 2, -- padding inside the menu's scrolling frame so strokes are not clipped
	centerMaxW = 300,
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
-- (0 = never). The server still decides; this only lights the dot.
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

-- Every HUD rectangle for a virtual screen of vw x vh. See the comments for the two modes.
function UiMath.layout(vw: number, vh: number, opts: LayoutOpts): Layout
	local k = UiMath.K
	local m = k.margin
	local top = opts.top + k.topPad
	local wide = vw >= vh
	local count = math.max(0, math.floor(opts.menuCount))

	-- Left stack: coins, then the backpack bar.
	local coins = rect(m, top, k.coinsW, k.coinsH)
	local pack = rect(m, coins.y + coins.h + k.stackGap, k.coinsW, k.packH)

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

	-- Left menu column under the backpack bar: 1, 2 or 3 columns, scrolls only if still too tight.
	local menuY = pack.y + pack.h + 6
	local avail = vh - m - menuY - (if wide then 0 else k.offlineH + m)
	local pad = k.menuPad
	local cols, rows, scroll = 1, count, false
	if count > 0 then
		local fitted = false
		for c = 1, 3 do
			local r = math.ceil(count / c)
			if r * k.touch + (r - 1) * k.menuGap + 2 * pad <= avail then
				cols, rows, fitted = c, r, true
				break
			end
		end
		if not fitted then
			cols = if wide then 2 else 1
			rows = math.ceil(count / cols)
			scroll = true
		end
	end
	local menuW = if count > 0 then cols * k.touch + (cols - 1) * k.menuGap + 2 * pad else 0
	local menuH = if count > 0
		then (if scroll
			then math.max(avail, k.touch)
			else rows * k.touch + (rows - 1) * k.menuGap + 2 * pad)
		else 0
	local menu = rect(m - pad, menuY, menuW, menuH)
	local menuRight = if count > 0 then menu.x + menu.w else m

	local clean: Rect, buffs: Rect, banner: Rect, offline: Rect
	if wide then
		-- Centre column between the left stack/menu and the SWEEP column.
		local leftLimit = math.max(coins.x + coins.w, menuRight) + m
		local rightLimit = sweep.x - m
		local colW = math.max(120, math.min(k.centerMaxW, rightLimit - leftLimit))
		local colX =
			math.clamp(vw / 2 - colW / 2, leftLimit, math.max(leftLimit, rightLimit - colW))
		clean = rect(colX, top, colW, k.cleanH)
		buffs = rect(colX, clean.y + clean.h + 4, colW, k.chipH)
		banner = rect(colX, buffs.y + buffs.h + 4, colW, k.bannerH)
		offline = rect(
			leftLimit,
			vh - m - k.offlineH,
			math.max(100, math.min(k.offlineW, sell.x - m - leftLimit)),
			k.offlineH
		)
	else
		-- Portrait: clean bar + buff chips sit right of the left stack; banner/toasts use the
		-- full width right of the menu column.
		local cx = coins.x + coins.w + m
		clean = rect(cx, top, vw - cx - m, k.cleanH)
		buffs = rect(cx, clean.y + clean.h + 4, clean.w, k.chipH)
		local colX = menuRight + m
		local bannerY = math.max(pack.y + pack.h, buffs.y + buffs.h) + 6
		banner = rect(colX, bannerY, vw - colX - m, k.bannerH)
		offline = rect(
			m,
			vh - m - k.offlineH,
			math.max(100, math.min(k.offlineW, sweep.x - 2 * m)),
			k.offlineH
		)
	end
	local toastTop = banner.y + banner.h + 4
	local toastBottom = sell.y - m
	local fit = math.floor((toastBottom - toastTop + k.toastGap) / (k.toastH + k.toastGap))
	local toastMax = math.clamp(fit, 0, k.toastCap)
	local toasts = rect(
		banner.x,
		toastTop,
		banner.w,
		if toastMax > 0 then toastMax * k.toastH + (toastMax - 1) * k.toastGap else 0
	)

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
		menuCols = cols,
		menuRows = rows,
		menuScroll = scroll,
		sweep = sweep,
		sell = sell,
		auto = auto,
		jump = jump,
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
