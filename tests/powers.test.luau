--!strict
-- Piece 43: the big level-up powers (Piercing Rounds, Rapid Fire, Aftershock, Heavy Shell, Long Slide).
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local StatBook = require("../src/shared/StatBook")
local UpgradeDefs = require("../src/shared/UpgradeDefs")
local Ballistics = require("../src/server/Combat/Ballistics")
local WeaponCatalog = require("../src/server/Combat/WeaponCatalog")

local function body(id: string, x: number): Ballistics.Target
	return { id = id, x = x, z = 0, r = 1.8 }
end

local function sheetWith(id: string)
	return UpgradeDefs.resolve(StatBook.base(Config), { [id] = 1 })
end

-- ===== Ballistics.line =====

Harness.test("line: with no pass-through it is the old first-hit shot", function()
	local targets = { body("a", 10), body("b", 20) }
	local r = Ballistics.line(0, 0, 1, 0, 70, nil, targets, 0)
	Harness.eq(#r.hits, 1)
	Harness.eq(r.hits[1].id, "a")
	Harness.eq(r.endKind, "target")
	local first = Ballistics.firstHit(0, 0, 1, 0, 70, nil, targets)
	Harness.near(r.endDist, first.dist)
end)

Harness.test("line: one extra body means two hits, nearest first, then the shot ends", function()
	local targets = { body("far", 30), body("near", 10), body("mid", 20) }
	local r = Ballistics.line(0, 0, 1, 0, 70, nil, targets, 1)
	Harness.eq(#r.hits, 2)
	Harness.eq(r.hits[1].id, "near")
	Harness.eq(r.hits[2].id, "mid")
	Harness.eq(r.endKind, "target")
	Harness.truthy(r.hits[1].dist < r.hits[2].dist)
end)

Harness.test("line: a wall stops a piercing shot, bodies behind it are safe", function()
	local targets = { body("a", 10), body("b", 40) }
	local r = Ballistics.line(0, 0, 1, 0, 70, 25, targets, 1)
	Harness.eq(#r.hits, 1)
	Harness.eq(r.hits[1].id, "a")
	Harness.eq(r.endKind, "wall")
	Harness.near(r.endDist, 25)
end)

Harness.test("line: fewer bodies than allowed ends at range, never repeats a body", function()
	local r = Ballistics.line(0, 0, 1, 0, 70, nil, { body("a", 10) }, 3)
	Harness.eq(#r.hits, 1)
	Harness.eq(r.endKind, "none")
	Harness.near(r.endDist, 70)
	local miss = Ballistics.line(0, 0, 1, 0, 70, nil, { body("a", 10) }, 0)
	Harness.eq(#miss.hits, 1)
	Harness.eq(#Ballistics.line(0, 0, 0, 1, 70, nil, { body("a", 10) }, 2).hits, 0)
end)

-- ===== the catalogue =====

Harness.test("powers: Piercing Rounds adds one pass-through and never more", function()
	Harness.eq(StatBook.base(Config).firearm.pierce, 0)
	Harness.eq(sheetWith("piercing_rounds").firearm.pierce, 1)
	Harness.eq(
		UpgradeDefs.resolve(StatBook.base(Config), { piercing_rounds = 50 }).firearm.pierce,
		1
	)
end)

Harness.test("powers: every gun gets the pass-through, not only the pistol", function()
	local pierced = sheetWith("piercing_rounds").firearm
	for id in Config.Weapons.Guns do
		Harness.eq(WeaponCatalog.stats(Config, id, pierced).pierce, 1, id)
	end
	Harness.eq(WeaponCatalog.stats(Config, "breaker", StatBook.base(Config).firearm).pierce, 0)
end)

Harness.test("powers: Rapid Fire shoots 40% faster for 10% less damage", function()
	local f = sheetWith("rapid_fire").firearm
	Harness.near(f.fireInterval, Config.Weapons.Firearm.fireInterval / 1.4, 1e-9)
	Harness.near(f.damage, Config.Weapons.Firearm.damage * 0.9, 1e-9)
end)

Harness.test("powers: Heavy Shell trades a slow reload for a big blast", function()
	local e = sheetWith("heavy_shell").explosive
	local base = Config.Weapons.Explosive
	Harness.near(e.damage, base.damage * 1.5, 1e-9)
	Harness.near(e.radius, base.radius * 1.3, 1e-9)
	Harness.near(e.reloadSeconds, base.reloadSeconds * 1.35, 1e-9)
end)

Harness.test("powers: Aftershock turns the second blast on, once", function()
	Harness.eq(StatBook.base(Config).explosive.aftershock, 0)
	Harness.eq(sheetWith("aftershock").explosive.aftershock, 1)
	Harness.eq(
		UpgradeDefs.resolve(StatBook.base(Config), { aftershock = 9 }).explosive.aftershock,
		1
	)
end)

Harness.test("powers: Long Slide stretches the slide and the cap holds", function()
	Harness.near(sheetWith("long_slide").slideDistance, Config.Slide.distance * 1.4, 1e-9)
	local all: { [string]: number } = {}
	for _, u in UpgradeDefs.list do
		all[u.id] = 1000
	end
	local sheet = UpgradeDefs.resolve(StatBook.base(Config), all)
	Harness.truthy(sheet.slideDistance <= Config.Slide.distance * 1.5 + 1e-9)
	Harness.truthy(sheet.firearm.fireInterval >= Config.Weapons.Firearm.fireInterval * 0.5 - 1e-9)
	Harness.truthy(sheet.firearm.pierce <= 1)
end)

Harness.test("powers: the mortar powers are not offered without the mortar", function()
	local base = StatBook.base(Config)
	local noMortar = { base = base, hasExplosive = false }
	local mortar = { base = base, hasExplosive = true }
	for _, id in { "aftershock", "heavy_shell" } do
		Harness.eq((UpgradeDefs.canOffer(id, {}, noMortar :: any)), false, id)
		Harness.eq((UpgradeDefs.canOffer(id, {}, mortar :: any)), true, id)
	end
	Harness.eq((UpgradeDefs.canOffer("piercing_rounds", {}, noMortar :: any)), true)
	Harness.eq(
		(UpgradeDefs.canOffer("piercing_rounds", { piercing_rounds = 1 }, mortar :: any)),
		false
	)
end)

Harness.test("powers: the numbers the shot code reads make sense", function()
	local p = Config.Powers
	Harness.truthy(p.pierceFalloff > 0 and p.pierceFalloff < 1)
	Harness.truthy(p.aftershockDamageShare > 0 and p.aftershockDamageShare < 1)
	Harness.truthy(p.aftershockDelaySeconds > 0 and p.aftershockDelaySeconds < 2)
end)

Harness.test("powers: each new pick says what it changes on its card", function()
	local base = StatBook.base(Config)
	local ctx = {
		base = base,
		hasExplosive = true,
		weaponNames = { firearm = "Volt Pistol", explosive = "Arc Mortar" },
	}
	for _, id in { "piercing_rounds", "rapid_fire", "aftershock", "heavy_shell", "long_slide" } do
		local option = UpgradeDefs.option(id, {}, ctx :: any)
		Harness.truthy(#option.change > 0, id .. " has no change line")
	end
end)
