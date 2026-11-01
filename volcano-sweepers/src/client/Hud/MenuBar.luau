--!strict
-- Menu bar (left edge): one big icon button per registered panel, built from PanelHost.menuButtons.
-- Red dots: Hud.setBadge(panelId, true) by hand, plus automatic ones (you can afford something,
-- the daily gift is ready, Cool Down is possible).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Rules.Economy)
local Pricing = require(Shared.Rules.Pricing)
local Tools = require(Shared.Catalog.Tools)
local Upgrades = require(Shared.Catalog.Upgrades)
local Zones = require(Shared.Catalog.Zones)
local UiMath = require(Shared.Ui.UiMath)
local Components = require(script.Parent.Parent.Ui.Components)
local PanelHost = require(script.Parent.Parent.Ui.PanelHost)
local Context = require(script.Parent.Context)
local Widget = require(script.Parent.Widget)

local MenuBar = {}

export type MenuWidget = Widget.Widget & {
	setBadge: (panelId: string, on: boolean) -> (),
	rebuild: () -> (),
}

-- Panel ids can be spelled a few ways ("cool_down", "CoolDown"): compare them squashed.
local function squash(id: string): string
	return (string.gsub(string.lower(id), "[^%w]", ""))
end

local KIND_OF: { [string]: string } = {
	upgrades = "upgrades",
	upgrade = "upgrades",
	tools = "tools",
	tool = "tools",
	helpers = "helpers",
	helper = "helpers",
	bots = "helpers",
	gates = "gates",
	gate = "gates",
	zones = "gates",
	daily = "daily",
	cooldown = "cooldown",
}

local function affordable(kind: string, id: string | number, view: { [string]: any }): boolean
	local ok, price = pcall(Pricing.priceOf, kind, id, view :: any)
	if not ok or type(price) ~= "number" then
		return false
	end
	local coins = view.coins
	return type(coins) == "number" and price <= coins
end

-- Which auto dots are on for this store view.
local function autoDots(view: { [string]: any }): { [string]: boolean }
	local dots: { [string]: boolean } = {}
	if type(view.coins) ~= "number" then
		return dots
	end
	for _, id in Upgrades.order do
		if affordable("upgrade", id, view) then
			dots.upgrades = true
			break
		end
	end
	for _, tool in Tools.list do
		if affordable("tool", tool.id, view) then
			dots.tools = true
			break
		end
	end
	for _, zone in Zones.list do
		if zone.id > 1 and affordable("zone", zone.id, view) then
			dots.gates = true
			break
		end
	end
	if affordable("helper", "", view) or affordable("helperUp", "", view) then
		dots.helpers = true
	end
	local daily = view.daily
	if
		type(daily) == "table"
		and type(daily.lastDay) == "number"
		and UiMath.dailyReady(daily.lastDay, os.time())
	then
		dots.daily = true
	end
	local okCool, can = pcall(Economy.canCoolDown, view :: any)
	if okCool and can == true then
		dots.cooldown = true
	end
	return dots
end

function MenuBar.new(parent: Instance, ctx: Context.Context): MenuWidget
	local K = UiMath.K
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Menu"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromOffset(K.touch + 2 * K.menuPad, 300)
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroll.Parent = parent

	local buttons: { [string]: { button: Components.Button, badge: Components.Badge } } = {}
	local order: { string } = {}
	local manual: { [string]: boolean } = {}
	local auto: { [string]: boolean } = {}
	local cols = 1
	local dirty = true

	local function place()
		local step = K.touch + K.menuGap
		for i, id in order do
			local entry = buttons[id]
			if entry then
				local col = (i - 1) % cols
				local row = (i - 1) // cols
				entry.button.root.Position =
					UDim2.fromOffset(K.menuPad + col * step, K.menuPad + row * step)
			end
		end
		local rows = math.ceil(#order / math.max(1, cols))
		scroll.CanvasSize = UDim2.fromOffset(0, K.menuPad * 2 + rows * step)
	end

	local function paintBadges()
		for id, entry in buttons do
			local kind = KIND_OF[squash(id)]
			local on = manual[id] == true or (kind ~= nil and auto[kind] == true)
			entry.badge.set(on)
		end
	end

	local function rebuild()
		for _, entry in buttons do
			entry.badge.destroy()
			entry.button.destroy()
		end
		table.clear(buttons)
		table.clear(order)
		for _, def in PanelHost.menuButtons do
			local id = def.id
			local button = Components.IconButton({
				parent = scroll,
				name = "Menu_" .. id,
				icon = def.icon,
				size = UDim2.fromOffset(K.touch, K.touch),
				variant = "neutral",
			})
			button.onClick(function()
				PanelHost.toggle(id)
			end)
			local badge = Components.Badge({ parent = button.root })
			buttons[id] = { button = button, badge = badge }
			table.insert(order, id)
		end
		place()
		paintBadges()
	end

	local function recompute()
		dirty = false
		auto = autoDots(ctx.view())
		paintBadges()
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
	local changedConn = PanelHost.changed:connect(rebuild)
	ctx.onCleanup(function()
		changedConn:disconnect()
	end)
	rebuild()

	return {
		root = scroll,
		setBadge = function(panelId: string, on: boolean)
			manual[panelId] = on
			paintBadges()
		end,
		rebuild = rebuild,
		layout = function(_rect: UiMath.Rect, all: UiMath.Layout)
			local newCols = math.max(1, all.menuCols)
			scroll.ScrollingEnabled = all.menuScroll
			scroll.ScrollBarThickness = if all.menuScroll then 3 else 0
			cols = newCols
			place()
		end,
		destroy = function()
			for _, entry in buttons do
				entry.badge.destroy()
			end
			scroll:Destroy()
		end,
	}
end

return MenuBar
