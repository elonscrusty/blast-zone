--!strict
-- Screen layers, one-panel-at-a-time, lobby slots, and HUD spacing on real phone shapes.
local fs = require("@lune/fs")
local Harness = require("./harness")
local Layout = require("../src/client/Hud/Layout")
local LobbyLayout = require("../src/client/Ui/LobbyLayout")
local ModalGate = require("../src/client/Ui/ModalGate")
local UiLayers = require("../src/client/Ui/UiLayers")

-- Phone shapes (width / height): 16:9, 2:1, 19.5:9, 20:9, 21:9. Tablets (4:3) get the 16:9 layout shrunk.
local PHONES = { 16 / 9, 2, 19.5 / 9, 20 / 9, 21 / 9 }
local TABLET = 4 / 3

local function layer(name: string): number
	return UiLayers.get(name)
end

Harness.test("ui layers: the list goes up, bottom to top", function()
	for i = 2, #UiLayers.order do
		Harness.truthy(
			layer(UiLayers.order[i]) > layer(UiLayers.order[i - 1]),
			`{UiLayers.order[i]} must sit above {UiLayers.order[i - 1]}`
		)
	end
end)

Harness.test("ui layers: settings and other panels draw over the lobby buttons", function()
	Harness.truthy(layer("Modal") > layer("MatchFlow"), "panel under the lobby")
	Harness.truthy(layer("Modal") > layer("MatchFlowExtra"), "panel under the results add-ons")
	Harness.truthy(layer("Onboarding") > layer("Modal"), "intro must block everything")
	Harness.truthy(layer("Toast") > layer("Onboarding"), "messages must always be seen")
	Harness.truthy(layer("Hud") > layer("TouchControls"), "HUD under the thumbs")
	Harness.truthy(layer("Spectate") > layer("Hud"), "spectate arrows under the HUD")
end)

-- Every ScreenGui in src/client takes its DisplayOrder from UiLayers, never a bare number.
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

Harness.test("ui layers: every ScreenGui uses UiLayers for DisplayOrder", function()
	local files = {}
	luauFiles("src/client", files)
	for _, path in files do
		local source = fs.readFile(path)
		Harness.eq(
			string.find(source, "DisplayOrder%s*=%s*%d"),
			nil,
			path .. " sets DisplayOrder to a bare number"
		)
		local makesGui = string.find(source, '"ScreenGui"', 1, true) ~= nil
			and (
				string.find(source, 'Instance.new("ScreenGui")', 1, true) ~= nil
				or string.find(source, 'make("ScreenGui"', 1, true) ~= nil
			)
		if makesGui then
			Harness.truthy(
				string.find(source, "UiLayers", 1, true),
				path .. " makes a ScreenGui without a UiLayers layer"
			)
		end
	end
end)

Harness.test("modal gate: opening a second panel closes the first", function()
	local settingsOpen, trackOpen = false, false
	local function openSettings()
		settingsOpen = true
		ModalGate.opened("settings", function()
			settingsOpen = false
			ModalGate.closed("settings")
		end)
	end
	local function openTrack()
		trackOpen = true
		ModalGate.opened("track", function()
			trackOpen = false
			ModalGate.closed("track")
		end)
	end
	openSettings()
	Harness.eq(ModalGate.current(), "settings")
	openTrack()
	Harness.eq(settingsOpen, false, "settings stayed open under track")
	Harness.eq(trackOpen, true)
	Harness.eq(ModalGate.current(), "track")
	openTrack() -- opening the same one again keeps it
	Harness.eq(trackOpen, true)
	ModalGate.closed("settings") -- a stale close does nothing
	Harness.eq(ModalGate.current(), "track")
	ModalGate.closeAll()
	Harness.eq(trackOpen, false)
	Harness.eq(ModalGate.current(), nil)
end)

local function slotNames(): { string }
	local out = {}
	for name in LobbyLayout.slots :: any do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

local function inside(inner: LobbyLayout.Rect, outer: LobbyLayout.Rect): boolean
	return inner.x >= outer.x
		and inner.y >= outer.y
		and inner.x + inner.w <= outer.x + outer.w
		and inner.y + inner.h <= outer.y + outer.h
end

local function grow(r: LobbyLayout.Rect, by: number): LobbyLayout.Rect
	return { x = r.x - by, y = r.y - by, w = r.w + by * 2, h = r.h + by * 2 }
end

Harness.test("lobby slots: inside their group, big enough to tap, not touching", function()
	local list = slotNames()
	for i, a in list do
		local slot = LobbyLayout.slots[a]
		Harness.truthy(LobbyLayout.groups[slot.group], a .. " has no group")
		Harness.truthy(
			inside(slot.rect, LobbyLayout.groups[slot.group]),
			a .. " sticks out of its group"
		)
		if slot.touch then
			Harness.truthy(slot.rect.h >= LobbyLayout.MIN_TOUCH, a .. " is under 48 points tall")
		end
		for j = i + 1, #list do
			local b = LobbyLayout.slots[list[j]]
			Harness.eq(
				Layout.overlaps(
					grow(slot.rect, LobbyLayout.GAP / 2),
					grow(b.rect, LobbyLayout.GAP / 2)
				),
				false,
				`{a} touches {list[j]}`
			)
		end
	end
end)

Harness.test("lobby slots: below the banner band and the Play slot is the biggest", function()
	for name, rect in LobbyLayout.groups :: any do
		if name == "menu" then
			Harness.truthy(
				rect.y >= LobbyLayout.bannerBottom,
				"lobby menu runs into the banner band"
			)
		end
	end
	local play = LobbyLayout.slots.play.rect
	for name, slot in LobbyLayout.slots :: any do
		if name ~= "play" and slot.group == "menu" then
			Harness.truthy(
				slot.rect.w * slot.rect.h < play.w * play.h,
				name .. " is bigger than PLAY"
			)
		end
	end
	local x, y, w, h = LobbyLayout.relative("play")
	Harness.truthy(
		x >= 0 and y >= 0 and x + w <= 1 + 1e-9 and y + h <= 1 + 1e-9,
		"play slot scale out of range"
	)
end)

local NOTCH = 48 -- landscape notch / rounded corner, in design units, on full-screen (IgnoreGuiInset) screens

Harness.test(
	"lobby groups: on every phone and tablet, on screen, clear of the notch, apart",
	function()
		for _, aspect in { TABLET, table.unpack(PHONES) } do
			local screenW = Layout.HEIGHT * aspect
			local placed = {}
			for name, rect in LobbyLayout.groups :: any do
				local r = Layout.onScreen(rect, aspect)
				local edge = if aspect == TABLET then 8 else NOTCH -- tablets have no notch
				Harness.truthy(
					r.x >= edge - 1e-6 and r.x + r.w <= screenW - edge + 1e-6,
					`{name} under the notch at {aspect}`
				)
				Harness.truthy(
					r.y >= 0 and r.y + r.h <= Layout.HEIGHT,
					`{name} off screen at {aspect}`
				)
				placed[name] = r
			end
			Harness.eq(
				Layout.overlaps(placed.menu, placed.side),
				false,
				`lobby columns overlap at {aspect}`
			)
		end
	end
)

Harness.test("HUD: no two pieces overlap on any phone shape or tablet", function()
	local names = {}
	for name in Layout.regions :: any do
		table.insert(names, name)
	end
	table.sort(names)
	for _, aspect in { TABLET, table.unpack(PHONES) } do
		for _, left in { false, true } do
			local placed = {}
			for _, name in names do
				placed[name] = Layout.onScreen(Layout.regions[name], aspect, left)
			end
			for i, a in names do
				for j = i + 1, #names do
					local b = names[j]
					Harness.eq(
						Layout.overlaps(grow(placed[a], -1e-6), grow(placed[b], -1e-6)),
						false,
						`{a} overlaps {b} at {aspect} (left {left})`
					)
				end
			end
		end
	end
end)

Harness.test("HUD: thumbs keep their size and edge spacing on every phone", function()
	for _, aspect in PHONES do
		local screenW = Layout.HEIGHT * aspect
		local fire = Layout.onScreen(Layout.regions.fireStick, aspect)
		Harness.near(fire.w, Layout.regions.fireStick.w, 1e-6, "fire stick changed size")
		Harness.near(
			screenW - (fire.x + fire.w),
			Layout.WIDTH - (Layout.regions.fireStick.x + Layout.regions.fireStick.w),
			1e-6,
			"fire stick moved off its edge"
		)
		for _, name in Layout.touchTargets do
			Harness.truthy(
				Layout.onScreen(Layout.regions[name], aspect).h >= Layout.MIN_TOUCH,
				name .. " under 48 points"
			)
		end
	end
	-- Without a screen shape the old design numbers come back unchanged.
	local design = Layout.place(Layout.regions.fireStick)
	Harness.near(design.posX, (630 + 126) / 780)
end)

Harness.test("HUD: on a tablet everything shrinks evenly and stays on screen", function()
	local screenW = Layout.HEIGHT * TABLET
	for name, rect in Layout.regions :: any do
		local r = Layout.onScreen(rect, TABLET)
		Harness.truthy(r.x >= -1e-6 and r.x + r.w <= screenW + 1e-6, name .. " off a tablet screen")
		Harness.truthy(
			r.y >= -1e-6 and r.y + r.h <= Layout.HEIGHT + 1e-6,
			name .. " off a tablet screen"
		)
	end
end)

-- Where a lobby slot really lands on a screen `aspect` wide (design height units): its group first,
-- then the slot's share of the group (this is what LobbyMenu builds).
local function slotOnScreen(name: string, aspect: number): LobbyLayout.Rect
	local slot = LobbyLayout.slots[name]
	local g = Layout.onScreen(LobbyLayout.groups[slot.group], aspect)
	local x, y, w, h = LobbyLayout.relative(name)
	return { x = g.x + x * g.w, y = g.y + y * g.h, w = w * g.w, h = h * g.h }
end

Harness.test(
	"lobby slots: on short wide phones too, every slot is on screen and none touch another",
	function()
		-- 1914 x 604 is the playtest window (landscape phone, 3.17 wide); 2.6 is a very long phone.
		local shapes = { TABLET, 1914 / 604, 2.6, table.unpack(PHONES) }
		local list = slotNames()
		for _, aspect in shapes do
			local screenW = Layout.HEIGHT * aspect
			local placed: { [string]: LobbyLayout.Rect } = {}
			for _, name in list do
				local r = slotOnScreen(name, aspect)
				placed[name] = r
				Harness.truthy(
					r.x >= -1e-6 and r.x + r.w <= screenW + 1e-6,
					`{name} off screen sideways at {aspect}`
				)
				Harness.truthy(
					r.y >= -1e-6 and r.y + r.h <= Layout.HEIGHT + 1e-6,
					`{name} off screen up/down at {aspect}`
				)
				if LobbyLayout.slots[name].touch and aspect >= Layout.MIN_ASPECT then
					Harness.truthy(
						r.h >= LobbyLayout.MIN_TOUCH - 1e-6,
						`{name} is under 48 points tall at {aspect}`
					)
				end
			end
			for i, a in list do
				for j = i + 1, #list do
					Harness.eq(
						Layout.overlaps(placed[a], placed[list[j]]),
						false,
						`{a} sits on {list[j]} at {aspect}`
					)
				end
			end
		end
	end
)

Harness.test("lobby groups: none overlap, and the top group stays above the menu band", function()
	local names = {}
	for name in LobbyLayout.groups :: any do
		table.insert(names, name)
	end
	table.sort(names)
	for _, aspect in { TABLET, 1914 / 604, table.unpack(PHONES) } do
		local placed = {}
		for _, name in names do
			placed[name] = Layout.onScreen(LobbyLayout.groups[name], aspect)
		end
		for i, a in names do
			for j = i + 1, #names do
				Harness.eq(
					Layout.overlaps(placed[a], placed[names[j]]),
					false,
					`group {a} overlaps {names[j]} at {aspect}`
				)
			end
		end
	end
	local top = LobbyLayout.groups.top
	Harness.truthy(top.y + top.h <= LobbyLayout.bannerBottom, "banner and vote run into the menu")
end)

Harness.test(
	"lobby slots: the vote row fits four maps and the banner holds a tap button",
	function()
		local vote = LobbyLayout.slots.vote.rect
		Harness.truthy(vote.w / 4 >= LobbyLayout.MIN_TOUCH * 2, "four vote buttons are too narrow")
		-- BotBannerSystem: the button is 58% of the banner slot's height.
		Harness.truthy(
			LobbyLayout.slots.banner.rect.h * 0.58 >= LobbyLayout.MIN_TOUCH,
			"banner button too short"
		)
		-- LookPickerSystem: three 48 point buttons and two 4 point gaps fill the looks slot exactly.
		Harness.near(LobbyLayout.slots.looks.rect.h, 3 * 48 + 2 * 4, 1e-6)
	end
)
