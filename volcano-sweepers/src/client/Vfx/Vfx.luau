--!strict
-- World and screen effects. Everything here is plain Instances (Parts, Neon, ParticleEmitters with
-- their default built-in texture, BillboardGuis, Frames): no asset ids. Hot things are pooled.
--
-- Calls other code may use:
--   Vfx.puff(worldPos, hexColor, amount?)        ash-coloured cloud
--   Vfx.floatText(worldPos, text, kind?)         rising number. kind: coin | ash | good | bad | find | info
--   Vfx.coinBurst(count)                         gold coins fly from the screen centre to the coin
--                                                counter (Hud.coinTargetPosition() if the Hud exists)
--   Vfx.shake(strength, duration)                camera shake (through CameraFx, respects settings.shake)
--   Vfx.fireworks(worldPos, count?)              rockets + bursts around a point
--   Vfx.lavaTelegraph(bomb)                      red pulsing disc until bomb.landsAt, then the impact
--   Vfx.lavaImpact(x, z, radius)                 the splash itself
--   Vfx.screenTint(colorHex, alpha, seconds)     full-screen colour flash (own ScreenGui, order 50)
--
-- Remote hooks (world-space only; toasts and banners belong to the HUD): SweepFx, Sold, Burp, Bombs,
-- BurpHit, Party, FindFound, CoolDownDone, GeyserGems. Cleared ash cells also sparkle a little.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CullLogic = require(Shared.Client.CullLogic)
local Layout = require(Shared.Ash.Layout)
local StoreLogic = require(Shared.Client.StoreLogic)
local Tools = require(Shared.Catalog.Tools)
local Types = require(Shared.Types)
local Zones = require(Shared.Catalog.Zones)
local Net = require(script.Parent.Parent.Core.Net)

local function softRequire(parent: Instance?, folderName: string, moduleName: string): any?
	if parent == nil then
		return nil
	end
	local folder = parent:FindFirstChild(folderName)
	local mod = if folder ~= nil then folder:FindFirstChild(moduleName) else nil
	if mod == nil or not mod:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn(`[Vfx] could not load {moduleName}: {result}`)
		return nil
	end
	return result
end

local clientRoot = script.Parent.Parent
local Sfx: any = softRequire(clientRoot, "Core", "Sfx")
local Haptics: any = softRequire(clientRoot, "Core", "Haptics")
local CameraFx: any = softRequire(clientRoot, "Core", "CameraFx")
local AshRenderer: any = softRequire(clientRoot, "Ash", "AshRenderer")

type Bomb = Types.Bomb

local Vfx = {}

local LocalPlayer = Players.LocalPlayer
local GROUND_Y: number = Config.World.groundY

-- ===== tiny helpers =====

local function color3(hex: string): Color3
	local r, g, b = CullLogic.parseHex(hex)
	return Color3.fromRGB(r, g, b)
end

local function sfx(name: string, volume: number?)
	if Sfx ~= nil then
		Sfx.play(name, volume)
	end
end

local function haptic(strength: number)
	if Haptics ~= nil then
		Haptics.tap(strength)
	end
end

local function myRoot(): BasePart?
	local character = LocalPlayer.Character
	if character == nil then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp ~= nil and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp ~= nil and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

-- Where the camera is looking, or the character: the centre for "is this near me" checks.
local function focusPos(): Vector3?
	local hrp = myRoot()
	if hrp ~= nil then
		return hrp.Position
	end
	local cam = workspace.CurrentCamera
	if cam ~= nil then
		return cam.Focus.Position
	end
	return nil
end

local function distFlat(x: number, z: number): number
	local f = focusPos()
	if f == nil then
		return math.huge
	end
	local dx, dz = x - f.X, z - f.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -1e7 and v < 1e7
end

local function playerGui(): PlayerGui?
	local existing = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if existing ~= nil then
		return existing
	end
	return LocalPlayer:WaitForChild("PlayerGui", 10) :: PlayerGui?
end

local fxFolder = workspace:FindFirstChild("VSFxClient")
if fxFolder ~= nil then
	fxFolder:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "VSFxClient"
folder.Parent = workspace

local function ashHexAt(x: number, z: number): string
	local zone = Layout.zoneAt(x, z)
	if zone ~= nil and Zones.byId[zone] ~= nil then
		return Zones.byId[zone].ash
	end
	return "#B8B2AA"
end

-- ===== pooled particle emitters =====

type EmitterKind = "puff" | "spark" | "glitter" | "firework"
type Slot = { part: Part, emitter: ParticleEmitter }

local POOL_SIZE: { [string]: number } = { puff = 28, spark = 14, glitter = 14, firework = 10 }
local emitterPools: { [string]: { Slot } } = { puff = {}, spark = {}, glitter = {}, firework = {} }
local emitterCursor: { [string]: number } = { puff = 0, spark = 0, glitter = 0, firework = 0 }

local function seq(points: { { number } }): NumberSequence
	local keys: { NumberSequenceKeypoint } = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function configure(kind: string, e: ParticleEmitter)
	e.Rate = 0
	e.Enabled = false
	e.LockedToPart = false
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	if kind == "puff" then
		e.Lifetime = NumberRange.new(0.5, 0.95)
		e.Speed = NumberRange.new(3, 8)
		e.SpreadAngle = Vector2.new(55, 55)
		e.Acceleration = Vector3.new(0, -4, 0)
		e.Drag = 2
		e.Size = seq({ { 0, 0.8 }, { 0.5, 1.9 }, { 1, 2.8 } })
		e.Transparency = seq({ { 0, 0.35 }, { 0.6, 0.6 }, { 1, 1 } })
		e.LightEmission = 0
		e.LightInfluence = 0.6
	elseif kind == "spark" then
		e.Lifetime = NumberRange.new(0.4, 0.85)
		e.Speed = NumberRange.new(10, 22)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, -34, 0)
		e.Size = seq({ { 0, 0.7 }, { 1, 0 } })
		e.Transparency = seq({ { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } })
		e.LightEmission = 1
		e.LightInfluence = 0
	elseif kind == "glitter" then
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(3, 9)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, 3, 0)
		e.Drag = 1.5
		e.Size = seq({ { 0, 0.6 }, { 0.5, 0.8 }, { 1, 0 } })
		e.Transparency = seq({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } })
		e.LightEmission = 1
		e.LightInfluence = 0
	else -- firework
		e.Lifetime = NumberRange.new(1, 1.6)
		e.Speed = NumberRange.new(22, 42)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, -16, 0)
		e.Drag = 1.6
		e.Size = seq({ { 0, 1.5 }, { 0.7, 1 }, { 1, 0 } })
		e.Transparency = seq({ { 0, 0 }, { 0.8, 0.1 }, { 1, 1 } })
		e.LightEmission = 1
		e.LightInfluence = 0
	end
end

local function makeSlot(kind: string): Slot
	local part = Instance.new("Part")
	part.Name = "Emitter_" .. kind
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = folder
	local emitter = Instance.new("ParticleEmitter")
	configure(kind, emitter)
	emitter.Parent = part
	return { part = part, emitter = emitter }
end

local function emit(kind: EmitterKind, pos: Vector3, c1: Color3, count: number, c2: Color3?)
	local pool = emitterPools[kind]
	local slot: Slot
	if #pool < POOL_SIZE[kind] then
		slot = makeSlot(kind)
		table.insert(pool, slot)
	else
		local at = emitterCursor[kind] % #pool + 1
		emitterCursor[kind] = at
		slot = pool[at]
	end
	slot.part.CFrame = CFrame.new(pos)
	slot.emitter.Color = ColorSequence.new(c1, c2 or c1)
	slot.emitter:Emit(math.clamp(math.floor(count), 1, 120))
end

-- ===== puff =====

function Vfx.puff(worldPos: Vector3, hexColor: string, amount: number?)
	emit("puff", worldPos, color3(hexColor), amount or 6)
end

-- ===== float text =====

type Style = { color: string, size: number, dur: number, rise: number }
local STYLES: { [string]: Style } = {
	coin = { color = "#FFD23F", size = 30, dur = 1.15, rise = 5 },
	ash = { color = "#EDE8E0", size = 24, dur = 0.8, rise = 3.5 },
	good = { color = "#6BCB77", size = 26, dur = 1.0, rise = 4 },
	bad = { color = "#FF5A36", size = 30, dur = 1.1, rise = 4 },
	find = { color = "#C79BFF", size = 32, dur = 1.5, rise = 5.5 },
	info = { color = "#FFFFFF", size = 26, dur = 1.0, rise = 4 },
}

type Floater = {
	part: Part,
	label: TextLabel,
	stroke: UIStroke,
	scale: UIScale,
	active: boolean,
	t: number,
	dur: number,
	rise: number,
	base: Vector3,
}

local FLOATERS = 24
local floaters: { Floater } = {}
local floaterCursor = 0

local function makeFloater(): Floater
	local part = Instance.new("Part")
	part.Name = "FloatText"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 64)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 170
	gui.LightInfluence = 0
	gui.Adornee = part
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 30
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = ""
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(40, 24, 24)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label

	local scale = Instance.new("UIScale")
	scale.Parent = label

	return {
		part = part,
		label = label,
		stroke = stroke,
		scale = scale,
		active = false,
		t = 0,
		dur = 1,
		rise = 4,
		base = Vector3.zero,
	}
end

function Vfx.floatText(worldPos: Vector3, text: string, kind: string?)
	if not finite(worldPos.X) or not finite(worldPos.Y) or not finite(worldPos.Z) then
		return
	end
	local f: Floater
	if #floaters < FLOATERS then
		f = makeFloater()
		table.insert(floaters, f)
	else
		floaterCursor = floaterCursor % #floaters + 1
		f = floaters[floaterCursor]
	end
	local style = STYLES[kind or "info"] or STYLES.info
	f.active = true
	f.t = 0
	f.dur = style.dur
	f.rise = style.rise
	f.base = worldPos
	f.label.Text = tostring(text)
	f.label.TextSize = style.size
	f.label.TextColor3 = color3(style.color)
	f.label.TextTransparency = 0
	f.stroke.Transparency = 0
	f.scale.Scale = 0.6
	f.part.CFrame = CFrame.new(worldPos)
	f.part.Parent = folder
end

local function stepFloaters(dt: number)
	for _, f in floaters do
		if f.active then
			f.t += dt
			local k = f.t / f.dur
			if k >= 1 then
				f.active = false
				f.part.Parent = nil
			else
				local rise = f.rise * (1 - (1 - k) * (1 - k))
				f.part.CFrame = CFrame.new(f.base + Vector3.new(0, rise, 0))
				local fade = math.clamp((k - 0.6) / 0.4, 0, 1)
				f.label.TextTransparency = fade
				f.stroke.Transparency = fade
				-- pop in: 0.6 -> 1.2 over the first 12%, settle to 1
				if k < 0.12 then
					f.scale.Scale = 0.6 + (k / 0.12) * 0.6
				elseif k < 0.25 then
					f.scale.Scale = 1.2 - ((k - 0.12) / 0.13) * 0.2
				else
					f.scale.Scale = 1
				end
			end
		end
	end
end

-- ===== coin burst (screen space) =====

type Coin = {
	frame: Frame,
	delay: number,
	t: number,
	dur: number,
	sx: number,
	sy: number,
	cx: number,
	cy: number,
	ex: number,
	ey: number,
}

local coinGui: ScreenGui? = nil
local coins: { Coin } = {}
local lastCoinSound = 0
local hudModule: any = nil
local hudTries = 0

local function ensureCoinGui(): ScreenGui?
	if coinGui ~= nil and coinGui.Parent ~= nil then
		return coinGui
	end
	local pg = playerGui()
	if pg == nil then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "VSFxCoins"
	gui.DisplayOrder = 45
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = pg
	coinGui = gui
	return gui
end

-- Pixel position of the coin counter, from the HUD when it exists.
local function coinTarget(size: Vector2): Vector2
	if hudModule == nil and hudTries < 3 then
		hudTries += 1
		hudModule = softRequire(clientRoot, "Hud", "Hud")
	end
	if hudModule ~= nil and type(hudModule.coinTargetPosition) == "function" then
		local ok, pos = pcall(hudModule.coinTargetPosition)
		if ok and typeof(pos) == "UDim2" then
			return Vector2.new(
				pos.X.Scale * size.X + pos.X.Offset,
				pos.Y.Scale * size.Y + pos.Y.Offset
			)
		end
	end
	return Vector2.new(size.X * 0.08, size.Y * 0.08)
end

function Vfx.coinBurst(count: number)
	if not finite(count) then
		return
	end
	local gui = ensureCoinGui()
	if gui == nil then
		return
	end
	local n = math.clamp(math.floor(count), 1, 24)
	local cam = workspace.CurrentCamera
	local size = gui.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		size = if cam ~= nil then cam.ViewportSize else Vector2.new(800, 400)
	end
	local target = coinTarget(size)
	local px = math.clamp(size.Y / 720, 0.8, 1.5) * 26
	for k = 1, n do
		local frame = Instance.new("Frame")
		frame.Name = "Coin"
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = UDim2.fromOffset(px, px)
		frame.BackgroundColor3 = Color3.fromRGB(255, 210, 63)
		frame.BorderSizePixel = 0
		frame.Visible = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = Color3.fromRGB(184, 120, 20)
		stroke.Parent = frame
		local shine = Instance.new("Frame")
		shine.AnchorPoint = Vector2.new(0.5, 0.5)
		shine.Position = UDim2.fromScale(0.42, 0.4)
		shine.Size = UDim2.fromScale(0.34, 0.34)
		shine.BackgroundColor3 = Color3.fromRGB(255, 244, 190)
		shine.BorderSizePixel = 0
		local shineCorner = Instance.new("UICorner")
		shineCorner.CornerRadius = UDim.new(0.5, 0)
		shineCorner.Parent = shine
		shine.Parent = frame
		frame.Parent = gui

		local angle = math.random() * math.pi * 2
		local spread = size.Y * (0.06 + math.random() * 0.1)
		local sx = size.X * 0.5 + math.cos(angle) * spread
		local sy = size.Y * 0.5 + math.sin(angle) * spread
		local mx, my = (sx + target.X) * 0.5, (sy + target.Y) * 0.5
		local bend = (math.random() * 2 - 1) * size.Y * 0.25
		table.insert(coins, {
			frame = frame,
			delay = (k - 1) * 0.03,
			t = 0,
			dur = 0.6 + math.random() * 0.25,
			sx = sx,
			sy = sy,
			cx = mx + bend,
			cy = my - math.abs(bend) * 0.5,
			ex = target.X,
			ey = target.Y,
		})
	end
end

local function stepCoins(dt: number)
	local i = #coins
	while i >= 1 do
		local c = coins[i]
		if c.delay > 0 then
			c.delay -= dt
		else
			c.frame.Visible = true
			c.t += dt
			local k = math.min(c.t / c.dur, 1)
			local e = k * k * (3 - 2 * k)
			local a = 1 - e
			local x = a * a * c.sx + 2 * a * e * c.cx + e * e * c.ex
			local y = a * a * c.sy + 2 * a * e * c.cy + e * e * c.ey
			c.frame.Position = UDim2.fromOffset(x, y)
			c.frame.Rotation = k * 360
			if k >= 1 then
				c.frame:Destroy()
				table.remove(coins, i)
				local now = os.clock()
				if now - lastCoinSound > 0.07 then
					lastCoinSound = now
					sfx("coin", 0.35)
				end
			end
		end
		i -= 1
	end
end

-- ===== camera =====

function Vfx.shake(strength: number, duration: number)
	if CameraFx ~= nil then
		CameraFx.shake(strength, duration)
	end
end

-- ===== screen tint =====

local tintFrame: Frame? = nil

local function ensureTint(): Frame?
	if tintFrame ~= nil and tintFrame.Parent ~= nil then
		return tintFrame
	end
	local pg = playerGui()
	if pg == nil then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "VSFxTint"
	gui.DisplayOrder = 50
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = pg
	local frame = Instance.new("Frame")
	frame.Name = "Tint"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.Parent = gui
	tintFrame = frame
	return frame
end

local tintToken = 0

function Vfx.screenTint(colorHex: string, alpha: number, seconds: number)
	if not finite(alpha) or not finite(seconds) then
		return
	end
	local frame = ensureTint()
	if frame == nil then
		return
	end
	tintToken += 1
	local mine = tintToken
	local total = math.clamp(seconds, 0.1, 10)
	local fadeIn = math.min(0.2, total * 0.25)
	frame.BackgroundColor3 = color3(colorHex)
	local target = 1 - math.clamp(alpha, 0, 1)
	if frame.BackgroundTransparency < target then
		frame.BackgroundTransparency = target -- never start fainter than where we are going
	end
	local tin = TweenService:Create(
		frame,
		TweenInfo.new(fadeIn, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = target }
	)
	tin.Completed:Once(function()
		if mine ~= tintToken then
			return
		end
		TweenService:Create(
			frame,
			TweenInfo.new(total - fadeIn, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		):Play()
	end)
	tin:Play()
end

-- ===== fireworks =====

local FIREWORK_COLORS =
	{ "#FF5A36", "#FFD23F", "#6BCB77", "#4FB3E8", "#9B5DE5", "#FF7AC8", "#FFFFFF" }
local activeRockets = 0
local MAX_ROCKETS = 24

local function launchRocket(base: Vector3)
	if activeRockets >= MAX_ROCKETS then
		return
	end
	activeRockets += 1
	local hexA = FIREWORK_COLORS[math.random(#FIREWORK_COLORS)]
	local hexB = FIREWORK_COLORS[math.random(#FIREWORK_COLORS)]
	local rocket = Instance.new("Part")
	rocket.Name = "Rocket"
	rocket.Shape = Enum.PartType.Ball
	rocket.Material = Enum.Material.Neon
	rocket.Color = color3(hexA)
	rocket.Size = Vector3.new(1.1, 1.1, 1.1)
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.CanQuery = false
	rocket.CanTouch = false
	rocket.CastShadow = false
	rocket.CFrame = CFrame.new(base + Vector3.new(0, 2, 0))
	local trail = Instance.new("ParticleEmitter")
	trail.Rate = 50
	trail.Lifetime = NumberRange.new(0.3, 0.5)
	trail.Speed = NumberRange.new(0, 2)
	trail.SpreadAngle = Vector2.new(30, 30)
	trail.Size = seq({ { 0, 0.8 }, { 1, 0 } })
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(color3(hexA), color3(hexB))
	trail.Parent = rocket
	rocket.Parent = folder
	local top = base + Vector3.new(0, 30 + math.random() * 16, 0)
	local tween = TweenService:Create(
		rocket,
		TweenInfo.new(0.5 + math.random() * 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(top) }
	)
	tween.Completed:Once(function()
		activeRockets -= 1
		rocket:Destroy()
		emit("firework", top, color3(hexA), 48, color3(hexB))
		emit("glitter", top, Color3.new(1, 1, 1), 14)
	end)
	tween:Play()
end

function Vfx.fireworks(worldPos: Vector3, count: number?)
	if not finite(worldPos.X) or not finite(worldPos.Y) or not finite(worldPos.Z) then
		return
	end
	local n = math.clamp(math.floor(count or 4), 1, 12)
	sfx("party")
	for k = 1, n do
		task.delay((k - 1) * 0.18 + math.random() * 0.1, function()
			launchRocket(
				worldPos
					+ Vector3.new((math.random() * 2 - 1) * 22, 0, (math.random() * 2 - 1) * 22)
			)
		end)
	end
end

-- ===== lava =====

type Telegraph = {
	outer: Part,
	inner: Part,
	x: number,
	z: number,
	y: number,
	radius: number,
	t0: number,
	landsAt: number,
}

local MAX_TELEGRAPHS = 60
local telegraphs: { [number]: Telegraph } = {}
local telegraphCount = 0
local landedAt: { [number]: number } = {}

local function flatDisc(name: string, hex: string, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	p.Color = color3(hex)
	p.Transparency = transparency
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function placeDisc(
	p: Part,
	x: number,
	y: number,
	z: number,
	diameter: number,
	thickness: number
)
	p.Size = Vector3.new(thickness, diameter, diameter)
	-- a Cylinder's axis is its X axis: roll it 90 degrees so it lies flat
	p.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90))
end

-- Height of the tallest ash slab under a disc, so the disc is not buried in the ash.
local function discHeight(x: number, z: number, radius: number): number
	local top = 0
	if AshRenderer ~= nil then
		for _, i in Layout.cellsInRadius(x, z, radius) do
			top = math.max(top, CullLogic.slabHeight(AshRenderer.levelAt(i)))
		end
	end
	return GROUND_Y + math.min(top, 3) + 0.12
end

function Vfx.lavaImpact(x: number, z: number, radius: number)
	if not finite(x) or not finite(z) or not finite(radius) then
		return
	end
	local r = math.clamp(radius, 1, 40)
	local y = discHeight(x, z, r)
	local ring = flatDisc("LavaSplash", "#FF8A1F", 0.15)
	placeDisc(ring, x, y, z, r, 0.4)
	ring.Parent = folder
	local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(ring, info, {
		Size = Vector3.new(0.4, r * 2.3, r * 2.3),
		Transparency = 1,
	})
	tween.Completed:Once(function()
		ring:Destroy()
	end)
	tween:Play()

	local centre = Vector3.new(x, y + 0.5, z)
	emit("puff", centre, color3("#4A3A38"), 26)
	emit("spark", centre, color3("#FFB020"), 36, color3("#FF3B1F"))

	local d = distFlat(x, z)
	if d < 120 then
		local near = 1 - d / 120
		Vfx.shake(0.15 + 0.7 * near, 0.45)
		sfx("bomb", 0.3 + 0.5 * near)
	end
end

function Vfx.lavaTelegraph(bomb: Bomb)
	if type(bomb) ~= "table" then
		return
	end
	local id, x, z, radius, landsAt = bomb.id, bomb.x, bomb.z, bomb.radius, bomb.landsAt
	if not (finite(id) and finite(x) and finite(z) and finite(radius) and finite(landsAt)) then
		return
	end
	if telegraphs[id] ~= nil or telegraphCount >= MAX_TELEGRAPHS then
		return
	end
	local was = landedAt[id]
	if was ~= nil and os.clock() - was < 10 then
		return -- a repeat of a bomb that already landed
	end
	local now = serverNow()
	if landsAt < now - 0.3 or landsAt > now + 20 then
		return
	end
	local r = math.clamp(radius, 1, 40)
	local y = discHeight(x, z, r)
	local outer = flatDisc("LavaTelegraph", "#FF3B1F", 0.55)
	placeDisc(outer, x, y, z, r * 2, 0.25)
	outer.Parent = folder
	local inner = flatDisc("LavaFill", "#FFB020", 0.35)
	placeDisc(inner, x, y + 0.06, z, 0.5, 0.25)
	inner.Parent = folder
	telegraphs[id] = {
		outer = outer,
		inner = inner,
		x = x,
		z = z,
		y = y,
		radius = r,
		t0 = now,
		landsAt = landsAt,
	}
	telegraphCount += 1
end

local function stepTelegraphs()
	if telegraphCount == 0 then
		return
	end
	local now = serverNow()
	for id, t in telegraphs do
		if now >= t.landsAt then
			telegraphs[id] = nil
			telegraphCount -= 1
			t.outer:Destroy()
			t.inner:Destroy()
			landedAt[id] = os.clock()
			Vfx.lavaImpact(t.x, t.z, t.radius)
		else
			local total = math.max(t.landsAt - t.t0, 0.2)
			local progress = math.clamp((now - t.t0) / total, 0, 1)
			placeDisc(t.inner, t.x, t.y + 0.06, t.z, math.max(0.5, t.radius * 2 * progress), 0.25)
			local pulse = math.sin(now * (8 + 14 * progress))
			t.outer.Transparency = math.clamp(0.6 - 0.25 * progress + 0.12 * pulse, 0.1, 0.9)
			t.inner.Transparency = math.clamp(0.4 - 0.15 * progress - 0.08 * pulse, 0.05, 0.9)
		end
	end
	-- forget old landings
	if next(landedAt) ~= nil then
		local clock = os.clock()
		for id, at in landedAt do
			if clock - at > 12 then
				landedAt[id] = nil
			end
		end
	end
end

-- ===== geyser gems =====

type Gem = { ball: Part, halo: Part, x: number, z: number, y: number, phase: number, born: number }

local GEM_COLORS: { [string]: string } = {
	common = "#BFE6FF", -- white-blue
	uncommon = "#6BCB77", -- green
	rare = "#B070FF", -- purple
	legendary = "#FFD23F", -- gold
}
local GEM_SCALE: { [string]: number } = { common = 1, uncommon = 1.1, rare = 1.25, legendary = 1.5 }
local GEM_TTL = 70
local MAX_GEMS = 60
local PICKUP_LOOK = 4
local gems: { [number]: Gem } = {}
local gemCount = 0

local function removeGem(id: number, popped: boolean)
	local g = gems[id]
	if g == nil then
		return
	end
	gems[id] = nil
	gemCount -= 1
	if popped then
		emit("glitter", Vector3.new(g.x, g.y, g.z), color3("#FFFFFF"), 14, color3("#7FE7FF"))
	end
	g.ball:Destroy()
	g.halo:Destroy()
end

local function clearGems()
	for id in gems do
		removeGem(id, false)
	end
end

local function addGem(id: number, x: number, z: number, rarity: string)
	if gems[id] ~= nil or gemCount >= MAX_GEMS then
		return
	end
	local hex = GEM_COLORS[rarity] or GEM_COLORS.common
	local scale = GEM_SCALE[rarity] or 1
	local ball = Instance.new("Part")
	ball.Name = "Gem"
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = color3(hex)
	ball.Size = Vector3.new(1.6, 1.6, 1.6) * scale
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	local halo = Instance.new("Part")
	halo.Name = "GemHalo"
	halo.Shape = Enum.PartType.Ball
	halo.Material = Enum.Material.Neon
	halo.Color = color3(hex)
	halo.Transparency = 0.72
	halo.Size = Vector3.new(3.4, 3.4, 3.4) * scale
	halo.Anchored = true
	halo.CanCollide = false
	halo.CanQuery = false
	halo.CanTouch = false
	halo.CastShadow = false
	local y = GROUND_Y + 3
	ball.CFrame = CFrame.new(x, y, z)
	halo.CFrame = ball.CFrame
	ball.Parent = folder
	halo.Parent = folder
	gems[id] =
		{ ball = ball, halo = halo, x = x, z = z, y = y, phase = id * 1.7, born = os.clock() }
	gemCount += 1
	emit("glitter", Vector3.new(x, y, z), color3("#FFFFFF"), 10, color3(hex))
end

local function stepGems()
	if gemCount == 0 then
		return
	end
	local now = os.clock()
	local mine = myRoot()
	for id, g in gems do
		if now - g.born > GEM_TTL then
			removeGem(id, false)
		else
			local bob = math.sin(now * 3 + g.phase) * 0.5
			local cf = CFrame.new(g.x, g.y + bob, g.z) * CFrame.Angles(0, now * 2 + g.phase, 0)
			g.ball.CFrame = cf
			g.halo.CFrame = cf
			if mine ~= nil then
				local dx, dz = mine.Position.X - g.x, mine.Position.Z - g.z
				if dx * dx + dz * dz < PICKUP_LOOK * PICKUP_LOOK then
					-- a guess for instant feedback; the server decides who really got the gem
					removeGem(id, true)
					sfx("coin", 0.5)
					haptic(0.3)
				end
			end
		end
	end
end

-- ===== one frame loop for all of the above =====

RunService.RenderStepped:Connect(function(dt: number)
	stepFloaters(dt)
	stepCoins(dt)
	stepTelegraphs()
	stepGems()
end)

-- ===== remote hooks =====

local rarityColor: { [string]: string } = {
	common = "#FFFFFF",
	uncommon = "#6BCB77",
	rare = "#4FB3E8",
	legendary = "#FFD23F",
}

local lastSweepFx: { [number]: number } = {}

-- Others' swings: a puff in front of them (not for my own: Controls already did that).
Net.on("SweepFx", function(info: any)
	if type(info) ~= "table" then
		return
	end
	local userId, x, z, dx, dz = info.userId, info.x, info.z, info.dx, info.dz
	if not (finite(userId) and finite(x) and finite(z) and finite(dx) and finite(dz)) then
		return
	end
	if userId == LocalPlayer.UserId then
		return
	end
	if distFlat(x, z) > 150 then
		return
	end
	local now = os.clock()
	if now - (lastSweepFx[userId] or -1) < 0.12 then
		return
	end
	lastSweepFx[userId] = now
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-3 then
		dx, dz, len = 0, -1, 1
	end
	local tool = if type(info.tool) == "string" then Tools.byId[info.tool] else nil
	local reach = if tool ~= nil then tool.reach else 7
	local ahead = math.min(reach * 0.6, 8)
	local px, pz = x + dx / len * ahead, z + dz / len * ahead
	local hex = ashHexAt(px, pz)
	if tool ~= nil then
		hex = CullLogic.mixHex(hex, tool.color, 0.3)
	end
	Vfx.puff(Vector3.new(px, GROUND_Y + 0.6, pz), hex, 4)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastSweepFx[player.UserId] = nil
end)

local function nearestSellPad(from: Vector3): Vector3?
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
	return best
end

Net.on("Sold", function(info: any)
	if type(info) ~= "table" then
		return
	end
	local coinsPaid = if finite(info.coins) then info.coins else 0
	local bonus = if finite(info.bonusCoins) then info.bonusCoins else 0
	local mine = myRoot()
	local at: Vector3
	if mine ~= nil then
		at = nearestSellPad(mine.Position) or mine.Position
	else
		at = Vector3.new(Layout.hubX, GROUND_Y, Layout.hubZ)
	end
	local top = at + Vector3.new(0, 7, 0)
	Vfx.floatText(top, "+" .. StoreLogic.formatNumber(coinsPaid), "coin")
	if bonus > 0 then
		task.delay(0.15, function()
			Vfx.floatText(
				top + Vector3.new(0, -2.2, 0),
				"+" .. StoreLogic.formatNumber(bonus) .. " bonus",
				"good"
			)
		end)
	end
	if info.luckyDouble == true then
		task.delay(0.3, function()
			Vfx.floatText(top + Vector3.new(0, 2.6, 0), "LUCKY x2!", "find")
		end)
	end
	local visual = 4 + math.floor(math.log10(math.max(coinsPaid, 1)) * 3)
	Vfx.coinBurst(math.clamp(visual, 4, 20))
	emit("glitter", top, color3("#FFD23F"), 18)
	sfx("sell")
	task.delay(0.12, function()
		sfx("coin")
	end)
	haptic(0.8)
end)

local burpToken = 0

Net.on("Burp", function(info: any)
	if type(info) ~= "table" then
		return
	end
	burpToken += 1
	local mine = burpToken
	local phase = info.phase
	local kind = info.kind
	local now = serverNow()
	local untilAt = if finite(info.endsAt) then info.endsAt else now + 6
	local left = math.clamp(untilAt - now, 1, 30)

	if phase == "rumble" then
		if CameraFx ~= nil then
			CameraFx.setRumble(0.28, left + 1)
		end
		sfx("rumble")
		haptic(0.4)
		task.spawn(function()
			while burpToken == mine and serverNow() < untilAt do
				Vfx.screenTint("#FF4A1C", 0.16, 1.1)
				haptic(0.25)
				task.wait(1.2)
			end
		end)
	elseif phase == "event" then
		if CameraFx ~= nil then
			CameraFx.setRumble(if kind == "pops" then 0.08 else 0, left + 1)
		end
		Vfx.shake(0.8, 0.7)
		haptic(0.9)
		sfx("bomb", 0.5)
		if kind == "ashStorm" then
			Vfx.screenTint("#8A8480", 0.22, 2)
		elseif kind == "golden" then
			Vfx.screenTint("#FFD23F", 0.22, 1.2)
		elseif kind == "geysers" then
			Vfx.screenTint("#4FE3E8", 0.18, 1)
		else
			Vfx.screenTint("#FF3B1F", 0.28, 1)
		end
	else
		if CameraFx ~= nil then
			CameraFx.setRumble(0)
		end
		clearGems()
	end
end)

Net.on("Bombs", function(info: any)
	if type(info) ~= "table" or type(info.bombs) ~= "table" then
		return
	end
	for _, bomb in info.bombs do
		Vfx.lavaTelegraph(bomb)
	end
end)

Net.on("BurpHit", function(info: any)
	if type(info) ~= "table" or not finite(info.userId) then
		return
	end
	local player = Players:GetPlayerByUserId(info.userId)
	if player == nil then
		return
	end
	local hrp = rootOf(player)
	if hrp == nil then
		return
	end
	local pos = hrp.Position
	emit("puff", pos, color3("#6B5A5A"), 22)
	emit("spark", pos, color3("#FFB020"), 18, color3("#FF3B1F"))
	local dropped = if finite(info.dropped) then info.dropped else 0
	if dropped > 0 then
		Vfx.floatText(pos + Vector3.new(0, 5, 0), "-" .. StoreLogic.formatNumber(dropped), "bad")
	end
	if player == LocalPlayer then
		Vfx.shake(1, 0.55)
		Vfx.screenTint("#FF5A36", 0.35, 0.6)
		haptic(1)
		sfx("hit")
	end
end)

Net.on("Party", function(_info: any)
	local hrp = myRoot()
	local at = if hrp ~= nil then hrp.Position else Vector3.new(Layout.hubX, GROUND_Y, Layout.hubZ)
	Vfx.fireworks(at, 6)
	haptic(0.5)
end)

Net.on("FindFound", function(info: any)
	if type(info) ~= "table" then
		return
	end
	local hrp = myRoot()
	if hrp == nil then
		return
	end
	local rarity = if type(info.rarity) == "string" then info.rarity else "common"
	local hex = rarityColor[rarity] or "#FFFFFF"
	local head = hrp.Position + Vector3.new(0, 3, 0)
	local big = rarity == "rare" or rarity == "legendary"
	emit(
		"glitter",
		head,
		color3(hex),
		if rarity == "legendary" then 70 elseif big then 44 else 24,
		color3("#FFFFFF")
	)
	Vfx.floatText(
		head + Vector3.new(0, 3, 0),
		if info.isNew == true then "NEW FIND!" else "Found!",
		"find"
	)
	if finite(info.coins) and info.coins > 0 then
		task.delay(0.3, function()
			Vfx.floatText(
				head + Vector3.new(0, 1, 0),
				"+" .. StoreLogic.formatNumber(info.coins),
				"coin"
			)
		end)
	end
	sfx(if big then "rare" else "find")
	haptic(0.6)
	if rarity == "legendary" then
		Vfx.fireworks(hrp.Position, 2)
	end
end)

Net.on("CoolDownDone", function(_info: any)
	local hrp = myRoot()
	local at = if hrp ~= nil then hrp.Position else Vector3.new(Layout.hubX, GROUND_Y, Layout.hubZ)
	Vfx.fireworks(at, 10)
	Vfx.screenTint("#FFFFFF", 0.5, 1.2)
	Vfx.shake(0.5, 0.6)
	haptic(1)
end)

-- Two shapes: a list of new gems { {x, z, id, rarity}, ... } and { removed = id } when one was taken
-- or expired. A removed marker inside a list is accepted too.
local function handleGemEntry(entry: any)
	if type(entry) ~= "table" then
		return
	end
	if finite(entry.removed) then
		removeGem(entry.removed, true)
	elseif finite(entry.id) and finite(entry.x) and finite(entry.z) then
		local rarity = if type(entry.rarity) == "string" then entry.rarity else "common"
		addGem(entry.id, entry.x, entry.z, rarity)
	end
end

Net.on("GeyserGems", function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.removed ~= nil then
		handleGemEntry(payload)
		return
	end
	for _, entry in payload do
		handleGemEntry(entry)
	end
end)

-- Cleared ash cells glitter a little (throttled; only near me).
if AshRenderer ~= nil and AshRenderer.cleared ~= nil then
	local lastSparkle = 0
	AshRenderer.cleared:connect(function(x: number, z: number, zone: number)
		local now = os.clock()
		if now - lastSparkle < 0.05 or distFlat(x, z) > 80 then
			return
		end
		lastSparkle = now
		local z1 = Zones.byId[zone]
		local r, g, b = CullLogic.shade(if z1 ~= nil then z1.ground else "#F2D9A0", 0.3)
		emit("glitter", Vector3.new(x, GROUND_Y + 0.8, z), Color3.fromRGB(r, g, b), 3)
	end)
end

return Vfx
