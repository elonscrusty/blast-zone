--!strict
-- The settings list and its rules, as pure data so Lune can test it.
-- Every value is checked and clamped here, so a bad value can never reach the game.
-- Defaults for the first four come from Config.Settings.defaults; the rest are ours.

export type Kind = "slider" | "toggle"

export type Def = {
	key: string,
	label: string,
	kind: Kind,
	min: number,
	max: number,
	step: number,
	default: number | boolean,
	group: "Sound" | "Controls" | "Display",
}

export type Settings = {
	[string]: number | boolean,
}

local SettingsModel = {}

-- Order here is the order on the panel.
SettingsModel.defs = {
	{
		key = "musicVolume",
		label = "Music",
		kind = "slider",
		min = 0,
		max = 1,
		step = 0.05,
		default = 0.6,
		group = "Sound",
	},
	{
		key = "effectsVolume",
		label = "Effects",
		kind = "slider",
		min = 0,
		max = 1,
		step = 0.05,
		default = 0.8,
		group = "Sound",
	},
	{
		key = "cameraShake",
		label = "Camera shake",
		kind = "slider",
		min = 0,
		max = 1,
		step = 0.05,
		default = 1,
		group = "Display",
	},
	{
		key = "reduceFlashes",
		label = "Fewer flashes",
		kind = "toggle",
		min = 0,
		max = 1,
		step = 1,
		default = false,
		group = "Display",
	},
	{
		key = "hudScale",
		label = "HUD size",
		kind = "slider",
		min = 0.7,
		max = 1.2,
		step = 0.05,
		default = 1,
		group = "Display",
	},
	{
		key = "aimSensitivity",
		label = "Aim speed",
		kind = "slider",
		min = 0.5,
		max = 2,
		step = 0.05,
		default = 1,
		group = "Controls",
	},
	{
		key = "touchScale",
		label = "Button size",
		kind = "slider",
		min = 0.8,
		max = 1.3,
		step = 0.05,
		default = 1,
		group = "Controls",
	},
	{
		key = "floatingSticks",
		label = "Floating sticks",
		kind = "toggle",
		min = 0,
		max = 1,
		step = 1,
		default = true,
		group = "Controls",
	},
	{
		key = "leftHanded",
		label = "Left-handed",
		kind = "toggle",
		min = 0,
		max = 1,
		step = 1,
		default = false,
		group = "Controls",
	},
} :: { Def }

local byKey: { [string]: Def } = {}
for _, d in SettingsModel.defs do
	byKey[d.key] = d
end

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function snap(def: Def, v: number): number
	local clamped = math.clamp(v, def.min, def.max)
	if def.step > 0 then
		clamped = def.min + math.floor((clamped - def.min) / def.step + 0.5) * def.step
		clamped = math.clamp(clamped, def.min, def.max)
	end
	-- Remove float dust like 0.30000000000000004.
	return math.floor(clamped * 1000 + 0.5) / 1000
end

-- A usable value for this key, or nil if the input is junk (wrong type, NaN, infinity, unknown key).
function SettingsModel.sanitize(key: string, value: any): (number | boolean)?
	local def = byKey[key]
	if def == nil then
		return nil
	end
	if def.kind == "toggle" then
		if type(value) == "boolean" then
			return value
		end
		return nil
	end
	if type(value) ~= "number" or not finite(value) then
		return nil
	end
	return snap(def, value)
end

-- defaults can override the built-in ones (pass Config.Settings.defaults).
function SettingsModel.new(overrides: { [string]: any }?): Settings
	local s: Settings = {}
	for _, d in SettingsModel.defs do
		s[d.key] = d.default
	end
	if overrides then
		for k, v in overrides do
			local clean = SettingsModel.sanitize(k, v)
			if clean ~= nil then
				s[k] = clean
			end
		end
	end
	return s
end

-- Returns true if the value changed.
function SettingsModel.set(s: Settings, key: string, value: any): boolean
	local clean = SettingsModel.sanitize(key, value)
	if clean == nil or s[key] == clean then
		return false
	end
	s[key] = clean
	return true
end

-- Keep only known keys with good values; everything else stays at what `base` had.
function SettingsModel.merge(base: Settings, saved: any): Settings
	local out = table.clone(base)
	if type(saved) == "table" then
		for k, v in saved :: { [any]: any } do
			if type(k) == "string" then
				local clean = SettingsModel.sanitize(k, v)
				if clean ~= nil then
					out[k] = clean
				end
			end
		end
	end
	return out
end

-- Slider position 0..1 for a value, and back. The panel never does this maths itself.
function SettingsModel.toFraction(key: string, value: number): number
	local def = byKey[key]
	if def == nil or def.max <= def.min then
		return 0
	end
	return math.clamp((value - def.min) / (def.max - def.min), 0, 1)
end

function SettingsModel.fromFraction(key: string, fraction: number): number?
	local def = byKey[key]
	if def == nil or not finite(fraction) then
		return nil
	end
	return snap(def, def.min + math.clamp(fraction, 0, 1) * (def.max - def.min))
end

-- One step up (+1) or down (-1) on a slider, for the gamepad. nil for a toggle or unknown key.
-- Stops at the ends instead of wrapping.
function SettingsModel.nudge(key: string, current: number, direction: number): number?
	local def = byKey[key]
	if def == nil or def.kind ~= "slider" or not finite(current) or not finite(direction) then
		return nil
	end
	local sign = if direction > 0 then 1 elseif direction < 0 then -1 else 0
	return snap(def, current + sign * def.step)
end

function SettingsModel.def(key: string): Def?
	return byKey[key]
end

return SettingsModel
