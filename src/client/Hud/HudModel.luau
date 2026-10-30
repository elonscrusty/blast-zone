--!strict
-- What the combat HUD knows and what it shows, as pure data so Lune can test it.
-- The server sends facts (HealthState, AmmoState, SlideState, MatchState, ZoneState, XpState...);
-- the HUD only displays them. `now` is always SERVER time (workspace:GetServerTimeNow()).
--
-- Payload shapes follow shared/Types.luau and shared/RemoteDefs.luau, copied here as plain
-- structural types so this file needs nothing from Roblox.

local MinimapMath = require("./MinimapMath")
local Warnings = require("./Warnings")

export type ZonePayload = MinimapMath.ZoneLike & {
	matchId: number,
	warningEndsAt: number?,
	damagePerSecond: number,
	stage: number,
}

export type Model = {
	localId: string?, -- "p<userId>"
	alive: boolean,
	matchId: number,
	phase: string,
	aliveCount: number,
	totalCount: number,
	health: number,
	maxHealth: number,
	weaponId: string,
	weaponName: string,
	slot: number, -- 1 firearm, 2 explosive
	ammo: number,
	magazine: number,
	reloadEndsAt: number?,
	reloadSeconds: number,
	slideCooldownEndsAt: number,
	slideCooldownTotal: number,
	level: number,
	xp: number,
	xpToNext: number,
	pendingOffers: number,
	zone: ZonePayload?,
	notice: string?,
	noticeUntil: number,
	hurtAt: number, -- server time of the last hit taken
	hurtAmount: number,
	hurtDirX: number?, -- world direction the hit came FROM (x/z), if the server said
	hurtDirZ: number?,
	hitConfirmAt: number,
	hitConfirmAmount: number,
	hitConfirmKilled: boolean,
}

export type Config = {
	maxHealth: number,
	weapons: { { id: string, name: string, magazine: number, reloadSeconds: number } }, -- by slot
	slideCooldown: number,
	lowHealthFraction: number,
	lowAmmoFraction: number,
	edgeTolerance: number,
	noticeSeconds: number,
	hurtSeconds: number,
	hitConfirmSeconds: number,
}

local HudModel = {}

HudModel.COMBAT_PHASES = { Active = true, FinalPressure = true }
HudModel.VISIBLE_PHASES = { Spawning = true, Active = true, FinalPressure = true }

function HudModel.new(config: Config, localId: string?): Model
	local first = config.weapons[1]
	return {
		localId = localId,
		alive = true,
		matchId = 0,
		phase = "Waiting",
		aliveCount = 0,
		totalCount = 0,
		health = config.maxHealth,
		maxHealth = config.maxHealth,
		weaponId = first.id,
		weaponName = first.name,
		slot = 1,
		ammo = first.magazine,
		magazine = first.magazine,
		reloadEndsAt = nil,
		reloadSeconds = first.reloadSeconds,
		slideCooldownEndsAt = 0,
		slideCooldownTotal = config.slideCooldown,
		level = 1,
		xp = 0,
		xpToNext = 1,
		pendingOffers = 0,
		zone = nil,
		notice = nil,
		noticeUntil = 0,
		hurtAt = -1000,
		hurtAmount = 0,
		hurtDirX = nil,
		hurtDirZ = nil,
		hitConfirmAt = -1000,
		hitConfirmAmount = 0,
		hitConfirmKilled = false,
	}
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- Back to a fresh match. Keeps who we are.
function HudModel.reset(m: Model, config: Config)
	local fresh = HudModel.new(config, m.localId)
	fresh.phase = m.phase
	fresh.matchId = m.matchId
	fresh.aliveCount = m.aliveCount
	fresh.totalCount = m.totalCount
	for k, v in fresh :: any do
		(m :: any)[k] = v
	end
end

-- ===== server messages. Bad payloads are ignored, never trusted blindly. =====

function HudModel.applyHealth(m: Model, p: { health: number, max: number })
	if finite(p.health) and finite(p.max) and p.max > 0 then
		m.health = math.clamp(p.health, 0, p.max)
		m.maxHealth = p.max
	end
end

function HudModel.applyAmmo(
	m: Model,
	p: {
		weaponId: string,
		ammo: number,
		magazine: number,
		reloadEndsAt: number?,
	},
	config: Config
)
	if not (finite(p.ammo) and finite(p.magazine)) or p.magazine <= 0 then
		return
	end
	m.weaponId = p.weaponId
	for slot, w in config.weapons do
		if w.id == p.weaponId then
			m.slot = slot
			m.weaponName = w.name
			m.reloadSeconds = w.reloadSeconds
		end
	end
	-- Found guns (not in config.weapons) come with their own name, slot and reload time.
	local extra: any = p
	if type(extra.weaponName) == "string" then
		m.weaponName = extra.weaponName
	end
	if finite(extra.slot) and extra.slot >= 1 then
		m.slot = extra.slot
	end
	if finite(extra.reloadSeconds) and extra.reloadSeconds > 0 then
		m.reloadSeconds = extra.reloadSeconds
	end
	m.ammo = math.clamp(p.ammo, 0, p.magazine)
	m.magazine = p.magazine
	m.reloadEndsAt = if finite(p.reloadEndsAt) then p.reloadEndsAt else nil
end

function HudModel.applySlide(m: Model, p: { cooldownEndsAt: number, serverNow: number })
	if finite(p.cooldownEndsAt) and finite(p.serverNow) then
		m.slideCooldownEndsAt = p.cooldownEndsAt
		-- Total length of this cooldown, so the dial fills smoothly. Never below 0.1 s.
		m.slideCooldownTotal = math.max(0.1, p.cooldownEndsAt - p.serverNow, m.slideCooldownTotal)
	end
end

function HudModel.applyMatch(
	m: Model,
	p: {
		matchId: number?,
		phase: string,
		aliveCount: number,
		totalCount: number,
	},
	config: Config
)
	local newMatch = finite(p.matchId) and (p.matchId :: number) ~= m.matchId
	local enteringStart = (p.phase == "Countdown" or p.phase == "Spawning") and m.phase ~= p.phase
	m.phase = p.phase
	if finite(p.matchId) then
		m.matchId = p.matchId :: number
	end
	if finite(p.aliveCount) then
		m.aliveCount = p.aliveCount
	end
	if finite(p.totalCount) then
		m.totalCount = p.totalCount
	end
	if newMatch or enteringStart then
		HudModel.reset(m, config)
	end
	if not (HudModel.VISIBLE_PHASES[p.phase] == true) then
		m.zone = nil
	end
end

function HudModel.applyZone(m: Model, p: ZonePayload)
	-- A zone from an older match never replaces the current one.
	if finite(p.matchId) and p.matchId < m.matchId then
		return
	end
	if finite(p.centerX) and finite(p.centerZ) and finite(p.fromRadius) and finite(p.toRadius) then
		m.zone = p
	end
end

function HudModel.applyXp(
	m: Model,
	p: { level: number, xp: number, xpToNext: number, pendingOffers: number }
)
	if finite(p.level) and finite(p.xp) and finite(p.xpToNext) and p.xpToNext > 0 then
		m.level, m.xp, m.xpToNext = p.level, p.xp, p.xpToNext
		m.pendingOffers = if finite(p.pendingOffers) then p.pendingOffers else 0
	end
end

function HudModel.applyDamageTaken(
	m: Model,
	p: { amount: number, fromDir: { x: number, z: number }? },
	now: number
)
	if not finite(p.amount) or p.amount <= 0 then
		return
	end
	m.hurtAt = now
	m.hurtAmount = p.amount
	if p.fromDir and finite(p.fromDir.x) and finite(p.fromDir.z) then
		m.hurtDirX, m.hurtDirZ = p.fromDir.x, p.fromDir.z
	else
		m.hurtDirX, m.hurtDirZ = nil, nil
	end
end

function HudModel.applyHitConfirm(m: Model, p: { amount: number, killed: boolean }, now: number)
	if finite(p.amount) then
		m.hitConfirmAt = now
		m.hitConfirmAmount = p.amount
		m.hitConfirmKilled = p.killed == true
	end
end

function HudModel.applyNotice(m: Model, p: { text: string }, now: number, config: Config)
	if type(p.text) == "string" and p.text ~= "" then
		m.notice = string.sub(p.text, 1, 40)
		m.noticeUntil = now + config.noticeSeconds
	end
end

-- The local player was eliminated (from the Eliminated remote).
function HudModel.applyEliminated(m: Model, victimId: string)
	if m.localId ~= nil and victimId == m.localId then
		m.alive = false
	end
end

-- ===== what is shown =====

function HudModel.visible(m: Model): boolean
	return HudModel.VISIBLE_PHASES[m.phase] == true and m.alive
end

-- Controls only work while fighting is allowed and the player is alive.
function HudModel.controlsOn(m: Model): boolean
	return HudModel.COMBAT_PHASES[m.phase] == true and m.alive
end

-- 72 seconds -> "1:12". Rounds up so "0:00" only shows when it really is over.
function HudModel.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds - 1e-9))
	return string.format("%d:%02d", s // 60, s % 60)
end

export type View = {
	visible: boolean,
	healthFraction: number,
	healthText: string,
	maxHealthText: string,
	lowHealth: boolean,
	weaponName: string,
	slot: number,
	ammoText: string,
	magazineText: string,
	ammoFraction: number,
	ammoLow: boolean,
	reloading: boolean,
	reloadFraction: number, -- 0 just started .. 1 done
	slideReady: boolean,
	slideFraction: number, -- 0 just used .. 1 ready
	slideSeconds: number,
	aliveText: string,
	levelText: string,
	xpFraction: number,
	pendingOffers: number,
	zoneText: string, -- "" when there is no zone yet
	zoneKind: string, -- none | warning | closing | holding | suddenDeath
	zoneRadius: number?,
	outsideZone: boolean,
	hurt: number, -- 0..1 red edge strength, fades quickly
	hitConfirm: number, -- 0..1 hit-marker strength
	warning: Warnings.Warning?,
}

local function zoneInfo(
	m: Model,
	now: number,
	px: number?,
	pz: number?,
	config: Config
): (string, string, number?, boolean, number?)
	local z = m.zone
	if z == nil then
		return "", "none", nil, false, nil
	end
	local radius = MinimapMath.currentRadius(z, now)
	local outside = false
	if px ~= nil and pz ~= nil then
		outside = MinimapMath.isOutside(px, pz, z.centerX, z.centerZ, radius, config.edgeTolerance)
	end
	if z.stage >= 99 then
		return "SUDDEN DEATH", "suddenDeath", radius, outside, nil
	end
	if z.warningEndsAt ~= nil and now < z.warningEndsAt then
		local left = z.warningEndsAt - now
		return "ZONE " .. HudModel.clock(left), "warning", radius, outside, left
	end
	if now < z.endsAt and z.fromRadius > z.toRadius then
		return "ZONE " .. HudModel.clock(z.endsAt - now), "closing", radius, outside, nil
	end
	return "ZONE SET", "holding", radius, outside, nil
end

-- Everything the screen needs for one frame. `px, pz` is the local character's position.
function HudModel.derive(m: Model, now: number, px: number?, pz: number?, config: Config): View
	local healthFraction = if m.maxHealth > 0 then math.clamp(m.health / m.maxHealth, 0, 1) else 0
	local lowHealth = m.alive and healthFraction > 0 and healthFraction <= config.lowHealthFraction

	local reloading = m.reloadEndsAt ~= nil and now < (m.reloadEndsAt :: number)
	local reloadFraction = 0
	if reloading then
		local total = math.max(0.05, m.reloadSeconds)
		reloadFraction = math.clamp(1 - ((m.reloadEndsAt :: number) - now) / total, 0, 1)
	end
	local ammoLow = m.magazine > 0 and m.ammo / m.magazine <= config.lowAmmoFraction

	local slideLeft = math.max(0, m.slideCooldownEndsAt - now)
	local slideTotal = math.max(0.1, m.slideCooldownTotal)

	local zoneText, zoneKind, zoneRadius, outside, warnLeft = zoneInfo(m, now, px, pz, config)
	local zoneHurts = m.zone ~= nil and m.zone.damagePerSecond > 0 and zoneKind ~= "warning"

	local hurt = math.clamp(1 - (now - m.hurtAt) / config.hurtSeconds, 0, 1)
	local hit = math.clamp(1 - (now - m.hitConfirmAt) / config.hitConfirmSeconds, 0, 1)

	local warning = Warnings.pick({
		outsideZone = outside and zoneHurts,
		suddenDeath = zoneKind == "suddenDeath",
		lowHealth = lowHealth,
		weaponEmpty = m.ammo <= 0 and not reloading,
		reloading = reloading,
		zoneWarningSeconds = warnLeft,
		zoneClosing = zoneKind == "closing",
		notice = if now < m.noticeUntil then m.notice else nil,
	})

	return {
		visible = HudModel.visible(m),
		healthFraction = healthFraction,
		healthText = tostring(math.ceil(m.health - 1e-9)),
		maxHealthText = "/" .. tostring(math.floor(m.maxHealth + 0.5)),
		lowHealth = lowHealth,
		weaponName = m.weaponName,
		slot = m.slot,
		ammoText = tostring(m.ammo),
		magazineText = "/ " .. tostring(m.magazine),
		ammoFraction = if m.magazine > 0 then math.clamp(m.ammo / m.magazine, 0, 1) else 0,
		ammoLow = ammoLow,
		reloading = reloading,
		reloadFraction = reloadFraction,
		slideReady = slideLeft <= 0,
		slideFraction = 1 - math.clamp(slideLeft / slideTotal, 0, 1),
		slideSeconds = slideLeft,
		aliveText = tostring(m.aliveCount),
		levelText = "LV" .. tostring(m.level),
		xpFraction = math.clamp(m.xp / m.xpToNext, 0, 1),
		pendingOffers = m.pendingOffers,
		zoneText = zoneText,
		zoneKind = zoneKind,
		zoneRadius = zoneRadius,
		outsideZone = outside and zoneHurts,
		hurt = hurt,
		hitConfirm = hit,
		warning = warning,
	}
end

return HudModel
