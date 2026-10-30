--!strict
-- The lobby's button slots (see LobbyLayout). The match screen (MatchFlow) attaches the menu to its
-- lobby frame, so every slot shows only in the lobby and sits on the MatchFlow layer. A piece that
-- adds a lobby button parents it into its slot and sizes it to fill the slot:
--
--   local slot = LobbyMenu.slot("track")
--   button.Size = UDim2.fromScale(1, 1)
--   button.Parent = slot
--
-- Never place a lobby button with your own numbers or in your own ScreenGui.

local Layout = require(script.Parent.Parent.Hud.Layout)
local UiKit = require(script.Parent.Parent.Hud.UiKit)
local LobbyLayout = require(script.Parent.LobbyLayout)

local LobbyMenu = {}

local holder: Frame? = nil
local slots: { [string]: Frame } = {}

local function build(): Frame
	local h = Instance.new("Frame")
	h.Name = "LobbyMenu"
	h.BackgroundTransparency = 1
	h.Size = UDim2.fromScale(1, 1)
	h.Active = false

	local groups: { [string]: Frame } = {}
	for name, rect in LobbyLayout.groups do
		local g = Instance.new("Frame")
		g.Name = name
		g.BackgroundTransparency = 1
		g.Active = false
		g.Parent = h
		UiKit.place(g, rect, nil, Layout.LOBBY_MIN_ASPECT)
		groups[name] = g
	end
	for name, slot in LobbyLayout.slots do
		local x, y, w, hgt = LobbyLayout.relative(name)
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.Active = false
		f.Position = UDim2.fromScale(x, y)
		f.Size = UDim2.fromScale(w, hgt)
		f.Parent = groups[slot.group]
		slots[name] = f
	end
	holder = h
	return h
end

-- The frame a lobby button goes in. Works before the lobby screen exists.
function LobbyMenu.slot(name: string): Frame
	local _ = holder or build()
	local f = slots[name]
	assert(f, "unknown lobby slot " .. name)
	return f
end

-- Called once by the match screen with its lobby frame.
function LobbyMenu.attach(parent: GuiObject)
	local h = holder or build()
	h.Parent = parent
end

return LobbyMenu
