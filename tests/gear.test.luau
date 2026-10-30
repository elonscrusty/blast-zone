--!strict
-- Piece 48: gear slots. The catalogue is all small trades, the totals stay inside the limits, the stat sheet is
-- tuned on a copy, the three gear tabs ride the normal loadout (server-checked picks, locks, saving shape).
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local Gear = require("../src/shared/Gear")
local Loadout = require("../src/shared/Loadout")
local LoadoutStore = require("../src/shared/LoadoutStore")
local LoadoutView = require("../src/shared/LoadoutView")
local StatBook = require("../src/shared/StatBook")

local function withSpread(spread: number): any
	local cfg: any = table.clone(Config :: any)
	local g: any = table.clone(Config.Gear :: any)
	g.spread = spread
	cfg.Gear = g
	return cfg
end

local function unlocks(level: number): Loadout.Unlocks
	return { level = level }
end

-- ===== catalogue =====

Harness.test("gear: three slots, each with a free Plain and a free first piece", function()
	Harness.eq(#Gear.slots, 3)
	for _, slot in Gear.slots do
		local plain = Gear.find(slot, "plain")
		Harness.truthy(plain ~= nil and plain.unlockAt == nil, slot .. " plain is free")
		Harness.eq(next((plain :: Gear.Piece).perks), nil, slot .. " plain changes nothing")
		local free = 0
		for _, piece in Gear.pieces[slot] do
			if piece.unlockAt == nil and piece.id ~= "plain" then
				free += 1
			end
		end
		Harness.truthy(free >= 1, slot .. " has a free piece to try")
		Harness.truthy(#Gear.pieces[slot] >= 3, slot .. " has choice")
	end
end)

Harness.test("gear: every piece is a trade, never plain power", function()
	for _, slot in Gear.slots do
		for _, piece in Gear.pieces[slot] do
			local net = Gear.net(piece)
			Harness.truthy(net <= 0, `{slot}/{piece.id} is above zero ({net})`)
			Harness.truthy(net >= -Gear.maxLoss, `{slot}/{piece.id} is junk ({net})`)
			local dials, gains, losses = 0, 0, 0
			for dial, amount in piece.perks do
				Harness.truthy(Gear.worth[dial] ~= nil, `{piece.id}: unknown dial {dial}`)
				dials += 1
				if amount > 0 then
					gains += 1
				elseif amount < 0 then
					losses += 1
				end
			end
			if piece.id ~= "plain" then
				Harness.truthy(gains >= 1 and losses >= 1, `{piece.id} must give and take`)
				Harness.truthy(dials <= 3, `{piece.id} has too many dials`)
			end
		end
	end
end)

Harness.test(
	"gear: ids are safe for the remote and unique, rewards stay on the board (1 to 6)",
	function()
		for _, slot in Gear.slots do
			local seen: { [string]: boolean } = {}
			for _, piece in Gear.pieces[slot] do
				Harness.truthy(not seen[piece.id], "duplicate " .. piece.id)
				seen[piece.id] = true
				Harness.truthy(string.match(piece.id, "^[%w_:%-]+$") ~= nil, "bad id " .. piece.id)
				Harness.truthy(#piece.id <= 24)
				Harness.truthy(#slot <= 12)
				if piece.unlockAt then
					Harness.truthy(
						piece.unlockAt >= 1 and piece.unlockAt <= 6,
						piece.id .. " unlockAt"
					)
				end
				Harness.truthy(piece.color >= 0 and piece.color <= 0xFFFFFF)
			end
		end
	end
)

-- ===== totals and limits =====

Harness.test("gear: every outfit of three pieces stays inside the limits at any spread", function()
	for _, spread in { 0.5, 1, 1.5, 3 } do
		local cfg = withSpread(spread)
		for _, h in Gear.pieces.head do
			for _, b in Gear.pieces.body do
				for _, f in Gear.pieces.feet do
					local t = Gear.totals(cfg, { head = h.id, body = b.id, feet = f.id })
					for _, dial in Gear.dials do
						local limit = cfg.Gear.limits[dial]
						Harness.truthy(
							t[dial] >= limit[1] and t[dial] <= limit[2],
							`{dial} out of limits`
						)
					end
				end
			end
		end
	end
end)

Harness.test(
	"gear: no outfit is stronger than going bare (worth adds up to zero or less)",
	function()
		for _, h in Gear.pieces.head do
			for _, b in Gear.pieces.body do
				for _, f in Gear.pieces.feet do
					Harness.truthy(Gear.net(h) + Gear.net(b) + Gear.net(f) <= 0)
				end
			end
		end
	end
)

Harness.test("gear: spread 0 changes nothing, bigger spread makes bigger trades", function()
	local picks = { head = "visor", body = "vest", feet = "spring" }
	local none = Gear.totals(withSpread(0), picks)
	for _, dial in Gear.dials do
		Harness.eq(none[dial], 0, dial)
	end
	local one = Gear.totals(withSpread(1), picks)
	local big = Gear.totals(withSpread(1.5), picks)
	Harness.near(one.health, 10)
	Harness.near(big.health, 15)
	Harness.near(one.speed, -6)
	Harness.near(one.range, 6)
	Harness.near(one.reload, -3)
	Harness.near(one.slideWait, 0.5)
end)

Harness.test("gear: a big spread cannot push past a limit", function()
	local cfg = withSpread(10)
	local t = Gear.totals(cfg, { head = "halo", body = "plate", feet = "skates" })
	Harness.eq(t.health, cfg.Gear.limits.health[2])
	Harness.eq(t.speed, cfg.Gear.limits.speed[1])
	Harness.eq(t.slideReach, cfg.Gear.limits.slideReach[2])
end)

Harness.test("gear: bad picks count as Plain", function()
	local t = Gear.totals(Config, { head = "godmode", body = 7, feet = nil })
	for _, dial in Gear.dials do
		Harness.eq(t[dial], 0)
	end
	local safe = Gear.sanitize({ head = "visor", body = "nope", extra = "x" })
	Harness.eq(safe.head, "visor")
	Harness.eq(safe.body, "plain")
	Harness.eq(safe.feet, "plain")
	Harness.eq((safe :: any).extra, nil)
	Harness.eq(Gear.sanitize("hello").head, "plain")
	Harness.eq(Gear.healthBonus(Config, nil), 0)
end)

Harness.test("gear: health bonus is a whole number read from the picks", function()
	Harness.eq(Gear.healthBonus(Config, { body = "vest" }), 10)
	Harness.eq(Gear.healthBonus(Config, { body = "wire" }), -10)
	Harness.eq(Gear.healthBonus(Config, { head = "halo", body = "plate" }), 24)
	Harness.eq(Gear.healthBonus(withSpread(0.5), { body = "vest" }), 5)
end)

-- ===== the stat sheet =====

Harness.test("gear: tunes a copy of the sheet and never below the Slide floors", function()
	local sheet = StatBook.base(Config)
	local speed, reload, range = sheet.moveSpeed, sheet.firearm.reloadSeconds, sheet.firearm.range
	Gear.applyToSheet(Config, sheet, { head = "echo", body = "wire", feet = "grip" })
	Harness.near(sheet.moveSpeed, speed * (1 + 6 / 100))
	Harness.near(sheet.firearm.reloadSeconds, reload * (1 - 4 / 100))
	Harness.near(sheet.explosive.reloadSeconds, Config.Weapons.Explosive.reloadSeconds * 0.96)
	Harness.near(sheet.firearm.range, range * (1 - 9 / 100))
	Harness.near(sheet.slideCooldown, Config.Slide.cooldown + 1)

	local tiny: any = {
		moveSpeed = 10,
		slideDistance = 5,
		slideCooldown = 1.2,
		firearm = { reloadSeconds = 1, range = 10 },
		explosive = { reloadSeconds = 1, range = 10 },
	}
	Gear.applyToSheet(Config, tiny, { feet = "spring" })
	Harness.near(tiny.slideCooldown, Config.Gear.slideCooldownFloor)
	Gear.applyToSheet(Config, tiny, { feet = "grip" })
	Harness.truthy(tiny.slideDistance >= Config.Gear.slideDistanceFloor)
end)

Harness.test("gear: skates add Slide reach, plain changes nothing", function()
	local a = StatBook.base(Config)
	Gear.applyToSheet(Config, a, { feet = "skates" })
	Harness.near(a.slideDistance, Config.Slide.distance + 3)
	local b = StatBook.base(Config)
	Gear.applyToSheet(Config, b, Gear.defaults)
	local c = StatBook.base(Config)
	Harness.near(b.moveSpeed, c.moveSpeed)
	Harness.near(b.slideCooldown, c.slideCooldown)
	Harness.near(b.firearm.range, c.firearm.range)
end)

Harness.test(
	"gear: through the stat book the shared base is never edited and stacks do not pile up",
	function()
		local book = StatBook.new(Config)
		local shared = StatBook.base(Config)
		book:setProvider(function()
			return shared
		end)
		book:addModifier(function(_, sheet)
			Gear.applyToSheet(Config, sheet, { head = "echo", body = "plate", feet = "skates" })
		end)
		local first = book:get("p1")
		local second = book:get("p1")
		Harness.near(first.moveSpeed, second.moveSpeed)
		Harness.near(first.firearm.range, second.firearm.range)
		Harness.near(shared.moveSpeed, Config.Movement.walkSpeed)
		Harness.near(shared.firearm.range, Config.Weapons.Firearm.range)
		Harness.near(shared.slideDistance, Config.Slide.distance)
	end
)

-- ===== who wears what =====

Harness.test("gear: players wear their picks, bots wear nothing", function()
	local function pick(userId: number): any
		return if userId == 7 then { head = "visor", body = "vest", feet = "grip" } else nil
	end
	local mine = Gear.of("p7", pick)
	Harness.eq(mine.head, "visor")
	Harness.eq(mine.feet, "grip")
	Harness.eq(Gear.of("p8", pick).body, "plain")
	Harness.eq(Gear.of("b3", pick).head, "plain")
	Harness.eq(Gear.of("p7", nil).head, "plain")
end)

-- ===== the loadout slots =====

Harness.test("loadout: head, body and feet are slots with Plain as the default", function()
	for _, slot in Gear.slots do
		Harness.truthy(Loadout.isSlot(slot))
		Harness.eq((Loadout.defaults :: any)[slot], "plain")
		Harness.eq(#Loadout.items[slot], #Gear.pieces[slot])
		Harness.eq(Loadout.slotNames[slot], Gear.slotNames[slot])
	end
	local sel = Loadout.sanitize(nil, unlocks(0))
	Harness.eq(sel.head, "plain")
	Harness.eq(sel.body, "plain")
	Harness.eq(sel.feet, "plain")
end)

Harness.test("loadout: gear is checked like every other pick (slot, item, unlock)", function()
	Harness.eq(Loadout.equipProblem("head", "visor", unlocks(0)), nil)
	Harness.eq(Loadout.equipProblem("head", "halo", unlocks(0)), "locked")
	Harness.eq(Loadout.equipProblem("head", "halo", unlocks(5)), nil)
	Harness.eq(Loadout.equipProblem("body", "visor", unlocks(6)), "unknown_item") -- a head piece is not a body piece
	Harness.eq(Loadout.equipProblem("feet", 3, unlocks(6)), "unknown_item")
	Harness.eq(Loadout.equipProblem("hat", "visor", unlocks(6)), "unknown_slot")
	local sel = Loadout.sanitize({ head = "halo", body = "vest", feet = "skates" }, unlocks(0))
	Harness.eq(sel.head, "plain") -- locked
	Harness.eq(sel.body, "vest")
	Harness.eq(sel.feet, "plain") -- locked
end)

Harness.test("loadout: the store keeps gear picks and refuses locked ones", function()
	local saved: { [string]: string } = {}
	local level = 0
	local store = LoadoutStore.new({
		read = function()
			return saved
		end,
		write = function(_, slot, id)
			saved[slot] = id
			return true
		end,
		unlocks = function()
			return unlocks(level)
		end,
		saved = function()
			return true
		end,
	})
	Harness.truthy(store:equip(1, "body", "vest"))
	Harness.eq(store:get(1).body, "vest")
	Harness.eq(saved.body, "vest")
	local ok, reason = store:equip(1, "feet", "skates")
	Harness.truthy(not ok)
	Harness.eq(reason, "locked")
	level = 6
	Harness.truthy(store:equip(1, "feet", "skates"))
	Harness.eq(Gear.healthBonus(Config, store:get(1)), 10)
end)

Harness.test("loadout view: gear cards print the trade, other cards stay plain", function()
	local state: LoadoutView.State = {
		selection = Loadout.defaults :: any,
		unlocked = Loadout.unlockedIds(unlocks(0)),
		level = 0,
		saved = true,
	}
	for _, slot in Gear.slots do
		local cards = LoadoutView.cards(state, slot)
		Harness.eq(#cards, #Gear.pieces[slot])
		Harness.truthy(cards[1].equipped, slot .. " Plain is worn")
		for _, card in cards do
			if card.id ~= "plain" then
				Harness.truthy(card.detail ~= nil and #(card.detail :: { string }) >= 2, card.id)
			end
		end
	end
	local halo = LoadoutView.cards(state, "head")[4]
	Harness.truthy(halo.locked)
	Harness.eq(halo.status, "Reward 5")
	for _, card in LoadoutView.cards(state, "gun") do
		Harness.eq(card.detail, nil)
	end
end)

Harness.test("gear: card lines show the real numbers", function()
	Harness.eq(table.concat(Gear.lines(Config, "body", "vest"), ", "), "+10 health, -4% speed")
	Harness.eq(
		table.concat(Gear.lines(Config, "head", "visor"), ", "),
		"Reload 3% slower, +6% range"
	)
	Harness.eq(
		table.concat(Gear.lines(Config, "feet", "spring"), ", "),
		"-2% speed, Slide ready 0.5 s sooner"
	)
	Harness.eq(
		table.concat(Gear.lines(Config, "feet", "skates"), ", "),
		"-3% speed, +3 studs Slide"
	)
	Harness.eq(
		table.concat(Gear.lines(withSpread(1.5), "body", "vest"), ", "),
		"+15 health, -6% speed"
	)
	Harness.eq(#Gear.lines(Config, "body", "plain"), 0)
	Harness.eq(#Gear.lines(Config, "body", "nope"), 0)
end)
