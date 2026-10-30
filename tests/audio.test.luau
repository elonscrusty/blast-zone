--!strict
local fs = require("@lune/fs")

local Harness = require("./harness")
local AudioCatalog = require("../src/client/Audio/AudioCatalog")
local AudioEvents = require("../src/client/Audio/AudioEvents")
local AudioIds = require("../src/client/Audio/AudioIds")
local AudioLimiter = require("../src/client/Audio/AudioLimiter")
local AudioMath = require("../src/client/Audio/AudioMath")
local MusicPlan = require("../src/client/Audio/MusicPlan")
local MatchPhase = require("../src/shared/MatchPhase")

local ME = "p1"

local function tracker(): AudioEvents.Tracker
	return AudioEvents.new(ME, "arc_mortar")
end

local function cueOf(r: AudioEvents.Request?): string?
	return if r then r.cue else nil
end

Harness.test("audio: every cue is sane and idFrom points at a real cue", function()
	for _, name in AudioCatalog.names() do
		local cue = AudioCatalog.cues[name]
		Harness.truthy(cue.volume > 0 and cue.volume <= 1, name .. " volume")
		Harness.truthy(cue.maxVoices >= 1, name .. " maxVoices")
		Harness.truthy(cue.minGap >= 0, name .. " minGap")
		Harness.truthy(cue.priority >= 1 and cue.priority <= 3, name .. " priority")
		Harness.truthy(cue.seconds > 0, name .. " seconds")
		Harness.truthy(#cue.brief > 0, name .. " brief")
		if cue.distance then
			Harness.truthy(cue.distance.max > cue.distance.ref, name .. " distance")
		end
		if cue.idFrom then
			Harness.truthy(AudioCatalog.cues[cue.idFrom] ~= nil, name .. " idFrom")
			Harness.truthy(AudioCatalog.cues[cue.idFrom].idFrom == nil, name .. " idFrom chain")
		end
		Harness.eq(cue.loop == true, cue.group == "Music", name .. " loop only for music")
	end
end)

Harness.test("audio: no sound ids are invented; the shipped table is empty and valid", function()
	Harness.eq(next(AudioIds), nil)
	Harness.eq(#AudioCatalog.problems(AudioIds), 0)
	Harness.eq(AudioCatalog.assetId("fire_pistol", AudioIds), nil)
end)

Harness.test("audio: ids are checked and idFrom shares one id", function()
	local problems = AudioCatalog.problems({ fire_pistol = 12.5, nope = 3, slide = 0, pickup = 77 })
	Harness.eq(#problems, 3)
	Harness.eq(AudioCatalog.assetId("fire_pistol_other", { fire_pistol = 555 }), 555)
	Harness.eq(
		AudioCatalog.assetId("fire_pistol_other", { fire_pistol_other = 9, fire_pistol = 555 }),
		9
	)
	Harness.eq(AudioCatalog.assetId("fire_pistol", { fire_pistol = -4 }), nil)
	Harness.eq(AudioCatalog.assetId("not_a_cue", { fire_pistol = 1 }), nil)
end)

Harness.test("audio: plans/AUDIO-IDS.md lists every cue", function()
	local doc = fs.readFile("plans/AUDIO-IDS.md")
	for _, name in AudioCatalog.names() do
		Harness.truthy(
			string.find(doc, "`" .. name .. "`", 1, true) ~= nil,
			name .. " missing in doc"
		)
	end
end)

Harness.test("audio: loudness is full near, falls off, and is silent far", function()
	Harness.near(AudioMath.scale(5, 10, 50), 1)
	Harness.near(AudioMath.scale(10, 10, 50), 1)
	Harness.near(AudioMath.scale(30, 10, 50), 0.25)
	Harness.eq(AudioMath.scale(50, 10, 50), 0)
	Harness.eq(AudioMath.scale(900, 10, 50), 0)
	Harness.eq(AudioMath.scale(0 / 0, 10, 50), 0)
	Harness.truthy(AudioMath.scale(20, 10, 50) > AudioMath.scale(40, 10, 50), "farther is quieter")
	Harness.near(AudioMath.groundDistance({ X = 0, Y = 50, Z = 0 }, { X = 3, Y = 0, Z = 4 }), 5)
end)

Harness.test("audio limiter: min gap, per-cue voices, release", function()
	local lim = AudioLimiter.new(10, 2)
	local spec = { maxVoices = 2, minGap = 0.5, priority = 1 }
	Harness.eq(lim:tryStart("a", spec, 0), true)
	Harness.eq(lim:tryStart("a", spec, 0.2), false, "too soon")
	Harness.eq(lim:tryStart("a", spec, 0.6), true)
	Harness.eq(lim:tryStart("a", spec, 1.2), false, "two already playing")
	lim:finish("a")
	Harness.eq(lim:tryStart("a", spec, 1.3), true)
	lim:finish("a")
	lim:finish("a")
	lim:finish("a") -- extra finishes are ignored
	Harness.eq(lim:active(), 0)
end)

Harness.test(
	"audio limiter: busy mix refuses far sounds first and keeps room for your own",
	function()
		local lim = AudioLimiter.new(10, 2)
		local far = { maxVoices = 99, minGap = 0, priority = 3 }
		local near = { maxVoices = 99, minGap = 0, priority = 2 }
		local own = { maxVoices = 99, minGap = 0, priority = 1 }
		for i = 1, 6 do
			Harness.eq(lim:tryStart("far" .. i, far, 0), true)
		end
		Harness.eq(lim:tryStart("far7", far, 0), false, "far sounds stop at 60% full")
		for i = 1, 2 do
			Harness.eq(lim:tryStart("near" .. i, near, 0), true)
		end
		Harness.eq(lim:tryStart("near3", near, 0), true) -- 8 -> 9, limit 8.5
		Harness.eq(lim:tryStart("near4", near, 0), false)
		Harness.eq(lim:tryStart("own1", own, 0), true)
		Harness.eq(lim:tryStart("own2", own, 0), true)
		Harness.eq(lim:tryStart("own3", own, 0), true)
		Harness.eq(lim:tryStart("own4", own, 0), false, "cap plus reserve is the hard limit")
		Harness.eq(lim:active(), 12)
	end
)

Harness.test("audio limiter: a 200-shot firefight never goes over the caps", function()
	local lim = AudioLimiter.new(18, 4)
	local spec = { maxVoices = 3, minGap = 0.09, priority = 3 }
	local started, peak = 0, 0
	for i = 0, 199 do
		if lim:tryStart("fire_pistol_other", spec, i * 0.02) then
			started += 1
			peak = math.max(peak, lim:active())
		end
		if i % 10 == 0 then
			lim:finish("fire_pistol_other") -- a sound ends every 0.2 s
		end
	end
	Harness.truthy(peak <= 3, "never more than 3 at once, was " .. peak)
	Harness.truthy(started < 100, "repeats were thinned out")
end)

Harness.test("audio limiter: clear forgets everything", function()
	local lim = AudioLimiter.new(4, 0)
	local spec = { maxVoices = 1, minGap = 10, priority = 1 }
	Harness.eq(lim:tryStart("a", spec, 0), true)
	lim:clear()
	Harness.eq(lim:active(), 0)
	Harness.eq(lim:tryStart("a", spec, 1), true)
end)

Harness.test("audio music: every phase has a plan and finished is quiet", function()
	for _, phase in MatchPhase.ORDER do
		local track = MusicPlan.forPhase(phase)
		if phase == "Finished" then
			Harness.eq(track, nil)
		else
			Harness.truthy(track ~= nil and AudioCatalog.cues[track].group == "Music", phase)
		end
	end
	Harness.eq(MusicPlan.forPhase("Active"), "music_match")
	Harness.eq(MusicPlan.forPhase("FinalPressure"), "music_final")
	Harness.eq(MusicPlan.forPhase("Waiting"), "music_lobby")
	Harness.eq(MusicPlan.forPhase(5), nil)
end)

Harness.test("audio events: shots are own, someone else's, or the mortar", function()
	local t = tracker()
	local pos = { X = 1, Y = 0, Z = 2 }
	Harness.eq(
		cueOf(t:shot({ shooterId = ME, weaponId = "volt_pistol", origin = pos })),
		"fire_pistol"
	)
	Harness.eq(
		cueOf(t:shot({ shooterId = "b2", weaponId = "volt_pistol", origin = pos })),
		"fire_pistol_other"
	)
	Harness.eq(
		cueOf(t:shot({ shooterId = "b2", weaponId = "arc_mortar", origin = pos })),
		"fire_mortar"
	)
	Harness.eq(t:shot({ shooterId = 5 }), nil)
	Harness.eq(t:shot("junk"), nil)
	local r = t:shot({ shooterId = "b2", weaponId = "volt_pistol", origin = pos })
	Harness.truthy(r ~= nil and r.pos == pos, "position travels with the request")
end)

Harness.test("audio events: the mortar warning ring is not a bang, the blast is", function()
	local t = tracker()
	Harness.eq(t:explosion({ pos = { X = 0, Y = 0, Z = 0 }, radius = 9, warnEndsAt = 5 }), nil)
	Harness.eq(cueOf(t:explosion({ pos = { X = 0, Y = 0, Z = 0 }, radius = 9 })), "explosion")
	Harness.eq(t:explosion({ radius = 9 }), nil)
end)

Harness.test("audio events: hits, kills and damage", function()
	local t = tracker()
	Harness.eq(cueOf(t:hit({ targetId = "b1", amount = 10, killed = false })), "hit_confirm")
	Harness.eq(cueOf(t:hit({ targetId = "b1", amount = 10, killed = true })), "kill_confirm")
	Harness.eq(cueOf(t:damageTaken({ amount = 5, cause = "bullet" })), "damage_taken")
	local zone = t:damageTaken({ amount = 4, cause = "zone" })
	Harness.truthy(zone ~= nil and zone.scale == 0.5, "zone damage is softer")
end)

Harness.test("audio events: reload start and end come once each", function()
	local t = tracker()
	Harness.eq(t:ammoState({ slot = 1, ammo = 12, reloadEndsAt = nil }), nil)
	Harness.eq(t:ammoState({ slot = 1, ammo = 11, reloadEndsAt = nil }), nil) -- firing
	Harness.eq(cueOf(t:ammoState({ slot = 1, ammo = 11, reloadEndsAt = 9 })), "reload_start")
	Harness.eq(t:ammoState({ slot = 1, ammo = 11, reloadEndsAt = 9 }), nil, "no repeat")
	Harness.eq(cueOf(t:ammoState({ slot = 1, ammo = 12, reloadEndsAt = nil })), "reload_end")
	Harness.eq(t:ammoState({ slot = 1, ammo = 12, reloadEndsAt = nil }), nil)
end)

Harness.test("audio events: switching weapon mid-reload makes no end click", function()
	local t = tracker()
	t:ammoState({ slot = 1, ammo = 5, reloadEndsAt = nil })
	Harness.eq(cueOf(t:ammoState({ slot = 1, ammo = 5, reloadEndsAt = 3 })), "reload_start")
	Harness.eq(t:ammoState({ slot = 1, ammo = 5, reloadEndsAt = nil }), nil)
end)

Harness.test("audio events: slide, containers, pickups", function()
	local t = tracker()
	local pos = { X = 4, Y = 0, Z = 4 }
	Harness.eq(cueOf(t:slide({ participantId = ME, fromPos = pos })), "slide")
	Harness.eq(cueOf(t:slide({ participantId = "b1", fromPos = pos })), "slide_other")
	Harness.eq(cueOf(t:containerHit(pos)), "container_hit")
	Harness.eq(t:containerHit(nil), nil)
	Harness.eq(cueOf(t:containerBroken({ containerId = "c1", pos = pos })), "container_break")
	Harness.eq(t:containerBroken({ containerId = "c1" }), nil)
	Harness.eq(cueOf(t:pickupRemoved({ pickupId = "x", collectedBy = ME })), "pickup")
	Harness.eq(t:pickupRemoved({ pickupId = "x", collectedBy = "b1" }), nil)
	Harness.eq(t:pickupRemoved({ pickupId = "x" }), nil)
end)

Harness.test("audio events: level-up only when the level goes up; upgrade pick", function()
	local t = tracker()
	Harness.eq(t:xp({ level = 1, xp = 3 }), nil)
	Harness.eq(cueOf(t:xp({ level = 2, xp = 0 })), "level_up")
	Harness.eq(t:xp({ level = 2, xp = 5 }), nil)
	Harness.eq(cueOf(t:upgradeApplied({ upgradeId = "u", stacks = 1 })), "upgrade_pick")
end)

Harness.test("audio events: zone warns once per stage and sudden death hits once", function()
	local t = tracker()
	Harness.eq(t:zone({ stage = 0 }), nil)
	Harness.eq(cueOf(t:zone({ stage = 1, warningEndsAt = 70 })), "zone_warning")
	Harness.eq(t:zone({ stage = 1, warningEndsAt = 70 }), nil, "same stage again")
	Harness.eq(t:zone({ stage = 1 }), nil, "closing, no warning")
	Harness.eq(cueOf(t:zone({ stage = 2, warningEndsAt = 110 })), "zone_warning")
	Harness.eq(cueOf(t:zone({ stage = 99 })), "sudden_death")
	Harness.eq(t:zone({ stage = 99 }), nil)
end)

Harness.test("audio events: eliminations and results", function()
	local t = tracker()
	Harness.eq(cueOf(t:eliminated({ victimId = ME, killerId = "b1" })), "eliminated_self")
	Harness.eq(cueOf(t:eliminated({ victimId = "b1", killerId = "b2" })), "eliminated_other")
	Harness.eq(t:eliminated({ victimId = "b1", killerId = ME }), nil, "kill_confirm covers it")
	Harness.eq(cueOf(t:results({ outcome = "win", you = { placement = 1 } })), "victory")
	Harness.eq(cueOf(t:results({ outcome = "draw", you = { placement = 1 } })), "victory")
	Harness.eq(cueOf(t:results({ outcome = "win", you = { placement = 3 } })), "defeat")
	Harness.eq(t:results({ outcome = "abandoned", you = { placement = 1 } }), nil)
	Harness.eq(t:results({ outcome = "win" }), nil)
end)

Harness.test("audio reset: a new match clears effects and per-match memory", function()
	local t = tracker()
	local a = t:matchState({ matchId = 1, phase = "Waiting" })
	Harness.truthy(a ~= nil and a.musicChanged and a.music == "music_lobby")
	t:xp({ level = 4 })
	t:zone({ stage = 1, warningEndsAt = 5 })
	t:ammoState({ slot = 1, ammo = 3, reloadEndsAt = 2 })

	local same = t:matchState({ matchId = 1, phase = "Waiting" })
	Harness.truthy(same ~= nil and not same.musicChanged and not same.resetEffects)

	local active = t:matchState({ matchId = 2, phase = "Active" })
	Harness.truthy(active ~= nil and active.resetEffects and active.music == "music_match")
	Harness.eq(cueOf(t:zone({ stage = 1, warningEndsAt = 5 })), "zone_warning", "warned again")
	Harness.eq(cueOf(t:xp({ level = 2 })), "level_up", "level restarted at 1")
	Harness.eq(cueOf(t:ammoState({ slot = 1, ammo = 3, reloadEndsAt = 2 })), "reload_start")

	local final = t:matchState({ matchId = 2, phase = "FinalPressure" })
	Harness.truthy(final ~= nil and final.musicChanged and not final.resetEffects)
	Harness.eq(final and final.music, "music_final")
	local over = t:matchState({ matchId = 2, phase = "Finished" })
	Harness.truthy(over ~= nil and over.music == nil and over.musicChanged)
	local reset = t:matchState({ matchId = 2, phase = "Resetting" })
	Harness.truthy(reset ~= nil and reset.resetEffects and reset.music == "music_lobby")
	Harness.eq(t:matchState("junk"), nil)
end)

Harness.test("audio: each found gun has its own shot cue, others are the far version", function()
	local t = tracker()
	local function shot(who: string, gun: string): string?
		return cueOf(t:shot({ shooterId = who, weaponId = gun, origin = { x = 0, y = 0, z = 0 } }))
	end
	Harness.eq(shot(ME, "breaker"), "fire_breaker")
	Harness.eq(shot("p2", "breaker"), "fire_breaker_other")
	Harness.eq(shot(ME, "hornet"), "fire_hornet")
	Harness.eq(shot("b1", "hornet"), "fire_hornet_other")
	Harness.eq(shot(ME, "longline"), "fire_longline")
	Harness.eq(shot("p2", "longline"), "fire_longline_other")
	Harness.eq(shot(ME, "volt_pistol"), "fire_pistol")
	Harness.eq(shot("p2", "mystery"), "fire_pistol_other", "unknown gun falls back to the pistol")
	Harness.eq(AudioCatalog.assetId("fire_hornet_other", { fire_hornet = 7 }), 7)
	Harness.eq(AudioCatalog.assetId("fire_breaker", AudioIds), nil, "no made-up ids")
end)

Harness.test("audio: gun swap and gun drop sounds", function()
	local t = tracker()
	local function ammo(gun: string, n: number, reload: number?): string?
		return cueOf(t:ammoState({ slot = 1, weaponId = gun, ammo = n, reloadEndsAt = reload }))
	end
	Harness.eq(ammo("volt_pistol", 12, nil), nil, "first message is only a baseline")
	Harness.eq(ammo("volt_pistol", 11, nil), nil)
	Harness.eq(ammo("hornet", 30, nil), "gun_swap")
	Harness.eq(ammo("hornet", 29, nil), nil)
	Harness.eq(ammo("hornet", 29, 5), "reload_start")
	t:reset()
	Harness.eq(ammo("volt_pistol", 12, nil), nil, "a new match starts with no swap sound")
	Harness.eq(cueOf(t:gunDropped({ x = 0, y = 0, z = 0 })), "gun_drop")
	Harness.eq(t:gunDropped(nil), nil)
end)
