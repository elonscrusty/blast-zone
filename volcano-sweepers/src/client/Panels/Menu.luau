--!strict
-- The tile menu (id "menu"), opened by the one MENU button on the HUD (Hud/MenuBar), M on a
-- keyboard or DPad up on a gamepad. One big tile per panel: picture + word, so a child who cannot
-- read yet still finds the robot or the gift. Tiles carry the same red dots as before, plus a tiny
-- note ("Ready!", "Later"). Tap a tile -> that panel opens in place of the menu. Escape / B / the X
-- / a tap outside close it, like every panel.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MenuModel = require(Shared.Ui.MenuModel)
local Badges = require(script.Parent.Parent.Ui.Badges)
local Bridge = require(script.Parent.Parent.Ui.Bridge)
local Components = require(script.Parent.Parent.Ui.Components)
local PanelHost = require(script.Parent.Parent.Ui.PanelHost)
local Theme = require(script.Parent.Parent.Ui.Theme)
local PanelKit = require(script.Parent.Shared.PanelKit)

local L = {
	colsWide = 5,
	colsTall = 3,
	tileMinH = 76,
	tileMaxH = 112,
	noteW = 58,
	noteH = 18,
}

type Tile = {
	id: string,
	button: Components.Button,
	badge: Components.Badge,
	note: Components.Pill,
}

local function build(parent: Frame, _ctx: PanelHost.Ctx): () -> ()
	local list = Components.ScrollList({ parent = parent, name = "Tiles", padding = 2 })
	local grid = PanelKit.useGrid(list)
	local tiles: { Tile } = {}

	for i, entry in PanelHost.menuButtons do
		local id = entry.id
		local button = Components.Button({
			parent = list.root,
			name = "Menu_" .. id, -- the tutorial finger looks for "Menu_upgrades"
			layoutOrder = i,
			variant = "neutral",
			icon = entry.icon,
			text = entry.title,
			textSize = Theme.text.body,
			stack = true,
			size = UDim2.fromScale(1, 1),
		})
		button.onClick(function()
			PanelHost.open(id)
		end)
		local badge = Components.Badge({ parent = button.root, size = 18 })
		local note = Components.Pill({
			parent = button.face,
			name = "Note",
			text = "",
			fill = Theme.color.gold,
			textColor = Theme.color.charcoal,
			textSize = Theme.text.tiny,
			bordered = false,
			position = UDim2.fromOffset(4, 4),
			size = UDim2.fromOffset(L.noteW, L.noteH),
		})
		note.root.Visible = false
		table.insert(tiles, { id = id, button = button, badge = badge, note = note })
	end

	local function paint()
		local view = Bridge.view()
		local now = workspace:GetServerTimeNow()
		for _, tile in tiles do
			tile.badge.set(Badges.isOn(tile.id))
			local text = MenuModel.tileNote(tile.id, view, now)
			tile.note.root.Visible = text ~= nil
			if text ~= nil then
				tile.note.setText(text)
				local later = text == "Later"
				tile.note.setFill(if later then Theme.color.creamDark else Theme.color.gold, nil)
				tile.note.setTextColor(
					if later then Theme.color.charcoalSoft else Theme.color.charcoal
				)
			end
		end
	end

	local stopSize = PanelKit.watchSize(parent, function(size: Vector2)
		-- a wide, short body (any landscape phone, even a 568 x 320 one) gets 5 tiles a row so the
		-- whole menu fits without scrolling; a tall body (portrait) gets 3
		local wide = size.X >= PanelKit.WIDE_FROM or size.X >= size.Y * 1.6
		local cols = if wide then L.colsWide else L.colsTall
		local rows = math.max(1, math.ceil(#tiles / cols))
		local fitH = (size.Y - 8 - (rows - 1) * Theme.size.gap) / rows
		PanelKit.setGrid(grid, cols, math.floor(math.clamp(fitH, L.tileMinH, L.tileMaxH)))
	end)
	local badgeConn = Badges.changed:connect(paint)
	paint()

	-- a gamepad player gets the first tile selected, so the D-pad and A work straight away
	local lastInput = UserInputService:GetLastInputType()
	local onPad = string.find(lastInput.Name, "Gamepad", 1, true) ~= nil
	if onPad and tiles[1] ~= nil then
		pcall(function()
			GuiService.SelectedObject = tiles[1].button.hit
		end)
	end

	return function()
		stopSize()
		badgeConn:disconnect()
		pcall(function()
			local selected = GuiService.SelectedObject
			if selected ~= nil and selected:IsDescendantOf(parent) then
				GuiService.SelectedObject = nil
			end
		end)
		for _, tile in tiles do
			tile.badge.destroy()
			tile.button.destroy()
		end
	end
end

local def: PanelHost.Def = {
	id = "menu",
	title = "Menu",
	icon = "",
	order = 0,
	build = build,
	inMenu = false,
}

PanelHost.register(def)

return def
