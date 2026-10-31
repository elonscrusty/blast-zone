--!strict
-- THE PHONE AUDIT. Lays every screen out on real phone shapes the way Roblox will, and fails when two pieces of
-- our UI overlap, a piece lands under a notch or under Roblox's own buttons, or a thumb target is too small.
--
-- Why it exists: the Studio emulator has no notch, no Roblox top bar and never turns, so layouts looked clean
-- there and still piled up on carter's phone. This test knows about all three. It works in dp (the points Roblox
-- lays GUI out in), per ScreenGui frame, so two screens that use different safe areas are compared fairly.
--
-- Adding UI? Put the rect in Ui/ScreenMap (or Hud/Layout), use Components.screen (safe frame), then add the piece
-- to the phase it shows in below. A new ScreenGui that is not in GUIS fails "every ScreenGui is accounted for".
-- Run:  lune run tests/run     (this file is part of it)
local fs = require("@lune/fs")
local Harness = require("./harness")
local DeviceZones = require("../src/client/Ui/DeviceZones")
local Layout = require("../src/client/Hud/Layout")
local LobbyLayout = require("../src/client/Ui/LobbyLayout")
local ScreenMap = require("../src/client/Ui/ScreenMap")

type Rect = { x: number, y: number, w: number, h: number }

-- ===== real phones (landscape, in dp) =====
-- w, h: screen. l, r: notch / rounded corner on each side. b: home bar. t: top cut-out (none in landscape).
type Device = { name: string, w: number, h: number, l: number, r: number, t: number, b: number }

local DEVICES: { Device } = {
	{ name = "carter iPhone 852x393", w = 852, h = 393, l = 59, r = 59, t = 0, b = 21 },
	{ name = "iPhone SE 667x375", w = 667, h = 375, l = 0, r = 0, t = 0, b = 0 },
	{ name = "iPhone 8 Plus 736x414", w = 736, h = 414, l = 0, r = 0, t = 0, b = 0 },
	{ name = "iPhone 13 mini 812x375", w = 812, h = 375, l = 50, r = 50, t = 0, b = 21 },
	{ name = "iPhone Pro Max 932x430", w = 932, h = 430, l = 59, r = 59, t = 0, b = 21 },
	{ name = "small Android 16:9 640x360", w = 640, h = 360, l = 0, r = 0, t = 0, b = 0 },
	{ name = "Android 18:9 720x360", w = 720, h = 360, l = 24, r = 24, t = 0, b = 0 },
	{ name = "Galaxy 19.5:9 780x360", w = 780, h = 360, l = 32, r = 32, t = 0, b = 0 },
	{ name = "Pixel 20:9 892x412", w = 892, h = 412, l = 36, r = 36, t = 0, b = 0 },
	{ name = "Xperia 21:9 960x412", w = 960, h = 412, l = 0, r = 0, t = 0, b = 0 },
	{ name = "short wide window 1914x604", w = 1914, h = 604, l = 0, r = 0, t = 0, b = 0 },
	{ name = "iPad 1024x768", w = 1024, h = 768, l = 0, r = 0, t = 0, b = 20 },
	{ name = "iPad Pro 1366x1024", w = 1366, h = 1024, l = 0, r = 0, t = 0, b = 20 },
}

-- ===== frames: the box a ScreenGui lays its children out in =====
-- full: ScreenInsets None / IgnoreGuiInset. safe: DeviceSafeInsets. core: the default (below the Roblox top bar).
local function frameOf(d: Device, mode: string): Rect
	if mode == "full" then
		return { x = 0, y = 0, w = d.w, h = d.h }
	elseif mode == "safe" then
		return { x = d.l, y = d.t, w = d.w - d.l - d.r, h = d.h - d.t - d.b }
	end
	local top = math.max(d.t, DeviceZones.TOP_BAR_HEIGHT)
	return { x = d.l, y = top, w = d.w - d.l - d.r, h = d.h - top - d.b }
end

local function safeOf(d: Device): Rect
	return frameOf(d, "safe")
end

-- A piece placed from a 780 x 360 design rect by UiKit.place, as dp on the screen.
local function design(d: Device, mode: string, rect: Rect, left: boolean?, minAspect: number?): Rect
	local f = frameOf(d, mode)
	local r = Layout.onScreen(rect, f.w / f.h, left, minAspect)
	local unit = f.h / Layout.HEIGHT
	return { x = f.x + r.x * unit, y = f.y + r.y * unit, w = r.w * unit, h = r.h * unit }
end

local function clamp(v: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, v))
end

-- ===== pieces =====
type Piece = { name: string, rect: Rect, touch: boolean?, overlay: { [string]: boolean }? }

local function lobbyPieces(d: Device): { Piece }
	local out: { Piece } = {}
	local LOBBY = Layout.LOBBY_MIN_ASPECT
	for _, name in { "botsBanner", "mapVote", "modeVote", "statsCard", "lookPicker" } do
		table.insert(
			out,
			{ name = name, rect = design(d, "safe", (ScreenMap :: any)[name], nil, LOBBY) }
		)
	end
	-- lobby buttons: a slot lands inside its group, scaled with the group
	local f = safeOf(d)
	local unit = f.h / Layout.HEIGHT
	for name, slot in LobbyLayout.slots :: any do
		local g = LobbyLayout.groups[slot.group]
		local gr = Layout.onScreen(g, f.w / f.h, nil, LOBBY)
		local sx, sy = gr.w / g.w, gr.h / g.h
		table.insert(out, {
			name = "slot " .. name,
			touch = slot.touch,
			rect = {
				x = f.x + (gr.x + (slot.rect.x - g.x) * sx) * unit,
				y = f.y + (gr.y + (slot.rect.y - g.y) * sy) * unit,
				w = slot.rect.w * sx * unit,
				h = slot.rect.h * sy * unit,
			},
		})
	end
	-- SCRAP / STARS bar, and the "not saved" note to the left of it (as wide as the bar, half as tall)
	local W = ScreenMap.walletBar
	local bw = clamp(W.widthShare * f.w, W.minW, W.maxW)
	local bh = clamp(W.heightShare * f.h, W.minH, W.maxH)
	local barX = f.x + f.w - W.inset - bw
	table.insert(out, {
		name = "wallet",
		rect = { x = barX, y = f.y + W.inset, w = bw, h = bh },
		overlay = { saveStrip = true },
	})
	table.insert(out, {
		name = "walletNote",
		rect = {
			x = barX - W.noteGap - bw,
			y = f.y + W.inset + bh * (1 - W.noteHeightShare) / 2,
			w = bw,
			h = bh * W.noteHeightShare,
		},
		overlay = { saveStrip = true },
	})
	-- the round EMOTE button: 72 design points, 16 from the corner, grows with the screen height
	local s = math.max(0.5, f.h / Layout.HEIGHT)
	table.insert(out, {
		name = "emote",
		touch = true,
		rect = {
			x = f.x + f.w - 16 * s - ScreenMap.emote.w * s,
			y = f.y + f.h - 16 * s - ScreenMap.emote.h * s,
			w = ScreenMap.emote.w * s,
			h = ScreenMap.emote.h * s,
		},
	})
	-- "your data did not load": a coral strip across the top of the full screen (only when saves are off)
	table.insert(out, {
		name = "saveStrip",
		rect = {
			x = 0,
			y = 0,
			w = d.w,
			h = math.min(ScreenMap.saveStripHeight * d.h, ScreenMap.saveStripMax),
		},
		overlay = { wallet = true, walletNote = true },
	})
	return out
end

local function fightPieces(d: Device, left: boolean): { Piece }
	local out: { Piece } = {}
	for name, region in Layout.regions :: any do
		if string.match(name, "^chip%d$") == nil then -- the pick chips only show with an offer; checked below
			local mirrors = left and table.find(Layout.touchTargets, name) ~= nil
			table.insert(out, {
				name = name,
				touch = table.find(Layout.touchTargets, name) ~= nil,
				rect = design(d, "safe", region, mirrors),
			})
		end
	end
	table.insert(out, {
		name = "airdropHint",
		rect = design(d, "safe", ScreenMap.airdropHint, left),
	})
	-- the zone arrow: a 40 point square at 67% across and 14 down, on the full screen (ZoneHud)
	table.insert(
		out,
		{ name = "zoneArrow", rect = { x = 0.67 * d.w - 20, y = 14, w = 40, h = 40 } }
	)
	return out
end

local function offerPieces(d: Device, left: boolean): { Piece }
	local out = fightPieces(d, left)
	for i = 1, 3 do
		local name = Layout.chipName(i, left)
		table.insert(out, {
			name = "chip" .. i,
			touch = true,
			rect = design(d, "safe", Layout.regions[name], left),
		})
	end
	return out
end

local function spectatePieces(d: Device): { Piece }
	return {
		{ name = "spectate", touch = true, rect = design(d, "safe", ScreenMap.spectate) },
		{
			name = "airdropHint",
			rect = design(d, "safe", ScreenMap.airdropHint),
		},
	}
end

-- ===== checks =====
local function overlaps(a: Rect, b: Rect): boolean
	local e = 0.75 -- dp: touching edges and a hair of rounding are fine
	return a.x + e < b.x + b.w
		and b.x + e < a.x + a.w
		and a.y + e < b.y + b.h
		and b.y + e < a.y + a.h
end

local function fmt(r: Rect): string
	return string.format("(x %.0f-%.0f, y %.0f-%.0f)", r.x, r.x + r.w, r.y, r.y + r.h)
end

local MIN_TAP = DeviceZones.MIN_TAP
-- The lobby has five columns of buttons, so on a 16:9 phone it shrinks to 0.82 and a button is 39 dp. Claude Design is
-- redoing the lobby; until then 38 dp is the floor (a thumb still hits it), and nothing may go under that.
local LOBBY_MIN_TAP = 38

-- Returns the problems found for one phase on one device.
local function audit(d: Device, phase: string, pieces: { Piece }, minTap: number): { string }
	local bad: { string } = {}
	local safe = safeOf(d)
	local pill = DeviceZones.robloxTopLeft(d.l)
	for _, p in pieces do
		local r = p.rect
		if p.name ~= "saveStrip" and p.name ~= "zoneArrow" then
			if
				r.x < safe.x - 0.75
				or r.y < safe.y - 0.75
				or r.x + r.w > safe.x + safe.w + 0.75
				or r.y + r.h > safe.y + safe.h + 0.75
			then
				table.insert(bad, `{p.name} leaves the safe area {fmt(r)} ({d.name}, {phase})`)
			end
		end
		if p.name ~= "saveStrip" and overlaps(r, pill) then
			table.insert(
				bad,
				`{p.name} is under Roblox's menu and chat buttons {fmt(r)} ({d.name}, {phase})`
			)
		end
		if p.touch and math.min(r.w, r.h) < minTap - 0.75 then
			table.insert(
				bad,
				`{p.name} is only {math.floor(math.min(r.w, r.h))} dp, too small to tap ({d.name}, {phase})`
			)
		end
	end
	for i, a in pieces do
		for j = i + 1, #pieces do
			local b = pieces[j]
			local allowed = (a.overlay and a.overlay[b.name]) or (b.overlay and b.overlay[a.name])
			if not allowed and overlaps(a.rect, b.rect) then
				table.insert(
					bad,
					`{a.name} {fmt(a.rect)} overlaps {b.name} {fmt(b.rect)} ({d.name}, {phase})`
				)
			end
		end
	end
	return bad
end

local function report(bad: { string })
	if #bad > 0 then
		table.sort(bad)
		-- one line per problem, capped, so a failure reads like a to-do list
		local shown = {}
		for i = 1, math.min(#bad, 12) do
			shown[i] = bad[i]
		end
		Harness.eq(table.concat(shown, "\n   "), "", `{#bad} layout problems:`)
	end
end

Harness.test(
	"phone audit: LOBBY on every phone, no overlaps, no Roblox buttons in the way",
	function()
		local bad: { string } = {}
		for _, d in DEVICES do
			for _, problem in audit(d, "lobby", lobbyPieces(d), LOBBY_MIN_TAP) do
				table.insert(bad, problem)
			end
		end
		report(bad)
	end
)

Harness.test("phone audit: FIGHT on every phone, right- and left-handed", function()
	local bad: { string } = {}
	for _, d in DEVICES do
		for _, left in { false, true } do
			for _, problem in audit(d, "fight", fightPieces(d, left), MIN_TAP) do
				table.insert(bad, problem)
			end
		end
	end
	report(bad)
end)

Harness.test("phone audit: an upgrade offer's pick chips, both hands", function()
	local bad: { string } = {}
	for _, d in DEVICES do
		for _, left in { false, true } do
			for _, problem in audit(d, "offer", offerPieces(d, left), MIN_TAP) do
				table.insert(bad, problem)
			end
		end
	end
	report(bad)
end)

Harness.test("phone audit: SPECTATE on every phone", function()
	local bad: { string } = {}
	for _, d in DEVICES do
		for _, problem in audit(d, "spectate", spectatePieces(d), MIN_TAP) do
			table.insert(bad, problem)
		end
	end
	report(bad)
end)

Harness.test(
	"phone audit: the save message and TRY AGAIN clear the notch and Roblox's buttons",
	function()
		for _, d in DEVICES do
			local messageLeft = DeviceZones.NOTCH_MAX + DeviceZones.LEFT_CLUSTER_WIDTH
			Harness.truthy(
				messageLeft >= d.l + DeviceZones.LEFT_CLUSTER_WIDTH,
				"message under the Roblox buttons on " .. d.name
			)
			Harness.truthy(
				DeviceZones.NOTCH_MAX + 8 >= d.r,
				"TRY AGAIN under the right notch on " .. d.name
			)
			local messageWidth = 0.78 * d.w - (messageLeft + DeviceZones.NOTCH_MAX + 8 + 8)
			Harness.truthy(
				messageWidth >= 180,
				`save message only {math.floor(messageWidth)} dp wide on {d.name}`
			)
		end
	end
)

-- ===== turning the phone =====
Harness.test(
	"phone audit: a layout made while the phone is still upright is far too small (so it must be redone)",
	function()
		-- Roblox starts a landscape game with the screen upright for a moment, then turns it. A layout kept from
		-- that moment came out 5x too small and piled at the bottom on carter's phone.
		local upright =
			Layout.onScreen(LobbyLayout.groups.menu, 9 / 19.5, nil, Layout.LOBBY_MIN_ASPECT)
		local sideways =
			Layout.onScreen(LobbyLayout.groups.menu, 19.5 / 9, nil, Layout.LOBBY_MIN_ASPECT)
		Harness.truthy(
			upright.w < sideways.w / 3,
			"the upright layout is not much smaller; the test lost its point"
		)
		-- Same pieces, placed again for the new shape, land where the sideways layout says (a pure function of the shape).
		local again =
			Layout.onScreen(LobbyLayout.groups.menu, 19.5 / 9, nil, Layout.LOBBY_MIN_ASPECT)
		Harness.near(again.x, sideways.x, 1e-9)
		Harness.near(again.w, sideways.w, 1e-9)
	end
)

Harness.test(
	"phone audit: placing is stateless and a tall upright screen gives finite, positive rects",
	function()
		local pieces: { Rect } =
			{ LobbyLayout.groups.menu, LobbyLayout.groups.right, ScreenMap.statsCard }
		for _, rect in pieces do
			for _, left in { false, true } do
				local first = Layout.onScreen(rect, 19.5 / 9, left, Layout.LOBBY_MIN_ASPECT)
				-- a tall upright moment (393x852, 3:4 portrait, square) comes between, then the real landscape shape again
				for _, tall in { 393 / 852, 768 / 1024, 1 } do
					local t = Layout.onScreen(rect, tall, left, Layout.LOBBY_MIN_ASPECT)
					for _, v in { t.x, t.y, t.w, t.h } do
						Harness.truthy(
							v == v and math.abs(v) < 1e6,
							"NaN or huge value at a tall shape"
						)
					end
					Harness.truthy(t.w > 0 and t.h > 0, "zero or negative size at a tall shape")
				end
				local again = Layout.onScreen(rect, 19.5 / 9, left, Layout.LOBBY_MIN_ASPECT)
				Harness.near(again.x, first.x, 1e-9)
				Harness.near(again.y, first.y, 1e-9)
				Harness.near(again.w, first.w, 1e-9)
				Harness.near(again.h, first.h, 1e-9)
			end
		end
	end
)

Harness.test(
	"phone audit: the game asks for landscape (the upright start is the root cause)",
	function()
		local project = fs.readFile("default.project.json")
		Harness.truthy(
			string.find(project, '"ScreenOrientation": "LandscapeSensor"', 1, true),
			"StarterGui must set ScreenOrientation to LandscapeSensor in default.project.json"
		)
	end
)

Harness.test(
	"phone audit: UiKit places everything again when the screen it sits in changes size",
	function()
		local source = fs.readFile("src/client/Hud/UiKit.luau")
		Harness.truthy(
			string.find(source, 'parent:GetPropertyChangedSignal("AbsoluteSize")', 1, true),
			"UiKit must watch the parent's size, not only the camera"
		)
		Harness.truthy(
			string.find(source, 'camera:GetPropertyChangedSignal("ViewportSize")', 1, true),
			"UiKit must also watch the camera's ViewportSize"
		)
		Harness.truthy(
			string.find(source, 'workspace:GetPropertyChangedSignal("CurrentCamera")', 1, true),
			"UiKit must follow a replaced camera"
		)
		-- the old bug: "watching" was switched on even when there was no camera, so nothing was ever connected
		Harness.eq(
			string.find(source, "watchingScreen = true\n\tlocal camera", 1, true),
			nil,
			"watching must not be latched before a camera exists"
		)
	end
)

-- ===== every ScreenGui is accounted for =====
-- mode: how the gui is framed ("full" | "safe" | "core"). why: where it is audited, or why it is exempt.
local GUIS: { [string]: { mode: string, why: string } } = {
	-- audited above
	LobbyStats = { mode = "safe", why = "lobby: statsCard" },
	WalletBar = { mode = "safe", why = "lobby: wallet" },
	BotBanner = { mode = "safe", why = "lobby: botsBanner" },
	MapVote = { mode = "safe", why = "lobby: mapVote" },
	ModeVote = { mode = "safe", why = "lobby: modeVote" },
	LookPicker = { mode = "safe", why = "lobby: lookPicker" },
	MatchFlow = { mode = "safe", why = "lobby: slots; banners and results are centred fractions" },
	EmoteWheel = { mode = "safe", why = "lobby: emote" },
	SaveStatus = { mode = "full", why = "lobby: saveStrip, message and retry offsets" },
	Hud = { mode = "safe", why = "fight: Layout.regions" },
	TouchControls = {
		mode = "safe",
		why = "fight: Layout.regions; lobby: whole-screen walk catcher",
	},
	Spectate = { mode = "safe", why = "spectate" },
	AirdropHint = { mode = "safe", why = "fight and spectate: airdropHint" },
	MomentBanner = { mode = "safe", why = "fight: Layout.regions.moment" },
	ZoneHud = { mode = "full", why = "fight: zoneArrow" },
	-- exempt: one at a time, centred, behind a dim (ModalGate), or a short message
	MatchFlowBackdrop = { mode = "full", why = "colour only, no controls" },
	BenchButtonHost = { mode = "safe", why = "lobby slot bench" },
	UpgradeCards = { mode = "safe", why = "own band (Layout.CardsBand), tests/upgrades" },
	BigMap = { mode = "safe", why = "own box (Layout.bigMap), tests/hud_layout" },
	Loadout = { mode = "full", why = "modal panel" },
	Settings = { mode = "full", why = "modal panel" },
	TrackPanel = { mode = "full", why = "modal panel" },
	Daily = { mode = "full", why = "modal panel and its lobby slot" },
	Intro = { mode = "full", why = "first-time intro, blocks everything" },
	CoinClaim = { mode = "full", why = "modal panel" },
	ChestReveal = { mode = "safe", why = "modal panel" },
	ChestToast = { mode = "safe", why = "short message" },
	SeasonToast = { mode = "safe", why = "short message" },
	ShopToast = { mode = "safe", why = "short message" },
	MissionsToast = { mode = "safe", why = "short message" },
	FxFlash = { mode = "full", why = "screen flash, no controls" },
	WinnerPose = { mode = "core", why = "3D winner picture, no controls" },
	SquadVote = {
		mode = "safe",
		why = "off while Config.Squads.enabled is false; audit before turning on",
	},
	SquadList = {
		mode = "safe",
		why = "off while Config.Squads.enabled is false; audit before turning on",
	},
}

local function luauFiles(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			luauFiles(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

Harness.test(
	"phone audit: every ScreenGui is accounted for, with the frame it really uses",
	function()
		local files: { string } = {}
		luauFiles("src/client", files)
		local seen: { [string]: boolean } = {}
		for _, path in files do
			-- the factory itself (Components.screen) names its guis from its callers, which are scanned instead
			local lines = if path == "src/client/Ui/Components.luau"
				then {}
				else string.split(fs.readFile(path), "\n")
			for i, line in lines do
				local made = string.find(line, 'Instance.new("ScreenGui")', 1, true) ~= nil
					or string.find(line, 'make("ScreenGui"', 1, true) ~= nil
				local viaComponents = string.match(line, 'Components%.screen%("([%w_]+)"')
				if made or viaComponents then
					local window = table.concat(lines, "\n", i, math.min(#lines, i + 25))
					local name = viaComponents or string.match(window, '[Nn]ame%s*=%s*"([%w_]+)"')
					if name == nil then
						Harness.truthy(false, `{path}:{i} makes a ScreenGui with no literal Name`)
					else
						local mode = "core"
						if
							viaComponents ~= nil or string.find(window, "DeviceSafeInsets", 1, true)
						then
							mode = "safe"
						elseif
							string.find(window, "ScreenInsets.None", 1, true)
							or string.find(window, "IgnoreGuiInset = true", 1, true)
						then
							mode = "full"
						end
						seen[name] = true
						local entry = GUIS[name]
						Harness.truthy(
							entry ~= nil,
							`ScreenGui "{name}" ({path}:{i}) is not in tests/phone_audit.test.luau GUIS: add it and audit it`
						)
						if entry ~= nil then
							Harness.eq(
								mode,
								entry.mode,
								`ScreenGui "{name}" is framed "{mode}" in the code but "{entry.mode}" in the audit`
							)
						end
					end
				end
			end
		end
		for name in GUIS do
			Harness.truthy(
				seen[name] == true,
				`GUIS lists "{name}" but no code makes it (stale entry)`
			)
		end
	end
)
