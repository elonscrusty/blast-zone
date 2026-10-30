--!strict
-- Turns server messages into "play this cue" requests. Only reads payloads; never trusts their shape
-- (anything odd is ignored). No Roblox services, so the tests can run it.
-- A Request: { cue, pos? (where it happened, for distance), scale? (extra loudness factor) }.

local MusicPlan = require("./MusicPlan")

local AudioEvents = {}
AudioEvents.__index = AudioEvents

export type Request = { cue: string, pos: any?, scale: number? }
export type Tracker = typeof(setmetatable(
	{} :: {
		myId: string,
		explosiveId: string,
		reloading: { [number]: boolean },
		ammo: { [number]: number },
		level: number,
		zoneWarned: { [number]: boolean },
		phase: string?,
		matchId: number?,
	},
	AudioEvents
))

function AudioEvents.new(myId: string, explosiveId: string): Tracker
	return setmetatable({
		myId = myId,
		explosiveId = explosiveId,
		reloading = {},
		ammo = {},
		level = 1,
		zoneWarned = {},
		phase = nil,
		matchId = nil,
	}, AudioEvents)
end

local function isTable(v: any): boolean
	return type(v) == "table"
end

-- Forget per-match memory (level, reload flags, zone warnings).
function AudioEvents.reset(self: Tracker)
	table.clear(self.reloading)
	table.clear(self.ammo)
	table.clear(self.zoneWarned)
	self.level = 1
end

function AudioEvents.shot(self: Tracker, p: any): Request?
	if not isTable(p) or type(p.shooterId) ~= "string" then
		return nil
	end
	if p.weaponId == self.explosiveId then
		return { cue = "fire_mortar", pos = p.origin }
	end
	return {
		cue = if p.shooterId == self.myId then "fire_pistol" else "fire_pistol_other",
		pos = p.origin,
	}
end

-- The blast itself. The earlier "warning ring" message (warnEndsAt set) is not a bang.
function AudioEvents.explosion(_self: Tracker, p: any): Request?
	if not isTable(p) or p.pos == nil or p.warnEndsAt ~= nil then
		return nil
	end
	return { cue = "explosion", pos = p.pos }
end

function AudioEvents.hit(_self: Tracker, p: any): Request?
	if not isTable(p) then
		return nil
	end
	return { cue = if p.killed == true then "kill_confirm" else "hit_confirm" }
end

function AudioEvents.damageTaken(_self: Tracker, p: any): Request?
	if not isTable(p) then
		return nil
	end
	-- Zone ticks come every second: keep them soft so they do not drown out real hits.
	return { cue = "damage_taken", scale = if p.cause == "zone" then 0.5 else 1 }
end

-- Reload start when the server says a reload is running; reload end when it stops and the ammo went up
-- (switching weapon mid-reload cancels it with no ammo gain, so it makes no end click).
function AudioEvents.ammoState(self: Tracker, p: any): Request?
	if not isTable(p) or type(p.slot) ~= "number" or type(p.ammo) ~= "number" then
		return nil
	end
	local slot: number = p.slot
	local nowReloading = type(p.reloadEndsAt) == "number"
	local wasReloading = self.reloading[slot] == true
	local before = self.ammo[slot]
	self.reloading[slot] = nowReloading
	self.ammo[slot] = p.ammo
	if nowReloading and not wasReloading then
		return { cue = "reload_start" }
	elseif wasReloading and not nowReloading and before ~= nil and p.ammo > before then
		return { cue = "reload_end" }
	end
	return nil
end

function AudioEvents.slide(self: Tracker, p: any): Request?
	if not isTable(p) or type(p.participantId) ~= "string" then
		return nil
	end
	return {
		cue = if p.participantId == self.myId then "slide" else "slide_other",
		pos = p.fromPos,
	}
end

-- `pos` is found by the caller from the container part (the message carries only an id).
function AudioEvents.containerHit(_self: Tracker, pos: any): Request?
	if pos == nil then
		return nil
	end
	return { cue = "container_hit", pos = pos }
end

function AudioEvents.containerBroken(_self: Tracker, p: any): Request?
	if not isTable(p) or p.pos == nil then
		return nil
	end
	return { cue = "container_break", pos = p.pos }
end

-- Only your own pickups make a sound; other people's orbs would just be noise.
function AudioEvents.pickupRemoved(self: Tracker, p: any): Request?
	if not isTable(p) or p.collectedBy ~= self.myId then
		return nil
	end
	return { cue = "pickup" }
end

function AudioEvents.xp(self: Tracker, p: any): Request?
	if not isTable(p) or type(p.level) ~= "number" then
		return nil
	end
	local before = self.level
	self.level = p.level
	if p.level > before then
		return { cue = "level_up" }
	end
	return nil
end

function AudioEvents.upgradeApplied(_self: Tracker, p: any): Request?
	if not isTable(p) then
		return nil
	end
	return { cue = "upgrade_pick" }
end

-- One warning per stage (a closing announcement), and one hit for sudden death (stage 99).
function AudioEvents.zone(self: Tracker, p: any): Request?
	if not isTable(p) or type(p.stage) ~= "number" then
		return nil
	end
	local stage: number = p.stage
	if stage == 99 then
		if self.zoneWarned[99] then
			return nil
		end
		self.zoneWarned[99] = true
		return { cue = "sudden_death" }
	end
	if type(p.warningEndsAt) == "number" and stage > 0 and not self.zoneWarned[stage] then
		self.zoneWarned[stage] = true
		return { cue = "zone_warning" }
	end
	return nil
end

function AudioEvents.eliminated(self: Tracker, p: any): Request?
	if not isTable(p) or type(p.victimId) ~= "string" then
		return nil
	end
	if p.victimId == self.myId then
		return { cue = "eliminated_self" }
	end
	-- If you got the kill, kill_confirm already told you.
	if p.killerId == self.myId then
		return nil
	end
	return { cue = "eliminated_other" }
end

-- Win or lose sting from the results message. Abandoned matches and missing data make no sound.
function AudioEvents.results(_self: Tracker, p: any): Request?
	if not isTable(p) or not isTable(p.you) or type(p.you.placement) ~= "number" then
		return nil
	end
	if p.outcome == "abandoned" then
		return nil
	end
	return { cue = if p.you.placement == 1 then "victory" else "defeat" }
end

export type PhaseChange = {
	music: string?, -- track to fade to (nil = fade to quiet)
	musicChanged: boolean,
	resetEffects: boolean,
}

-- Call for every MatchState. Says which music to use and whether to drop leftover effects
-- (a new match id, or the Resetting/Waiting edge).
function AudioEvents.matchState(self: Tracker, p: any): PhaseChange?
	if not isTable(p) or type(p.phase) ~= "string" then
		return nil
	end
	local phase: string = p.phase
	local matchId = if type(p.matchId) == "number" then p.matchId else nil
	local phaseChanged = phase ~= self.phase
	local newMatch = matchId ~= nil and matchId ~= self.matchId
	local reset = (phaseChanged and MusicPlan.isReset(phase)) or newMatch
	self.phase = phase
	self.matchId = matchId
	if reset then
		self:reset()
	end
	return {
		music = MusicPlan.forPhase(phase),
		musicChanged = phaseChanged,
		resetEffects = reset,
	}
end

return AudioEvents
