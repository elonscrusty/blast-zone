--!strict
-- The HUD entry point. Hud.init() builds every widget once; layout comes from shared/Ui/UiMath so
-- nothing overlaps on a phone (landscape or portrait), a tablet or a PC.
--
--   Hud.init()                          build the HUD (safe to call twice)
--   Hud.destroy()                       remove everything, disconnect everything
--   Hud.toast(text, kind?)              kind: "info" | "good" | "warn" | "gold"
--   Hud.setBadge(panelId, on)           red dot on a menu button
--   Hud.coinTargetPosition(): UDim2?    centre of the coin icon in screen pixels (for flying coins)
--   Hud.sweepHeld(): boolean            true while the SWEEP button is held
--
-- Screens (one ScreenGui per layer, ResetOnSpawn off): HUD 10, Panels 20 (PanelHost), Banner 25,
-- Toasts 30, Splash 40.

local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiMath = require(Shared.Ui.UiMath)
local Bridge = require(script.Parent.Parent.Ui.Bridge)
local Components = require(script.Parent.Parent.Ui.Components)
local PanelHost = require(script.Parent.Parent.Ui.PanelHost)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Actions = require(script.Parent.Actions)
local Backpack = require(script.Parent.Backpack)
local BuffChips = require(script.Parent.BuffChips)
local BurpBanner = require(script.Parent.BurpBanner)
local CleanBar = require(script.Parent.CleanBar)
local Coins = require(script.Parent.Coins)
local Context = require(script.Parent.Context)
local MenuBar = require(script.Parent.MenuBar)
local OfflineBadge = require(script.Parent.OfflineBadge)
local Splash = require(script.Parent.Splash)
local Toasts = require(script.Parent.Toasts)
local Widget = require(script.Parent.Widget)

local Hud = {}

type State = {
	ctx: Context.Context,
	hudScreen: Components.Screen,
	bannerScreen: Components.Screen,
	toastScreen: Components.Screen,
	splash: Splash.SplashHandle?,
	coins: Coins.CoinsWidget?,
	pack: Widget.Widget?,
	clean: Widget.Widget?,
	buffs: Widget.Widget?,
	banner: Widget.Widget?,
	toasts: Toasts.ToastsWidget?,
	offline: Widget.Widget?,
	menu: MenuBar.MenuWidget?,
	actions: Actions.ActionsWidget?,
	connections: { any },
}

local state: State? = nil
local pendingToasts: { { text: string, kind: string? } } = {}
local MAX_PENDING_TOASTS = 5

local function place(obj: GuiObject, r: UiMath.Rect)
	obj.AnchorPoint = Vector2.zero
	obj.Position = UDim2.fromOffset(r.x, r.y)
	obj.Size = UDim2.fromOffset(r.w, r.h)
end

-- Build one widget; a failure is reported and that widget is skipped, the rest still appear.
local function build<T>(name: string, fn: () -> T): T?
	local ok, result = pcall(fn)
	if not ok then
		warn(`[Hud] {name} failed to build: {result}`)
		return nil
	end
	return result
end

local function relayout(s: State)
	local screen = s.hudScreen
	local l = UiMath.layout(screen.size.X, screen.size.Y, {
		top = Theme.topInset() / screen.scale,
		touch = UserInputService.TouchEnabled,
		menuCount = #PanelHost.menuButtons,
	})

	local function put(w: Widget.Widget?, r: UiMath.Rect)
		if w then
			place(w.root, r)
			if w.layout then
				w.layout(r, l)
			end
		end
	end
	put(s.coins, l.coins)
	put(s.pack, l.pack)
	put(s.clean, l.clean)
	put(s.buffs, l.buffs)
	put(s.banner, l.banner)
	put(s.offline, l.offline)
	put(s.menu, l.menu)
	if s.toasts then
		-- keep a one-row region even when the screen is very short (a toast must never vanish)
		place(s.toasts.root, {
			x = l.toasts.x,
			y = l.toasts.y,
			w = l.toasts.w,
			h = math.max(l.toasts.h, UiMath.K.toastH),
		})
		s.toasts.setMax(math.max(1, l.toastMax))
	end
	if s.actions then
		place(s.actions.sweep, l.sweep)
		place(s.actions.sell, l.sell)
		place(s.actions.auto, l.auto)
	end
end

function Hud.toast(text: string, kind: string?)
	local s = state
	if s and s.toasts then
		s.toasts.push(text, kind)
	elseif #pendingToasts < MAX_PENDING_TOASTS then
		table.insert(pendingToasts, { text = text, kind = kind })
	end
end

function Hud.setBadge(panelId: string, on: boolean)
	local s = state
	if s and s.menu then
		s.menu.setBadge(panelId, on)
	end
end

function Hud.coinTargetPosition(): UDim2?
	local s = state
	if s and s.coins then
		return s.coins.targetPosition()
	end
	return nil
end

function Hud.sweepHeld(): boolean
	local controls = Bridge.controls()
	if controls ~= nil and type(controls.sweepHeld) == "function" then
		local ok, held = pcall(controls.sweepHeld)
		return ok and held == true
	end
	return false
end

function Hud.init()
	if state ~= nil then
		return
	end
	local ctx = Context.new()
	local splash = build("Splash", function()
		return Splash.new()
	end)
	PanelHost.init()
	local hudScreen = Components.screen("VSHud", Theme.DisplayOrder.hud)
	local bannerScreen = Components.screen("VSBanner", Theme.DisplayOrder.banner)
	local toastScreen = Components.screen("VSToasts", Theme.DisplayOrder.toasts)

	local s: State = {
		ctx = ctx,
		hudScreen = hudScreen,
		bannerScreen = bannerScreen,
		toastScreen = toastScreen,
		splash = splash,
		coins = build("Coins", function()
			return Coins.new(hudScreen.root, ctx)
		end),
		pack = build("Backpack", function()
			return Backpack.new(hudScreen.root, ctx)
		end),
		clean = build("CleanBar", function()
			return CleanBar.new(hudScreen.root, ctx)
		end),
		buffs = build("BuffChips", function()
			return BuffChips.new(hudScreen.root, ctx)
		end),
		banner = build("BurpBanner", function()
			return BurpBanner.new(bannerScreen.root, ctx)
		end),
		toasts = build("Toasts", function()
			return Toasts.new(toastScreen.root, ctx)
		end),
		offline = build("OfflineBadge", function()
			return OfflineBadge.new(hudScreen.root, ctx)
		end),
		menu = build("MenuBar", function()
			return MenuBar.new(hudScreen.root, ctx)
		end),
		actions = build("Actions", function()
			return Actions.new(hudScreen.root, ctx)
		end),
		connections = {},
	}
	state = s

	-- toasts: the Toast remote, panels (ctx.toast) and local callers all end up in one place
	ctx.toastImpl = Hud.toast
	PanelHost.toastHandler = Hud.toast
	ctx.listen("Toast", function(payload: any)
		if type(payload) == "table" and type(payload.text) == "string" then
			Hud.toast(payload.text, if type(payload.kind) == "string" then payload.kind else "info")
		end
	end)
	for _, p in pendingToasts do
		Hud.toast(p.text, p.kind)
	end
	table.clear(pendingToasts)

	-- opening a panel lets go of SWEEP so it never stays stuck behind the backdrop
	local openConn = PanelHost.stateChanged:connect(function(openId: string?)
		if openId ~= nil and s.actions then
			s.actions.releaseSweep()
		end
	end)
	local changedConn = PanelHost.changed:connect(function()
		relayout(s)
	end)
	local resizeConn = hudScreen.resized:connect(function()
		relayout(s)
	end)
	table.insert(s.connections, openConn)
	table.insert(s.connections, changedConn)
	table.insert(s.connections, resizeConn)

	relayout(s)
end

function Hud.destroy()
	local s = state
	if s == nil then
		return
	end
	state = nil
	for _, c in s.connections do
		c:disconnect()
	end
	if s.actions then
		s.actions.releaseSweep()
	end
	s.ctx.destroy()
	local function kill(w: Widget.Widget?)
		if w then
			w.destroy()
		end
	end
	kill(s.coins)
	kill(s.pack)
	kill(s.clean)
	kill(s.buffs)
	kill(s.banner)
	kill(s.toasts)
	kill(s.offline)
	kill(s.menu)
	if s.actions then
		s.actions.destroy()
	end
	if s.splash then
		s.splash.destroy()
	end
	PanelHost.toastHandler = nil
	PanelHost.destroy()
	s.hudScreen.destroy()
	s.bannerScreen.destroy()
	s.toastScreen.destroy()
end

return Hud
