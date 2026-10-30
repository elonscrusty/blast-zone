--!strict
-- Stat cards for guns and heroes, as plain data (no Roblox). The screen's look (Claude Design) only draws
-- these rows; every number and every bar comes from here, so a card can never disagree with the real gun.
-- Bars run 0..1 against the best value in the roster, so a new gun or hero rescales on its own.
--
--   GunCards.gun(cfg, gunId)       -> Card   a slot 1 gun (Volt Pistol or a key of Config.Weapons.Guns)
--   GunCards.launcher(cfg, heroId) -> Card   the hero's slot 2 blast launcher
--   GunCards.hero(cfg, heroId)     -> HeroCard  health + speed bars and both cards
--   GunCards.heroLines(cfg, heroId) -> { string }  the same thing as short plain lines (placeholder screens)
local Heroes = require("./Heroes")

export type Line = {
	key: string, -- "damage" | "range" | "rate" | "magazine" | "reload" | "radius"
	label: string,
	value: number,
	text: string, -- what to print, units included
	bar: number, -- 0..1 against the roster's best (reload is flipped: shorter is fuller)
}

export type Card = {
	id: string,
	name: string,
	kind: string, -- "gun" | "blast"
	lines: { Line },
}

export type HeroCard = {
	id: string,
	name: string,
	role: string,
	blurb: string,
	health: number,
	healthBar: number,
	speed: number, -- share of normal run speed
	speedBar: number,
	guns: { Card }, -- slot 1 then slot 2
}

local GunCards = {}

local function round1(n: number): number
	return math.floor(n * 10 + 0.5) / 10
end

local function fmt(n: number): string
	local r = round1(n)
	if r == math.floor(r) then
		return tostring(math.floor(r))
	end
	return tostring(r)
end

-- 0..1 against the roster's best. `flip` is for "shorter is better" numbers: the best is the smallest.
local function bar(value: number, bestValue: number, flip: boolean?): number
	if value <= 0 or bestValue <= 0 then
		return 0
	end
	return math.clamp(if flip then bestValue / value else value / bestValue, 0, 1)
end

-- ===== slot 1 guns =====

local function gunNumbers(cfg: any, id: string): { [string]: number }
	local def: any = cfg.Weapons.Guns[id] or cfg.Weapons.Firearm
	return {
		damage = def.damage * def.pellets, -- a full shotgun blast counts as one shot
		range = def.range,
		rate = 1 / def.fireInterval,
		magazine = def.magazine,
		reload = def.reloadSeconds,
	}
end

local function gunIds(cfg: any): { string }
	local ids = { cfg.Weapons.Firearm.id }
	for id in cfg.Weapons.Guns do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function best(
	cfg: any,
	key: string,
	numbersOf: (any, string) -> { [string]: number },
	ids: { string },
	flip: boolean?
): number
	local top: number? = nil
	for _, id in ids do
		local v = numbersOf(cfg, id)[key]
		if top == nil or (if flip then v < top else v > top) then
			top = v
		end
	end
	return top or 0
end

function GunCards.gun(cfg: any, gunId: string): Card
	local def: any = cfg.Weapons.Guns[gunId] or cfg.Weapons.Firearm
	local n = gunNumbers(cfg, gunId)
	local ids = gunIds(cfg)
	local function line(key: string, label: string, text: string, flip: boolean?): Line
		return {
			key = key,
			label = label,
			value = n[key],
			text = text,
			bar = bar(n[key], best(cfg, key, gunNumbers, ids, flip), flip),
		}
	end
	local damageText = if def.pellets > 1
		then `{fmt(def.damage)} x {def.pellets}`
		else fmt(def.damage)
	return {
		id = def.id,
		name = def.displayName,
		kind = "gun",
		lines = {
			line("damage", "Damage", damageText),
			line("range", "Range", fmt(n.range)),
			line("rate", "Fire rate", `{fmt(n.rate)}/s`),
			line("magazine", "Magazine", fmt(n.magazine)),
			line("reload", "Reload", `{fmt(n.reload)} s`, true),
		},
	}
end

-- ===== slot 2 launchers =====

local function launcherNumbers(cfg: any, heroId: string): { [string]: number }
	local s = Heroes.launcherStats(cfg, heroId)
	return {
		damage = s.damage,
		radius = s.radius,
		range = s.range,
		reload = s.reloadSeconds,
		magazine = s.magazine,
	}
end

function GunCards.launcher(cfg: any, heroId: string): Card
	local hero = Heroes.sanitize(heroId)
	local n = launcherNumbers(cfg, hero)
	local ids: { string } = {}
	for _, h in Heroes.list do
		table.insert(ids, h.id)
	end
	local function line(key: string, label: string, text: string, flip: boolean?): Line
		return {
			key = key,
			label = label,
			value = n[key],
			text = text,
			bar = bar(n[key], best(cfg, key, launcherNumbers, ids, flip), flip),
		}
	end
	return {
		id = hero .. "_launcher",
		name = Heroes.launcherName(hero),
		kind = "blast",
		lines = {
			line("damage", "Damage", fmt(n.damage)),
			line("radius", "Blast size", fmt(n.radius)),
			line("range", "Range", fmt(n.range)),
			line("magazine", "Magazine", fmt(n.magazine)),
			line("reload", "Reload", `{fmt(n.reload)} s`, true),
		},
	}
end

-- ===== heroes =====

function GunCards.hero(cfg: any, heroId: string): HeroCard
	local id = Heroes.sanitize(heroId)
	local hero = Heroes.find(id) :: Heroes.Hero
	local top = 0
	local topSpeed = 0
	for _, h in Heroes.list do
		top = math.max(top, Heroes.maxHealth(cfg, h.id))
		topSpeed = math.max(topSpeed, Heroes.speedScale(cfg, h.id))
	end
	local health = Heroes.maxHealth(cfg, id)
	local speed = Heroes.speedScale(cfg, id)
	return {
		id = id,
		name = hero.name,
		role = hero.role,
		blurb = hero.blurb,
		health = health,
		healthBar = bar(health, top),
		speed = speed,
		speedBar = bar(speed, topSpeed),
		guns = { GunCards.gun(cfg, hero.primary), GunCards.launcher(cfg, id) },
	}
end

local function summaryOf(card: Card): string
	local function text(key: string): string
		for _, l in card.lines do
			if l.key == key then
				return l.text
			end
		end
		return "?"
	end
	if card.kind == "blast" then
		return `{card.name}: {text("damage")} dmg, size {text("radius")}`
	end
	return `{card.name}: {text("damage")} dmg, {text("rate")}, range {text("range")}`
end

function GunCards.heroLines(cfg: any, heroId: string): { string }
	local card = GunCards.hero(cfg, heroId)
	return {
		`{card.role}, {card.health} health`,
		summaryOf(card.guns[1]),
		summaryOf(card.guns[2]),
	}
end

return GunCards
