--!strict
-- Who has equipped what (server use). Pure logic: the Roblox parts (saving, unlock levels) are passed in, so Lune can test it.
-- The server decides: a client only asks to equip, and this checks the slot, the item and the unlock first.
--
--   local store = LoadoutStore.new({
--     read    = function(userId) return { outfit = "courier" } or nil end, -- saved picks, nil when nothing is saved/loaded
--     write   = function(userId, slot, id) return true end,           -- false = could not save (picks still last this visit)
--     unlocks = function(userId) return { level = 0, owned = {} } end,
--     saved   = function(userId) return true end,                     -- is saving working for this player?
--   })
--   store:get(userId)                -> Selection (always valid)
--   store:equip(userId, slot, id)    -> true | false, reason   reason: unknown_slot, unknown_item, locked
--   store.Changed:connect(function(userId, selection) end)
local Loadout = require("./Loadout")
local Signal = require("./Signal")

export type Deps = {
	read: (userId: number) -> { [string]: any }?,
	write: (userId: number, slot: string, id: string) -> boolean,
	unlocks: (userId: number) -> Loadout.Unlocks,
	saved: (userId: number) -> boolean,
}

local LoadoutStore = {}
LoadoutStore.__index = LoadoutStore

function LoadoutStore.new(deps: Deps): any
	return setmetatable({
		_deps = deps,
		_session = {} :: { [number]: { [string]: string } }, -- picks made this visit (also the fallback when nothing is saved)
		Changed = Signal.new(),
	}, LoadoutStore)
end

function LoadoutStore.get(self: any, userId: number): Loadout.Selection
	local deps: Deps = self._deps
	local raw: { [string]: any } = {}
	local fromSession = self._session[userId]
	local fromSave = deps.read(userId)
	-- A saved pick wins; picks made this visit fill any gap (for example when saving failed).
	if fromSession then
		for k, v in fromSession do
			raw[k] = v
		end
	end
	if fromSave then
		for k, v in fromSave do
			raw[k] = v
		end
	end
	return Loadout.sanitize(raw, deps.unlocks(userId))
end

function LoadoutStore.equip(self: any, userId: number, slot: any, id: any): (boolean, string?)
	local deps: Deps = self._deps
	local problem = Loadout.equipProblem(slot, id, deps.unlocks(userId))
	if problem then
		return false, problem
	end
	local session = self._session[userId]
	if session == nil then
		session = {}
		self._session[userId] = session
	end
	session[slot :: string] = id :: string
	deps.write(userId, slot :: string, id :: string)
	self.Changed:fire(userId, self:get(userId))
	return true, nil
end

function LoadoutStore.isSaved(self: any, userId: number): boolean
	return (self._deps :: Deps).saved(userId)
end

function LoadoutStore.forget(self: any, userId: number)
	self._session[userId] = nil
end

return LoadoutStore
