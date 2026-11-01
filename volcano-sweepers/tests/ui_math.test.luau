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

Harness.test(
	"UiMath.chipWidth splits a row evenly (the readability floor is chipPlan's job)",
	function()
		Harness.eq(UiMath.chipWidth(200, 2, 96, 4), 96)
		Harness.eq(UiMath.chipWidth(148, 2, 96, 4), 72)
		Harness.eq(UiMath.chipWidth(148, 3, 96, 4), 46)
		Harness.eq(UiMath.chipWidth(100, 0, 96, 4), 96)
	end
)

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
	Harness.eq(UiMath.dailyReady(day, 0 / 0), false)
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

local function eachLayout(fn: (
	vp: any,
	inset: number,
	offline: boolean,
	l: UiMath.Layout,
	vw: number,
	vh: number,
	s: number
) -> ())
	for _, vp in VIEWPORTS do
		for _, inset in INSETS do
			for _, offline in { false, true } do
				local s = UiMath.scaleFor(vp.w, vp.h)
				local vw, vh = vp.w / s, vp.h / s
				local l =
					UiMath.layout(vw, vh, { top = inset / s, touch = vp.touch, offline = offline })
				fn(vp, inset, offline, l, vw, vh, s)
			end
		end
	end
end

Harness.test("UiMath.layout: no widget overlaps another, all inside the screen", function()
	eachLayout(function(vp, inset, offline, l, vw, vh, s)
		local rects = names(l)
		local keys: { string } = {}
		for key in rects do
			table.insert(keys, key)
		end
		table.sort(keys)
		local tag = `{vp.name} inset {inset} offline {offline}`
		for i = 1, #keys do
			local a = rects[keys[i]]
			if a.w > 0 then
				Harness.truthy(a.x >= 0 and a.y >= 0, `{tag}: {keys[i]} off the top/left`)
				Harness.truthy(
					a.x + a.w <= vw + 1e-6 and a.y + a.h <= vh + 1e-6,
					`{tag}: {keys[i]} off the bottom/right`
				)
				Harness.truthy(
					a.y >= inset / s or keys[i] == "jump",
					`{tag}: {keys[i]} under the top bar`
				)
			end
			for j = i + 1, #keys do
				local b = rects[keys[j]]
				Harness.truthy(not UiMath.intersects(a, b), `{tag}: {keys[i]} overlaps {keys[j]}`)
			end
		end
	end)
end)

Harness.test(
	"UiMath.layout: touch targets are >= 44 real px, main buttons 48 virtual px",
	function()
		local K = UiMath.K
		for _, key in
			{ "touch", "button", "closeButton", "menuSize", "autoH", "sweepSize", "sellSize" }
		do
			Harness.truthy((K :: any)[key] >= 44, `K.{key} under 44`)
		end
		Harness.truthy(
			K.button >= 48 and K.menuSize >= 48 and K.closeButton >= 48,
			"main buttons are 48"
		)
		eachLayout(function(vp, _inset, _offline, l, _vw, _vh, s)
			for name, r in { sweep = l.sweep, sell = l.sell, auto = l.auto, menu = l.menu } do
				Harness.truthy(math.min(r.w, r.h) * s >= 44, `{vp.name}: {name} too small`)
			end
			Harness.truthy(
				l.menu.w >= K.menuSize and l.menu.h >= K.menuSize,
				`{vp.name}: menu not 48`
			)
		end)
	end
)

Harness.test("UiMath.layout: ONE menu button, high on the left, clear of the thumbstick", function()
	eachLayout(function(vp, _inset, _offline, l, _vw, vh, _s)
		-- the movement stick lives in the lower-left; the launcher stays in the top half
		-- (a 58 px notch bar on a 320 px tall phone pushes it a little lower; still the upper part)
		Harness.truthy(l.menu.y + l.menu.h <= vh * 0.56, `{vp.name}: menu reaches the thumbstick`)
		Harness.truthy(
			l.menu.x + l.menu.w <= l.pack.x + l.pack.w,
			`{vp.name}: menu wider than stack`
		)
		Harness.truthy(l.menu.y >= l.pack.y + l.pack.h, `{vp.name}: menu not under the pack`)
	end)
end)

Harness.test("UiMath.layout: toasts and the banner never cover the character", function()
	eachLayout(function(vp, inset, _offline, l, _vw, _vh, _s)
		Harness.truthy(
			not UiMath.intersects(l.toasts, l.play),
			`{vp.name} inset {inset}: toasts on the character`
		)
		if inset <= 36 then
			Harness.truthy(
				not UiMath.intersects(l.banner, l.play),
				`{vp.name} inset {inset}: banner on the character`
			)
		end
		Harness.truthy(l.toastMax >= 1, `{vp.name} inset {inset}: no room for a toast`)
		Harness.truthy(l.toastMax <= UiMath.K.toastCap, "toast cap")
	end)
end)

Harness.test("UiMath.layout: the guest badge only takes room when it shows", function()
	local off = UiMath.layout(800, 360, { top = 36, touch = true, offline = false })
	Harness.eq(off.offline.w, 0)
	local on = UiMath.layout(800, 360, { top = 36, touch = true, offline = true })
	Harness.truthy(on.offline.w >= 100, "badge has room when offline")
	local tallOff = UiMath.layout(320, 568, { top = 36, touch = true })
	Harness.eq(tallOff.offline.w, 0)
end)

Harness.test("UiMath.layout: reference sizes pick the intended mode", function()
	local l = UiMath.layout(800, 360, { top = 36, touch = true })
	Harness.eq(l.mode, "wide")
	Harness.truthy(l.toastMax >= 2, "landscape phone shows at least 2 toasts")
	-- landscape toasts live in the top-right corner, right of the centre column
	Harness.truthy(l.toasts.x >= l.clean.x + l.clean.w, "toasts beside the centre column")
	local p = UiMath.layout(360, 740, { top = 36, touch = true })
	Harness.eq(p.mode, "tall")
	Harness.truthy(p.toastMax >= 2, "portrait phone shows at least 2 toasts")
	Harness.eq(p.banner.w, 360 - 2 * UiMath.K.margin) -- portrait banner spans the screen
end)

Harness.test("UiMath.chipPlan: three buffs stay readable on every screen", function()
	local K = UiMath.K
	eachLayout(function(vp, _inset, _offline, l, _vw, _vh, _s)
		for count = 1, 3 do
			local plan = UiMath.chipPlan(l.buffs.w, count, "+10% 2:59", "2:59")
			Harness.truthy(
				plan.count >= math.min(count, 3),
				`{vp.name}: only {plan.count} of {count} chips fit`
			)
			Harness.truthy(plan.w >= K.chipMinW, `{vp.name}: chip {plan.w} px`)
			Harness.truthy(plan.labelW >= 28, `{vp.name}: chip label {plan.labelW} px`)
			Harness.truthy(plan.textSize >= K.textMin, `{vp.name}: chip text {plan.textSize} px`)
			local shown = if plan.full then "+10% 2:59" else "2:59"
			Harness.truthy(
				UiMath.textWidth(shown, plan.textSize) <= plan.labelW + 1e-6,
				`{vp.name}: "{shown}" does not fit {plan.labelW} px`
			)
			local used = plan.count * plan.w + (plan.count - 1) * K.chipGap
			Harness.truthy(used <= l.buffs.w + 1e-6, `{vp.name}: chips spill out of their row`)
		end
	end)
	-- an absurdly narrow row drops chips instead of crushing them
	local tight = UiMath.chipPlan(100, 3, "x2 4:59", "4:59")
	Harness.eq(tight.count, 1)
	Harness.truthy(tight.w >= K.chipMinW)
end)

Harness.test("UiMath.textWidth counts characters, not bytes", function()
	Harness.near(UiMath.textWidth("4:59", 10), 4 * 6.2)
	Harness.near(UiMath.textWidth("✨", 10), 6.2)
end)

Harness.test("UiMath.titleBarFor: slim title bar on short screens", function()
	Harness.eq(UiMath.titleBarFor(300), UiMath.K.titleBarShort)
	Harness.eq(UiMath.titleBarFor(600), UiMath.K.titleBar)
	-- the slim bar still holds a close X of full touch size
	Harness.truthy(UiMath.K.titleBarShort >= UiMath.K.touch, "close X fits the slim bar")
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

Harness.test(
	"UiMath.layout: SWEEP, AUTO and SELL stay clear of Roblox's own jump button",
	function()
		-- Roblox TouchJump: short side <= 500 px -> 70 px at (W - 95, H - 90); else 120 px at (W - 170, H - 210)
		local screens = {
			{ 800, 360 },
			{ 844, 390 },
			{ 640, 360 },
			{ 568, 320 },
			{ 1024, 768 },
			{ 1366, 1024 },
		}
		for _, sc in screens do
			local w, h = sc[1], sc[2]
			local s = UiMath.scaleFor(w, h)
			local big = math.min(w, h) > 500
			local size = if big then 120 else 70
			local jx = w - (size * 1.5 - 10)
			local jy = if big then h - size * 1.75 else h - size - 20
			local jump = { x = jx / s, y = jy / s, w = size / s, h = size / s }
			local l = UiMath.layout(w / s, h / s, { top = 58 / s, touch = true, bigJump = big })
			for _, key in { "sweep", "auto", "sell" } do
				Harness.truthy(
					not UiMath.intersects((l :: any)[key], jump),
					`{w}x{h}: {key} overlaps Roblox's jump button`
				)
			end
		end
	end
)
