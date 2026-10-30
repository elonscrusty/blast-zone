--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local LootRules = require("../src/shared/Loot/LootRules")
local Bindings = require("../src/client/Controls/Bindings")
local Layout = require("../src/client/Hud/Layout")
local RemoteDefs = require("../src/shared/RemoteDefs")

Harness.test("loot: a pack goes in until the bag is full", function()
	local n, ok = LootRules.addPack(0, 3)
	Harness.eq(n, 1)
	Harness.eq(ok, true)
	local n2, ok2 = LootRules.addPack(3, 3)
	Harness.eq(n2, 3)
	Harness.eq(ok2, false)
end)

Harness.test("loot: using a pack needs a pack, a hurt body, and a ready button", function()
	local function use(count: number, hp: number, now: number, readyAt: number)
		local ok, why = LootRules.canUse(count, hp, 100, now, readyAt)
		return ok, why
	end
	Harness.eq((use(0, 50, 10, 0)), false)
	Harness.eq(select(2, use(0, 50, 10, 0)), "none")
	Harness.eq(select(2, use(2, 0, 10, 0)), "down")
	Harness.eq(select(2, use(2, 100, 10, 0)), "full")
	Harness.eq(select(2, use(2, 60, 10, 11)), "cooling")
	Harness.eq((use(2, 60, 10, 10)), true)
	Harness.eq(select(2, use(2, 60, 10, 10)), nil)
end)

Harness.test("loot: spots are never closer than the separation and never repeat", function()
	local cands = {}
	for i = 1, 20 do
		table.insert(cands, { x = i * 5, z = 0 })
	end
	local seed = 0
	local function roll()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local out = LootRules.pickSpots(cands, 6, 18, roll)
	Harness.truthy(#out >= 2 and #out <= 6, `took {#out}`)
	for i = 1, #out do
		for j = i + 1, #out do
			Harness.truthy(math.abs(out[i].x - out[j].x) >= 18, "two spots too close")
		end
	end
end)

Harness.test("loot: pickSpots stays away from spots already taken", function()
	local cands = { { x = 0, z = 0 }, { x = 100, z = 0 } }
	local out = LootRules.pickSpots(cands, 2, 30, function()
		return 0
	end, { { x = 2, z = 2 } })
	Harness.eq(#out, 1)
	Harness.eq(out[1].x, 100)
end)

Harness.test("loot: asking for more spots than exist gives what fits", function()
	local out = LootRules.pickSpots({ { x = 0, z = 0 } }, 5, 10, function()
		return 0.5
	end)
	Harness.eq(#out, 1)
	Harness.eq(#LootRules.pickSpots({}, 3, 10, function()
		return 0
	end), 0)
end)

Harness.test("loot: floor guns follow the weights and every gun exists", function()
	for _, id in Config.Loot.floorGuns.order do
		Harness.truthy(Config.Weapons.Guns[id] ~= nil, id .. " is not a gun")
	end
	Harness.eq(LootRules.pickGun(Config, 0), "breaker")
	Harness.eq(LootRules.pickGun(Config, 0.5), "hornet")
	Harness.eq(LootRules.pickGun(Config, 0.99), "longline")
	local heavy = {
		Loot = { floorGuns = { order = { "a", "b" }, weights = { a = 0, b = 2 } } },
	}
	Harness.eq(LootRules.pickGun(heavy, 0), "b")
	local none = { Loot = { floorGuns = { order = { "a" }, weights = { a = 0 } } } }
	Harness.eq(LootRules.pickGun(none, 0.3), nil)
end)

Harness.test("loot: ring points sit the offset away from the marker", function()
	for i = 1, 8 do
		local s = LootRules.ringPoint(10, -4, 7, i, 8, 0.3)
		Harness.near(math.sqrt((s.x - 10) ^ 2 + (s.z + 4) ^ 2), 7, 1e-9)
	end
end)

Harness.test("loot: heal numbers make sense", function()
	local h = Config.Loot.heal
	Harness.truthy(
		h.amount > 0 and h.amount < Config.Health.max,
		"one pack must not be a full heal"
	)
	Harness.truthy(h.carryMax >= 1)
	Harness.truthy(h.floorPacks <= h.maxOnFloor)
	Harness.truthy(h.useCooldownSeconds > 0)
	Harness.truthy(h.botUseBelowFraction > 0 and h.botUseBelowFraction < 1)
end)

Harness.test("loot: the heal key, pad button and touch button are free and unique", function()
	local heal = Bindings.actions.heal
	Harness.eq(heal.touch, "heal")
	Harness.eq(Bindings.actionFor("F"), "heal")
	Harness.eq(Bindings.actionFor("DPadDown"), "heal")
	local seen: { [string]: string } = {}
	for _, name in Bindings.actionOrder do
		local b = Bindings.actions[name]
		for _, code in b.keyboard do
			Harness.eq(seen[code], nil, `{code} is used twice`)
			seen[code] = name
		end
		for _, code in b.gamepad do
			Harness.eq(seen[code], nil, `{code} is used twice`)
			seen[code] = name
		end
	end
end)

Harness.test("loot: the heal button is a real touch target", function()
	local r = Layout.regions.heal
	Harness.truthy(r.w >= Layout.MIN_TOUCH and r.h >= Layout.MIN_TOUCH)
	Harness.truthy(table.find(Layout.touchTargets, "heal") ~= nil)
	Harness.eq(Layout.circles.heal, true)
end)

Harness.test("loot: the heal remotes exist, and the request is rate limited", function()
	local ask = RemoteDefs.byName.UseHealRequest
	Harness.eq(ask.direction, "toServer")
	Harness.truthy(ask.rate ~= nil and ask.rate.perSecond <= 5)
	Harness.eq(RemoteDefs.byName.LootState.direction, "toClient")
end)
