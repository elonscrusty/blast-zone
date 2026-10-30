--!strict
-- Day to night for the Neon Night city (piece 14). Pure maths, no Roblox calls, so Lune tests it.
-- The client draws it (src/client/Arena/DayNightSystem); the server never needs it.
--
--   t = 0   bright day, neon signs dim
--   t = .55 sunset, neon waking up
--   t = 1   night, full neon glow
--
-- t is tied to the match clock: it hits 1 when sudden death starts. Colors are 0-255 triples.

local DayNight = {}

export type Rgb = { number }

export type Look = {
	clockTime: number, -- Lighting.ClockTime (hours)
	brightness: number,
	ambient: Rgb,
	outdoorAmbient: Rgb,
	atmosphereColor: Rgb,
	atmosphereDecay: Rgb,
	density: number,
	haze: number,
	glare: number,
	bloom: number, -- BloomEffect.Intensity
	tint: Rgb, -- ColorCorrection.TintColor
	saturation: number,
	glow: number, -- 0 = neon at its dimmest, 1 = full glow
}

local DAY: Look = {
	clockTime = 13.5,
	brightness = 3,
	ambient = { 118, 132, 158 },
	outdoorAmbient = { 150, 160, 180 },
	atmosphereColor = { 185, 212, 238 },
	atmosphereDecay = { 120, 150, 190 },
	density = 0.3,
	haze = 1.2,
	glare = 0.2,
	bloom = 0.15,
	tint = { 255, 255, 255 },
	saturation = 0.12,
	glow = 0.12,
}

local SUNSET: Look = {
	clockTime = 18,
	brightness = 2.2,
	ambient = { 130, 105, 135 },
	outdoorAmbient = { 170, 125, 135 },
	atmosphereColor = { 255, 160, 120 },
	atmosphereDecay = { 190, 90, 90 },
	density = 0.38,
	haze = 2.2,
	glare = 0.5,
	bloom = 0.4,
	tint = { 255, 222, 205 },
	saturation = 0.15,
	glow = 0.7,
}

-- Neon Pop Night (carter picked C after video 3): a bright, saturated night. Blue-violet ambient,
-- strong neon bloom, deep navy haze. Night keeps real light on the ground on purpose: crates,
-- shots and players must stay readable.
local NIGHT: Look = {
	clockTime = 23,
	brightness = 1.6,
	ambient = { 104, 128, 214 },
	outdoorAmbient = { 124, 150, 228 },
	atmosphereColor = { 24, 38, 100 },
	atmosphereDecay = { 16, 28, 84 },
	density = 0.36,
	haze = 1,
	glare = 0,
	bloom = 0.85,
	tint = { 222, 228, 255 },
	saturation = 0.3,
	glow = 1,
}

DayNight.SUNSET_AT = 0.55
DayNight.looks = { day = DAY, sunset = SUNSET, night = NIGHT }

local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

local function lerpRgb(a: Rgb, b: Rgb, k: number): Rgb
	return { lerp(a[1], b[1], k), lerp(a[2], b[2], k), lerp(a[3], b[3], k) }
end

local function mix(a: Look, b: Look, k: number): Look
	return {
		clockTime = lerp(a.clockTime, b.clockTime, k),
		brightness = lerp(a.brightness, b.brightness, k),
		ambient = lerpRgb(a.ambient, b.ambient, k),
		outdoorAmbient = lerpRgb(a.outdoorAmbient, b.outdoorAmbient, k),
		atmosphereColor = lerpRgb(a.atmosphereColor, b.atmosphereColor, k),
		atmosphereDecay = lerpRgb(a.atmosphereDecay, b.atmosphereDecay, k),
		density = lerp(a.density, b.density, k),
		haze = lerp(a.haze, b.haze, k),
		glare = lerp(a.glare, b.glare, k),
		bloom = lerp(a.bloom, b.bloom, k),
		tint = lerpRgb(a.tint, b.tint, k),
		saturation = lerp(a.saturation, b.saturation, k),
		glow = lerp(a.glow, b.glow, k),
	}
end

local function clamp01(x: number): number
	if x ~= x then
		return 0
	end
	return math.clamp(x, 0, 1)
end

-- The whole look at t (0 to 1). Smooth, no jumps.
function DayNight.look(t: number): Look
	local x = clamp01(t)
	if x <= DayNight.SUNSET_AT then
		return mix(DAY, SUNSET, x / DayNight.SUNSET_AT)
	end
	return mix(SUNSET, NIGHT, (x - DayNight.SUNSET_AT) / (1 - DayNight.SUNSET_AT))
end

export type ZoneStamp = { startedAt: number, stage: number }
export type ZoneConfig = {
	stages: { { closeAt: number } },
	suddenDeath: { startsAt: number },
}

-- Server time at which the Active phase began, worked out from any ZoneState (a late joiner gets
-- one too). A ZoneState's startedAt is "when this circle began closing", which Config says is
-- closeAt seconds after Active (0 before the first warning, startsAt for sudden death).
function DayNight.matchStart(state: ZoneStamp, zone: ZoneConfig): number
	local offset = 0
	if state.stage == 99 then
		offset = zone.suddenDeath.startsAt
	elseif state.stage >= 1 and zone.stages[state.stage] ~= nil then
		offset = zone.stages[state.stage].closeAt
	end
	return state.startedAt - offset
end

-- t for a match that started at matchStart (server time). 1 from sudden death on.
function DayNight.progress(matchStart: number, now: number, zone: ZoneConfig): number
	local length = zone.suddenDeath.startsAt
	if length <= 0 then
		return 1
	end
	return clamp01((now - matchStart) / length)
end

-- Where t is heading right now: the match clock during a live match, the lobby value otherwise.
-- matchStart is nil until the first ZoneState of the match has arrived. A fixedT (0 to 1) holds
-- the sky still at that value, match or lobby (Neon Pop Night holds it at 1).
function DayNight.targetT(
	live: boolean,
	matchStart: number?,
	now: number,
	zone: ZoneConfig,
	lobbyT: number,
	fixedT: number?
): number
	if fixedT ~= nil then
		return clamp01(fixedT)
	end
	if not live or matchStart == nil then
		return clamp01(lobbyT)
	end
	return DayNight.progress(matchStart, now, zone)
end

-- Moves `current` toward `target` by at most maxPerSecond * dt. Used so the sky glides.
function DayNight.follow(current: number, target: number, dt: number, maxPerSecond: number): number
	local step = math.max(maxPerSecond, 0) * math.max(dt, 0)
	local delta = target - current
	if math.abs(delta) <= step then
		return target
	end
	return current + (if delta > 0 then step else -step)
end

-- Neon is updated in `steps` levels, so a part is only touched when the level changes.
function DayNight.glowLevel(glow: number, steps: number): number
	local n = math.max(math.floor(steps), 1)
	return math.floor(clamp01(glow) * n + 0.5)
end

-- A window is lit once the glow passes its own threshold, so windows come on one by one.
function DayNight.windowLit(glow: number, litAt: number): boolean
	return glow >= litAt
end

-- Soft neon (strips, signs) fades its color between dim and bright as glow rises.
function DayNight.blend(glow: number): number
	return clamp01(glow)
end

return DayNight
