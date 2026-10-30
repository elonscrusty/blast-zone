--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local Loadout = require("../src/shared/Loadout")
local LoadoutStore = require("../src/shared/LoadoutStore")
local LoadoutView = require("../src/shared/LoadoutView")
local LobbyLayout = require("../src/shared/LobbyLayout")
local RemoteDefs = require("../src/shared/RemoteDefs")
local StatBook = require("../src/shared/StatBook")

local function unlocks(level: number, owned: { [string]: boolean }?): Loadout.Unlocks
	return { level = level, owned = owned }
end

-- ===== catalogue =====

Harness.test("loadout: every slot has a free default item", function()
	for _, slot in Loadout.slots do
		local id = (Loadout.defaults :: any)[slot]
		local item = Loadout.find(slot, id)
		Harness.truthy(item ~= nil, slot .. " default exists")
		Harness.truthy((item :: Loadout.Item).unlockAt == nil, slot .. " default is free")
	end
end)

Harness.test("loadout: ids are unique per slot and safe for the remote check", function()
	for _, slot in Loadout.slots do
		local seen: { [string]: boolean } = {}
		for _, item in Loadout.items[slot] do
			Harness.truthy(not seen[item.id], "duplicate " .. item.id)
			seen[item.id] = true
			Harness.truthy(string.match(item.id, "^[%w_:%-]+$") ~= nil, "bad id " .. item.id)
			Harness.truthy(#item.id <= 24, "id too long")
		end
		Harness.truthy(#slot <= 12, "slot name too long for the remote")
	end
end)

Harness.test("loadout: unlock levels stay inside the Rewards board (0 to 6)", function()
	for _, slot in Loadout.slots do
		for _, item in Loadout.items[slot] do
			if item.unlockAt then
				Harness.truthy(item.unlockAt >= 1 and item.unlockAt <= 6, item.id .. " unlockAt")
			end
		end
	end
end)

Harness.test("loadout: sidegrades trade, they do not just add power", function()
	for _, item in Loadout.items.slide do
		local d, c = item.slideDistance or 0, item.slideCooldown or 0
		-- farther must wait longer; shorter must be ready sooner; or nothing changes
		Harness.truthy((d > 0) == (c > 0) and (d < 0) == (c < 0), item.id .. " is a fair trade")
	end
end)

Harness.test("loadout: locked items need the level or ownership", function()
	local courier = Loadout.find("outfit", "courier") :: Loadout.Item
	Harness.truthy(not Loadout.isUnlocked(courier, unlocks(0)))
	Harness.truthy(not Loadout.isUnlocked(courier, unlocks(1)))
	Harness.truthy(Loadout.isUnlocked(courier, unlocks(courier.unlockAt :: number)))
	Harness.truthy(Loadout.isUnlocked(courier, unlocks(0, { courier = true })))
end)

Harness.test("loadout: equipProblem names the reason", function()
	Harness.eq(Loadout.equipProblem("hat", "x", unlocks(6)), "unknown_slot")
	Harness.eq(Loadout.equipProblem(5, "x", unlocks(6)), "unknown_slot")
	Harness.eq(Loadout.equipProblem("outfit", "nope", unlocks(6)), "unknown_item")
	Harness.eq(Loadout.equipProblem("outfit", 7, unlocks(6)), "unknown_item")
	Harness.eq(Loadout.equipProblem("outfit", "spark", unlocks(0)), "locked")
	Harness.eq(Loadout.equipProblem("outfit", "runner", unlocks(0)), nil)
	-- an item from another slot is not valid here
	Harness.eq(Loadout.equipProblem("gun", "runner", unlocks(6)), "unknown_item")
end)

Harness.test("loadout: sanitize repairs anything bad", function()
	local sel =
		Loadout.sanitize({ outfit = "spark", gun = "hazard", slide = 12, extra = "x" }, unlocks(0))
	Harness.eq(sel.outfit, "runner") -- locked
	Harness.eq(sel.gun, "hazard") -- free and valid
	Harness.eq(sel.slide, "std") -- wrong type
	Harness.eq((sel :: any).extra, nil)
	local none = Loadout.sanitize(nil, unlocks(0))
	Harness.eq(none.outfit, "runner")
	local unlocked = Loadout.sanitize({ outfit = "spark" }, unlocks(6))
	Harness.eq(unlocked.outfit, "spark")
end)

Harness.test("loadout: rgb splits a colour", function()
	local r, g, b = Loadout.rgb(0xF15B64)
	Harness.eq(r, 0xF1)
	Harness.eq(g, 0x5B)
	Harness.eq(b, 0x64)
end)

Harness.test("loadout: mergedLook has the gun colours", function()
	local look = Loadout.mergedLook({ outfit = "runner", gun = "hazard", slide = "std" })
	Harness.eq(look.gunBody, 0xFFC44D)
	Harness.eq(look.gunAcc, 0x14243A)
end)

Harness.test("loadout: every outfit is one of the three fighters", function()
	local Looks = require("../src/shared/Character/Looks")
	for _, item in Loadout.items.outfit do
		local found = false
		for _, name in Looks.NAMES do
			if name == item.fighter then
				found = true
			end
		end
		Harness.truthy(found, item.id .. " names a real fighter")
	end
	Harness.eq(Loadout.defaults.outfit, "runner")
	Harness.eq(Config.Character.defaultLook, "Runner")
end)

-- ===== slide sidegrade through the stat book =====

Harness.test("slide sidegrade: applies on a copy and never below the floor", function()
	local sheet = StatBook.base(Config)
	local baseDistance, baseCooldown = sheet.slideDistance, sheet.slideCooldown
	Loadout.applySlide(sheet, "long")
	Harness.near(sheet.slideDistance, baseDistance + 4)
	Harness.near(sheet.slideCooldown, baseCooldown + 1)
	local tiny = { slideDistance = 5, slideCooldown = 1.5 }
	Loadout.applySlide(tiny, "quick")
	Harness.near(tiny.slideDistance, Loadout.minSlideDistance)
	Harness.near(tiny.slideCooldown, Loadout.minSlideCooldown)
	Loadout.applySlide(tiny, "nonsense") -- unknown id: nothing happens
	Harness.near(tiny.slideDistance, Loadout.minSlideDistance)
end)

Harness.test("stat book: modifiers run on a copy so stacks never pile up", function()
	local book = StatBook.new(Config)
	local shared = StatBook.base(Config)
	book:setProvider(function()
		return shared -- a provider that hands out the same table every time
	end)
	book:addModifier(function(_, sheet)
		Loadout.applySlide(sheet, "long")
	end)
	local a = book:get("p1")
	local b = book:get("p1")
	Harness.near(a.slideDistance, shared.slideDistance + 4)
	Harness.near(b.slideDistance, a.slideDistance, 1e-9, "second read is the same, not +8")
	Harness.near(
		shared.slideDistance,
		StatBook.base(Config).slideDistance,
		1e-9,
		"the provider's sheet is untouched"
	)
end)

Harness.test("stat book: with no modifier the provider's sheet comes back as is", function()
	local book = StatBook.new(Config)
	local shared = StatBook.base(Config)
	book:setProvider(function()
		return shared
	end)
	Harness.truthy(book:get("p1") == shared)
end)

-- ===== store =====

local function makeStore(level: number, savedPicks: { [string]: any }?, canSave: boolean?)
	local writes: { { any } } = {}
	local picks = savedPicks
	local store = LoadoutStore.new({
		read = function()
			return picks
		end,
		write = function(_, slot, id)
			table.insert(writes, { slot, id })
			if canSave then
				picks = picks or {}
				picks[slot] = id
			end
			return canSave == true
		end,
		unlocks = function()
			return unlocks(level)
		end,
		saved = function()
			return canSave == true
		end,
	})
	return store, writes
end

Harness.test("store: new player gets the defaults", function()
	local store = makeStore(0, nil, true)
	local sel = store:get(1)
	Harness.eq(sel.outfit, "runner")
	Harness.eq(sel.slide, "std")
end)

Harness.test("store: equip checks slot, item and unlock, and writes only good picks", function()
	local store, writes = makeStore(0, nil, true)
	local ok, why = store:equip(1, "outfit", "spark")
	Harness.eq(ok, false)
	Harness.eq(why, "locked")
	ok, why = store:equip(1, "hat", "x")
	Harness.eq(why, "unknown_slot")
	ok, why = store:equip(1, "outfit", "bogus")
	Harness.eq(why, "unknown_item")
	Harness.eq(#writes, 0)
	ok = store:equip(1, "gun", "hazard")
	Harness.eq(ok, true)
	Harness.eq(#writes, 1)
	Harness.eq(store:get(1).gun, "hazard")
end)

Harness.test("store: picks survive when saving is down, for this visit", function()
	local store = makeStore(0, nil, false)
	Harness.eq(store:equip(1, "gun", "hazard"), true)
	Harness.eq(store:get(1).gun, "hazard")
	Harness.eq(store:isSaved(1), false)
end)

Harness.test("store: a saved item that is locked now falls back to the default", function()
	local store = makeStore(0, { outfit = "spark", gun = "hazard" }, true)
	local sel = store:get(1)
	Harness.eq(sel.outfit, "runner")
	Harness.eq(sel.gun, "hazard")
end)

Harness.test("store: Changed fires with the new selection", function()
	local store = makeStore(6, nil, true)
	local seenUser: number? = nil
	local seenOutfit: string? = nil
	store.Changed:connect(function(userId: number, sel: Loadout.Selection)
		seenUser, seenOutfit = userId, sel.outfit
	end)
	store:equip(42, "outfit", "spark")
	Harness.eq(seenUser, 42)
	Harness.eq(seenOutfit, "spark")
end)

-- ===== view =====

local function state(level: number, selection: { [string]: string }?): LoadoutView.State
	return {
		selection = selection or (Loadout.defaults :: any),
		unlocked = Loadout.unlockedIds(unlocks(level)),
		level = level,
		saved = true,
	}
end

Harness.test("view: tabs are the slots in order", function()
	local tabs = LoadoutView.tabs()
	Harness.eq(#tabs, #Loadout.slots)
	Harness.eq(tabs[1].slot, "outfit")
	Harness.eq(tabs[1].label, "OUTFIT")
end)

Harness.test("view: cards say wearing, tap to wear, or what reward is needed", function()
	local cards = LoadoutView.cards(state(0), "outfit")
	Harness.eq(cards[1].status, "Wearing")
	Harness.truthy(cards[1].equipped)
	local locked = cards[2]
	Harness.truthy(locked.locked)
	Harness.eq(locked.status, "Reward " .. tostring(locked.unlockAt))
end)

Harness.test("view: the word track never reaches the player", function()
	for _, slot in Loadout.slots do
		for _, card in LoadoutView.cards(state(0), slot) do
			Harness.truthy(string.find(string.lower(card.status), "track") == nil)
			Harness.truthy(string.find(string.lower(card.desc), "track") == nil)
		end
	end
end)

Harness.test("view: a locked pick is not shown as worn", function()
	local cards =
		LoadoutView.cards(state(0, { outfit = "spark", gun = "sleek", slide = "std" }), "outfit")
	for _, c in cards do
		Harness.truthy(not c.equipped, c.id)
	end
end)

Harness.test("view: step wraps both ways", function()
	Harness.eq(LoadoutView.step(1, -1, 4), 4)
	Harness.eq(LoadoutView.step(4, 1, 4), 1)
	Harness.eq(LoadoutView.step(2, 1, 4), 3)
	Harness.eq(LoadoutView.step(1, 1, 0), 1)
end)

Harness.test("view: summary names what you wear", function()
	local rows = LoadoutView.summary(state(0))
	Harness.eq(rows[1].name, "Runner")
	Harness.eq(#rows, #Loadout.slots)
end)

-- ===== lobby layout =====

Harness.test("lobby: carter's locked size", function()
	Harness.near(LobbyLayout.width, 260, 0.01)
	Harness.near(LobbyLayout.depth, 182, 0.01)
end)

Harness.test("lobby: four stations, all inside the plaza and far from the arena", function()
	Harness.eq(#LobbyLayout.stations, 4)
	for _, id in { "loadout", "play", "settings", "rewards" } do
		local s = LobbyLayout.station(id)
		Harness.truthy(s ~= nil, id)
		local st = s :: LobbyLayout.Station
		Harness.truthy(st.pad.x > 0 and st.pad.x < LobbyLayout.width, id .. " pad x")
		Harness.truthy(st.pad.z > 0 and st.pad.z < LobbyLayout.depth, id .. " pad z")
	end
	-- The arena is a square around (centerX, centerZ); the lobby must be well clear of it.
	local half = Config.Arena.size / 2 + LobbyLayout.width / 2
	Harness.truthy(math.abs(LobbyLayout.origin.x - Config.Arena.centerX) > half + 200)
end)

Harness.test("lobby: every walk from the start is short on a phone (3 to 7 seconds)", function()
	local speed = Config.Movement.walkSpeed
	for _, s in LobbyLayout.stations do
		local t = LobbyLayout.walkSeconds(
			LobbyLayout.spawn.x,
			LobbyLayout.spawn.z,
			s.pad.x,
			s.pad.z,
			speed
		)
		Harness.truthy(t >= 3 and t <= 7, `{s.id} walk is {t} s`)
	end
end)

Harness.test("lobby: stationAt finds the pad you stand on and nothing else", function()
	for _, s in LobbyLayout.stations do
		local wx, wz = LobbyLayout.toWorld(s.pad.x, s.pad.z)
		Harness.eq(LobbyLayout.stationAt(wx, wz), s.id)
		-- just outside the trigger circle
		local out = s.pad.radius * LobbyLayout.padTriggerShare + 1
		Harness.eq(LobbyLayout.stationAt(wx + out, wz), nil, s.id .. " edge")
	end
	local sx, sz = LobbyLayout.toWorld(LobbyLayout.spawn.x, LobbyLayout.spawn.z)
	Harness.eq(LobbyLayout.stationAt(sx, sz), nil, "the start is not a pad")
end)

Harness.test("lobby: pads do not overlap each other or sit on a building", function()
	local pads = LobbyLayout.stations
	for i = 1, #pads do
		for j = i + 1, #pads do
			local a, b = pads[i].pad, pads[j].pad
			local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
			Harness.truthy(d > a.radius + b.radius, pads[i].id .. " vs " .. pads[j].id)
		end
	end
	for _, s in pads do
		local boxes: { { number } } = {}
		for _, o in pads do
			if o.box then
				table.insert(boxes, o.box)
			end
			if o.pillars then
				for _, p in o.pillars do
					table.insert(boxes, p)
				end
			end
		end
		for _, d in LobbyLayout.decor do
			if d.box then
				table.insert(boxes, d.box)
			end
		end
		for _, b in boxes do
			-- the pad's trigger circle centre must be clear of every box
			local inside = s.pad.x >= b[1]
				and s.pad.x <= b[1] + b[3]
				and s.pad.z >= b[2]
				and s.pad.z <= b[2] + b[4]
			Harness.truthy(not inside, s.id .. " pad is inside a box")
		end
	end
end)

Harness.test("lobby: start spot and leaderboard spot are inside the plaza", function()
	Harness.truthy(LobbyLayout.spawn.x > 0 and LobbyLayout.spawn.x < LobbyLayout.width)
	Harness.truthy(LobbyLayout.spawn.z > 0 and LobbyLayout.spawn.z < LobbyLayout.depth)
	local lb = LobbyLayout.leaderboardSpot
	Harness.truthy(lb.x - lb.width / 2 >= 0 and lb.x + lb.width / 2 <= LobbyLayout.width)
	Harness.truthy(lb.z >= 0 and lb.z < LobbyLayout.depth)
end)

Harness.test("lobby: world conversion round trips", function()
	local wx, wz = LobbyLayout.toWorld(40, 90)
	local x, z = LobbyLayout.fromWorld(wx, wz)
	Harness.near(x, 40, 1e-6)
	Harness.near(z, 90, 1e-6)
	Harness.truthy(LobbyLayout.contains(wx, wz))
	Harness.truthy(not LobbyLayout.contains(0, 0))
end)

-- ===== remotes =====

Harness.test("remotes: the loadout asks are small and rate limited", function()
	local equip = RemoteDefs.byName["LoadoutEquip"]
	Harness.truthy(equip ~= nil and equip.direction == "toServer")
	Harness.eq(#(equip.schema :: any), 2)
	Harness.truthy((equip.rate :: any).perSecond <= 5)
	Harness.truthy(RemoteDefs.byName["LoadoutSync"] ~= nil)
	local state = RemoteDefs.byName["LoadoutState"]
	Harness.truthy(state ~= nil and state.direction == "toClient")
end)
