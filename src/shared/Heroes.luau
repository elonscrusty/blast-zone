--!strict
-- The hero roster, as plain data and pure rules (no Roblox), so Lune can test it.
-- A hero is a sidegrade: its own health, a small speed change, its own starter gun in slot 1 (one of the
-- guns in Config.Weapons) and its own blast launcher in slot 2 (the Arc Mortar tuned a different way).
-- Looks are NOT heroes: the outfit slot stays cosmetic and any hero can wear any outfit.
-- Nothing here is sold. Every hero is free (no unlockAt, no product id), so nothing can be bought for power.
-- The numbers are placeholders for carter to tune; `Config.Heroes.spread` scales how different they are.
--
--   Heroes.list / Heroes.find(id) / Heroes.isHero(id)
--   Heroes.maxHealth(cfg, id)   Heroes.speedScale(cfg, id)   Heroes.primaryGun(id)
--   Heroes.applyToSheet(cfg, sheet, id)     tunes a copy of the stat sheet (speed + the slot 2 launcher)
--   Heroes.forBot(cfg, number)              the hero a bot plays
--   Heroes.sanitize(id)                     always a real hero id

export type Launcher = {
	name: string, -- the slot 2 gun's name on the hero's card and the HUD
	damage: number, -- multipliers of the Arc Mortar numbers
	radius: number,
	reload: number,
	range: number,
	speed: number, -- how fast the shell flies
	magazine: number, -- shells added to (or taken from) the magazine, never below 1
}

export type Hero = {
	id: string,
	name: string,
	role: string, -- a short word for the card
	blurb: string,
	healthDelta: number, -- added to Config.Health.max, times Config.Heroes.spread
	speedDelta: number, -- added to 1, times Config.Heroes.spread
	primary: string, -- slot 1 starter gun: the Volt Pistol or a key of Config.Weapons.Guns
	launcher: Launcher,
}

local Heroes = {}

Heroes.list = {
	{
		id = "ranger",
		name = "Ranger",
		role = "All-rounder",
		blurb = "Steady health, steady gun. Good at everything.",
		healthDelta = 0,
		speedDelta = 0,
		primary = "volt_pistol",
		launcher = {
			name = "Arc Mortar",
			damage = 1,
			radius = 1,
			reload = 1,
			range = 1,
			speed = 1,
			magazine = 0,
		},
	},
	{
		id = "bulwark",
		name = "Bulwark",
		role = "Tank",
		blurb = "Lots of health and a pump shotgun. Slow on its feet.",
		healthDelta = 35,
		speedDelta = -0.08,
		primary = "breaker",
		launcher = {
			name = "Slam Pop",
			damage = 1,
			radius = 1.1,
			reload = 1.2,
			range = 0.9,
			speed = 0.9,
			magazine = -1,
		},
	},
	{
		id = "wisp",
		name = "Wisp",
		role = "Scout",
		blurb = "Quick and fragile with a spray gun. Hit and run.",
		healthDelta = -20,
		speedDelta = 0.08,
		primary = "hornet",
		launcher = {
			name = "Mini Pop",
			damage = 0.7,
			radius = 0.8,
			reload = 0.75,
			range = 1,
			speed = 1.1,
			magazine = 1,
		},
	},
	{
		id = "sentinel",
		name = "Sentinel",
		role = "Sniper",
		blurb = "Hits hard from far away. Keep your distance.",
		healthDelta = 0,
		speedDelta = -0.03,
		primary = "longline",
		launcher = {
			name = "Far Pop",
			damage = 0.9,
			radius = 0.9,
			reload = 1.1,
			range = 1.3,
			speed = 1.2,
			magazine = 0,
		},
	},
	{
		id = "rigger",
		name = "Rigger",
		role = "Blaster",
		blurb = "Plain pistol, huge blasts. Two big pops, then wait.",
		healthDelta = 0,
		speedDelta = -0.05,
		primary = "volt_pistol",
		launcher = {
			name = "Big Pop",
			damage = 1.3,
			radius = 1.25,
			reload = 1.4,
			range = 1,
			speed = 0.9,
			magazine = -1,
		},
	},
} :: { Hero }

Heroes.default = "ranger"

local byId: { [string]: Hero } = {}
for _, hero in Heroes.list do
	byId[hero.id] = hero
end

function Heroes.find(id: any): Hero?
	return if type(id) == "string" then byId[id] else nil
end

function Heroes.isHero(id: any): boolean
	return Heroes.find(id) ~= nil
end

-- Always a real hero: anything unknown becomes the default.
function Heroes.sanitize(id: any): string
	local hero = Heroes.find(id)
	return if hero then hero.id else Heroes.default
end

local function hero_(id: any): Hero
	return byId[Heroes.sanitize(id)]
end

-- Health at the start of a match.
function Heroes.maxHealth(cfg: any, id: any): number
	local h = cfg.Heroes
	local value = cfg.Health.max + hero_(id).healthDelta * h.spread
	return math.floor(math.clamp(value, h.healthMin, h.healthMax) + 0.5)
end

-- Share of normal run speed (1 = normal).
function Heroes.speedScale(cfg: any, id: any): number
	local h = cfg.Heroes
	return math.clamp(1 + hero_(id).speedDelta * h.spread, h.speedMin, h.speedMax)
end

function Heroes.primaryGun(id: any): string
	return hero_(id).primary
end

function Heroes.launcherName(id: any): string
	return hero_(id).launcher.name
end

-- The hero's blast launcher as full numbers (base Arc Mortar tuned by the hero). Pure: reads `cfg` only.
function Heroes.launcherStats(cfg: any, id: any): { [string]: number }
	local m = cfg.Weapons.Explosive
	local l = hero_(id).launcher
	return {
		damage = m.damage * l.damage,
		radius = m.radius * l.radius,
		fireInterval = m.fireInterval,
		magazine = math.max(1, m.magazine + l.magazine),
		reloadSeconds = m.reloadSeconds * l.reload,
		range = m.range * l.range,
		projectileSpeed = m.projectileSpeed * l.speed,
	}
end

-- Tunes a copy of a stat sheet (speed and the slot 2 launcher), on top of whatever upgrades did. The
-- upgrade numbers ride on the hero's own base: a hero with 0.7 damage and a +30% upgrade ends at 0.7 x 1.3.
-- `sheet.explosive` must be this caller's own table (StatBook.get clones it before modifiers run).
function Heroes.applyToSheet(cfg: any, sheet: any, id: any)
	local l = hero_(id).launcher
	sheet.moveSpeed = sheet.moveSpeed * Heroes.speedScale(cfg, id)
	local e = sheet.explosive
	e.damage = e.damage * l.damage
	e.radius = e.radius * l.radius
	e.reloadSeconds = e.reloadSeconds * l.reload
	e.range = e.range * l.range
	e.projectileSpeed = e.projectileSpeed * l.speed
	e.magazine = math.max(1, e.magazine + l.magazine)
end

-- Bots play a hero by their number, so a match always has a mix and the same bot is the same hero.
function Heroes.forBot(cfg: any, number: number): string
	if not cfg.Heroes.botsUseHeroes then
		return Heroes.default
	end
	local n = #Heroes.list
	return Heroes.list[(math.floor(number) % n + n) % n + 1].id
end

return Heroes
