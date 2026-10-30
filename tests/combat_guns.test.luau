--!strict
-- Piece 23: found guns (Breaker, Hornet, Longline). Numbers, upgrade scaling, drop odds, the slot swap,
-- fire-rate limits for the fastest gun, and the held-model part lists.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local RemoteDefs = require("../src/shared/RemoteDefs")
local StatBook = require("../src/shared/StatBook")
local UpgradeDefs = require("../src/shared/UpgradeDefs")
local WeaponCatalog = require("../src/server/Combat/WeaponCatalog")
local WeaponState = require("../src/server/Combat/WeaponState")
local WeaponModels = require("../src/client/Combat/WeaponModels")

local GUN_IDS = { "breaker", "hornet", "longline" }
local TOL = Config.Combat.fireTolerance

local function basePistol(): any
	return StatBook.base(Config).firearm
end

Harness.test("guns: every found gun has sane numbers and stays on screen", function()
	for _, id in GUN_IDS do
		local g = Config.Weapons.Guns[id]
		Harness.truthy(g ~= nil, id .. " defined")
		Harness.eq(g.id, id)
		Harness.truthy(g.damage > 0 and g.pellets >= 1 and g.magazine >= 1, id .. " can hurt")
		Harness.truthy(g.fireInterval > 0 and g.reloadSeconds > 0, id .. " has timings")
		-- no unseen long shots: nothing reaches much past the pistol
		Harness.truthy(g.range <= Config.Weapons.Firearm.range * 1.2, id .. " range capped")
	end
end)

Harness.test("guns: each one wins a different kind of fight", function()
	local b, h, l =
		Config.Weapons.Guns.breaker, Config.Weapons.Guns.hornet, Config.Weapons.Guns.longline
	local p = Config.Weapons.Firearm
	Harness.truthy(b.damage * b.pellets > p.damage * 3, "Breaker blast beats three pistol shots")
	Harness.truthy(b.range < p.range / 2, "Breaker is short range")
	Harness.truthy(1 / h.fireInterval > p.fireRate * 2, "Hornet fires over twice as fast")
	Harness.truthy(h.damage < p.damage, "Hornet hits softer")
	Harness.truthy(l.damage * 3 >= Config.Health.max, "Longline: three hits end a fight")
	Harness.truthy(l.range > p.range, "Longline reaches farthest")
	Harness.truthy(l.fireInterval > p.fireInterval * 4, "Longline is slow")
end)

Harness.test("catalog: the pistol passes straight through; unknown ids are the pistol", function()
	local sheet = basePistol()
	local s = WeaponCatalog.stats(Config, "volt_pistol", sheet)
	Harness.eq(s.damage, sheet.damage)
	Harness.eq(WeaponCatalog.stats(Config, "nope", sheet).magazine, sheet.magazine)
	Harness.truthy(WeaponCatalog.isGun(Config, "volt_pistol"))
	Harness.truthy(WeaponCatalog.isGun(Config, "longline"))
	Harness.truthy(not WeaponCatalog.isGun(Config, "arc_mortar"), "the mortar is not a slot 1 gun")
	Harness.eq(WeaponCatalog.displayName(Config, "hornet"), "Hornet")
end)

Harness.test("catalog: a found gun with no upgrades uses its own base numbers", function()
	local s = WeaponCatalog.stats(Config, "breaker", basePistol())
	local g = Config.Weapons.Guns.breaker
	Harness.near(s.damage, g.damage, 1e-9)
	Harness.eq(s.pellets, g.pellets)
	Harness.eq(s.magazine, g.magazine)
	Harness.near(s.range, g.range, 1e-9)
	Harness.near(s.spreadDegrees, g.spreadDegrees, 1e-9)
end)

Harness.test("catalog: pistol upgrades carry over to found guns by the same share", function()
	local base = StatBook.base(Config)
	local upgraded = UpgradeDefs.resolve(
		base,
		{ hard_rounds = 2, quick_hands = 1, long_sight = 1, twin_shot = 1 }
	)
	local s = WeaponCatalog.stats(Config, "longline", upgraded.firearm)
	local g = Config.Weapons.Guns.longline
	local p = Config.Weapons.Firearm
	Harness.near(s.damage, g.damage * upgraded.firearm.damage / p.damage, 1e-9, "damage share")
	Harness.near(s.reloadSeconds, g.reloadSeconds * 0.8, 1e-9, "reload 20% faster")
	Harness.near(s.range, g.range * 1.2, 1e-9, "range 20% farther")
	Harness.eq(s.pellets, 2, "Twin Shot adds a bullet")
	Harness.near(s.spreadDegrees, 4, 1e-9, "Twin Shot adds spread")
	local sg = WeaponCatalog.stats(Config, "breaker", upgraded.firearm)
	Harness.eq(
		sg.pellets,
		Config.Weapons.Guns.breaker.pellets + 1,
		"Breaker gets the extra pellet too"
	)
end)

Harness.test("catalog: extra pellets are capped and spread never goes negative", function()
	local fake = table.clone(basePistol())
	fake.pellets = 50
	fake.spreadDegrees = -100
	local s = WeaponCatalog.stats(Config, "hornet", fake)
	Harness.eq(s.pellets, 1 + 4)
	Harness.eq(s.spreadDegrees, 0)
end)

Harness.test("drops: odds add up to the drop chance and split evenly", function()
	local odds = WeaponCatalog.dropOdds(Config)
	local sum = 0
	for _, id in GUN_IDS do
		sum += odds[id]
		Harness.near(odds[id], Config.Weapons.Drops.chance / 3, 1e-9, id .. " one third")
	end
	Harness.near(sum, Config.Weapons.Drops.chance, 1e-9)
end)

Harness.test("drops: rolls map to guns the same way every time", function()
	local c = Config.Weapons.Drops.chance
	Harness.eq(WeaponCatalog.rollDrop(Config, c, 0), nil, "a roll at the chance drops nothing")
	Harness.eq(WeaponCatalog.rollDrop(Config, 0.99, 0.5), nil)
	Harness.eq(WeaponCatalog.rollDrop(Config, 0, 0), "breaker")
	Harness.eq(WeaponCatalog.rollDrop(Config, 0, 0.5), "hornet")
	Harness.eq(WeaponCatalog.rollDrop(Config, 0, 0.999), "longline")
	local seen: { [string]: number } = {}
	for i = 0, 299 do
		local id = WeaponCatalog.rollDrop(Config, 0, i / 300)
		if id ~= nil then
			seen[id] = (seen[id] or 0) + 1
		end
	end
	for _, id in GUN_IDS do
		Harness.eq(seen[id], 100, id .. " gets a third of the rolls")
	end
end)

Harness.test(
	"swap: a found gun arrives full, cancels a slot 1 reload, keeps the mortar ammo",
	function()
		local pistol = {
			fireInterval = Config.Weapons.Firearm.fireInterval,
			magazine = 12,
			reloadSeconds = 1.2,
		}
		local s = WeaponState.new({ 12, 3 }, TOL)
		for i = 0, 11 do
			s:tryFire(i, pistol)
		end
		Harness.truthy(s:isReloading(), "empty pistol reloads")
		s.ammo[2] = 1
		Harness.truthy(s:replace(1, 6, 20, Config.Combat.switchSeconds))
		Harness.eq(s.ammo[1], 6)
		Harness.truthy(not s:isReloading(), "reload dropped")
		Harness.eq(s.ammo[2], 1, "mortar ammo untouched")
		local shotgun = { fireInterval = 0.9, magazine = 6, reloadSeconds = 2.2 }
		Harness.truthy(not s:tryFire(20.1, shotgun).ok, "short swap delay before the first shot")
		Harness.truthy(s:tryFire(20 + Config.Combat.switchSeconds, shotgun).ok)
		-- a later reload fills to the new gun's magazine
		s:startReload(21, shotgun)
		s:update(30, function()
			return shotgun
		end)
		Harness.eq(s.ammo[1], 6)
	end
)

Harness.test("swap: refused once eliminated", function()
	local s = WeaponState.new({ 12, 3 }, TOL)
	s:lock()
	Harness.truthy(not s:replace(1, 30, 0, 0.25))
	Harness.eq(s.ammo[1], 12)
end)

Harness.test("fire rate: hammering the Hornet trigger cannot beat its 11 shots a second", function()
	local h = Config.Weapons.Guns.hornet
	local st = { fireInterval = h.fireInterval, magazine = 999, reloadSeconds = h.reloadSeconds }
	local s = WeaponState.new({ 999, 3 }, TOL)
	local shots = 0
	for i = 0, 1000 do
		if s:tryFire(i * 0.001, st).ok then
			shots += 1
		end
	end
	Harness.truthy(shots <= 12, `fired {shots} in one second`)
end)

Harness.test("remotes: the fire-request limit leaves room for the fastest gun", function()
	local rate = RemoteDefs.byName.FireRequest.rate
	Harness.truthy(
		rate ~= nil and rate.perSecond >= 1 / Config.Weapons.Guns.hornet.fireInterval,
		"Hornet fits"
	)
end)

Harness.test(
	"models: every gun has Slide and Grip, known looks, frames and a sane part count",
	function()
		local looks = {
			poly = true,
			gun = true,
			steel = true,
			blued = true,
			brass = true,
			dark = true,
			hull = true,
			rubber = true,
			tan = true,
			glass = true,
			cyan = true,
			coral = true,
		}
		for _, id in { "volt_pistol", "breaker", "hornet", "longline" } do
			local m = WeaponModels.models[id]
			Harness.truthy(m ~= nil, id .. " has a model")
			local names: { [string]: boolean } = {}
			for _, p in m.parts do
				Harness.truthy(not names[p.name], `{id}: part name {p.name} is unique`)
				names[p.name] = true
				Harness.truthy(looks[p.look], `{id}: {p.name} look {p.look}`)
				Harness.truthy(
					p.frame == nil or m.frames[p.frame] ~= nil,
					`{id}: {p.name} frame exists`
				)
				Harness.truthy(p.w > 0 and p.h > 0 and p.d > 0, `{id}: {p.name} has size`)
			end
			Harness.truthy(
				names.Slide and names.Grip,
				id .. " keeps Slide and Grip for the character piece"
			)
			Harness.truthy(#m.parts <= 90, `{id}: {#m.parts} parts (budget 90)`)
		end
		Harness.eq(WeaponModels.get("unknown").id, "volt_pistol")
	end
)
