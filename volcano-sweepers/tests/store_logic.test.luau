--!strict
local Harness = require("./harness")
local StoreLogic = require("../src/shared/Client/StoreLogic")

Harness.test("store merge: keys replace, unchanged keys are not changes", function()
	local view: { [string]: any } = { coins = 5, derived = { reach = 7, interval = 0.4 } }
	local changes = StoreLogic.merge(view, {
		coins = 9,
		derived = { reach = 7, interval = 0.4 }, -- deeply equal: no change
		carried = 3,
	})
	Harness.eq(#changes, 2)
	Harness.eq(view.coins, 9)
	Harness.eq(view.carried, 3)
	local byKey: { [string]: StoreLogic.Change } = {}
	for _, c in changes do
		byKey[c.key] = c
	end
	Harness.eq((byKey.coins :: StoreLogic.Change).old, 5)
	Harness.eq((byKey.coins :: StoreLogic.Change).new, 9)
	Harness.eq(byKey.derived, nil)
end)

Harness.test("store merge: a table value replaces, it is not merged deeper", function()
	local view: { [string]: any } = { settings = { music = true, sfx = true } }
	StoreLogic.merge(view, { settings = { music = false } })
	Harness.eq(view.settings.music, false)
	Harness.eq(view.settings.sfx, nil)
end)

Harness.test("store merge: junk is ignored", function()
	local view: { [string]: any } = { coins = 1 }
	Harness.eq(#StoreLogic.merge(view, nil), 0)
	Harness.eq(#StoreLogic.merge(view, "hello"), 0)
	Harness.eq(#StoreLogic.merge(view, { [1] = "x", [2.5] = "y" }), 0)
	Harness.eq(#StoreLogic.merge(view, { coins = 0 / 0 }), 0)
	Harness.eq(view.coins, 1)
end)

Harness.test("store: subscribe calls once now if the value exists, then on change only", function()
	local store = StoreLogic.new()
	local seen: { string } = {}
	store.apply({ coins = 10 })
	local off = store.subscribe("coins", function(v, old)
		table.insert(seen, `{tostring(v)}/{tostring(old)}`)
	end)
	Harness.eq(#seen, 1)
	Harness.eq(seen[1], "10/nil")
	store.apply({ coins = 10 }) -- same value: silent
	Harness.eq(#seen, 1)
	store.apply({ coins = 12 })
	Harness.eq(seen[2], "12/10")
	store.apply({ carried = 4 }) -- other key: silent
	Harness.eq(#seen, 2)
	off()
	store.apply({ coins = 99 })
	Harness.eq(#seen, 2)
end)

Harness.test("store: subscribe on a missing key waits for the first value", function()
	local store = StoreLogic.new()
	local calls = 0
	store.subscribe("tool", function()
		calls += 1
	end)
	Harness.eq(calls, 0)
	store.apply({ tool = "twig_broom" })
	Harness.eq(calls, 1)
end)

Harness.test("store: ready flips on the first payload and onReady fires once", function()
	local store = StoreLogic.new()
	local fired = 0
	Harness.eq(store.ready, false)
	store.onReady(function()
		fired += 1
	end)
	Harness.eq(fired, 0)
	store.apply({ coins = 1 })
	Harness.eq(store.ready, true)
	Harness.eq(fired, 1)
	store.apply({ coins = 2 })
	Harness.eq(fired, 1)
	local late = 0
	store.onReady(function()
		late += 1
	end)
	Harness.eq(late, 1, "late onReady runs now")
end)

Harness.test("store: a throwing listener cannot stop the others or the merge", function()
	local store = StoreLogic.new()
	local ok = 0
	store.subscribe("coins", function()
		error("boom")
	end)
	store.subscribe("coins", function()
		ok += 1
	end)
	store.apply({ coins = 5 })
	Harness.eq(ok, 1)
	Harness.eq(store.get("coins"), 5)
end)

Harness.test("store: a listener may disconnect itself while being notified", function()
	local store = StoreLogic.new()
	local a, b = 0, 0
	local offA: () -> () = function() end
	offA = store.subscribe("x", function()
		a += 1
		offA()
	end)
	store.subscribe("x", function()
		b += 1
	end)
	store.apply({ x = 1 })
	store.apply({ x = 2 })
	Harness.eq(a, 1)
	Harness.eq(b, 2)
end)

Harness.test("store: subscribeAll sees every change", function()
	local store = StoreLogic.new()
	local keys: { string } = {}
	store.subscribeAll(function(key)
		table.insert(keys, key)
	end)
	store.apply({ a = 1, b = 2 })
	Harness.eq(#keys, 2)
end)

Harness.test("store: view is the same live table", function()
	local store = StoreLogic.new()
	local v = store.view
	store.apply({ coins = 3 })
	Harness.eq(v.coins, 3)
	Harness.eq(store.view, v)
end)

Harness.test("helpers: sweepInterval is clamped and tolerates a missing view", function()
	Harness.near(StoreLogic.sweepInterval({}), 0.4)
	Harness.near(StoreLogic.sweepInterval({ derived = { interval = 0.26 } }), 0.26)
	Harness.near(StoreLogic.sweepInterval({ derived = { interval = 0.01 } }), 0.1)
	Harness.near(StoreLogic.sweepInterval({ derived = { interval = "fast" } }), 0.4)
	Harness.near(StoreLogic.sweepInterval({ derived = { interval = 0 / 0 } }), 0.4)
end)

Harness.test("helpers: backpackFull / fraction", function()
	Harness.eq(StoreLogic.backpackFull({}), false)
	Harness.eq(StoreLogic.backpackFull({ derived = { capacity = 30 }, carried = 29 }), false)
	Harness.eq(StoreLogic.backpackFull({ derived = { capacity = 30 }, carried = 30 }), true)
	Harness.eq(StoreLogic.backpackFull({ derived = { capacity = 30 }, carried = 99 }), true)
	Harness.eq(StoreLogic.backpackFull({ derived = { capacity = 0 }, carried = 5 }), false)
	Harness.near(StoreLogic.backpackFraction({ derived = { capacity = 40 }, carried = 10 }), 0.25)
	Harness.near(StoreLogic.backpackFraction({ derived = { capacity = 40 }, carried = 400 }), 1)
	Harness.near(StoreLogic.backpackFraction({}), 0)
end)

Harness.test("helpers: zones", function()
	local view: { [string]: any } = { zones = { ["2"] = true, ["3"] = false } }
	Harness.eq(StoreLogic.zoneUnlocked(view, 1), true)
	Harness.eq(StoreLogic.zoneUnlocked(view, 2), true)
	Harness.eq(StoreLogic.zoneUnlocked(view, 3), false)
	Harness.eq(StoreLogic.zoneUnlocked(view, 5), false)
	Harness.eq(StoreLogic.zoneUnlocked({}, 1), true)
	local set = StoreLogic.unlockedSet(view, 5)
	Harness.eq(set[1], true)
	Harness.eq(set[2], true)
	Harness.eq(set[3], nil)
end)

Harness.test("helpers: setting default", function()
	Harness.eq(StoreLogic.setting({}, "shake", true), true)
	Harness.eq(StoreLogic.setting({ settings = { shake = false } }, "shake", true), false)
	Harness.eq(StoreLogic.setting({ settings = { shake = "no" } }, "shake", true), true)
end)

Harness.test("helpers: formatNumber", function()
	Harness.eq(StoreLogic.formatNumber(0), "0")
	Harness.eq(StoreLogic.formatNumber(999), "999")
	Harness.eq(StoreLogic.formatNumber(1000), "1K")
	Harness.eq(StoreLogic.formatNumber(1234), "1.2K")
	Harness.eq(StoreLogic.formatNumber(3400000), "3.4M")
	Harness.eq(StoreLogic.formatNumber(999999), "1M")
	Harness.eq(StoreLogic.formatNumber(-1500), "-1.5K")
	Harness.eq(StoreLogic.formatNumber(0 / 0), "0")
	Harness.eq(StoreLogic.formatNumber(2.4e9), "2.4B")
end)
