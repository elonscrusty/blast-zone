--!strict
-- Ammo, reload, fire rate and weapon switching for ONE participant. Pure: time is passed in, so a
-- reload can never finish after it was cancelled and a fast client can never out-shoot the server.
-- Slots: 1 = firearm, 2 = explosive. Each slot has its own magazine, so switching never copies ammo.

local WeaponState = {}
WeaponState.__index = WeaponState

export type Stats = { fireInterval: number, magazine: number, reloadSeconds: number }

export type State = typeof(setmetatable(
	{} :: {
		slot: number,
		ammo: { [number]: number },
		reloadEndsAt: { [number]: number },
		nextFireAt: { [number]: number },
		swapReadyAt: number,
		locked: boolean,
		tolerance: number,
	},
	WeaponState
))

export type FireResult = { ok: boolean, reason: string?, startedReload: boolean }

-- `magazines` = starting ammo per slot. `tolerance` = how early (seconds) a shot may arrive.
function WeaponState.new(magazines: { number }, tolerance: number): State
	local ammo = table.clone(magazines)
	return setmetatable({
		slot = 1,
		ammo = ammo,
		reloadEndsAt = {},
		nextFireAt = {},
		swapReadyAt = 0,
		locked = false,
		tolerance = tolerance,
	}, WeaponState)
end

local function no(reason: string): FireResult
	return { ok = false, reason = reason, startedReload = false }
end

function WeaponState.isReloading(self: State): boolean
	return self.reloadEndsAt[self.slot] ~= nil
end

function WeaponState.canFire(self: State, now: number): boolean
	return not self.locked
		and now >= self.swapReadyAt
		and self.reloadEndsAt[self.slot] == nil
		and (self.ammo[self.slot] or 0) > 0
		and now + self.tolerance >= (self.nextFireAt[self.slot] or 0)
end

function WeaponState.startReload(self: State, now: number, st: Stats): (boolean, string?)
	if self.locked then
		return false, "locked"
	end
	if now < self.swapReadyAt then
		return false, "switching"
	end
	if self.reloadEndsAt[self.slot] ~= nil then
		return false, "reloading"
	end
	if (self.ammo[self.slot] or 0) >= st.magazine then
		return false, "full"
	end
	self.reloadEndsAt[self.slot] = now + st.reloadSeconds
	return true, nil
end

-- One trigger pull for the equipped weapon. Spends the round when it succeeds.
function WeaponState.tryFire(self: State, now: number, st: Stats): FireResult
	if self.locked then
		return no("locked")
	end
	if now < self.swapReadyAt then
		return no("switching")
	end
	local slot = self.slot
	if self.reloadEndsAt[slot] ~= nil then
		return no("reloading")
	end
	if (self.ammo[slot] or 0) <= 0 then
		-- Empty: pulling the trigger starts the reload (auto reload).
		local started = self:startReload(now, st)
		return { ok = false, reason = "empty", startedReload = started }
	end
	if now + self.tolerance < (self.nextFireAt[slot] or 0) then
		return no("too-fast")
	end
	self.ammo[slot] -= 1
	self.nextFireAt[slot] = math.max(self.nextFireAt[slot] or 0, now - self.tolerance)
		+ st.fireInterval
	local started = false
	if self.ammo[slot] == 0 then
		started = self:startReload(now, st) -- last round gone: reload right away
	end
	return { ok = true, reason = nil, startedReload = started }
end

-- Switching drops a reload in progress (its time is lost) and keeps each slot's own ammo.
function WeaponState.equip(self: State, slot: number, now: number, swapSeconds: number): boolean
	if self.locked or slot == self.slot or self.ammo[slot] == nil then
		return false
	end
	self.reloadEndsAt[self.slot] = nil
	self.slot = slot
	self.swapReadyAt = now + swapSeconds
	return true
end

-- A different gun now sits in `slot` (a found gun): full magazine, no reload, its own fire rate.
-- A short swap delay applies when it is the equipped slot. Refused once locked.
function WeaponState.replace(
	self: State,
	slot: number,
	magazine: number,
	now: number,
	swapSeconds: number
): boolean
	if self.locked or self.ammo[slot] == nil then
		return false
	end
	self.ammo[slot] = magazine
	self.reloadEndsAt[slot] = nil
	self.nextFireAt[slot] = nil
	if slot == self.slot then
		self.swapReadyAt = math.max(self.swapReadyAt, now + swapSeconds)
	end
	return true
end

-- Finishes reloads whose time is up. Returns the slots that just completed.
function WeaponState.update(self: State, now: number, statsOf: (number) -> Stats): { number }
	local done = {}
	for slot, endsAt in self.reloadEndsAt do
		if now >= endsAt then
			self.ammo[slot] = statsOf(slot).magazine
			self.reloadEndsAt[slot] = nil
			table.insert(done, slot)
		end
	end
	return done
end

-- Eliminated (or the match left combat): nothing fires, reloads, switches or completes again.
function WeaponState.lock(self: State)
	self.locked = true
	self.reloadEndsAt = {}
end

return WeaponState
