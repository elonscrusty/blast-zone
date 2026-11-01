--!strict
-- The MENU button (left, under the backpack bar): ONE 48 px button that opens the tile menu
-- (Panels/Menu, id "menu"). It replaced a column of nine icon buttons that sat where the left thumb
-- steers on a landscape phone.
--
-- Red dots: one dot on this button when ANY tile has one. Tile dots come from two places:
--   * by hand: Hud.setBadge(panelId, on) (Book and Goals use it)
--   * automatic (shared/Ui/MenuModel): a shop can sell you something NEW since you last opened it,
--     the daily gift is ready (server UTC day), a Cool Down is possible (until you have looked).
-- Opening a panel "acks" what it offers right now, so its dot goes out until there is news.
-- Desktop: M opens/closes the menu. Gamepad: DPad up.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MenuModel = require(Shared.Ui.MenuModel)
local UiMath = require(Shared.Ui.UiMath)
local Badges = require(script.Parent.Parent.Ui.Badges)
local Components = require(script.Parent.Parent.Ui.Components)
local PanelHost = require(script.Parent.Parent.Ui.PanelHost)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Context = require(script.Parent.Context)
local Widget = require(script.Parent.Widget)

local MenuBar = {}

export type MenuWidget = Widget.Widget & {
	setBadge: (panelId: string, on: boolean) -> (),
	rebuild: () -> (),
}

local MENU_ID = "menu"
local BAR_W = 0.5 -- hamburger bars: share of the face width
local BAR_H = 4
local BAR_GAP = 6

function MenuBar.new(parent: Instance, ctx: Context.Context): MenuWidget
	local K = UiMath.K
	local button = Components.Button({
		parent = parent,
		name = "Menu_menu", -- the tutorial finger looks for this name
		size = UDim2.fromOffset(K.menuSize, K.menuSize),
		variant = "secondary",
	})
	-- three bars drawn from frames (no font needed) + the word MENU under them
	for i = 1, 3 do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. i
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.new(0.5, 0, 0, 9 + (i - 1) * BAR_GAP)
		bar.Size = UDim2.new(BAR_W, 0, 0, BAR_H)
		bar.BackgroundColor3 = Theme.color.white
		bar.BorderSizePixel = 0
		bar.Active = false
		bar.Parent = button.face
		local round = Instance.new("UICorner")
		round.CornerRadius = Theme.radius.full
		round.Parent = bar
	end
	Components.Label({
		parent = button.face,
		name = "Word",
		text = "MENU",
		textSize = Theme.text.min,
		font = Theme.font.title,
		color = Theme.color.white,
		outline = Theme.color.tealInk,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -2),
		size = UDim2.new(1, -4, 0, 13),
	})
	local badge = Components.Badge({ parent = button.root })

	button.onClick(function()
		PanelHost.toggle(MENU_ID)
	end)

	local acks: MenuModel.Acks = {}
	local dirty = true

	local function paint()
		badge.set(Badges.anyOn())
	end

	local function recompute()
		dirty = false
		local view = ctx.view()
		Badges.setAuto(MenuModel.dots(view, ctx.serverNow(), acks))
		paint()
	end

	-- Store changes only mark the dots dirty; the 4 Hz tick recomputes them (cheap, no flicker).
	ctx.watch({
		"coins",
		"upgrades",
		"toolsOwned",
		"zones",
		"helpers",
		"helperLevel",
		"daily",
		"runCoins",
		"sparks",
		"sparkPerks",
		"coolDowns",
	}, function()
		dirty = true
	end)
	ctx.every(0.25, function()
		if dirty then
			recompute()
		end
	end)
	-- the daily dot must also turn on at UTC midnight with no store change
	ctx.every(30, function()
		dirty = true
	end)

	-- opening a panel = "I have seen what it sells": quiet its dot until something new comes
	local stateConn = PanelHost.stateChanged:connect(function(openId: string?)
		if openId ~= nil and openId ~= MENU_ID then
			MenuModel.ack(acks, openId, ctx.view())
			dirty = true
		end
	end)
	local badgeConn = Badges.changed:connect(paint)
	ctx.onCleanup(function()
		stateConn:disconnect()
		badgeConn:disconnect()
	end)

	-- keyboard / gamepad shortcut (never while typing in chat)
	ctx.connect(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.M or input.KeyCode == Enum.KeyCode.DPadUp then
			PanelHost.toggle(MENU_ID)
		end
	end))

	recompute()

	return {
		root = button.root,
		setBadge = function(panelId: string, on: boolean)
			Badges.setManual(panelId, on)
		end,
		rebuild = function()
			dirty = true
		end,
		destroy = function()
			badge.destroy()
			button.destroy()
		end,
	}
end

return MenuBar
