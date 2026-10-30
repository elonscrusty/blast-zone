--!strict
local Harness = require("./harness")
local SettingsModel = require("../src/client/Settings/SettingsModel")

Harness.test("defaults cover every setting and Config defaults override them", function()
	local s = SettingsModel.new({
		musicVolume = 0.3,
		effectsVolume = 0.9,
		cameraShake = 0,
		aimSensitivity = 1.5,
	})
	Harness.near(s.musicVolume :: number, 0.3)
	Harness.near(s.cameraShake :: number, 0)
	Harness.eq(s.leftHanded, false)
	Harness.eq(s.reduceFlashes, false)
	for _, d in SettingsModel.defs do
		Harness.truthy(s[d.key] ~= nil, d.key .. " has no value")
	end
end)

Harness.test("values are clamped into range and snapped to the step", function()
	Harness.eq(SettingsModel.sanitize("musicVolume", 7), 1)
	Harness.eq(SettingsModel.sanitize("musicVolume", -3), 0)
	Harness.eq(SettingsModel.sanitize("aimSensitivity", 0.01), 0.5)
	Harness.eq(SettingsModel.sanitize("hudScale", 0.93), 0.95)
end)

Harness.test("junk never gets in: NaN, infinity, wrong type, unknown key", function()
	Harness.eq(SettingsModel.sanitize("musicVolume", 0 / 0), nil)
	Harness.eq(SettingsModel.sanitize("musicVolume", math.huge), nil)
	Harness.eq(SettingsModel.sanitize("musicVolume", "loud"), nil)
	Harness.eq(SettingsModel.sanitize("leftHanded", 1), nil) -- a toggle only takes true/false
	Harness.eq(SettingsModel.sanitize("godMode", true), nil)
end)

Harness.test("set reports a change only when something changed", function()
	local s = SettingsModel.new()
	Harness.eq(SettingsModel.set(s, "cameraShake", 0.5), true)
	Harness.eq(SettingsModel.set(s, "cameraShake", 0.5), false)
	Harness.eq(SettingsModel.set(s, "cameraShake", "x"), false)
	Harness.near(s.cameraShake :: number, 0.5)
end)

Harness.test("loading saved data keeps good values and drops bad ones", function()
	local base = SettingsModel.new()
	local merged = SettingsModel.merge(base, {
		musicVolume = 0.2,
		effectsVolume = "max",
		leftHanded = true,
		hackerKey = 99,
		[1] = 5,
	})
	Harness.near(merged.musicVolume :: number, 0.2)
	Harness.near(merged.effectsVolume :: number, base.effectsVolume :: number)
	Harness.eq(merged.leftHanded, true)
	Harness.eq(merged.hackerKey, nil)
	Harness.eq(SettingsModel.merge(base, "not a table").leftHanded, false)
	Harness.eq(base.leftHanded, false) -- the base is not changed
end)

Harness.test("slider fractions round-trip and stay in range", function()
	for _, d in SettingsModel.defs do
		if d.kind == "slider" then
			local lo = SettingsModel.fromFraction(d.key, 0)
			local hi = SettingsModel.fromFraction(d.key, 1)
			Harness.eq(lo, d.min)
			Harness.eq(hi, d.max)
			Harness.eq(SettingsModel.fromFraction(d.key, 5), d.max)
			Harness.near(
				SettingsModel.toFraction(d.key, d.default :: number),
				SettingsModel.toFraction(
					d.key,
					SettingsModel.fromFraction(
						d.key,
						SettingsModel.toFraction(d.key, d.default :: number)
					) :: number
				),
				0.03
			)
		end
	end
	Harness.eq(SettingsModel.fromFraction("musicVolume", 0 / 0), nil)
end)

Harness.test("gamepad nudges a slider one step and stops at the ends", function()
	Harness.near(SettingsModel.nudge("musicVolume", 0.5, 1) :: number, 0.55)
	Harness.near(SettingsModel.nudge("musicVolume", 0.5, -1) :: number, 0.45)
	Harness.eq(SettingsModel.nudge("musicVolume", 1, 1), 1)
	Harness.eq(SettingsModel.nudge("musicVolume", 0, -1), 0)
	Harness.eq(SettingsModel.nudge("leftHanded", 0, 1), nil) -- toggles are not sliders
	Harness.eq(SettingsModel.nudge("nope", 0.5, 1), nil)
	Harness.eq(SettingsModel.nudge("musicVolume", 0 / 0, 1), nil)
end)
