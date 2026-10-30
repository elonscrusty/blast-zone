--!strict
-- Which gun sits in slot 1 and what its numbers are. Pure: the Config table is passed in, so Lune tests it.
-- The upgrade piece only knows the pistol ("firearm" block of the stat sheet). A found gun gets the same
-- upgrades by scaling: each stat is the gun's base times (upgraded pistol / base pistol). Pellets and
-- spread are added on top (a pistol with Twin Shot has +1 bullet, so a Breaker with it has 7).

local WeaponCatalog = {}

export type GunStats = {
	damage: number,
	fireInterval: number,
	magazine: number,
	reloadSeconds: number,
	range: number,
	pellets: number,
	spreadDegrees: number,
}

local MAX_EXTRA_PELLETS = 4

-- True for the pistol and every found gun.
function WeaponCatalog.isGun(cfg: any, id: string): boolean
	return id == cfg.Weapons.Firearm.id or cfg.Weapons.Guns[id] ~= nil
end

-- The gun's own definition (the pistol for unknown ids).
function WeaponCatalog.def(cfg: any, id: string): any
	return cfg.Weapons.Guns[id] or cfg.Weapons.Firearm
end

function WeaponCatalog.displayName(cfg: any, id: string): string
	return WeaponCatalog.def(cfg, id).displayName
end

local function ratio(upgraded: number, base: number): number
	if base <= 0 then
		return 1
	end
	return upgraded / base
end

-- Effective numbers for gun `id`, given the participant's upgraded pistol block.
function WeaponCatalog.stats(cfg: any, id: string, upgradedPistol: GunStats): GunStats
	local pistol = cfg.Weapons.Firearm
	local gun = cfg.Weapons.Guns[id]
	if gun == nil then
		return table.clone(upgradedPistol)
	end
	local extraPellets = math.clamp(upgradedPistol.pellets - pistol.pellets, 0, MAX_EXTRA_PELLETS)
	return {
		damage = gun.damage * ratio(upgradedPistol.damage, pistol.damage),
		fireInterval = gun.fireInterval * ratio(upgradedPistol.fireInterval, pistol.fireInterval),
		magazine = math.max(
			1,
			math.floor(gun.magazine * ratio(upgradedPistol.magazine, pistol.magazine) + 0.5)
		),
		reloadSeconds = gun.reloadSeconds
			* ratio(upgradedPistol.reloadSeconds, pistol.reloadSeconds),
		range = gun.range * ratio(upgradedPistol.range, pistol.range),
		pellets = gun.pellets + extraPellets,
		spreadDegrees = math.max(
			0,
			gun.spreadDegrees + (upgradedPistol.spreadDegrees - pistol.spreadDegrees)
		),
	}
end

-- What a broken container drops. `chanceRoll` and `pickRoll` are in [0, 1). nil = no gun.
function WeaponCatalog.rollDrop(cfg: any, chanceRoll: number, pickRoll: number): string?
	local drops = cfg.Weapons.Drops
	if chanceRoll >= drops.chance then
		return nil
	end
	local total = 0
	for _, id in drops.order do
		total += drops.weights[id] or 0
	end
	if total <= 0 then
		return nil
	end
	local at = pickRoll * total
	local last: string? = nil
	for _, id in drops.order do
		local w = drops.weights[id] or 0
		if w > 0 then
			last = id
			if at < w then
				return id
			end
			at -= w
		end
	end
	return last
end

-- The odds of each gun from one container, for showing players (and tests). Sums to `chance`.
function WeaponCatalog.dropOdds(cfg: any): { [string]: number }
	local drops = cfg.Weapons.Drops
	local total = 0
	for _, id in drops.order do
		total += drops.weights[id] or 0
	end
	local out = {}
	for _, id in drops.order do
		out[id] = if total > 0 then drops.chance * (drops.weights[id] or 0) / total else 0
	end
	return out
end

return WeaponCatalog
