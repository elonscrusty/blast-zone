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
	},
	explosive: {
		damage: number,
		radius: number,
		fireInterval: number,
		magazine: number,
		reloadSeconds: number,
		range: number,
		projectileSpeed: number,
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
		},
		explosive = {
			damage = e.damage,
			radius = e.radius,
			fireInterval = e.fireInterval,
			magazine = e.magazine,
			reloadSeconds = e.reloadSeconds,
			range = e.range,
			projectileSpeed = e.projectileSpeed,
		},
	}
end

function StatBook.new(cfg: any): any
	return setmetatable({
		_cfg = cfg,
		_provider = nil :: ((string) -> Sheet?)?,
		Changed = Signal.new(), -- (participantId)
	}, StatBook)
end

function StatBook.setProvider(self: any, fn: ((string) -> Sheet?)?)
	self._provider = fn
end

function StatBook.get(self: any, id: string): Sheet
	local provider: ((string) -> Sheet?)? = self._provider
	if provider then
		local sheet = provider(id)
		if sheet then
			return sheet
		end
	end
	return StatBook.base(self._cfg)
end

-- Provider owners call this after an upgrade lands or a match resets.
function StatBook.invalidate(self: any, id: string)
	self.Changed:fire(id)
end

return StatBook
