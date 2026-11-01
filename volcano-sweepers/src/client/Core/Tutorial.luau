--!strict
-- First-time hints, drawn so a 7-year-old needs no reading menus. The stage machine is pure and
-- tested (Shared/Client/TutorialLogic); this file only gathers the facts and draws:
--   * one short line of text floating above the character
--   * a glowing line on the ground to where they must walk (the nearest ash, or the Trade Hut)
--   * a bouncing finger + pulsing ring on the one button they need (SWEEP, AUTO, SELL, Upgrades)
-- Stages: walk to the ash -> hold SWEEP -> fill the backpack (AUTO tip on touch) -> walk to the hut
-- -> SELL -> open Upgrades and buy something -> "You got stronger!". Each step advances on what
-- REALLY happened (ash in the backpack, a sale, a purchase), never on a button press.
-- `TutorialDone` is sent after the first sale (so a rejoin never repeats the basics); the shop step
-- then runs for the rest of this visit. Skipped completely when Store.tutorialDone is already true.
--
-- The finger finds HUD buttons by name (Hud/Actions: SweepButton, AutoButton, SellButton; Hud/MenuBar:
-- the MENU launcher Menu_menu; Panels/Menu: the Upgrades tile Menu_upgrades, only while the tile menu
-- is open). A missing button just means no finger.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Layout = require(Shared.Ash.Layout)
local StoreLogic = require(Shared.Client.StoreLogic)
local TutorialLogic = require(Shared.Client.TutorialLogic)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Net = require(script.Parent.Net)
local Store = require(script.Parent.Store)

local function softRequire(folderName: string, moduleName: string): any?
	local folder = script.Parent.Parent:FindFirstChild(folderName)
	local mod = if folder ~= nil then folder:FindFirstChild(moduleName) else nil
	if mod == nil or not mod:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn(`[Tutorial] could not load {moduleName}: {result}`)
		return nil
	end
	return result
end

local Tutorial = {}

local POLL = 0.2
local GROUND_Y: number = Config.World.groundY
local SELL_RANGE: number = Config.World.sellRange
local ZONE_COUNT: number = #Layout.zoneIds
local FIND_RADII = { 24, 48, 80, 130 } -- growing search for the nearest ash
local POINT_NAMES: { [string]: { string } } = {
	sweep = { "SweepButton" },
	auto = { "AutoButton" },
	sell = { "SellButton" },
	menu = { "Menu_menu" }, -- the HUD's MENU launcher
	upgrades = { "Menu_upgrades" }, -- the Upgrades tile inside the open tile menu
}

-- Colours and font: the one UI Theme (one palette for the whole game).
local TEXT_COLOR: Color3 = Theme.color.goldLight
local STROKE_COLOR: Color3 = Theme.color.ink
local BEAM_A: Color3 = Theme.color.gold
local BEAM_B: Color3 = Theme.color.lava
local FONT: Enum.Font = Theme.font.title
local ORDER_POINTER: number = Theme.DisplayOrder.overlay - 1 -- over panels, under the splash

local stage = "idle"
local logic: TutorialLogic.State? = nil
local started = false
local gui: BillboardGui? = nil
local label: TextLabel? = nil
local beam: Beam? = nil
local att0: Attachment? = nil
local targetPart: Part? = nil
local pointerGui: ScreenGui? = nil
local finger: TextLabel? = nil
local ring: Frame? = nil
local pointCache: { [string]: GuiObject } = {}
local pointSearchAt: { [string]: number } = {}
local conns: { RBXScriptConnection } = {}
local signalConns: { any } = {} -- Shared/Signal connections (disconnect, lowercase)
local polled = 0
local openPanelId: string? = nil
local lastPoint: string? = nil -- what the finger points at (refreshed every frame while shown)
local lastAshCell: number? = nil
local lastAshSearch = -10

local function myRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp ~= nil and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function hutPosition(from: Vector3): Vector3
	local best: Vector3? = nil
	local bestD = math.huge
	for _, inst in CollectionService:GetTagged("VSSellPad") do
		if inst:IsA("BasePart") then
			local d = (inst.Position - from).Magnitude
			if d < bestD then
				bestD = d
				best = inst.Position
			end
		end
	end
	return best or Vector3.new(Layout.hubX, GROUND_Y, Layout.hubZ)
end

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- ===== world text =====

local function ensureGui(): (BillboardGui?, TextLabel?)
	if gui ~= nil and gui.Parent ~= nil and label ~= nil then
		return gui, label
	end
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return nil, nil
	end
	local g = Instance.new("BillboardGui")
	g.Name = "VSTutorialHint"
	g.Size = UDim2.fromOffset(300, 70)
	g.StudsOffset = Vector3.new(0, 5.5, 0)
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.ResetOnSpawn = false
	g.Enabled = false
	g.Parent = pg
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextScaled = true
	l.TextColor3 = TEXT_COLOR
	l.Text = ""
	l.Parent = g
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 30
	limit.MinTextSize = 14
	limit.Parent = l
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = STROKE_COLOR
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = l
	gui, label = g, l
	return g, l
end

local function showText(text: string, hrp: BasePart)
	local g, l = ensureGui()
	if g == nil or l == nil then
		return
	end
	local character = Players.LocalPlayer.Character
	local head = if character ~= nil then character:FindFirstChild("Head") else nil
	local adornee: Instance = if head ~= nil and head:IsA("BasePart") then head else hrp
	if g.Adornee ~= adornee then
		g.Adornee = adornee
	end
	l.Text = text
	g.Enabled = true
end

local function hideText()
	if gui ~= nil then
		gui.Enabled = false
	end
end

-- ===== ground line =====

local function ensureBeam(hrp: BasePart): Beam?
	if beam == nil or beam.Parent == nil or targetPart == nil or targetPart.Parent == nil then
		if targetPart ~= nil then
			targetPart:Destroy()
		end
		local part = Instance.new("Part")
		part.Name = "VSTutorialTarget"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.5, 0.5, 0.5)
		part.Parent = workspace
		local a1 = Instance.new("Attachment")
		a1.Parent = part
		local b = Instance.new("Beam")
		b.Attachment1 = a1
		b.FaceCamera = true
		b.Segments = 1
		b.Width0 = 0.9
		b.Width1 = 0.9
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Transparency = NumberSequence.new(0.25)
		b.Color = ColorSequence.new(BEAM_A, BEAM_B)
		b.Parent = part
		beam, targetPart = b, part
	end
	-- The start sits in the CURRENT character. After a respawn the old one was destroyed with the old
	-- character (its Parent is locked), so make a fresh one instead of moving it.
	local a = att0
	if a == nil or a.Parent ~= hrp then
		if a ~= nil and a.Parent ~= nil then
			a:Destroy()
		end
		local fresh = Instance.new("Attachment")
		fresh.Name = "VSTutorialStart"
		fresh.Position = Vector3.new(0, -2.4, 0)
		fresh.Parent = hrp
		att0 = fresh
		a = fresh
	end
	local b = beam :: Beam
	if b.Attachment0 ~= a then
		b.Attachment0 = a
	end
	return b
end

local function showBeam(hrp: BasePart, to: Vector3)
	local b = ensureBeam(hrp)
	if b ~= nil and targetPart ~= nil then
		targetPart.Position = Vector3.new(to.X, GROUND_Y + 1.2, to.Z)
		b.Enabled = true
	end
end

local function hideBeam()
	if beam ~= nil then
		beam.Enabled = false
	end
end

-- ===== finger on a HUD button =====

local function ensurePointer(): boolean
	if pointerGui ~= nil and pointerGui.Parent ~= nil and finger ~= nil and ring ~= nil then
		return true
	end
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return false
	end
	local g = Instance.new("ScreenGui")
	g.Name = "VSTutorialPointer"
	g.DisplayOrder = ORDER_POINTER
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.Enabled = false
	pcall(function()
		(g :: any).ScreenInsets = Enum.ScreenInsets.None
	end)
	g.Parent = pg
	local r = Instance.new("Frame")
	r.Name = "Ring"
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.BackgroundTransparency = 1
	r.Active = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = r
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = BEAM_A
	stroke.Parent = r
	r.Parent = g
	local f = Instance.new("TextLabel")
	f.Name = "Finger"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(56, 56)
	f.BackgroundTransparency = 1
	f.Text = "👇"
	f.TextScaled = true
	f.Font = FONT
	f.Active = false
	f.Parent = g
	pointerGui, finger, ring = g, f, r
	return true
end

local function visibleOnScreen(obj: GuiObject): boolean
	if obj.Parent == nil or obj.AbsoluteSize.X < 4 then
		return false
	end
	local node: Instance? = obj
	while node ~= nil do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("ScreenGui") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

local function findButton(kind: string): GuiObject?
	local cached = pointCache[kind]
	if cached ~= nil and cached.Parent ~= nil and visibleOnScreen(cached) then
		return cached
	end
	pointCache[kind] = nil
	local now = os.clock()
	if now - (pointSearchAt[kind] or -10) < 0.5 then
		return nil
	end
	pointSearchAt[kind] = now
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return nil
	end
	for _, name in POINT_NAMES[kind] or {} do
		for _, inst in pg:GetDescendants() do
			if inst.Name == name and inst:IsA("GuiObject") and visibleOnScreen(inst) then
				pointCache[kind] = inst
				return inst
			end
		end
	end
	return nil
end

local function hidePointer()
	if pointerGui ~= nil then
		pointerGui.Enabled = false
	end
end

local function showPointer(kind: string)
	local target = findButton(kind)
	if target == nil or not ensurePointer() then
		hidePointer()
		return
	end
	local g = pointerGui :: ScreenGui
	local f = finger :: TextLabel
	local r = ring :: Frame
	local screen = g.AbsoluteSize
	local centre = target.AbsolutePosition + target.AbsoluteSize / 2 - g.AbsolutePosition
	local half = math.max(target.AbsoluteSize.X, target.AbsoluteSize.Y) / 2
	local t = os.clock()
	local bounce = math.abs(math.sin(t * 5)) * 12
	-- a finger beside the button, pointing at it (never off screen)
	local fx, fy, glyph
	if centre.X < screen.X * 0.3 then
		fx, fy, glyph = centre.X + half + 34 + bounce, centre.Y, "👈"
	elseif centre.Y > screen.Y * 0.5 then
		fx, fy, glyph = centre.X, centre.Y - half - 34 - bounce, "👇"
	else
		fx, fy, glyph = centre.X, centre.Y + half + 34 + bounce, "👆"
	end
	f.Text = glyph
	f.Position = UDim2.fromOffset(fx, fy)
	local grow = 1 + 0.12 * (0.5 + 0.5 * math.sin(t * 6))
	local d = (half * 2 + 14) * grow
	r.Size = UDim2.fromOffset(d, d)
	r.Position = UDim2.fromOffset(centre.X, centre.Y)
	g.Enabled = true
end

-- ===== facts =====

local rendererCache: any = nil
local function renderer(): any
	if rendererCache == nil then
		rendererCache = softRequire("Ash", "AshRenderer")
	end
	return rendererCache
end

-- Nearest cell with ash in an unlocked zone (searched in growing circles, at most twice a second).
local function nearestAsh(hrp: BasePart, view: { [string]: any }): Vector3?
	local now = os.clock()
	local r = renderer()
	if r == nil then
		return nil
	end
	if lastAshCell ~= nil and r.levelAt(lastAshCell) > 0 and now - lastAshSearch < 0.5 then
		return Vector3.new(Layout.cx[lastAshCell], GROUND_Y, Layout.cz[lastAshCell])
	end
	lastAshSearch = now
	lastAshCell = nil
	local allowed = StoreLogic.unlockedSet(view, ZONE_COUNT)
	local p = hrp.Position
	for _, radius in FIND_RADII do
		local best, bestD = nil, math.huge
		for _, i in Layout.cellsInRadius(p.X, p.Z, radius) do
			if allowed[Layout.zone[i]] and r.levelAt(i) > 0 then
				local dx, dz = Layout.cx[i] - p.X, Layout.cz[i] - p.Z
				local d = dx * dx + dz * dz
				if d < bestD then
					best, bestD = i, d
				end
			end
		end
		if best ~= nil then
			lastAshCell = best
			return Vector3.new(Layout.cx[best], GROUND_Y, Layout.cz[best])
		end
	end
	return nil
end

local function ashInReach(hrp: BasePart, view: { [string]: any }): boolean
	local r = renderer()
	if r == nil or type(r.ashAhead) ~= "function" then
		return true -- cannot tell: assume yes so the basic hint still shows
	end
	local derived = view.derived
	local reach = if type(derived) == "table" and type(derived.reach) == "number"
		then derived.reach
		else 7
	-- any direction counts: turning to face it is part of sweeping
	return r.ashAhead(
		hrp.Position.X,
		hrp.Position.Z,
		0,
		-1,
		reach,
		360,
		StoreLogic.unlockedSet(view, ZONE_COUNT)
	)
end

local function canBuy(view: { [string]: any }): boolean
	local ok, Model = pcall(function()
		return require(Shared.Ui.UpgradesModel) :: any
	end)
	if ok and Model ~= nil and type(Model.canBuyAny) == "function" then
		local ok2, yes = pcall(Model.canBuyAny, view)
		return ok2 and yes == true
	end
	return false
end

-- ===== the loop =====

local function cleanup()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	for _, c in signalConns do
		pcall(function()
			c:disconnect()
		end)
	end
	table.clear(signalConns)
	if gui ~= nil then
		gui:Destroy()
	end
	if targetPart ~= nil then
		targetPart:Destroy()
	end
	if att0 ~= nil and att0.Parent ~= nil then
		att0:Destroy()
	end
	if pointerGui ~= nil then
		pointerGui:Destroy()
	end
	gui, label, beam, att0, targetPart = nil, nil, nil, nil, nil
	pointerGui, finger, ring = nil, nil, nil
	table.clear(pointCache)
end

local function finish()
	stage = "done"
	cleanup()
end

local function poll()
	local s = logic
	if s == nil then
		return
	end
	local hrp = myRoot()
	if hrp == nil then
		hideText()
		hideBeam()
		hidePointer()
		return
	end
	local view = Store.view()
	local hut = hutPosition(hrp.Position)
	local flatHut = Vector3.new(hut.X - hrp.Position.X, 0, hut.Z - hrp.Position.Z).Magnitude
	local carried = view.carried
	local facts: TutorialLogic.Facts = {
		now = os.clock(),
		carried = if type(carried) == "number" then carried else 0,
		fraction = StoreLogic.backpackFraction(view),
		ashInReach = ashInReach(hrp, view),
		nearHut = flatHut <= SELL_RANGE,
		canBuy = s.stage == "buy" and canBuy(view),
		panelOpen = openPanelId ~= nil,
		menuOpen = openPanelId == "menu",
		autoOn = StoreLogic.setting(view, "autoSweep", true),
		touch = isTouch(),
	}
	local hint = TutorialLogic.step(s, facts)
	if s.stage == "done" then
		finish()
		return
	end

	if hint.text ~= nil then
		showText(hint.text, hrp)
	else
		hideText()
	end

	if hint.beam == "hut" then
		showBeam(hrp, hut)
	elseif hint.beam == "ash" then
		local ash = nearestAsh(hrp, view)
		if ash ~= nil then
			showBeam(hrp, ash)
		else
			hideBeam()
		end
	else
		hideBeam()
	end

	lastPoint = hint.point
	if hint.point ~= nil then
		showPointer(hint.point)
	else
		hidePointer()
	end
end

function Tutorial.init()
	if started then
		return
	end
	started = true
	Store.onReady(function()
		if Store.get("tutorialDone") == true then
			stage = "done"
			return
		end
		stage = "running"
		local s = TutorialLogic.new(os.clock())
		logic = s

		table.insert(
			conns,
			Net.on("Sold", function()
				if stage == "done" then
					return
				end
				if not s.sold then
					Net.send("TutorialDone") -- saved by the server: a rejoin skips the basics
				end
				TutorialLogic.onSold(s, os.clock())
			end)
		)

		-- something bought: an upgrade level, a tool or a zone
		local function bought(value: any, old: any)
			if old ~= nil and type(value) == "table" and not StoreLogic.deepEqual(value, old) then
				TutorialLogic.onBought(s, os.clock())
			end
		end
		for _, key in { "upgrades", "toolsOwned", "zones" } do
			local unsub = Store.subscribe(key, bought)
			table.insert(signalConns, { disconnect = unsub })
		end

		-- is a panel open? (no finger over an open panel)
		local PanelHost: any = softRequire("Ui", "PanelHost")
		if PanelHost ~= nil and PanelHost.stateChanged ~= nil then
			table.insert(
				signalConns,
				PanelHost.stateChanged:connect(function(openId: any)
					openPanelId = if type(openId) == "string" then openId else nil
					polled = POLL -- re-point at once (MENU -> the Upgrades tile)
				end)
			)
		end

		table.insert(
			conns,
			RunService.Heartbeat:Connect(function(dt: number)
				polled += dt
				-- the finger bounces smoothly between polls
				if
					pointerGui ~= nil
					and pointerGui.Enabled
					and s.stage ~= "done"
					and lastPoint ~= nil
				then
					showPointer(lastPoint)
				end
				if polled < POLL then
					return
				end
				polled = 0
				if stage ~= "done" then
					local ok, err = pcall(poll)
					if not ok then
						warn(`[Tutorial] {err}`)
					end
				end
			end)
		)
	end)
end

return Tutorial
