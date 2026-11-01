--!strict
-- Settings view-model: five toggles, guest note, how-to-play steps.
local Harness = require("./harness")
local ProfileSchema = require("../src/shared/Profile/ProfileSchema")
local Economy = require("../src/shared/Rules/Economy")
local SettingsModel = require("../src/shared/Ui/SettingsModel")

Harness.test("settings: five rows, in the profile's key set", function()
	local v = SettingsModel.build({ settings = Economy.blankProfile().settings })
	Harness.eq(#v.rows, 5)
	local seen: { [string]: boolean } = {}
	for _, row in v.rows do
		seen[row.key] = true
		Harness.truthy(SettingsModel.isKey(row.key), row.key)
		Harness.truthy(row.label ~= "" and row.hint ~= "" and row.icon ~= "", row.key)
		Harness.eq(row.value, true, row.key)
	end
	for _, key in ProfileSchema.SETTING_KEYS do
		Harness.eq(seen[key], true, "profile key shown: " .. key)
	end
end)

Harness.test("settings: values follow the store", function()
	local settings = { music = false, sfx = true, autoSweep = false, shake = true, vibrate = false }
	local v = SettingsModel.build({ settings = settings })
	local byKey: { [string]: boolean } = {}
	for _, row in v.rows do
		byKey[row.key] = row.value
	end
	Harness.eq(byKey.music, false)
	Harness.eq(byKey.sfx, true)
	Harness.eq(byKey.autoSweep, false)
	Harness.eq(byKey.shake, true)
	Harness.eq(byKey.vibrate, false)
end)

Harness.test("settings: missing settings count as on", function()
	for _, source in { {}, { settings = "x" }, { settings = { music = "no" } } } do
		local v = SettingsModel.build(source :: any)
		for _, row in v.rows do
			Harness.eq(row.value, true, row.key)
		end
	end
end)

Harness.test("settings: only the five keys are allowed", function()
	Harness.eq(SettingsModel.isKey("music"), true)
	Harness.eq(SettingsModel.isKey("vibrate"), true)
	Harness.eq(SettingsModel.isKey("coins"), false)
	Harness.eq(SettingsModel.isKey(5), false)
	Harness.eq(SettingsModel.isKey(nil), false)
end)

Harness.test("settings: guest note only when offline", function()
	Harness.eq(SettingsModel.build({}).offline, false)
	Harness.eq(SettingsModel.build({ offline = false }).offline, false)
	local off = SettingsModel.build({ offline = true })
	Harness.eq(off.offline, true)
	Harness.truthy(string.find(off.offlineText, "not being saved", 1, true) ~= nil)
	local loading = SettingsModel.build({ offline = true, offlineRetrying = true })
	Harness.truthy(string.find(loading.offlineText, "still loading", 1, true) ~= nil)
end)

Harness.test("settings: the vibrate row is honest about controllers", function()
	local v = SettingsModel.build({})
	for _, row in v.rows do
		if row.key == "vibrate" then
			Harness.truthy(string.find(string.lower(row.hint), "controller", 1, true) ~= nil)
		end
	end
end)

Harness.test("settings: three how-to-play steps and a credits line", function()
	local v = SettingsModel.build({})
	Harness.eq(#v.steps, 3)
	for _, step in v.steps do
		Harness.truthy(step.icon ~= "" and #step.text > 0 and #step.text < 50)
	end
	Harness.truthy(string.find(v.credits, "Volcano Sweepers", 1, true) ~= nil)
end)
