--!strict
-- Piece 44: heroes. Roster rules, balance guard, stat sheet tuning, stat cards, the loadout slot,
-- who plays which hero, and per-hero health.
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local GunCards = require("../src/shared/GunCards")
local HeroRoster = require("../src/shared/HeroRoster")
local Heroes = require("../src/shared/Heroes")
local HealthBook = require("../src/server/Combat/HealthBook")
local Ids = require("../src/shared/Ids")
local Loadout = require("../src/shared/Loadout")
local LoadoutStore = require("../src/shared/LoadoutStore")
local LoadoutView = require("../src/shared/LoadoutView")
local StatBook = require("../src/shared/StatBook")
local WeaponCatalog = require("../src/server/Combat/WeaponCatalog")

local function withSpread(spread: number): any
	local cfg: any = table.clone(Config :: any)
	local h: any = table.clone(Config.Heroes :: any)
	h.spread = spread
	cfg.Heroes = h
	return cfg
end

-- ===== roster =====

Harness.test("heroes: ids are unique and safe, names are not copied from anywhere", function()
	local seen: { [string]: boolean } = {}
	for _, hero in Heroes.list do
		Harness.truthy(not seen[hero.id], "duplicate " .. hero.id)
		seen[hero.id] = true
		Harness.truthy(string.match(hero.id, "^[%w_]+$") ~= nil and #hero.id <= 24, "bad id")
		Harness.truthy(#hero.name > 0 and #hero.role > 0 and #hero.blurb > 0, hero.id .. " text")
	end
	Harness.truthy(#Heroes.list >= 5, "a roster of five or more")
	Harness.truthy(Heroes.isHero(Heroes.default), "default exists")
end)

Harness.test("heroes: every starter gun and launcher is real", function()
	for _, hero in Heroes.list do
		Harness.truthy(WeaponCatalog.isGun(Config, hero.primary), hero.id .. " starter gun")
		local l = hero.launcher
		Harness.truthy(#l.name > 0, hero.id .. " launcher name")
		for _, v in { l.damage, l.radius, l.reload, l.range, l.speed } do
			Harness.truthy(v > 0.3 and v < 2, hero.id .. " launcher multiplier in range")
		end
		Harness.truthy(math.abs(l.magazine) <= 2, hero.id .. " magazine change small")
	end
end)

Harness.test("heroes: each hero has its own two guns", function()
	local seen: { [string]: boolean } = {}
	for _, hero in Heroes.list do
		local key = hero.primary .. "+" .. hero.launcher.name
		Harness.truthy(not seen[key], hero.id .. " pair is not shared")
		seen[key] = true
	end
end)

Harness.test("heroes: nothing is sold (free, no product ids)", function()
	for _, item in Loadout.items.hero do
		Harness.eq(item.unlockAt, nil)
	end
	for _, hero in Heroes.list do
		for key in hero :: any do
			Harness.truthy(
				string.find(string.lower(key), "robux") == nil
					and string.find(string.lower(key), "product") == nil
					and string.find(string.lower(key), "price") == nil,
				"no money field " .. key
			)
		end
	end
end)

Harness.test("heroes: health and speed stay inside the limits at any spread", function()
	for _, spread in { 0, 0.5, 1, 1.5, 3 } do
		local cfg = withSpread(spread)
		for _, hero in Heroes.list do
			local hp = Heroes.maxHealth(cfg, hero.id)
			Harness.truthy(hp >= cfg.Heroes.healthMin and hp <= cfg.Heroes.healthMax, hero.id)
			Harness.eq(hp, math.floor(hp))
			local sp = Heroes.speedScale(cfg, hero.id)
			Harness.truthy(sp >= cfg.Heroes.speedMin and sp <= cfg.Heroes.speedMax, hero.id)
		end
	end
	local plain = withSpread(0)
	for _, hero in Heroes.list do
		Harness.eq(Heroes.maxHealth(plain, hero.id), Config.Health.max)
		Harness.near(Heroes.speedScale(plain, hero.id), 1, 1e-9)
	end
end)

Harness.test("heroes: health is different between heroes (the point of heroes)", function()
	local lowest, highest = math.huge, 0
	for _, hero in Heroes.list do
		local hp = Heroes.maxHealth(Config, hero.id)
		lowest, highest = math.min(lowest, hp), math.max(highest, hp)
	end
	Harness.truthy(
		highest - lowest >= 30,
		"at least 30 health between the frailest and the tankiest"
	)
end)

-- A guard, not a promise: no hero may be much stronger or weaker than the roster average on paper.
-- Health x (gun damage per second, credited for reach, + blast damage per second). Speed and blast size are
-- left out and balanced by hand (they do not fit in one number); this catches typos, not feel.
local function paperPower(cfg: any, id: string): number
	local gun = WeaponCatalog.stats(cfg, Heroes.primaryGun(id), StatBook.base(cfg).firearm)
	local perMag = gun.damage * gun.pellets * gun.magazine
	local cycle = gun.magazine * gun.fireInterval + gun.reloadSeconds
	local gunDps = perMag / cycle
	local l = Heroes.launcherStats(cfg, id)
	local blastDps = l.damage * l.magazine / (l.magazine * l.fireInterval + l.reloadSeconds)
	local reach = 0.6 + gun.range / 100
	return Heroes.maxHealth(cfg, id) * (gunDps * reach + blastDps)
end

Harness.test("heroes: nobody is far above or below the roster average on paper", function()
	for _, spread in { 0.5, 1, 1.5 } do
		local cfg = withSpread(spread)
		local total = 0
		for _, hero in Heroes.list do
			total += paperPower(cfg, hero.id)
		end
		local average = total / #Heroes.list
		for _, hero in Heroes.list do
			local ratio = paperPower(cfg, hero.id) / average
			Harness.truthy(ratio > 0.55 and ratio < 1.45, `{hero.id} at spread {spread}: {ratio}`)
		end
	end
end)

Harness.test("heroes: unknown ids always become the default hero", function()
	for _, bad in { "nope", "", 5, false, {} } do
		Harness.eq(Heroes.sanitize(bad), Heroes.default)
	end
	Harness.eq(Heroes.sanitize("bulwark"), "bulwark")
	Harness.eq(Heroes.maxHealth(Config, "nope"), Heroes.maxHealth(Config, Heroes.default))
end)

-- ===== stat sheet =====

Harness.test("heroes: the default hero changes nothing", function()
	local sheet = StatBook.base(Config)
	Heroes.applyToSheet(Config, sheet, Heroes.default)
	local base = StatBook.base(Config)
	Harness.eq(sheet.moveSpeed, base.moveSpeed)
	for k, v in base.explosive :: any do
		Harness.eq((sheet.explosive :: any)[k], v, k)
	end
end)

Harness.test("heroes: the launcher matches the sheet the shells will read", function()
	for _, hero in Heroes.list do
		local sheet = StatBook.base(Config)
		Heroes.applyToSheet(Config, sheet, hero.id)
		local want = Heroes.launcherStats(Config, hero.id)
		Harness.near(sheet.explosive.damage, want.damage, 1e-9)
		Harness.near(sheet.explosive.radius, want.radius, 1e-9)
		Harness.near(sheet.explosive.range, want.range, 1e-9)
		Harness.near(sheet.explosive.reloadSeconds, want.reloadSeconds, 1e-9)
		Harness.near(sheet.explosive.projectileSpeed, want.projectileSpeed, 1e-9)
		Harness.eq(sheet.explosive.magazine, want.magazine)
		Harness.near(
			sheet.moveSpeed,
			Config.Movement.walkSpeed * Heroes.speedScale(Config, hero.id),
			1e-9
		)
	end
end)

Harness.test("heroes: a StatBook modifier never edits the upgrade piece's own sheet", function()
	local book = StatBook.new(Config)
	local owned = StatBook.base(Config)
	book:setProvider(function(): any
		return owned
	end)
	book:addModifier(function(_: string, sheet: any)
		Heroes.applyToSheet(Config, sheet, "wisp")
	end)
	local tuned = book:get("p1")
	Harness.truthy(tuned.explosive.damage < owned.explosive.damage, "tuned copy is weaker")
	Harness.eq(owned.explosive.damage, Config.Weapons.Explosive.damage)
	Harness.eq(owned.explosive.magazine, Config.Weapons.Explosive.magazine)
	Harness.eq(owned.moveSpeed, Config.Movement.walkSpeed)
	-- and asking twice gives the same answer, not a stack
	Harness.eq(book:get("p1").explosive.damage, tuned.explosive.damage)
end)

Harness.test("heroes: upgrades ride on the hero's own base", function()
	local book = StatBook.new(Config)
	local upgraded = StatBook.base(Config)
	upgraded.explosive.damage = upgraded.explosive.damage * 1.5
	book:setProvider(function(): any
		return upgraded
	end)
	book:addModifier(function(_: string, sheet: any)
		Heroes.applyToSheet(Config, sheet, "rigger")
	end)
	local l = Heroes.launcherStats(Config, "rigger")
	Harness.near(book:get("p1").explosive.damage, l.damage * 1.5, 1e-9)
end)

-- ===== bots and players =====

Harness.test(
	"heroes: bots get a steady mix, players get their pick, strangers get the default",
	function()
		local seen: { [string]: number } = {}
		for n = 1, #Heroes.list * 3 do
			local id = HeroRoster.heroOf(Config, Ids.bot(n), nil)
			seen[id] = (seen[id] or 0) + 1
			Harness.eq(HeroRoster.heroOf(Config, Ids.bot(n), nil), id)
		end
		for _, hero in Heroes.list do
			Harness.eq(seen[hero.id], 3, hero.id)
		end
		local pick = function(userId: number): string?
			return if userId == 7 then "wisp" else nil
		end
		Harness.eq(HeroRoster.heroOf(Config, Ids.player(7), pick), "wisp")
		Harness.eq(HeroRoster.heroOf(Config, Ids.player(8), pick), Heroes.default)
		Harness.eq(
			HeroRoster.heroOf(Config, Ids.player(7), function(): string?
				return "cheat"
			end),
			Heroes.default
		)
		Harness.eq(HeroRoster.heroOf(Config, "garbage", pick), Heroes.default)
		local off: any = table.clone(Config :: any)
		off.Heroes = table.clone(Config.Heroes :: any)
		off.Heroes.botsUseHeroes = false
		Harness.eq(HeroRoster.heroOf(off, Ids.bot(2), nil), Heroes.default)
	end
)

-- ===== health =====

Harness.test("heroes: each fighter keeps their own maximum health", function()
	local book = HealthBook.new(Config.Health.max)
	book:add("p1", 140)
	book:add("p2", 75)
	book:add("p3")
	Harness.eq(book:get("p1"), 140)
	Harness.eq(book:get("p2"), 75)
	Harness.eq(book:get("p3"), Config.Health.max)
	book:apply("p1", 100, "p2")
	book:apply("p2", 50, "p1")
	Harness.eq(book:heal("p1", 999), 100, "heals back to 140, no further")
	Harness.eq(book:get("p1"), 140)
	Harness.eq(book:heal("p2", 999), 50)
	Harness.eq(book:get("p2"), 75)
	Harness.eq(book:max_("p2"), 75)
end)

-- ===== loadout slot =====

Harness.test("heroes: the hero slot is first, free, and defaults to the default hero", function()
	Harness.eq(Loadout.slots[1], "hero")
	Harness.eq((Loadout.defaults :: any).hero, Heroes.default)
	Harness.eq(#Loadout.items.hero, #Heroes.list)
	local sel = Loadout.sanitize({ hero = "nope" }, { level = 0 })
	Harness.eq(sel.hero, Heroes.default)
	Harness.eq(Loadout.sanitize({ hero = "bulwark" }, { level = 0 }).hero, "bulwark")
end)

Harness.test("heroes: the server store checks a hero pick", function()
	local picks: { [string]: string } = {}
	local store = LoadoutStore.new({
		read = function(): { [string]: any }?
			return picks
		end,
		write = function(_: number, slot: string, id: string): boolean
			picks[slot] = id
			return true
		end,
		unlocks = function(): Loadout.Unlocks
			return { level = 0 }
		end,
		saved = function(): boolean
			return true
		end,
	})
	Harness.eq(store:get(1).hero, Heroes.default)
	local ok = store:equip(1, "hero", "sentinel")
	Harness.truthy(ok)
	Harness.eq(store:get(1).hero, "sentinel")
	local bad, reason = store:equip(1, "hero", "godmode")
	Harness.truthy(not bad)
	Harness.eq(reason, "unknown_item")
	Harness.eq(store:get(1).hero, "sentinel")
end)

Harness.test("heroes: hero cards carry health and both guns, other cards stay plain", function()
	local state: LoadoutView.State = {
		selection = Loadout.defaults :: any,
		unlocked = Loadout.unlockedIds({ level = 0 }),
		level = 0,
		saved = true,
	}
	local cards = LoadoutView.cards(state, "hero")
	Harness.eq(#cards, #Heroes.list)
	for _, card in cards do
		Harness.truthy(
			card.detail ~= nil and #(card.detail :: { string }) == 3,
			card.id .. " detail"
		)
		Harness.truthy(not card.locked, card.id .. " is open")
	end
	Harness.truthy(cards[1].equipped)
	for _, card in LoadoutView.cards(state, "outfit") do
		Harness.eq(card.detail, nil)
	end
end)

-- ===== stat cards =====

Harness.test("cards: a gun card shows the real numbers", function()
	local card = GunCards.gun(Config, "breaker")
	Harness.eq(card.name, "Breaker")
	Harness.eq(card.kind, "gun")
	local byKey: { [string]: GunCards.Line } = {}
	for _, line in card.lines do
		byKey[line.key] = line
	end
	Harness.eq(byKey.damage.value, 42, "6 pellets of 7")
	Harness.eq(byKey.damage.text, "7 x 6")
	Harness.eq(byKey.range.value, Config.Weapons.Guns.breaker.range)
	Harness.near(byKey.rate.value, 1 / 0.9, 1e-9)
	Harness.eq(byKey.magazine.value, 6)
	Harness.eq(byKey.reload.text, "2.2 s")
end)

Harness.test("cards: bars are 0..1 and the best gun in each row is full", function()
	local ids = { Config.Weapons.Firearm.id }
	for id in Config.Weapons.Guns do
		table.insert(ids, id)
	end
	local topPerKey: { [string]: number } = {}
	for _, id in ids do
		for _, line in GunCards.gun(Config, id).lines do
			Harness.truthy(line.bar > 0 and line.bar <= 1, `{id} {line.key} bar {line.bar}`)
			topPerKey[line.key] = math.max(topPerKey[line.key] or 0, line.bar)
		end
	end
	for key, top in topPerKey do
		Harness.near(top, 1, 1e-9, key .. " has a full bar somewhere")
	end
	-- Longline reaches farthest, Hornet fires fastest
	local function bar(id: string, key: string): number
		for _, line in GunCards.gun(Config, id).lines do
			if line.key == key then
				return line.bar
			end
		end
		return -1
	end
	Harness.near(bar("longline", "range"), 1, 1e-9)
	Harness.near(bar("hornet", "rate"), 1, 1e-9)
	Harness.truthy(bar("breaker", "range") < bar("hornet", "range"))
end)

Harness.test("cards: a hero card matches the hero and shows two different guns", function()
	for _, hero in Heroes.list do
		local card = GunCards.hero(Config, hero.id)
		Harness.eq(card.health, Heroes.maxHealth(Config, hero.id))
		Harness.truthy(card.healthBar > 0 and card.healthBar <= 1)
		Harness.truthy(card.speedBar > 0 and card.speedBar <= 1)
		Harness.eq(#card.guns, 2)
		Harness.eq(card.guns[1].kind, "gun")
		Harness.eq(card.guns[2].kind, "blast")
		Harness.eq(card.guns[1].name, WeaponCatalog.displayName(Config, hero.primary))
		Harness.eq(card.guns[2].name, hero.launcher.name)
	end
	local top = 0
	for _, hero in Heroes.list do
		top = math.max(top, GunCards.hero(Config, hero.id).healthBar)
	end
	Harness.near(top, 1, 1e-9)
end)

Harness.test("cards: the blast card follows the launcher numbers", function()
	local card = GunCards.launcher(Config, "rigger")
	local l = Heroes.launcherStats(Config, "rigger")
	for _, line in card.lines do
		if line.key == "damage" then
			Harness.near(line.value, l.damage, 1e-9)
		elseif line.key == "radius" then
			Harness.near(line.value, l.radius, 1e-9)
		elseif line.key == "magazine" then
			Harness.eq(line.value, l.magazine)
		end
	end
end)
