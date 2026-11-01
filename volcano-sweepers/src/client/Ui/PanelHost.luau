--!strict
-- One modal panel at a time, always the same way: dimmed backdrop, pop-in, big red X, tap outside /
-- Escape / gamepad B to close. Panels only describe themselves; the host builds the frame.
--
--   PanelHost.register(def)    def = { id, title, icon, order, build = function(parent, ctx) ... end }
--                              build fills `parent` (the panel body) and may return a cleanup function
--                              that runs when the panel closes (stop timers, disconnect events).
--   PanelHost.open(id) / close() / toggle(id) / isOpen(): boolean / currentId(): string?
--   PanelHost.menuButtons      LIVE list { {id,title,icon,order} } sorted by order (the HUD menu reads it)
--   PanelHost.changed          Signal: fires when a panel is registered
--   PanelHost.stateChanged     Signal(openId: string?): fires when a panel opens or closes
--   PanelHost.toastHandler     set by the HUD so ctx.toast works from panels
--
-- ctx (second argument of build): { id, close(), toast(text, kind?), setTitle(text), size(): Vector2 }

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)
local UiMath = require(Shared.Ui.UiMath)
local Bridge = require(script.Parent.Bridge)
local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

export type Ctx = {
	id: string,
	close: () -> (),
	toast: (text: string, kind: string?) -> (),
	setTitle: (text: string) -> (),
	size: () -> Vector2,
}

export type Def = {
	id: string,
	title: string,
	icon: string,
	order: number,
	build: (parent: Frame, ctx: Ctx) -> (() -> ())?,
}

export type MenuButton = { id: string, title: string, icon: string, order: number }

type Open = {
	id: string,
	holder: Frame,
	backdrop: TextButton,
	panel: Components.Panel,
	pop: UIScale,
	cleanup: (() -> ())?,
	closing: boolean,
}

local PanelHost = {}

PanelHost.menuButtons = {} :: { MenuButton }
PanelHost.changed = Signal.new()
PanelHost.stateChanged = Signal.new()
PanelHost.toastHandler = nil :: ((text: string, kind: string?) -> ())?

local ACTION = "VSClosePanel"
local BACKDROP_DIM = 0.45
local CLOSE_TIME = 0.14
local SPILL = 1000 -- backdrop extends this far past the screen so notches/insets are covered

local defs: { [string]: Def } = {}
local screen: Components.Screen? = nil
local current: Open? = nil
local resizeConn: any = nil

local function rebuildMenu()
	local list = PanelHost.menuButtons
	table.clear(list)
	for _, def in defs do
		table.insert(list, { id = def.id, title = def.title, icon = def.icon, order = def.order })
	end
	table.sort(list, function(a: MenuButton, b: MenuButton)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.id < b.id
	end)
end

function PanelHost.register(def: Def)
	if
		type(def) ~= "table"
		or type(def.id) ~= "string"
		or def.id == ""
		or type(def.build) ~= "function"
	then
		warn("[PanelHost] register: bad panel definition")
		return
	end
	defs[def.id] = {
		id = def.id,
		title = if type(def.title) == "string" then def.title else def.id,
		icon = if type(def.icon) == "string" then def.icon else "",
		order = if type(def.order) == "number" then def.order else 100,
		build = def.build,
	}
	rebuildMenu()
	PanelHost.changed:fire()
end

function PanelHost.isOpen(): boolean
	return current ~= nil and not current.closing
end

function PanelHost.currentId(): string?
	if current ~= nil and not current.closing then
		return current.id
	end
	return nil
end

local function ensureScreen(): Components.Screen
	if screen == nil then
		screen = Components.screen("VSPanels", Theme.DisplayOrder.panels, { spill = true })
	end
	return screen :: Components.Screen
end

local function placePanel(open: Open)
	local s = ensureScreen()
	local rect = UiMath.panelRect(s.size.X, s.size.Y, Theme.topInset() / s.scale)
	open.panel.root.AnchorPoint = Vector2.new(0.5, 0.5)
	open.panel.root.Position = UDim2.fromOffset(rect.x + rect.w / 2, rect.y + rect.h / 2)
	open.panel.root.Size = UDim2.fromOffset(rect.w, rect.h)
	open.backdrop.Position = UDim2.fromOffset(-SPILL, -SPILL)
	open.backdrop.Size = UDim2.fromOffset(s.size.X + 2 * SPILL, s.size.Y + 2 * SPILL)
end

-- Remove the open panel right now (no animation).
local function destroyNow(open: Open)
	if open.cleanup then
		local fn = open.cleanup
		open.cleanup = nil
		local ok, err = pcall(fn)
		if not ok then
			warn(`[PanelHost] cleanup for {open.id} failed: {err}`)
		end
	end
	open.holder:Destroy()
	if current == open then
		current = nil
	end
end

local function unbindKeys()
	pcall(function()
		ContextActionService:UnbindAction(ACTION)
	end)
	if resizeConn then
		resizeConn:disconnect()
		resizeConn = nil
	end
end

function PanelHost.close()
	local open = current
	if open == nil or open.closing then
		return
	end
	open.closing = true
	unbindKeys()
	-- stop panel timers right away; the frame fades out on its own
	if open.cleanup then
		local fn = open.cleanup
		open.cleanup = nil
		local ok, err = pcall(fn)
		if not ok then
			warn(`[PanelHost] cleanup for {open.id} failed: {err}`)
		end
	end
	Bridge.play("click")
	Components.tween(open.backdrop, { BackgroundTransparency = 1 }, TweenInfo.new(CLOSE_TIME))
	local t = Components.tween(
		open.pop,
		{ Scale = 0.88 },
		TweenInfo.new(CLOSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	)
	PanelHost.stateChanged:fire(nil)
	t.Completed:Connect(function()
		if open.holder.Parent ~= nil then
			destroyNow(open)
		end
	end)
end

function PanelHost.open(id: string)
	local def = defs[id]
	if def == nil then
		warn(`[PanelHost] open: no panel called {id}`)
		return
	end
	if current ~= nil then
		if current.id == id and not current.closing then
			return
		end
		unbindKeys()
		destroyNow(current)
	end
	local s = ensureScreen()

	local holder = Instance.new("Frame")
	holder.Name = "PanelLayer_" .. id
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = s.root

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BorderSizePixel = 0
	backdrop.BackgroundColor3 = Theme.color.ink
	backdrop.BackgroundTransparency = 1
	backdrop.Parent = holder

	local panel = Components.Panel({
		parent = holder,
		name = "Panel_" .. id,
		title = def.title,
		icon = def.icon,
		onClose = function()
			PanelHost.close()
		end,
	})
	-- tapping the backdrop (outside the panel) closes it
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Scale = 0.8
	pop.Parent = panel.root

	local open: Open = {
		id = id,
		holder = holder,
		backdrop = backdrop,
		panel = panel,
		pop = pop,
		cleanup = nil,
		closing = false,
	}
	current = open
	placePanel(open)

	backdrop.Activated:Connect(function()
		PanelHost.close()
	end)

	local ctx: Ctx = {
		id = id,
		close = function()
			PanelHost.close()
		end,
		toast = function(text: string, kind: string?)
			local handler = PanelHost.toastHandler
			if handler then
				handler(text, kind)
			end
		end,
		setTitle = function(text: string)
			panel.setTitle(text)
		end,
		size = function(): Vector2
			return panel.body.AbsoluteSize
		end,
	}
	local ok, result = pcall(def.build, panel.body, ctx)
	if ok then
		open.cleanup = result :: (() -> ())?
	else
		warn(`[PanelHost] panel {id} failed to build: {result}`)
		Components.Label({
			parent = panel.body,
			text = "Oops! Something went wrong.\nTap X and try again.",
			textSize = Theme.text.big,
			wrap = true,
		})
	end

	Components.tween(backdrop, { BackgroundTransparency = BACKDROP_DIM }, Theme.ease.normal)
	Components.tween(pop, { Scale = 1 }, Theme.ease.pop)
	Bridge.play("click")

	resizeConn = s.resized:connect(function()
		if current == open and not open.closing then
			placePanel(open)
		end
	end)

	ContextActionService:BindActionAtPriority(
		ACTION,
		function(_name: string, state: Enum.UserInputState, _input: InputObject)
			if state == Enum.UserInputState.Begin then
				PanelHost.close()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Escape
	)
	PanelHost.stateChanged:fire(id)
end

function PanelHost.toggle(id: string)
	if PanelHost.currentId() == id then
		PanelHost.close()
	else
		PanelHost.open(id)
	end
end

-- Builds the layer early (so the first open is instant). Safe to call more than once.
function PanelHost.init()
	ensureScreen()
end

-- Tear everything down (used by Hud.destroy).
function PanelHost.destroy()
	if current then
		unbindKeys()
		destroyNow(current)
	end
	if screen then
		screen.destroy()
		screen = nil
	end
end

return PanelHost
