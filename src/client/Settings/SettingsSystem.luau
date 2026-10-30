--!strict
-- Applies settings to the game: creates the Music and Effects SoundGroups (other pieces play
-- their sounds through them so the volume sliders work) and passes aim speed to Controls.
-- The panel itself is SettingsPanel.

local SoundService = game:GetService("SoundService")

local Controls = require(script.Parent.Parent.Controls.Controls)
local Settings = require(script.Parent.Settings)
local SettingsPanel = require(script.Parent.SettingsPanel)

local SettingsSystem = {}
SettingsSystem.order = 60

local GROUPS: { [string]: string } = { musicVolume = "Music", effectsVolume = "Effects" }

local function group(name: string): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Parent = SoundService
	return g
end

local function apply(key: string, value: number | boolean)
	local groupName = GROUPS[key]
	if groupName and type(value) == "number" then
		group(groupName).Volume = value
	elseif key == "aimSensitivity" and type(value) == "number" then
		Controls.setAimSensitivity(value)
	end
end

function SettingsSystem.start()
	for key in GROUPS do
		apply(key, Settings.get(key))
	end
	apply("aimSensitivity", Settings.get("aimSensitivity"))
	Settings.Changed:connect(apply)
	SettingsPanel.start()
end

return SettingsSystem
