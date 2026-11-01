--!strict
local Harness = require("./harness")
local UiMath = require("../src/shared/Ui/UiMath")
local Config = require("../src/shared/Config")

Harness.test("UiMath.scaleFor: 1 on phones, grows on big screens, clamped", function()
	Harness.eq(UiMath.scaleFor(800, 360), 1)
	Harness.eq(UiMath.scaleFor(360, 740), 1)
	Harness.eq(UiMath.scaleFor(844, 390) >= 1, true)
	Harness.eq(UiMath.scaleFor(1920, 1080), 1.5)
	Harness.eq(UiMath.scaleFor(1024, 768), 1.5)
	Harness.eq(UiMath.scaleFor(568, 320), 1) -- never below 1: touch targets stay >= 44 px
	Harness.eq(UiMath.scaleFor(0, 0), 1)
	Harness.eq(UiMath.scaleFor(0 / 0, 100), 1)
end)

Harness.test("UiMath.scaleFor: virtual short side stays >= 320 for real screens", function()
	for w = 320, 3000, 40 do
		for h = 320, 2000, 60 do
			local s = UiMath.scaleFor(w, h)
			Harness.truthy(s >= 1 and s <= 1.5, "scale range")
			Harness.truthy(math.min(w, h) / s >= 320 - 1e-6, `virtual too small at {w}x{h}`)
		end
	end
end)

Harness.test("UiMath.barFill clamps", function()
	Harness.eq(UiMath.barFill(-1), 0)
	Harness.eq(UiMath.barFill(0.4), 0.4)
	Harness.eq(UiMath.barFill(3), 1)
	Harness.eq(UiMath.barFill(0 / 0), 0)
end)

Harness.test("UiMath.approach counts up, never overshoots, lands exactly", function()
	local v = 0
	local target = 1000
	local last = -1
	for _ = 1, 600 do
		v = UiMath.approach(v, target, 1 / 60, 6)
		Harness.truthy(v >= last and v <= target, "monotonic, no overshoot")
		last = v
	end
	Harness.eq(v, target)
	-- counting down works too
	local d = 500
	for _ = 1, 600 do
		d = UiMath.approach(d, 10, 1 / 60, 6)
	end
	Harness.eq(d, 10)
	Harness.eq(UiMath.approach(5, 9, 0, 6), 5)
	Harness.eq(UiMath.approach(0 / 0, 9, 0.1, 6), 0)
end)

Harness.test("UiMath.approach finishes within about a second", function()
	local v = 0
	local frames = 0
	while v ~= 100000 and frames < 1000 do
		v = UiMath.approach(v, 100000, 1 / 60, 6)
		frames += 1
	end
	Harness.truthy(frames < 120, `took {frames} frames`)
end)

Harness.test("UiMath.chipWidth", function()
	Harness.eq(UiMath.chipWidth(200, 2, 96, 4), 96)
	Harness.eq(UiMath.chipWidth(148, 2, 96, 4), 72)
	Harness.eq(UiMath.chipWidth(148, 3, 96, 4), 46)
	Harness.eq(UiMath.chipWidth(100, 0, 96, 4), 96)
end)

Harness.test("UiMath.zoneAt follows the rings", function()
	local zones = Config.World.zones
	Harness.eq(UiMath.zoneAt(0, 222, zones), 1) -- the hub on the beach
	Harness.eq(UiMath.zoneAt(0, 300, zones), 1) -- beyond the beach edge
	Harness.eq(UiMath.zoneAt(160, 0, zones), 2)
	Harness.eq(UiMath.zoneAt(0, -120, zones), 3)
	Harness.eq(UiMath.zoneAt(80, 0, zones), 4)
	Harness.eq(UiMath.zoneAt(45, 0, zones), 5)
	Harness.eq(UiMath.zoneAt(0, 0, zones), 5) -- inside the volcano
	Harness.eq(UiMath.zoneAt(0 / 0, 0, zones), 1)
end)

Harness.test("UiMath.nearAny", function()
	local pads = { { x = 0, z = 222 }, { x = 30, z = 222 } }
	Harness.eq(UiMath.nearAny(pads, 5, 215, 16), true)
	Harness.eq(UiMath.nearAny(pads, 0, 100, 16), false)
	Harness.eq(UiMath.nearAny({}, 0, 0, 16), false)
	Harness.eq(UiMath.nearAny(pads, 0, 238, 16), true) -- exactly on the edge
end)

Harness.test("UiMath.dailyReady uses UTC days", function()
	local day = 20000
	local noon = day * 86400 + 43200
	Harness.eq(UiMath.dailyReady(0, noon), true)
	Harness.eq(UiMath.dailyReady(day, noon), false)
	Harness.eq(UiMath.dailyReady(day - 1, noon), true)
	Harness.eq(UiMath.dailyReady(day, (day + 1) * 86400), true) -- next midnight
	Harness.eq(UiMath.dailyReady(day, (day + 1) * 86400 - 1), false)
end)

Harness.test("UiMath.banner text per phase and kind", function()
	local function info(phase: string, kind: string?)
		return { phase = phase, kind = kind, startsAt = 100, endsAt = 110 }
	end
	Harness.eq(UiMath.banner(info("calm", nil), 100), nil)
	Harness.eq(UiMath.banner(info("recover", "pops"), 105), nil)
	local r = UiMath.banner(info("rumble", "pops"), 104)
	Harness.truthy(r ~= nil)
	if r then
		Harness.eq(r.text, "RUMBLE! Get ready!")
		Harness.eq(r.showCount, true)
		Harness.eq(r.secondsLeft, 6)
		Harness.near(r.fraction, 0.6)
	end
	local pops = UiMath.banner(info("event", "pops"), 100)
	Harness.eq(pops and pops.text, "DODGE THE LAVA!")
	Harness.eq(pops and pops.tone, "pops")
	Harness.eq(pops and pops.showCount, false)
	Harness.eq(
		(UiMath.banner(info("event", "ashStorm"), 100) :: any).text,
		"ASH STORM — sweep more!"
	)
	Harness.eq(
		(UiMath.banner(info("event", "golden"), 100) :: any).text,
		"GOLDEN BURP — grab the gold!"
	)
	Harness.eq(
		(UiMath.banner(info("event", "geysers"), 100) :: any).text,
		"GEYSERS — grab the gems!"
	)
	Harness.eq((UiMath.banner(info("event", "nope"), 100) :: any).text, "VOLCANO BURP!")
	-- a late event never goes negative
	local late = UiMath.banner(info("event", "pops"), 130)
	Harness.eq(late and late.fraction, 0)
	Harness.eq(late and late.secondsLeft, 0)
end)

-- ===== layout =====
local VIEWPORTS = {
	{ name = "phone landscape 800x360", w = 800, h = 360, touch = true },
	{ name = "phone landscape 844x390", w = 844, h = 390, touch = true },
	{ name = "phone landscape 640x360", w = 640, h = 360, touch = true },
	{ name = "small phone landscape 568x320", w = 568, h = 320, touch = true },
	{ name = "phone portrait 360x740", w = 360, h = 740, touch = true },
	{ name = "phone portrait 390x844", w = 390, h = 844, touch = true },
	{ name = "small phone portrait 320x568", w = 320, h = 568, touch = true },
	{ name = "tablet 1024x768", w = 1024, h = 768, touch = true },
	{ name = "PC 1920x1080", w = 1920, h = 1080, touch = false },
}

local INSETS = { 0, 36, 58 } -- top bar height in real px (varies by device)

local function names(l: UiMath.Layout): { [string]: UiMath.Rect }
	return {
		coins = l.coins,
		pack = l.pack,
		clean = l.clean,
		buffs = l.buffs,
		banner = l.banner,
		toasts = l.toasts,
		offline = l.offline,
		menu = l.menu,
		sweep = l.sweep,
		sell = l.sell,
		auto = l.auto,
		jump = l.jump,
	}
end

Harness.test("UiMath.layout: no widget overlaps another, all inside the screen", function()
	for _, vp in VIEWPORTS do
		for _, inset in INSETS do
			local s = UiMath.scaleFor(vp.w, vp.h)
			local vw, vh = vp.w / s, vp.h / s
			local l = UiMath.layout(vw, vh, { top = inset / s, touch = vp.touch, menuCount = 9 })
			local rects = names(l)
			local keys: { string } = {}
			for key in rects do
				table.insert(keys, key)
			end
			table.sort(keys)
			for i = 1, #keys do
				local a = rects[keys[i]]
				if a.w > 0 then
					Harness.truthy(
						a.x >= 0 and a.y >= 0,
						`{vp.name} inset {inset}: {keys[i]} off the top/left`
					)
					Harness.truthy(
						a.x + a.w <= vw + 1e-6 and a.y + a.h <= vh + 1e-6,
						`{vp.name} inset {inset}: {keys[i]} off the bottom/right`
					)
					Harness.truthy(
						a.y >= inset / s or keys[i] == "jump",
						`{vp.name}: {keys[i]} under the top bar`
					)
				end
				for j = i + 1, #keys do
					local b = rects[keys[j]]
					Harness.truthy(
						not UiMath.intersects(a, b),
						`{vp.name} inset {inset}: {keys[i]} overlaps {keys[j]}`
					)
				end
			end
		end
	end
end)

Harness.test("UiMath.layout: touch targets are >= 44 real px", function()
	for _, vp in VIEWPORTS do
		local s = UiMath.scaleFor(vp.w, vp.h)
		local l =
			UiMath.layout(vp.w / s, vp.h / s, { top = 36 / s, touch = vp.touch, menuCount = 9 })
		local K = UiMath.K
		Harness.truthy(K.touch * s >= 44, `{vp.name}: menu button too small`)
		for name, r in { sweep = l.sweep, sell = l.sell, auto = l.auto } do
			Harness.truthy(math.min(r.w, r.h) * s >= 44, `{vp.name}: {name} too small`)
		end
		-- the menu really has room for 44 px buttons
		Harness.truthy(l.menu.w >= K.touch * l.menuCols, `{vp.name}: menu too narrow`)
	end
end)

Harness.test(
	"UiMath.layout: the menu fits without scrolling on every phone/tablet/PC size",
	function()
		for _, vp in VIEWPORTS do
			local s = UiMath.scaleFor(vp.w, vp.h)
			local l =
				UiMath.layout(vp.w / s, vp.h / s, { top = 36 / s, touch = vp.touch, menuCount = 9 })
			Harness.eq(l.menuScroll, false, `{vp.name} menu scrolls (cols {l.menuCols})`)
		end
	end
)

Harness.test("UiMath.layout: reference sizes pick the intended mode and columns", function()
	local l = UiMath.layout(800, 360, { top = 36, touch = true, menuCount = 9 })
	Harness.eq(l.mode, "wide")
	Harness.eq(l.menuCols, 2)
	Harness.truthy(l.toastMax >= 2, "landscape phone shows at least 2 toasts")
	local p = UiMath.layout(360, 740, { top = 36, touch = true, menuCount = 9 })
	Harness.eq(p.mode, "tall")
	Harness.eq(p.menuCols, 1)
	Harness.eq(p.toastMax, 3)
end)

Harness.test("UiMath.layout: many or few menu buttons still never overlap", function()
	for _, count in { 0, 1, 4, 9, 14, 30 } do
		for _, vp in VIEWPORTS do
			local s = UiMath.scaleFor(vp.w, vp.h)
			local l = UiMath.layout(
				vp.w / s,
				vp.h / s,
				{ top = 36 / s, touch = vp.touch, menuCount = count }
			)
			local rects = names(l)
			for an, a in rects do
				for bn, b in rects do
					if an < bn then
						Harness.truthy(
							not UiMath.intersects(a, b),
							`{vp.name} menu {count}: {an} overlaps {bn}`
						)
					end
				end
			end
		end
	end
end)

Harness.test("UiMath.panelRect stays on screen, under the top bar", function()
	for _, vp in VIEWPORTS do
		local s = UiMath.scaleFor(vp.w, vp.h)
		local vw, vh = vp.w / s, vp.h / s
		local top = 36 / s
		local r = UiMath.panelRect(vw, vh, top)
		Harness.truthy(r.x >= 0 and r.y >= top, `{vp.name}: panel under the top bar`)
		Harness.truthy(r.x + r.w <= vw and r.y + r.h <= vh, `{vp.name}: panel off screen`)
		Harness.truthy(r.w >= 280 and r.h >= 240, `{vp.name}: panel too small`)
	end
end)
