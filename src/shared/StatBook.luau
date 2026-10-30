--!strict
-- Effective stats per participant = base Config + whatever the upgrade system says.
-- Movement (02) and Combat (03) call get() and never read upgrade state themselves.
-- Piece 08 installs a provider with setProvider(); until then everyone gets base stats.

local Signal = require("./Signal")

export type Sheet = {
	moveSpeed: number,
	slideDistance: number,
	slideDuration: number,
	slideCooldown: number,
	firearm: {
		damage: number,
		fireInterval: number,
		magazine: number,
		reloadSeconds: number,
		range: number,
		pellets: number,
		spreadDegrees: number,
		pierce: number,
	},
	explosive: {
		damage: number,
		radius: number,
		fireInterval: number,
		magazine: number,
		reloadSeconds: number,
		range: number,
		projectileSpeed: number,
		aftershock: number,
	},
}

local StatBook = {}
StatBook.__index = StatBook

-- A fresh sheet every call, so callers can never edit the shared base by accident.
function StatBook.base(cfg: any): Sheet
	local f, e = cfg.Weapons.Firearm, cfg.Weapons.Explosive
	return {
		moveSpeed = cfg.Movement.walkSpeed,
		slideDistance = cfg.Slide.distance,
		slideDuration = cfg.Slide.duration,
		slideCooldown = cfg.Slide.cooldown,
		firearm = {
			damage = f.damage,
			fireInterval = f.fireInterval,
			magazine = f.magazine,
			reloadSeconds = f.reloadSeconds,
			range = f.range,
			pellets = f.pellets,
			spreadDegrees = f.spreadDegrees,
			pierce = f.pierce,
		},
		explosive = {
			damage = e.damage,
			radius = e.radius,
			fireInterval = e.fireInterval,
			magazine = e.magazine,
			reloadSeconds = e.reloadSeconds,
			range = e.range,
			projectileSpeed = e.projectileSpeed,
			aftershock = e.aftershock,
		},
	}
end

function StatBook.new(cfg: any): any
	return setmetatable({
		_cfg = cfg,
		_provider = nil :: ((string) -> Sheet?)?,
		_modifiers = {} :: { (string, Sheet) -> () },
		Changed = Signal.new(), -- (participantId)
	}, StatBook)
end

function StatBook.setProvider(self: any, fn: ((string) -> Sheet?)?)
	self._provider = fn
end

-- Modifiers run after the provider, on a copy, in the order they were added (piece 19: the Slide sidegrade).
-- They may change the plain numbers on the sheet and, since piece 46, the numbers inside its `firearm` /
-- `explosive` tables: `get` hands them their own copy of both, so the upgrade piece's sheet is never touched.
function StatBook.addModifier(self: any, fn: (string, Sheet) -> ())
	table.insert(self._modifiers, fn)
end

function StatBook.get(self: any, id: string): Sheet
	local sheet: Sheet? = nil
	local provider: ((string) -> Sheet?)? = self._provider
	if provider then
		sheet = provider(id)
	end
	local modifiers: { (string, Sheet) -> () } = self._modifiers
	if #modifiers == 0 then
		return sheet or StatBook.base(self._cfg)
	end
	local copy: Sheet = table.clone(sheet or StatBook.base(self._cfg))
	copy.firearm = table.clone(copy.firearm)
	copy.explosive = table.clone(copy.explosive)
	for _, fn in modifiers do
		fn(id, copy)
	end
	return copy
end

-- Provider owners call this after an upgrade lands or a match resets.
function StatBook.invalidate(self: any, id: string)
	self.Changed:fire(id)
end

return StatBook
