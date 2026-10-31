--!strict
local Harness = require("./harness")
local HudModel = require("../src/client/Hud/HudModel")

local config: HudModel.Config = {
	maxHealth = 100,
	weapons = {
		{ id = "volt_pistol", name = "Volt Pistol", magazine = 12, reloadSeconds = 1.2 },
		{ id = "arc_mortar", name = "Arc Mortar", magazine = 3, reloadSeconds = 2.4 },
	},
	slideCooldown = 5,
	lowHealthFraction = 0.3,
	lowAmmoFraction = 0.25,
	edgeTolerance = 0.5,
	noticeSeconds = 3,
	hurtSeconds = 0.6,
	hitConfirmSeconds = 0.25,
}

local function fresh(): HudModel.Model
	local m = HudModel.new(config, "p1")
	HudModel.applyMatch(
		m,
		{ matchId = 1, phase = "Active", aliveCount = 6, totalCount = 6 },
		config
	)
	return m
end

Harness.test("health shows the server's number and flags low health", function()
	local m = fresh()
	HudModel.applyHealth(m, { health = 72, max = 100 })
	local v = HudModel.derive(m, 0, nil, nil, config)
	Harness.eq(v.healthText, "72")
	Harness.near(v.healthFraction, 0.72)
	Harness.eq(v.lowHealth, false)
	HudModel.applyHealth(m, { health = 20, max = 100 })
	Harness.eq(HudModel.derive(m, 0, nil, nil, config).lowHealth, true)
	HudModel.applyHealth(m, { health = 0, max = 100 })
	Harness.eq(HudModel.derive(m, 0, nil, nil, config).lowHealth, false) -- dead is not "low"
end)

Harness.test("bad server numbers are ignored, not shown", function()
	local m = fresh()
	HudModel.applyHealth(m, { health = 0 / 0, max = 100 })
	HudModel.applyHealth(m, { health = 50, max = 0 })
	Harness.eq(m.health, 100)
	HudModel.applyAmmo(m, { weaponId = "volt_pistol", ammo = 3, magazine = 0 }, config)
	Harness.eq(m.ammo, 12)
	HudModel.applyHealth(m, { health = 500, max = 100 })
	Harness.eq(m.health, 100) -- clamped to the maximum
end)

Harness.test("reload progress runs from 0 to 1 and ends by itself", function()
	local m = fresh()
	HudModel.applyAmmo(
		m,
		{ weaponId = "volt_pistol", ammo = 0, magazine = 12, reloadEndsAt = 11.2 },
		config
	)
	local start = HudModel.derive(m, 10, nil, nil, config)
	Harness.eq(start.reloading, true)
	Harness.near(start.reloadFraction, 0, 1e-9)
	local mid = HudModel.derive(m, 10.6, nil, nil, config)
	Harness.near(mid.reloadFraction, 0.5, 1e-9)
	local done = HudModel.derive(m, 11.3, nil, nil, config)
	Harness.eq(done.reloading, false)
end)

Harness.test("an empty magazine asks for a reload, but not while already reloading", function()
	local m = fresh()
	HudModel.applyAmmo(m, { weaponId = "volt_pistol", ammo = 0, magazine = 12 }, config)
	Harness.eq((HudModel.derive(m, 0, nil, nil, config).warning :: any).key, "empty")
	HudModel.applyAmmo(
		m,
		{ weaponId = "volt_pistol", ammo = 0, magazine = 12, reloadEndsAt = 5 },
		config
	)
	Harness.eq(HudModel.derive(m, 1, nil, nil, config).warning, nil)
end)

Harness.test("switching weapon changes the slot, name and magazine", function()
	local m = fresh()
	HudModel.applyAmmo(m, { weaponId = "arc_mortar", ammo = 3, magazine = 3 }, config)
	local v = HudModel.derive(m, 0, nil, nil, config)
	Harness.eq(v.slot, 2)
	Harness.eq(v.weaponName, "Arc Mortar")
	Harness.eq(v.magazineText, "/ 3")
end)

Harness.test("slide dial fills up and says ready at the end", function()
	local m = fresh()
	HudModel.applySlide(m, { cooldownEndsAt = 15, serverNow = 10 })
	local early = HudModel.derive(m, 10, nil, nil, config)
	Harness.eq(early.slideReady, false)
	Harness.near(early.slideFraction, 0, 1e-9)
	local mid = HudModel.derive(m, 12.5, nil, nil, config)
	Harness.near(mid.slideFraction, 0.5, 1e-9)
	Harness.eq(HudModel.derive(m, 15, nil, nil, config).slideReady, true)
end)

Harness.test("clock text counts up to the next whole second", function()
	Harness.eq(HudModel.clock(72), "1:12")
	Harness.eq(HudModel.clock(11.2), "0:12")
	Harness.eq(HudModel.clock(0), "0:00")
	Harness.eq(HudModel.clock(-4), "0:00")
end)

local function zone(overrides: { [string]: any }?): HudModel.ZonePayload
	local z: any = {
		matchId = 1,
		centerX = 0,
		centerZ = 0,
		fromRadius = 100,
		toRadius = 50,
		startedAt = 20,
		endsAt = 40,
		warningEndsAt = nil,
		damagePerSecond = 2,
		stage = 1,
	}
	for k, v in overrides or {} do
		z[k] = v
	end
	return z
end

Harness.test("zone: warning counts down, then closing, then holding", function()
	local m = fresh()
	HudModel.applyZone(m, zone({ warningEndsAt = 20 }))
	local warn = HudModel.derive(m, 12, 0, 0, config)
	Harness.eq(warn.zoneKind, "warning")
	Harness.eq(warn.zoneText, "ZONE 0:08")
	Harness.eq((warn.warning :: any).key, "zoneWarning")
	local closing = HudModel.derive(m, 30, 0, 0, config)
	Harness.eq(closing.zoneKind, "closing")
	Harness.near(closing.zoneRadius :: number, 75, 1e-9)
	Harness.eq(HudModel.derive(m, 45, 0, 0, config).zoneKind, "holding")
end)

Harness.test("outside-the-zone warning needs a hurting zone and a real position", function()
	local m = fresh()
	HudModel.applyZone(m, zone())
	Harness.eq(HudModel.derive(m, 45, 80, 0, config).outsideZone, true)
	Harness.eq(HudModel.derive(m, 45, 50, 0, config).outsideZone, false) -- exactly on the edge
	Harness.eq(HudModel.derive(m, 45, nil, nil, config).outsideZone, false) -- no character yet
	-- During the warning nothing hurts yet, so no "outside" scare.
	HudModel.applyZone(m, zone({ warningEndsAt = 60, startedAt = 60, endsAt = 80 }))
	Harness.eq(HudModel.derive(m, 45, 80, 0, config).outsideZone, false)
end)

Harness.test("sudden death is announced", function()
	local m = fresh()
	HudModel.applyZone(m, zone({ stage = 99, damagePerSecond = 25 }))
	local v = HudModel.derive(m, 45, 0, 0, config)
	Harness.eq(v.zoneKind, "suddenDeath")
	Harness.eq(v.zoneText, "SUDDEN DEATH")
end)

Harness.test("getting hit flashes the screen edge, then fades quickly", function()
	local m = fresh()
	HudModel.applyDamageTaken(m, { amount = 10 }, 100)
	Harness.near(HudModel.derive(m, 100, nil, nil, config).hurt, 1, 1e-9)
	Harness.near(HudModel.derive(m, 100.3, nil, nil, config).hurt, 0.5, 1e-9)
	Harness.eq(HudModel.derive(m, 101, nil, nil, config).hurt, 0)
	HudModel.applyDamageTaken(m, { amount = 0 }, 200) -- nothing happened
	Harness.eq(HudModel.derive(m, 200, nil, nil, config).hurt, 0)
end)

Harness.test(
	"the HUD shows only while fighting, and controls only while alive in combat",
	function()
		local m = HudModel.new(config, "p1")
		Harness.eq(HudModel.visible(m), false) -- Waiting
		HudModel.applyMatch(m, { phase = "Spawning", aliveCount = 6, totalCount = 6 }, config)
		Harness.eq(HudModel.visible(m), true)
		Harness.eq(HudModel.controlsOn(m), false) -- spawn presentation: no steering yet
		HudModel.applyMatch(m, { phase = "Active", aliveCount = 6, totalCount = 6 }, config)
		Harness.eq(HudModel.controlsOn(m), true)
		HudModel.applyEliminated(m, "p2") -- somebody else
		Harness.eq(HudModel.controlsOn(m), true)
		HudModel.applyEliminated(m, "p1")
		Harness.eq(HudModel.visible(m), false)
		Harness.eq(HudModel.controlsOn(m), false)
		HudModel.applyMatch(m, { phase = "Results", aliveCount = 1, totalCount = 6 }, config)
		Harness.eq(HudModel.controlsOn(m), false)
	end
)

Harness.test("a new match wipes the last one (no leaking health, ammo, zone or death)", function()
	local m = fresh()
	HudModel.applyHealth(m, { health = 5, max = 100 })
	HudModel.applyAmmo(m, { weaponId = "volt_pistol", ammo = 0, magazine = 12 }, config)
	HudModel.applyZone(m, zone())
	HudModel.applyEliminated(m, "p1")
	HudModel.applyMatch(m, { phase = "Resetting", aliveCount = 0, totalCount = 0 }, config)
	HudModel.applyMatch(m, { phase = "Countdown", aliveCount = 6, totalCount = 6 }, config)
	Harness.eq(m.alive, true)
	Harness.eq(m.health, 100)
	Harness.eq(m.ammo, 12)
	Harness.eq(m.zone, nil)
	Harness.eq(m.localId, "p1")
	Harness.eq(m.aliveCount, 6)
end)

Harness.test("run level and xp bar follow the XpState message", function()
	local m = fresh()
	HudModel.applyXp(m, { level = 3, xp = 20, xpToNext = 55, pendingOffers = 1 })
	local v = HudModel.derive(m, 0, nil, nil, config)
	Harness.eq(v.levelText, "LV3")
	Harness.near(v.xpFraction, 20 / 55)
	Harness.eq(v.pendingOffers, 1)
	HudModel.applyXp(m, { level = 9, xp = 1, xpToNext = 0, pendingOffers = 0 }) -- bad: ignored
	Harness.eq(m.level, 3)
end)

Harness.test("a notice shows for a few seconds and the text is shortened", function()
	local m = fresh()
	HudModel.applyNotice(m, { text = string.rep("x", 100) }, 10, config)
	Harness.eq(#(m.notice :: string), 40)
	Harness.eq((HudModel.derive(m, 11, nil, nil, config).warning :: any).key, "notice")
	Harness.eq(HudModel.derive(m, 14, nil, nil, config).warning, nil)
end)

Harness.test("a zone message from an older match is ignored", function()
	local m = fresh()
	HudModel.applyMatch(
		m,
		{ matchId = 2, phase = "Active", aliveCount = 6, totalCount = 6 },
		config
	)
	HudModel.applyZone(m, zone({ matchId = 1 }))
	Harness.eq(m.zone, nil)
	HudModel.applyZone(m, zone({ matchId = 2 }))
	Harness.truthy(m.zone ~= nil)
end)

Harness.test("the zone circle goes away when the match leaves combat", function()
	local m = fresh()
	HudModel.applyZone(m, zone())
	HudModel.applyMatch(
		m,
		{ matchId = 1, phase = "Results", aliveCount = 1, totalCount = 6 },
		config
	)
	Harness.eq(m.zone, nil)
end)

Harness.test("you can walk in the lobby phases only, never in a fight or while spawning", function()
	local m = HudModel.new(config, "p1")
	for _, phase in { "Waiting", "Countdown" } do
		HudModel.applyMatch(m, { phase = phase, aliveCount = 0, totalCount = 0 }, config)
		Harness.eq(HudModel.walkOn(m), true, phase .. " should walk")
		Harness.eq(HudModel.controlsOn(m), false, phase .. " must not fight")
	end
	for _, phase in { "Spawning", "Active", "FinalPressure", "Finished", "Results", "Resetting" } do
		HudModel.applyMatch(m, { phase = phase, aliveCount = 6, totalCount = 6 }, config)
		Harness.eq(HudModel.walkOn(m), false, phase .. " must not walk the lobby")
	end
end)
