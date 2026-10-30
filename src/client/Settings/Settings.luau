--!strict
-- Player settings for this session. Everyone else reads them through here:
--   Settings.get("cameraShake")    -- 0..1, 0 turns shake off (piece 02 / effects)
--   Settings.get("aimSensitivity") -- Controls already applies this
--   Settings.get("effectsVolume")  -- also applied to the "Effects" SoundGroup (SettingsSystem)
--   Settings.Changed:connect(function(key, value) end)
-- Values are checked and clamped by SettingsModel. NOT saved between sessions yet: saving needs a
-- server remote and SaveRetry (a later phase). `serialize()` / `load()` are ready for that.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)

local SettingsModel = require("./SettingsModel")

local Settings = {}

Settings.Changed = Signal.new()

local values: SettingsModel.Settings = SettingsModel.new(Config.Settings.defaults :: any)

function Settings.get(key: string): number | boolean
	local v = values[key]
	if v == nil then
		error("Unknown setting '" .. tostring(key) .. "'", 2)
	end
	return v
end

function Settings.number(key: string): number
	local v = Settings.get(key)
	return if type(v) == "number" then v else 0
end

function Settings.flag(key: string): boolean
	return Settings.get(key) == true
end

function Settings.set(key: string, value: any): boolean
	if SettingsModel.set(values, key, value) then
		Settings.Changed:fire(key, values[key])
		return true
	end
	return false
end

function Settings.resetAll()
	for _, d in SettingsModel.defs do
		Settings.set(d.key, d.default)
	end
end

function Settings.serialize(): SettingsModel.Settings
	return table.clone(values)
end

-- For when saved data arrives: bad values are dropped, good ones fire Changed.
function Settings.load(saved: any)
	local merged = SettingsModel.merge(values, saved)
	for k, v in merged do
		if values[k] ~= v then
			values[k] = v
			Settings.Changed:fire(k, v)
		end
	end
end

return Settings
