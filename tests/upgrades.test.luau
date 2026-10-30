--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local StatBook = require("../src/shared/StatBook")
local UpgradeDefs = require("../src/shared/UpgradeDefs")
local RunUpgrades = require("../src/server/Upgrades/RunUpgrades")

local function makeCtx(hasExplosive: boolean): any
	return {
		base = StatBook.base(Config),
		hasExplosive = hasExplosive,
		weaponNames = { firearm = "Volt Pistol", explosive = "Arc Mortar" },
	}
end

-- A rand that walks through a fixed list, then repeats the last value.
local function seq(values: { number }): () -> number
	local i = 0
	return function()
		i += 1
		return values[math.min(i, #values)]
	end
end

local function ids(list: { any }): { string }
	local out = {}
	for _, u in list do
		table.insert(out, u.id)
	end
	return out
end

-- ===== catalogue =====

Harness.test("catalogue: ids are unique, numbers sane, links point at real upgrades", function()
	local seen: { [string]: boolean } = {}
	local base = StatBook.base(Config) :: any
	for _, u in UpgradeDefs.list do
		Harness.eq(seen[u.id], nil, "duplicate id " .. u.id)
		seen[u.id] = true
		Harness.truthy(u.weight > 0, u.id .. " weight")
		Harness.truthy(u.maxStacks >= 1, u.id .. " maxStacks")
		Harness.truthy(#u.name > 0 and #u.description > 0 and #u.feedback > 0, u.id .. " text")
		Harness.truthy(#u.effects > 0, u.id .. " has effects")
		for _, e in u.effects do
			for _, g in e.groups do
				local tbl = if g == "self" then base else base[g]
				Harness.truthy(tbl ~= nil and tbl[e.stat] ~= nil, `{u.id}: no stat {g}.{e.stat}`)
			end
		end
		for reqId in u.requires or {} do
			Harness.truthy(UpgradeDefs.byId[reqId] ~= nil, u.id .. " requires unknown " .. reqId)
		end
		for _, other in u.incompatible or {} do
			Harness.truthy(
				UpgradeDefs.byId[other] ~= nil,
				u.id .. " incompatible unknown " .. other
			)
		end
	end
	Harness.eq(#UpgradeDefs.list, 14)
end)

-- ===== effective stats =====

Harness.test("resolve: no upgrades gives the base numbers and never edits the base", function()
	local base = StatBook.base(Config)
	local before = base.firearm.reloadSeconds
	local sheet = UpgradeDefs.resolve(base, {})
	Harness.eq(sheet.firearm.reloadSeconds, before)
	sheet.firearm.reloadSeconds = 99
	Harness.eq(base.firearm.reloadSeconds, before, "base untouched")
end)

Harness.test("resolve: stacks come from base, not from a running value", function()
	local base = StatBook.base(Config)
	Harness.near(UpgradeDefs.resolve(base, { quick_hands = 1 }).firearm.reloadSeconds, 1.2 * 0.8)
	Harness.near(
		UpgradeDefs.resolve(base, { quick_hands = 3 }).firearm.reloadSeconds,
		1.2 * 0.8 ^ 3
	)
	-- same stacks, same answer, however many times we ask
	local a = UpgradeDefs.resolve(base, { quick_hands = 2 }).firearm.reloadSeconds
	local b = UpgradeDefs.resolve(base, { quick_hands = 2 }).firearm.reloadSeconds
	Harness.eq(a, b)
end)

Harness.test("resolve: add, pct and mult combine in one fixed order", function()
	local base = StatBook.base(Config)
	-- damage: base 10, hard_rounds x4 = +60%, twin_shot = x0.7 -> 10 * 1.6 * 0.7
	local sheet = UpgradeDefs.resolve(base, { hard_rounds = 4, twin_shot = 1 })
	Harness.near(sheet.firearm.damage, 10 * 1.6 * 0.7)
	Harness.eq(sheet.firearm.pellets, 2)
	Harness.near(sheet.firearm.spreadDegrees, 4)
	-- spread: (0 + 4 + 6) after twin_shot and fan_fire
	Harness.near(
		UpgradeDefs.resolve(base, { twin_shot = 1, fan_fire = 1 }).firearm.spreadDegrees,
		10
	)
end)

Harness.test("resolve: a tradeoff upgrade costs damage per bullet but adds bullets", function()
	local base = StatBook.base(Config)
	local sheet = UpgradeDefs.resolve(base, { twin_shot = 1 })
	Harness.truthy(sheet.firearm.damage < base.firearm.damage, "each bullet weaker")
	Harness.truthy(
		sheet.firearm.pellets * sheet.firearm.damage > base.firearm.damage,
		"more total damage"
	)
end)

Harness.test("resolve: stack counts above the maximum and unknown ids are ignored", function()
	local base = StatBook.base(Config)
	local capped = UpgradeDefs.resolve(base, { light_feet = 99, not_real = 5 })
	Harness.near(capped.moveSpeed, 20 * (1 + 0.08 * 3))
	Harness.near(UpgradeDefs.resolve(base, { light_feet = 3 }).moveSpeed, capped.moveSpeed)
	Harness.eq(UpgradeDefs.resolve(base, { light_feet = -2 }).moveSpeed, 20)
end)

Harness.test("resolve: hard limits hold even with a huge stack table", function()
	local base = StatBook.base(Config)
	local all: { [string]: number } = {}
	for _, u in UpgradeDefs.list do
		all[u.id] = 1000
	end
	local sheet = UpgradeDefs.resolve(base, all)
	Harness.truthy(
		sheet.moveSpeed <= 20 * Config.Movement.maxSpeedUpgradeMultiplier + 1e-9,
		"speed cap"
	)
	Harness.truthy(sheet.slideCooldown >= 1.5, "slide cooldown floor")
	Harness.truthy(sheet.firearm.reloadSeconds >= 0.3, "reload floor")
	Harness.truthy(sheet.firearm.damage <= 10 * 1.75 + 1e-9, "damage cap")
	Harness.truthy(sheet.firearm.pellets <= 5, "bullet cap")
	Harness.truthy(sheet.firearm.range <= 70 * 1.6 + 1e-9, "range cap")
	Harness.truthy(sheet.explosive.radius <= 9 * 1.8 + 1e-9, "blast cap")
end)

Harness.test("resolve: a limit really clamps (tightened for the test)", function()
	local limits = UpgradeDefs.limits :: any
	local saved = limits["self.slideCooldown"]
	limits["self.slideCooldown"] = { min = 3.5 }
	local sheet = UpgradeDefs.resolve(StatBook.base(Config), { slick_soles = 3 })
	limits["self.slideCooldown"] = saved
	Harness.near(sheet.slideCooldown, 3.5)
end)

Harness.test("resolve: slide cooldown drops by one second per stack", function()
	local base = StatBook.base(Config)
	Harness.near(UpgradeDefs.resolve(base, { slick_soles = 2 }).slideCooldown, 3)
end)

Harness.test("resolve: reload and damage upgrades reach both weapons", function()
	local sheet = UpgradeDefs.resolve(StatBook.base(Config), { quick_hands = 1, hard_rounds = 1 })
	Harness.near(sheet.explosive.reloadSeconds, 2.4 * 0.8)
	Harness.near(sheet.explosive.damage, 45 * 1.15)
	Harness.near(sheet.firearm.damage, 10 * 1.15)
end)

-- ===== eligibility =====

Harness.test("canOffer: a maxed upgrade is not offered", function()
	local ok, why = UpgradeDefs.canOffer("twin_shot", { twin_shot = 1 }, makeCtx(false))
	Harness.eq(ok, false)
	Harness.eq(why, "maxed")
end)

Harness.test("canOffer: prerequisite must be owned first", function()
	local ctx = makeCtx(false)
	local ok, why = UpgradeDefs.canOffer("fan_fire", {}, ctx)
	Harness.eq(ok, false)
	Harness.eq(why, "needs_prereq")
	Harness.eq((UpgradeDefs.canOffer("fan_fire", { twin_shot = 1 }, ctx)), true)
end)

Harness.test("canOffer: incompatible upgrades never mix, in either order", function()
	local ctx = makeCtx(false)
	local _, why1 = UpgradeDefs.canOffer("steady_aim", { twin_shot = 1, fan_fire = 1 }, ctx)
	Harness.eq(why1, "incompatible")
	local _, why2 = UpgradeDefs.canOffer("fan_fire", { twin_shot = 1, steady_aim = 1 }, ctx)
	Harness.eq(why2, "incompatible")
end)

Harness.test("canOffer: blast upgrade only when the mortar is in the build", function()
	local ok, why = UpgradeDefs.canOffer("bigger_boom", {}, makeCtx(false))
	Harness.eq(ok, false)
	Harness.eq(why, "no_effect")
	Harness.eq((UpgradeDefs.canOffer("bigger_boom", {}, makeCtx(true))), true)
end)

Harness.test("canOffer: an upgrade that would change nothing is not offered", function()
	local ctx = makeCtx(false)
	-- the pistol starts with no spread, so Steady Aim does nothing until Twin Shot adds some
	local ok, why = UpgradeDefs.canOffer("steady_aim", {}, ctx)
	Harness.eq(ok, false)
	Harness.eq(why, "no_effect")
	Harness.eq((UpgradeDefs.canOffer("steady_aim", { twin_shot = 1 }, ctx)), true)
end)

Harness.test("canOffer: an unknown id is refused", function()
	local ok, why = UpgradeDefs.canOffer("free_robux", {}, makeCtx(false))
	Harness.eq(ok, false)
	Harness.eq(why, "unknown")
end)

-- ===== rolling offers =====

Harness.test("roll: three different, eligible upgrades", function()
	local ctx = makeCtx(false)
	local picks = UpgradeDefs.roll({}, ctx, seq({ 0.1, 0.5, 0.9 }), 3)
	Harness.eq(#picks, 3)
	local seen: { [string]: boolean } = {}
	for _, id in picks do
		Harness.eq(seen[id], nil, "duplicate " .. id)
		seen[id] = true
		Harness.eq((UpgradeDefs.canOffer(id, {}, ctx)), true, id .. " eligible")
	end
end)

Harness.test("roll: weight decides, low roll takes the first and high roll the last", function()
	local ctx = makeCtx(false)
	local pool = ids(UpgradeDefs.eligible({}, ctx))
	Harness.eq(UpgradeDefs.roll({}, ctx, seq({ 0 }), 1)[1], pool[1])
	Harness.eq(UpgradeDefs.roll({}, ctx, seq({ 0.999999 }), 1)[1], pool[#pool])
end)

Harness.test(
	"roll: gives fewer than three when fewer are eligible, and none when none are",
	function()
		local ctx = makeCtx(false)
		local nearlyAll: { [string]: number } = {}
		for _, u in UpgradeDefs.list do
			nearlyAll[u.id] = u.maxStacks
		end
		Harness.eq(#UpgradeDefs.roll(nearlyAll, ctx, seq({ 0.5 }), 3), 0)
		nearlyAll.hard_rounds = 0
		nearlyAll.quick_hands = 0
		local two = UpgradeDefs.roll(nearlyAll, ctx, seq({ 0.5 }), 3)
		Harness.eq(#two, 2)
	end
)

Harness.test("roll: never offers what the build cannot use", function()
	local ctx = makeCtx(false)
	for i = 0, 40 do
		local picks = UpgradeDefs.roll({}, ctx, seq({ (i % 10) / 10, 0.37, 0.81 }), 3)
		for _, id in picks do
			Harness.truthy(id ~= "bigger_boom" and id ~= "steady_aim" and id ~= "fan_fire", id)
		end
	end
end)

-- ===== card text =====

Harness.test("option: says the real numbers and the stack count", function()
	local opt = UpgradeDefs.option("quick_hands", { quick_hands = 1 }, makeCtx(false))
	Harness.eq(opt.stacks, 1)
	Harness.eq(opt.maxStacks, 3)
	Harness.eq(opt.change, "Reload 0.96s → 0.77s")
end)

Harness.test("option: first stack text, slide and bullets", function()
	local ctx = makeCtx(false)
	Harness.eq(UpgradeDefs.option("quick_hands", {}, ctx).change, "Reload 1.2s → 0.96s")
	Harness.eq(UpgradeDefs.option("slick_soles", {}, ctx).change, "Slide wait 5s → 4s")
	Harness.truthy(
		string.find(
			UpgradeDefs.option("twin_shot", {}, ctx).change or "",
			"Bullets 1 → 2",
			1,
			true
		)
	)
end)

Harness.test("option: with the mortar on, each weapon is named", function()
	local text = UpgradeDefs.option("quick_hands", {}, makeCtx(true)).change or ""
	Harness.truthy(string.find(text, "Volt Pistol Reload 1.2s → 0.96s", 1, true), text)
	Harness.truthy(string.find(text, "Arc Mortar Reload 2.4s → 1.92s", 1, true), text)
end)

-- ===== run state and validation =====

local function newRun(t: { now: number }, rand: (() -> number)?, hasExplosive: boolean?): (any, any)
	local ctx = makeCtx(hasExplosive == true)
	local run = RunUpgrades.new(UpgradeDefs, ctx, rand or seq({ 0.2, 0.5, 0.8 }), function()
		return t.now
	end, Config.Upgrades.selectionLockSeconds)
	return run, ctx
end

Harness.test("run: an offer has three options and a match-stamped id", function()
	local t = { now = 0 }
	local run = newRun(t)
	run:enroll("p1", 4)
	local offer = run:issue("p1")
	Harness.eq(#offer.options, Config.Upgrades.offerSize)
	Harness.eq(offer.matchId, 4)
	Harness.eq(offer.offerId, "u4-p1-1")
end)

Harness.test("run: one offer at a time", function()
	local t = { now = 0 }
	local run = newRun(t)
	run:enroll("p1", 1)
	run:issue("p1")
	local second, why = run:issue("p1")
	Harness.eq(second, nil)
	Harness.eq(why, "active_exists")
end)

Harness.test("run: a good pick stacks the upgrade and updates the numbers", function()
	local t = { now = 0 }
	local run = newRun(t)
	run:enroll("p1", 1)
	local offer = run:issue("p1")
	t.now = 1
	local pickedId = offer.options[2].id
	local res = run:choose("p1", 1, offer.offerId, 2)
	Harness.eq(res.ok, true)
	Harness.eq(res.upgradeId, pickedId)
	Harness.eq(res.stacks, 1)
	Harness.eq(run:stacksOf("p1")[pickedId], 1)
	local sheet = run:sheet("p1")
	Harness.truthy(sheet ~= nil)
end)

Harness.test("run: picking twice from one offer only counts once", function()
	local t = { now = 0 }
	local run = newRun(t)
	run:enroll("p1", 1)
	local offer = run:issue("p1")
	t.now = 1
	Harness.eq(run:choose("p1", 1, offer.offerId, 1).ok, true)
	local again = run:choose("p1", 1, offer.offerId, 1)
	Harness.eq(again.ok, false)
	Harness.eq(again.reason, "no_offer")
	local total = 0
	for _, n in run:stacksOf("p1") do
		total += n
	end
	Harness.eq(total, 1)
end)

Harness.test("run: tapping right after a new card appears is ignored", function()
	local t = { now = 10 }
	local run = newRun(t)
	run:enroll("p1", 1)
	local offer = run:issue("p1")
	t.now = 10.1
	local early = run:choose("p1", 1, offer.offerId, 1)
	Harness.eq(early.ok, false)
	Harness.eq(early.reason, "too_fast")
	t.now = 10.5
	Harness.eq(run:choose("p1", 1, offer.offerId, 1).ok, true)
end)

Harness.test("run: bad offer ids and bad indexes are refused", function()
	local t = { now = 0 }
	local run = newRun(t)
	run:enroll("p1", 1)
	local offer = run:issue("p1")
	t.now = 1
	Harness.eq(run:choose("p1", 1, "u1-p1-99", 1).reason, "stale_offer")
	Harness.eq(run:choose("p1", 1, offer.offerId, 0).reason, "bad_option")
	Harness.eq(run:choose("p1", 1, offer.offerId, 4).reason, "bad_option")
	Harness.eq(run:choose("p1", 1, offer.offerId, 1.5).reason, "bad_option")
	Harness.eq(run:choose("p1", 1, offer.offerId, (0 / 0) :: number).reason, "bad_option")
	Harness.eq(run:choose("p1", 1, offer.offerId, "1" :: any).reason, "bad_option")
	Harness.eq(run:choose("p9", 1, offer.offerId, 1).reason, "unknown")
	Harness.eq(run:choose("p1", 2, offer.offerId, 1).reason, "stale_match")
	Harness.eq(run:hasActive("p1"), true, "still open after refusals")
end)

Harness.test("run: one player cannot take another player's offer", function()
	local t = { now = 0 }
	local run = newRun(t)
	run:enroll("p1", 1)
	run:enroll("p2", 1)
	local offer1 = run:issue("p1")
	run:issue("p2")
	t.now = 1
	Harness.eq(run:choose("p2", 1, offer1.offerId, 1).reason, "stale_offer")
	Harness.eq(next(run:stacksOf("p2")), nil)
end)

Harness.test(
	"run: an eliminated player loses the open offer and cannot pick or get more",
	function()
		local t = { now = 0 }
		local run = newRun(t)
		run:enroll("p1", 1)
		local offer = run:issue("p1")
		Harness.eq(run:eliminate("p1"), true, "had an offer open")
		t.now = 1
		Harness.eq(run:choose("p1", 1, offer.offerId, 1).reason, "eliminated")
		local nope, why = run:issue("p1")
		Harness.eq(nope, nil)
		Harness.eq(why, "eliminated")
		Harness.eq(run:eliminate("p1"), false, "second time: nothing to close")
	end
)

Harness.test("run: a new match starts everyone clean, and old offers cannot land", function()
	local t = { now = 0 }
	local run = newRun(t)
	run:enroll("p1", 1)
	local old = run:issue("p1")
	t.now = 1
	run:choose("p1", 1, old.offerId, 1)
	Harness.truthy(next(run:stacksOf("p1")) ~= nil)
	run:enroll("p1", 2) -- next match
	Harness.eq(next(run:stacksOf("p1")), nil, "stacks reset")
	Harness.eq(run:hasActive("p1"), false)
	local fresh = run:issue("p1")
	Harness.eq(fresh.offerId, "u2-p1-1")
	t.now = 2
	Harness.eq(run:choose("p1", 2, old.offerId, 1).reason, "stale_offer")
	Harness.eq(run:choose("p1", 1, fresh.offerId, 1).reason, "stale_match")
end)

Harness.test("run: clear forgets everyone", function()
	local t = { now = 0 }
	local run = newRun(t)
	run:enroll("p1", 1)
	run:issue("p1")
	run:clear()
	Harness.eq(run:isEnrolled("p1"), false)
	Harness.eq(run:sheet("p1"), nil)
	local _, why = run:issue("p1")
	Harness.eq(why, "unknown")
end)

Harness.test("run: stacks stop at the maximum, then the upgrade drops out of offers", function()
	local t = { now = 0 }
	-- always roll the first eligible upgrade (quick_hands)
	local run = newRun(t, seq({ 0 }))
	run:enroll("p1", 1)
	for n = 1, 3 do
		local offer = run:issue("p1")
		Harness.eq(offer.options[1].id, "quick_hands")
		Harness.eq(offer.options[1].stacks, n - 1)
		t.now += 1
		Harness.eq(run:choose("p1", 1, offer.offerId, 1).stacks, n)
	end
	local after = run:issue("p1")
	for _, o in after.options do
		Harness.truthy(o.id ~= "quick_hands", "maxed upgrade is gone")
	end
end)

Harness.test("run: no offer when nothing is left to improve", function()
	local t = { now = 0 }
	local run = newRun(t)
	run:enroll("p1", 1)
	local entries = (run :: any)._entries
	for _, u in UpgradeDefs.list do
		entries.p1.stacks[u.id] = u.maxStacks
	end
	-- fan_fire and steady_aim exclude each other, so maxing both is not reachable; clear the loser
	entries.p1.stacks.steady_aim = nil
	local offer, why = run:issue("p1")
	Harness.eq(offer, nil)
	Harness.eq(why, "nothing_eligible")
end)

Harness.test("run: an offer that no longer fits the build is dropped, not applied", function()
	local t = { now = 0 }
	-- the last rolls pick from the end of the catalogue: they include a mortar-only power
	local ctxRand = seq({ 0.999999, 0.999999, 0.999999 })
	local run, ctx = newRun(t, ctxRand, true)
	run:enroll("p1", 1)
	local offer = run:issue("p1")
	local blastIndex: number? = nil
	local blastId = ""
	for i, o in offer.options do
		if o.id == "bigger_boom" or o.id == "aftershock" or o.id == "heavy_shell" then
			blastIndex = i
			blastId = o.id
		end
	end
	Harness.truthy(blastIndex ~= nil, "test needs a mortar card in the offer")
	ctx.hasExplosive = false -- the mortar went away
	t.now = 1
	local res = run:choose("p1", 1, offer.offerId, blastIndex :: number)
	Harness.eq(res.ok, false)
	Harness.eq(res.reason, "offer_invalid")
	Harness.eq(run:hasActive("p1"), false)
	Harness.eq(run:stacksOf("p1")[blastId], nil)
end)

Harness.test(
	"run: the sheet is a copy, resets with the match, and unknown ids have none",
	function()
		local t = { now = 0 }
		local run = newRun(t, seq({ 0 }))
		run:enroll("p1", 1)
		local before = run:sheet("p1")
		Harness.eq(before.firearm.reloadSeconds, 1.2)
		local offer = run:issue("p1")
		t.now = 1
		run:choose("p1", 1, offer.offerId, 1) -- quick_hands
		local after = run:sheet("p1")
		Harness.near(after.firearm.reloadSeconds, 0.96)
		after.firearm.reloadSeconds = 0 -- editing the copy changes nothing
		Harness.near(run:sheet("p1").firearm.reloadSeconds, 0.96)
		run:enroll("p1", 2)
		Harness.eq(run:sheet("p1").firearm.reloadSeconds, 1.2)
		Harness.eq(run:sheet("nobody"), nil)
	end
)
