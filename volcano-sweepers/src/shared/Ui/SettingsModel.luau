--!strict
-- The Settings panel as plain data. Pure.
--   SettingsModel.build(source) -> View
--   SettingsModel.isKey(key) -> boolean           only these five keys may be sent with SetSetting
--   SettingsModel.valueOf(settings, key) -> boolean
-- `source` is the store view: it needs `settings` and may have `offline`.

local Config = require("../Config")

local SettingsModel = {}

export type Source = { [string]: any }

export type Row = {
	key: string, -- the Types.Settings key sent to the server
	icon: string,
	label: string,
	hint: string,
	value: boolean,
}

export type Step = { icon: string, text: string }

export type View = {
	rows: { Row },
	offline: boolean,
	offlineText: string,
	steps: { Step },
	credits: string,
}

type Def = { key: string, icon: string, label: string, hint: string }

-- Order = order on screen. Kid words; the controller note is honest (phones cannot buzz in Roblox).
local DEFS: { Def } = {
	{ key = "music", icon = "🎵", label = "Music", hint = "Happy island tunes" },
	{ key = "sfx", icon = "🔊", label = "Sounds", hint = "Swish, pop and cha-ching" },
	{
		key = "autoSweep",
		icon = "🧹",
		label = "Auto-sweep",
		hint = "Sweeps for you while you walk",
	},
	{
		key = "shake",
		icon = "📳",
		label = "Screen shake",
		hint = "Wiggles when things go boom",
	},
	{
		key = "vibrate",
		icon = "🎮",
		label = "Controller buzz",
		hint = "Only works with a controller",
	},
}

local KEYS: { [string]: boolean } = {}
for _, d in DEFS do
	KEYS[d.key] = true
end

function SettingsModel.isKey(key: any): boolean
	return type(key) == "string" and KEYS[key] == true
end

-- Missing or broken values count as ON (that is how a brand new player starts).
function SettingsModel.valueOf(settings: any, key: string): boolean
	if type(settings) ~= "table" then
		return true
	end
	local v = (settings :: { [string]: any })[key]
	if type(v) == "boolean" then
		return v
	end
	return true
end

local STEPS: { Step } = {
	{ icon = "🧹", text = "Hold SWEEP to clean up the ash." },
	{ icon = "💰", text = "Go to the Trade Hut and tap SELL." },
	{ icon = "🛠", text = "Buy better brooms and upgrades!" },
}

function SettingsModel.build(source: Source): View
	local rows: { Row } = {}
	for _, d in DEFS do
		table.insert(rows, {
			key = d.key,
			icon = d.icon,
			label = d.label,
			hint = d.hint,
			value = SettingsModel.valueOf(source.settings, d.key),
		})
	end
	return {
		rows = rows,
		offline = source.offline == true,
		offlineText = "Guest mode: your game is not being saved this time.",
		steps = STEPS,
		credits = `Thanks for playing {Config.Game.Name}!`,
	}
end

return SettingsModel
