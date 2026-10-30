--!strict
-- The loadout screen's brain, with no drawing in it. Whatever look the screen has (the plain placeholder
-- now, Claude Design's later) reads and calls this:
--   Controller.getState() -> LoadoutView.State     what the server says you wear and can wear
--   Controller.getTab() / Controller.setTab(slot)  which tab is showing
--   Controller.cards()    -> { LoadoutView.Card }  the items in the current tab
--   Controller.equip(slot, itemId)                 ask the server; it checks, then sends the new state
--   Controller.Changed:connect(function() end)     state or tab changed: redraw
--   Controller.Notice:connect(function(text) end)  one-line messages ("Still locked...")
-- The client only asks. The server checks the slot, the item, the unlock and whether you are in a match.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loadout = require(Shared.Loadout)
local LoadoutView = require(Shared.LoadoutView)
local Signal = require(Shared.Signal)

local Net = require(script.Parent.Parent.Core.Net)

local Controller = {}

Controller.Changed = Signal.new()
Controller.Notice = Signal.new()

local state: LoadoutView.State = {
	selection = {},
	unlocked = {},
	level = 0,
	coins = nil,
	saved = false,
}
for _, slot in Loadout.slots do
	state.selection[slot] = (Loadout.defaults :: any)[slot]
	local ids = {}
	for _, item in Loadout.items[slot] do
		if item.unlockAt == nil then
			table.insert(ids, item.id)
		end
	end
	state.unlocked[slot] = ids
end

local tab: string = Loadout.slots[1]
local started = false

function Controller.getState(): LoadoutView.State
	return state
end

function Controller.getTab(): string
	return tab
end

function Controller.setTab(slot: string)
	if Loadout.isSlot(slot) and slot ~= tab then
		tab = slot
		Controller.Changed:fire()
	end
end

function Controller.cards(): { LoadoutView.Card }
	return LoadoutView.cards(state, tab)
end

function Controller.equip(slot: string, itemId: string)
	local cards = LoadoutView.cards(state, slot)
	for _, card in cards do
		if card.id == itemId then
			if card.locked then
				Controller.Notice:fire(
					`Still locked. Earn it on the Rewards board ({card.status}).`
				)
				return
			end
			if card.equipped then
				return
			end
			Net.send("LoadoutEquip", slot, itemId)
			return
		end
	end
end

function Controller.start()
	if started then
		return
	end
	started = true
	Net.on("LoadoutState", function(payload: any)
		if
			type(payload) ~= "table"
			or type(payload.selection) ~= "table"
			or type(payload.unlocked) ~= "table"
		then
			return
		end
		state = {
			selection = payload.selection,
			unlocked = payload.unlocked,
			level = payload.level,
			coins = payload.coins,
			saved = payload.saved == true,
		}
		Controller.Changed:fire()
	end)
	Net.on("Notice", function(payload: any)
		if type(payload) == "table" and type(payload.text) == "string" then
			Controller.Notice:fire(payload.text)
		end
	end)
	Net.send("LoadoutSync")
end

return Controller
