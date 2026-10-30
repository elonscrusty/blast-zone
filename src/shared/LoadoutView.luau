--!strict
-- What the loadout screen shows, as plain data. The screen's look (Claude Design) only has to draw these
-- rows; all the rules about locked / equipped / wording live here and are tested in Lune.
--   LoadoutView.tabs()                 -> { { slot, label } }          the buttons across the top
--   LoadoutView.cards(state, slot)     -> { Card }                      the items in one tab
--   LoadoutView.summary(state)         -> { { slot, label, name } }     what you are wearing now
--   LoadoutView.step(index, delta, n)  -> index                         wraps around, for arrow buttons
local Config = require("./Config")
local Gear = require("./Gear")
local GunCards = require("./GunCards")
local Loadout = require("./Loadout")

export type Card = {
	id: string,
	name: string,
	desc: string,
	equipped: boolean,
	locked: boolean,
	status: string, -- "Wearing" | "Tap to wear" | "Reward 3" (what to show under the name)
	unlockAt: number?,
	detail: { string }?, -- hero cards: health and both guns as short lines (GunCards has the full bars); gear cards: the trade as short lines
}

export type State = {
	selection: { [string]: string },
	unlocked: { [string]: { string } },
	level: number?,
	coins: number?,
	saved: boolean?,
}

local LoadoutView = {}

LoadoutView.rewardsWord = "Reward" -- carter's word. Never "track".

function LoadoutView.tabs(): { { slot: string, label: string } }
	local out = {}
	for _, slot in Loadout.slots do
		table.insert(out, { slot = slot, label = Loadout.slotNames[slot] })
	end
	return out
end

local function isOpen(state: State, slot: string, id: string): boolean
	local ids = state.unlocked[slot]
	if ids then
		for _, v in ids do
			if v == id then
				return true
			end
		end
	end
	return false
end

function LoadoutView.lockText(item: Loadout.Item): string
	return if item.unlockAt then `{LoadoutView.rewardsWord} {item.unlockAt}` else ""
end

function LoadoutView.cards(state: State, slot: string): { Card }
	local out: { Card } = {}
	local items = Loadout.items[slot]
	if not items then
		return out
	end
	local wearing = state.selection[slot] or (Loadout.defaults :: any)[slot]
	for _, item in items do
		local open = isOpen(state, slot, item.id)
		local equipped = open and item.id == wearing
		table.insert(out, {
			id = item.id,
			name = item.name,
			desc = item.desc,
			equipped = equipped,
			locked = not open,
			status = if not open
				then LoadoutView.lockText(item)
				elseif equipped then "Wearing"
				else "Tap to wear",
			unlockAt = item.unlockAt,
			detail = if slot == "hero"
				then GunCards.heroLines(Config, item.id)
				elseif Gear.isSlot(slot) then Gear.lines(Config, slot, item.id)
				else nil,
		})
	end
	return out
end

function LoadoutView.summary(state: State): { { slot: string, label: string, name: string } }
	local out = {}
	for _, slot in Loadout.slots do
		local item = Loadout.find(slot, state.selection[slot] or (Loadout.defaults :: any)[slot])
		table.insert(out, {
			slot = slot,
			label = Loadout.slotNames[slot],
			name = if item then item.name else "?",
		})
	end
	return out
end

function LoadoutView.step(index: number, delta: number, count: number): number
	if count <= 0 then
		return 1
	end
	return (index - 1 + delta) % count + 1
end

-- The one line under the screen about saving and money.
function LoadoutView.footer(state: State): string
	if state.saved == false then
		return "Not saved yet. Your picks last until you leave."
	end
	return ""
end

return LoadoutView
