--!strict
-- What a saved profile looks like, and how an old one is brought up to date.
-- Rules:
--   * `schemaVersion` is stored in the data. A profile from a NEWER game version is never loaded
--     or changed (no downgrades). Add a step to `steps` when you bump CURRENT.
--   * Missing keys are filled from the defaults. Unknown keys and unknown item ids are KEPT, so an
--     item removed from the game later does not delete what a player owns.
--   * Items are saved by stable text id (lowercase a-z 0-9 _), never by list position. If an id
--     must change, add old -> new to `itemRenames`; it is applied on every load.
--   * Sections: progression (piece 18), loadout (piece 19), flags (piece 20), receipts (piece 17).
-- Pure Luau so Lune can test it.

local Serializable = require("./Serializable")

local Schema = {}

Schema.CURRENT = 1

export type Data = { [string]: any }
export type Steps = { [number]: (Data) -> () }

-- A fresh profile for a player who has never saved. Always a new copy.
function Schema.defaults(): Data
	return {
		schemaVersion = Schema.CURRENT,
		progression = {
			coins = 0,
			totalEarned = 0,
			unlocked = {},
			equipped = {},
			grantedKeys = {},
		},
		loadout = {},
		flags = {},
		receipts = {},
	}
end

-- Old item id -> new item id. Empty until the first rename.
Schema.itemRenames = {} :: { [string]: string }

-- steps[n] upgrades a profile from version n to n + 1. Version 0 means "no version stored".
Schema.steps = {
	[0] = function(_: Data) end,
} :: Steps

function Schema.isItemId(id: any): boolean
	return type(id) == "string"
		and #id >= 1
		and #id <= 40
		and string.match(id, "^[a-z][a-z0-9_]*$") ~= nil
end

local function isRecordDefault(v: any): boolean
	return type(v) == "table" and next(v) ~= nil
end

-- Fills holes from `defaults`. A field of the wrong type is replaced by its default (listed in
-- `repairs`) because later code relies on the type. Returns true when anything changed.
local function reconcile(data: Data, defaults: Data, path: string, repairs: { string }): boolean
	local changed = false
	for key, def in defaults do
		local have = data[key]
		if have == nil then
			data[key] = Serializable.copy(def)
			changed = true
		elseif type(have) ~= type(def) then
			table.insert(repairs, path .. key)
			data[key] = Serializable.copy(def)
			changed = true
		elseif isRecordDefault(def) then
			if reconcile(have, def, path .. key .. ".", repairs) then
				changed = true
			end
		end
	end
	return changed
end

local function applyRenames(data: Data, renames: { [string]: string }): boolean
	if next(renames) == nil then
		return false
	end
	local changed = false
	local p = data.progression
	if type(p) ~= "table" then
		return false
	end
	if type(p.unlocked) == "table" then
		for old, new in renames do
			if p.unlocked[old] ~= nil then
				p.unlocked[new] = p.unlocked[old]
				p.unlocked[old] = nil
				changed = true
			end
		end
	end
	if type(p.equipped) == "table" then
		for slot, id in p.equipped do
			local new = renames[id]
			if new ~= nil then
				p.equipped[slot] = new
				changed = true
			end
		end
	end
	return changed
end

-- Brings `data` up to date in place. Returns ok, then either the reason (ok = false:
-- "future" or "noStep") or a list of repaired field paths (ok = true), and whether anything changed.
function Schema.prepare(
	data: Data,
	target: number?,
	steps: Steps?,
	defaults: Data?,
	renames: { [string]: string }?
): (boolean, any, boolean)
	local goal = target or Schema.CURRENT
	local table_ = steps or Schema.steps
	local v = data.schemaVersion
	if v ~= nil and type(v) ~= "number" then
		return false, "badVersion", false
	end
	local version: number = v or 0
	if version > goal then
		return false, "future", false
	end
	local changed = false
	while version < goal do
		local step = table_[version]
		if step == nil then
			return false, "noStep", false
		end
		step(data)
		version += 1
		data.schemaVersion = version
		changed = true
	end
	local repairs: { string } = {}
	if reconcile(data, defaults or Schema.defaults(), "", repairs) then
		changed = true
	end
	if applyRenames(data, renames or Schema.itemRenames) then
		changed = true
	end
	return true, repairs, changed
end

return Schema
