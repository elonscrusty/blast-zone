--!strict
-- Draws the fight effects in the "Sticker Punch" look: navy outlines, gold and white stars, confetti,
-- comic words, rings on the ground. Cosmetic only: nothing here decides a hit, and nothing here
-- is ever a reason to wait for the server.
--
-- How it stays cheap:
--   * Everything comes from a pool built once at start (`Fx.start`). Nothing is created during a fight.
--   * Particle bursts are counted against `Config.Effects.caps.particles`; when the arena is busy a
--     burst gets fewer particles (or none) instead of making the frame rate worse.
--   * Numbers, words and rings use pools the size of their cap. When all are in use the oldest is reused.
--   * One RenderStepped connection moves all of it.
--   * Effects are small and short, and nothing sits on top of a fighter for long, so opponents stay visible.
-- Outlines on particles are not possible without art, and we do not invent asset ids, so confetti and
-- clouds use the built-in textures. The outlined parts are the stars, words, rings and tracers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Budget = require("./FxBudget")
local Recipes = require("./EffectRecipes")
local Shake = require("./Shake")
local Settings = require(script.Parent.Parent.Settings.Settings)
local UiLayers = require(script.Parent.Parent.Ui.UiLayers)

local Fx = {}

-- ===== settings of the look =====
local NAVY = Color3.fromHex(Config.Palette.Navy)
local CYAN = Color3.fromHex(Config.Palette.Cyan)
local GOLD = Color3.fromHex(Config.Palette.RewardGold)
local CORAL = Color3.fromHex(Config.Palette.DangerCoral)
local WHITE = Color3.new(1, 1, 1)
local SCORCH = Color3.fromHex("#1B1B20")

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local OFFSTAGE = CFrame.new(0, -300, 0) -- parked here (the engine deletes parts below -500)
local HOLDERS_PER_RECIPE = 3
local STAR_POOL = 8
local TRACER_POOL = 8
local HIGHLIGHT_POOL = 6
local REFERENCE_RADIUS = 4.4 -- the radius the blast recipe's puff sizes were made for
local TRACER_SPEED = 200 -- studs per second, how fast the streak flies (look only)
local TRACER_TAIL = 3.2
local BUSY_FRACTION = 0.7 -- above this share of the particle cap, bursts shrink to half

local caps = Config.Effects.caps
local budget = Budget.new(caps)

-- ===== the world folder and tiny helpers =====
local root: Folder? = nil
local started = false

local function effectsFolder(): Folder
	if root ~= nil and root.Parent ~= nil then
		return root
	end
	local found = Workspace:FindFirstChild(Config.Workspace.EffectsFolder)
	if found ~= nil and found:IsA("Folder") then
		root = found
		return found
	end
	local made = Instance.new("Folder")
	made.Name = Config.Workspace.EffectsFolder
	made.Parent = Workspace
	root = made
	return made
end

local function newPart(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = OFFSTAGE
	p.Parent = effectsFolder()
	return p
end

local function hexColor(hex: string): Color3
	return Color3.fromHex(hex)
end

local function tierHex(tier: string?): string?
	if tier == nil then
		return nil
	end
	local t = Config.Containers.tiers[tier]
	return if t ~= nil then t.color else nil
end

local function lookAlong(pos: Vector3, dir: Vector3?): CFrame
	local d = dir
	if d == nil or d.Magnitude < 0.01 then
		d = Vector3.yAxis
	end
	local unit = (d :: Vector3).Unit
	local up = if math.abs(unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(pos, pos + unit, up)
end

-- ===== the one animator =====
type Anim = { t0: number, dur: number, update: (k: number) -> (), finish: () -> () }
local anims: { Anim } = {}

local function animate(dur: number, update: (k: number) -> (), finish: () -> ())
	table.insert(
		anims,
		{ t0 = os.clock(), dur = math.max(dur, 0.01), update = update, finish = finish }
	)
end

local function stepAnims()
	local now = os.clock()
	for i = #anims, 1, -1 do
		local a = anims[i]
		local k = (now - a.t0) / a.dur
		if k >= 1 then
			table.remove(anims, i)
			a.finish()
		else
			a.update(k)
		end
	end
end

local function easeOut(k: number): number
	return 1 - (1 - k) ^ 3
end

-- ===== particle holders: one invisible part per recipe slot, with one emitter per group =====
type Holder = { part: Part, emitters: { [number]: ParticleEmitter } }
type HolderPool = { holders: { Holder }, nextIndex: number }
local holderPools: { [string]: HolderPool } = {}

local function makeEmitter(g: Recipes.Particles, parent: Part): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Rate = 0
	e.Texture = if g.kind == "puff" then SMOKE else SPARKLE
	e.Lifetime = NumberRange.new(g.life[1], g.life[2])
	e.Speed = NumberRange.new(g.speed[1], g.speed[2])
	e.SpreadAngle = Vector2.new(g.spread, g.spread)
	e.EmissionDirection = if g.direction == "side" then Enum.NormalId.Right else Enum.NormalId.Front
	e.Acceleration = Vector3.new(0, -g.gravity, 0)
	e.Drag = g.drag or 0
	e.Size = NumberSequence.new(g.size[1], g.size[2])
	local first = hexColor(g.colors[1])
	local last = hexColor(g.colors[#g.colors])
	e.Color = ColorSequence.new(first, last)
	if g.kind == "puff" then
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.6, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.LightEmission = 0
	else
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.75, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.LightEmission = g.light or 0.35
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-240, 240)
	end
	e.LightInfluence = 0
	e.Parent = parent
	return e
end

local function holderPool(name: string, tierColor: string?): HolderPool
	local key = name .. "|" .. (tierColor or "")
	local existing = holderPools[key]
	if existing ~= nil then
		return existing
	end
	local full = Recipes.resolve(name, { tierColor = tierColor })
	local pool: HolderPool = { holders = {}, nextIndex = 0 }
	for i = 1, HOLDERS_PER_RECIPE do
		local part = newPart("Fx_" .. name .. "_" .. i, Vector3.new(0.2, 0.2, 0.2))
		part.Transparency = 1
		local holder: Holder = { part = part, emitters = {} }
		for _, g in full.particles do
			if g.index ~= nil then
				holder.emitters[g.index] = makeEmitter(g, part)
			end
		end
		table.insert(pool.holders, holder)
	end
	holderPools[key] = pool
	return pool
end

-- ===== stars: two squares turned against each other, gold or white with a navy outline =====
type Star = { anchor: Part, gui: BillboardGui, group: CanvasGroup, frames: { Frame }, gen: number }
local stars: { Star } = {}
local starNext = 0

local function makeStar(): Star
	local anchor = newPart("Fx_Star", Vector3.new(0.2, 0.2, 0.2))
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(4, 4)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Enabled = false
	gui.ResetOnSpawn = false
	gui.Adornee = anchor
	gui.Parent = anchor
	local group = Instance.new("CanvasGroup")
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.Parent = gui
	local frames: { Frame } = {}
	for i = 1, 4 do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(0.72, 0.72)
		f.Rotation = if i % 2 == 0 then 45 else 0
		f.BorderSizePixel = 0
		if i <= 2 then
			-- Only the first two squares have an outline. The last two hide the lines where the squares cross.
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 3
			stroke.Color = NAVY
			stroke.Parent = f
		end
		f.Parent = group
		table.insert(frames, f)
	end
	return { anchor = anchor, gui = gui, group = group, frames = frames, gen = 0 }
end

local function playStar(
	s: Recipes.Star,
	pos: Vector3,
	dir: Vector3?,
	radius: number?,
	alphaScale: number
)
	starNext = starNext % #stars + 1
	local star = stars[starNext]
	star.gen += 1
	local gen = star.gen
	local k = if s.radiusScale == true and radius ~= nil then radius else 1
	local from, to = s.size[1] * k, s.size[2] * k
	local at = pos
	if s.along ~= nil and dir ~= nil and dir.Magnitude > 0.01 then
		at = pos + dir.Unit * s.along
	end
	star.anchor.CFrame = CFrame.new(at)
	local fill = hexColor(s.fill)
	for _, f in star.frames do
		f.BackgroundColor3 = fill
	end
	star.gui.Size = UDim2.fromScale(from, from)
	star.gui.Enabled = true
	local spin = s.spin or 0
	local spinStart = math.random() * 360
	animate(s.life, function(t)
		if star.gen ~= gen then
			return
		end
		local size = from + (to - from) * easeOut(t)
		star.gui.Size = UDim2.fromScale(size, size)
		star.group.Rotation = spinStart + spin * t * s.life
		star.group.GroupTransparency = 1 - alphaScale * (1 - t * t)
	end, function()
		if star.gen == gen then
			star.gui.Enabled = false
		end
	end)
end

-- ===== words and numbers: outlined text that pops up and drifts =====
type Label = { anchor: Part, gui: BillboardGui, text: TextLabel, stroke: UIStroke, gen: number }

local function makeLabel(name: string): Label
	local anchor = newPart(name, Vector3.new(0.2, 0.2, 0.2))
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(6, 2.5)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.ResetOnSpawn = false
	gui.Adornee = anchor
	gui.Parent = anchor
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.LuckiestGuy
	text.TextScaled = true
	text.TextColor3 = WHITE
	text.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = NAVY
	stroke.Thickness = 4
	stroke.Parent = text
	return { anchor = anchor, gui = gui, text = text, stroke = stroke, gen = 0 }
end

local numbers: { Label } = {}
local numberNext = 0
local banners: { Label } = {}
local bannerNext = 0

local function playLabel(
	label: Label,
	text: string,
	color: Color3,
	pos: Vector3,
	width: number,
	life: number,
	rise: number,
	drift: number,
	tilt: number,
	bouncy: boolean
)
	label.gen += 1
	local gen = label.gen
	label.text.Text = text
	label.text.TextColor3 = color
	label.text.Rotation = tilt
	label.gui.Enabled = true
	local height = width * 0.42
	label.gui.Size = UDim2.fromScale(width, height)
	animate(life, function(k)
		if label.gen ~= gen then
			return
		end
		local pop = if bouncy
			then 1 + 0.5 * math.max(0, 1 - k * 6) * math.cos(k * 40)
			else 1 + 0.25 * math.max(0, 1 - k * 8)
		label.anchor.CFrame =
			CFrame.new(pos + Vector3.new(drift * easeOut(k), rise * easeOut(k), 0))
		label.gui.Size = UDim2.fromScale(width * pop, height * pop)
		local fade = if k < 0.7 then 0 else (k - 0.7) / 0.3
		label.text.TextTransparency = fade
		label.stroke.Transparency = fade
	end, function()
		if label.gen == gen then
			label.gui.Enabled = false
		end
	end)
end

-- Kinds: "hit" (white), "big" (gold, larger), "kill" (gold), "mine" (coral, damage you took), "xp" (gold, smaller).
function Fx.number(pos: Vector3, text: string, kind: string)
	if not started then
		return
	end
	numberNext = numberNext % #numbers + 1
	local label = numbers[numberNext]
	local n = Config.Effects.numbers
	local width = 4.4
	local color = WHITE
	if kind == "big" then
		width = 6.4
		color = GOLD
	elseif kind == "kill" then
		width = 5.6
		color = GOLD
	elseif kind == "mine" then
		color = CORAL
	elseif kind == "xp" then
		width = 3.8
		color = GOLD
	end
	local drift = (math.random() - 0.5) * 2 * n.spreadStuds
	local tilt = (math.random() - 0.5) * 18
	playLabel(
		label,
		text,
		color,
		pos + Vector3.new(0, math.random() * 0.8, 0),
		width,
		n.seconds,
		n.riseStuds,
		drift,
		tilt,
		true
	)
end

local function playWord(w: Recipes.Word, pos: Vector3)
	bannerNext = bannerNext % #banners + 1
	local label = banners[bannerNext]
	local text = w.texts[math.random(1, #w.texts)]
	playLabel(
		label,
		text,
		hexColor(w.color),
		pos,
		w.size,
		w.life,
		w.rise or 1,
		0,
		(math.random() - 0.5) * 20,
		true
	)
end

-- ===== rings flat on the ground =====
type Ring = {
	part: Part,
	group: CanvasGroup,
	fill: Frame,
	outer: Frame,
	outerStroke: UIStroke,
	inner: Frame,
	innerStroke: UIStroke,
	gen: number,
}
local rings: { Ring } = {}
local ringNext = 0
local INSET = UDim2.new(1, -48, 1, -48)

local function makeRing(): Ring
	local part = newPart("Fx_Ring", Vector3.new(4, 0.1, 4))
	part.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(256, 256)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Parent = part
	local group = Instance.new("CanvasGroup")
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.Parent = gui

	local function circle(name: string): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = INSET
		f.BorderSizePixel = 0
		f.BackgroundTransparency = 1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		f.Parent = group
		return f
	end
	local fill = circle("Fill")
	local outer = circle("Outer")
	local outerStroke = Instance.new("UIStroke")
	outerStroke.Parent = outer
	local inner = circle("Inner")
	local innerStroke = Instance.new("UIStroke")
	innerStroke.Parent = inner
	return {
		part = part,
		group = group,
		fill = fill,
		outer = outer,
		outerStroke = outerStroke,
		inner = inner,
		innerStroke = innerStroke,
		gen = 0,
	}
end

type RingStyle = {
	outer: number,
	inner: number,
	innerColor: Color3,
	fill: Color3?,
	fillTransparency: number,
}
local ringStyles: { [string]: RingStyle } = {
	sticker = { outer = 22, inner = 10, innerColor = WHITE, fill = nil, fillTransparency = 1 },
	warn = { outer = 22, inner = 10, innerColor = GOLD, fill = CORAL, fillTransparency = 0.72 },
	shrink = { outer = 0, inner = 8, innerColor = WHITE, fill = nil, fillTransparency = 1 },
	scorch = { outer = 0, inner = 0, innerColor = WHITE, fill = SCORCH, fillTransparency = 0.45 },
}

local function takeRing(style: string, color: Color3?): Ring
	ringNext = ringNext % #rings + 1
	local ring = rings[ringNext]
	ring.gen += 1
	local s = ringStyles[style]
	ring.outerStroke.Thickness = s.outer
	ring.outerStroke.Color = NAVY
	ring.innerStroke.Thickness = s.inner
	ring.innerStroke.Color = color or s.innerColor
	if s.fill ~= nil then
		ring.fill.BackgroundColor3 = s.fill
	end
	ring.fill.BackgroundTransparency = s.fillTransparency
	ring.group.GroupTransparency = 0
	return ring
end

local function placeRing(ring: Ring, center: Vector3, diameter: number)
	ring.part.Size = Vector3.new(diameter, 0.1, diameter)
	ring.part.CFrame = CFrame.new(center.X, center.Y + 0.15, center.Z)
end

local function hideRing(ring: Ring)
	ring.part.CFrame = OFFSTAGE
end

-- A ring that grows from d0 to d1 and fades.
local function playRing(r: Recipes.RingPlan, center: Vector3, radius: number?)
	local k = if r.radiusScale == true and radius ~= nil then radius * 2 else 1
	local d0, d1 = r.diameter[1] * k, r.diameter[2] * k
	local color = if r.color ~= nil then hexColor(r.color) else nil
	local ring = takeRing(r.style, color)
	local gen = ring.gen
	placeRing(ring, center, d0)
	animate(r.life, function(t)
		if ring.gen ~= gen then
			return
		end
		placeRing(ring, center, d0 + (d1 - d0) * easeOut(t))
		ring.group.GroupTransparency = t * t
	end, function()
		if ring.gen == gen then
			hideRing(ring)
		end
	end)
end

-- ===== tracers and speed streaks: a navy bar with a colored bar inside, and a ball at the head =====
type Tracer = { outer: Part, inner: Part, head: Part, shell: Part, gen: number }
local tracers: { Tracer } = {}
local tracerNext = 0

local function makeTracer(): Tracer
	local outer = newPart("Fx_TracerOuter", Vector3.new(0.9, 0.9, 1))
	outer.Material = Enum.Material.SmoothPlastic
	outer.Color = NAVY
	local inner = newPart("Fx_TracerInner", Vector3.new(0.45, 0.45, 1))
	inner.Material = Enum.Material.Neon
	inner.Color = CYAN
	local head = newPart("Fx_TracerHead", Vector3.new(1, 1, 1))
	head.Shape = Enum.PartType.Ball
	head.Material = Enum.Material.SmoothPlastic
	head.Color = GOLD
	local shell = newPart("Fx_TracerShell", Vector3.new(1.5, 1.5, 1.5))
	shell.Shape = Enum.PartType.Ball
	shell.Material = Enum.Material.SmoothPlastic
	shell.Color = NAVY
	return { outer = outer, inner = inner, head = head, shell = shell, gen = 0 }
end

local function hideTracer(t: Tracer)
	t.outer.CFrame = OFFSTAGE
	t.inner.CFrame = OFFSTAGE
	t.head.CFrame = OFFSTAGE
	t.shell.CFrame = OFFSTAGE
end

local function placeBar(part: Part, from: Vector3, to: Vector3)
	local len = (to - from).Magnitude
	if len < 0.05 then
		part.CFrame = OFFSTAGE
		return
	end
	part.Size = Vector3.new(part.Size.X, part.Size.Y, len)
	part.CFrame = CFrame.lookAt((from + to) / 2, to)
end

-- A bar from a to b. "shot" flies out with a ball at its head; "streak" just fades where it is.
local function playBar(kind: string, a: Vector3, b: Vector3, innerColor: Color3, widthScale: number)
	local want = if kind == "shot" then 4 else 2
	local now = os.clock()
	local dist = (b - a).Magnitude
	if dist < 0.2 then
		return
	end
	local travel = if kind == "shot" then dist / TRACER_SPEED else 0.001
	local life = travel + 0.1
	if Budget.tryTake(budget, "parts", want, now, life) < want then
		return
	end
	tracerNext = tracerNext % #tracers + 1
	local t = tracers[tracerNext]
	t.gen += 1
	local gen = t.gen
	local dir = (b - a).Unit
	t.outer.Size = Vector3.new(0.9 * widthScale, 0.9 * widthScale, 1)
	t.inner.Size = Vector3.new(0.45 * widthScale, 0.45 * widthScale, 1)
	t.inner.Color = innerColor
	local showHead = kind == "shot"
	animate(life, function(k)
		if t.gen ~= gen then
			return
		end
		local time = k * life
		local headD: number = 0
		local tailD: number = 0
		if kind == "shot" then
			headD = math.clamp(time / travel, 0, 1) * dist
			if time <= travel then
				tailD = math.max(0, headD - TRACER_TAIL)
			else
				local tail0 = math.max(0, dist - TRACER_TAIL)
				tailD = tail0 + (dist - tail0) * math.clamp((time - travel) / 0.1, 0, 1)
			end
		else
			headD = dist
			tailD = dist * k
		end
		local from = a + dir * tailD
		local to = a + dir * headD
		placeBar(t.outer, from - dir * 0.1, to + dir * 0.1)
		placeBar(t.inner, from, to)
		if showHead and time < travel then
			t.head.CFrame = CFrame.new(to + Vector3.new(0, 0.25, 0))
			t.shell.CFrame = CFrame.new(to)
		else
			t.head.CFrame = OFFSTAGE
			t.shell.CFrame = OFFSTAGE
		end
	end, function()
		if t.gen == gen then
			hideTracer(t)
		end
	end)
end

-- ===== hit flash on a body =====
local highlights: { Highlight } = {}
local highlightNext = 0

local function makeHighlight(): Highlight
	local h = Instance.new("Highlight")
	h.Name = "Fx_HitFlash"
	h.FillColor = WHITE
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Enabled = false
	h.Parent = effectsFolder()
	return h
end

function Fx.hitFlash(model: Model)
	if not started or model.Parent == nil then
		return
	end
	highlightNext = highlightNext % #highlights + 1
	local h = highlights[highlightNext]
	local start = if Settings.flag("reduceFlashes") then 0.7 else 0.3
	h.Adornee = model
	h.FillTransparency = start
	h.Enabled = true
	local token = os.clock()
	h:SetAttribute("Token", token)
	animate(0.16, function(k)
		if h:GetAttribute("Token") == token then
			h.FillTransparency = start + (1 - start) * k
		end
	end, function()
		if h:GetAttribute("Token") == token then
			h.Enabled = false
			h.Adornee = nil
		end
	end)
end

-- ===== screen flash (skipped for players who turned on Fewer flashes) =====
local flashFrame: Frame? = nil

local function makeFlashGui()
	local localPlayer = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "FxFlash"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = UiLayers.ZoneTint -- under the HUD and controls, takes no taps
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = WHITE
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	flashFrame = frame
end

local function screenFlash(alpha: number)
	local frame = flashFrame
	if frame == nil or alpha <= 0 or Settings.flag("reduceFlashes") then
		return
	end
	local start = 1 - math.clamp(alpha, 0, 1)
	frame.BackgroundTransparency = start
	local token = os.clock()
	frame:SetAttribute("Token", token)
	animate(Config.Effects.flash.seconds, function(k)
		if frame:GetAttribute("Token") == token then
			frame.BackgroundTransparency = start + (1 - start) * k
		end
	end, function()
		if frame:GetAttribute("Token") == token then
			frame.BackgroundTransparency = 1
		end
	end)
end

-- ===== play a recipe =====
export type PlayOpts = {
	tier: string?, -- container tier, colors "@tier" parts
	radius: number?, -- blast radius
	shake: string?, -- "mine" (the camera always shakes) or "world" (shakes less when far away)
	flashScale: number?, -- 0..1, multiplies the recipe's screen flash
}

local function burstScale(now: number): number
	local used = Budget.used(budget, "particles", now)
	return if used > caps.particles * BUSY_FRACTION then 0.5 else 1
end

function Fx.play(name: string, pos: Vector3, dir: Vector3?, opts: PlayOpts?)
	if not started then
		return
	end
	local o: PlayOpts = opts or {}
	local now = os.clock()
	local reduce = Settings.flag("reduceFlashes")
	local tierColor = tierHex(o.tier)
	local recipe = Recipes.resolve(
		name,
		{ reduceFlashes = reduce, tierColor = tierColor, scale = burstScale(now) }
	)

	if #recipe.particles > 0 then
		local pool = holderPool(name, tierColor)
		pool.nextIndex = pool.nextIndex % #pool.holders + 1
		local holder = pool.holders[pool.nextIndex]
		holder.part.CFrame = lookAlong(pos, dir)
		local sizeK = if o.radius ~= nil then o.radius / REFERENCE_RADIUS else 1
		for _, g in recipe.particles do
			local emitter = if g.index ~= nil then holder.emitters[g.index] else nil
			if emitter ~= nil then
				local granted = Budget.tryTake(budget, "particles", g.count, now, g.life[2])
				if granted > 0 then
					if g.radiusScale == true then
						emitter.Size = NumberSequence.new(g.size[1] * sizeK, g.size[2] * sizeK)
					end
					emitter:Emit(granted)
				end
			end
		end
	end

	local alpha = if reduce then 0.5 else 1
	for _, s in recipe.stars do
		playStar(s, pos, dir, o.radius, if s.flashy == true then alpha else 1)
	end
	for _, w in recipe.words do
		playWord(w, pos + Vector3.new(0, 3, 0))
	end
	for _, r in recipe.rings do
		playRing(r, Vector3.new(pos.X, math.max(pos.Y - 1, 0), pos.Z), o.radius)
	end
	if recipe.flash ~= nil and recipe.flash > 0 then
		screenFlash(recipe.flash * (o.flashScale or 1))
	end
	if recipe.shake ~= nil and o.shake ~= nil then
		if o.shake == "world" then
			Shake.addAt(recipe.shake, pos)
		else
			Shake.add(recipe.shake)
		end
	end
end

-- ===== the effects the game asks for =====
local function surfaceNormal(travelDir: Vector3?): Vector3
	if travelDir ~= nil and travelDir.Magnitude > 0.01 then
		return -travelDir.Unit
	end
	return Vector3.yAxis
end

-- A shot leaves the barrel.
function Fx.muzzle(pos: Vector3, dir: Vector3, mine: boolean)
	Fx.play("muzzle", pos, dir, { shake = if mine then "mine" else nil })
end

-- The streak a shot draws from the barrel to where it ended.
function Fx.tracer(from: Vector3, to: Vector3, color: Color3?)
	if not started then
		return
	end
	playBar("shot", from, to, color or CYAN, 1)
end

-- Where a shot ended. kind: "target", "wall", "container" or "none".
function Fx.impact(pos: Vector3, travelDir: Vector3?, kind: string, big: boolean)
	local normal = surfaceNormal(travelDir)
	if kind == "target" then
		Fx.play(if big then "hitBig" else "hit", pos, normal)
	elseif kind == "wall" then
		Fx.play("hitSurface", pos, normal)
	end
end

-- A knockout you can see. `mine` means you landed it: the camera gives a kick.
function Fx.kill(pos: Vector3, mine: boolean)
	Fx.play("kill", pos, nil, { shake = if mine then "mine" else nil })
end

function Fx.containerHit(pos: Vector3, tier: string)
	Fx.play("containerHit", pos, Vector3.yAxis, { tier = tier })
end

function Fx.containerBreak(pos: Vector3, tier: string)
	Fx.play("containerBreak", pos, nil, { tier = tier, shake = "world" })
end

-- An orb is gone. If you took it, show it and the XP you got.
function Fx.orb(pos: Vector3, mine: boolean, xp: number?)
	if mine then
		Fx.play("pickupMine", pos, nil)
		if xp ~= nil then
			Fx.number(pos + Vector3.new(0, 3, 0), "+" .. tostring(xp) .. " XP", "xp")
		end
	else
		Fx.play("orbPop", pos, nil)
	end
end

-- The blast marker: a coral disc with a navy and gold edge, and a white ring that shrinks to zero as it lands.
type Warn = { ring: Ring, shrink: Ring, gen: number }
local warns: { [string]: Warn } = {}

function Fx.warnClear(id: string)
	local w = warns[id]
	if w ~= nil then
		w.ring.gen += 1
		w.shrink.gen += 1
		hideRing(w.ring)
		hideRing(w.shrink)
		warns[id] = nil
	end
end

function Fx.blastWarn(id: string, pos: Vector3, radius: number, seconds: number)
	if not started then
		return
	end
	Fx.warnClear(id)
	local center = Vector3.new(pos.X, math.max(pos.Y - 2.8, 0), pos.Z)
	local diameter = radius * 2
	local ring = takeRing("warn", nil)
	local shrink = takeRing("shrink", nil)
	placeRing(ring, center, diameter)
	placeRing(shrink, center + Vector3.new(0, 0.05, 0), diameter)
	local warn: Warn = { ring = ring, shrink = shrink, gen = ring.gen }
	warns[id] = warn
	local ringGen, shrinkGen = ring.gen, shrink.gen
	animate(math.max(seconds, 0.1), function(k)
		if ring.gen ~= ringGen or shrink.gen ~= shrinkGen then
			return
		end
		local pulse = 0.5 + 0.5 * math.sin(k * k * 30)
		ring.fill.BackgroundTransparency = 0.8 - 0.25 * pulse
		placeRing(shrink, center + Vector3.new(0, 0.05, 0), math.max(0.2, diameter * (1 - k)))
	end, function()
		if warns[id] == warn then
			Fx.warnClear(id)
		end
	end)
end

-- The blast: gold star, clouds, confetti, rings, a scorch mark, camera shake and a flash.
function Fx.blast(pos: Vector3, radius: number)
	if not started then
		return
	end
	local camera = Workspace.CurrentCamera
	local flashScale = 1
	if camera ~= nil then
		local fall = Config.Effects.falloff
		flashScale = math.clamp(
			1 - ((camera.CFrame.Position - pos) * Vector3.new(1, 0, 1)).Magnitude / fall.noneStuds,
			0,
			1
		)
	end
	Fx.play(
		"blast",
		Vector3.new(pos.X, pos.Y + 1, pos.Z),
		nil,
		{ radius = radius, shake = "world", flashScale = flashScale }
	)
	-- The dark mark on the ground fades slowly.
	local ring = takeRing("scorch", nil)
	local gen = ring.gen
	local center = Vector3.new(pos.X, math.max(pos.Y - 2.8, 0), pos.Z)
	placeRing(ring, center, radius * 1.7)
	animate(Config.Effects.scorchSeconds, function(k)
		if ring.gen == gen then
			ring.group.GroupTransparency = k * k
		end
	end, function()
		if ring.gen == gen then
			hideRing(ring)
		end
	end)
end

-- Your slide: a puff at the start, then dust and a white speed streak every few hundredths of a second.
function Fx.slide(character: Model, duration: number, mine: boolean)
	if not started then
		return
	end
	local body = character:FindFirstChild("HumanoidRootPart")
	if body == nil or not body:IsA("BasePart") then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local drop = body.Size.Y / 2 + (if humanoid ~= nil then humanoid.HipHeight else 2)
	local function feet(): Vector3
		return body.Position - Vector3.new(0, drop - 0.3, 0)
	end
	Fx.play("slideStart", feet(), nil, { shake = if mine then "mine" else nil })
	local last = body.Position
	local nextAt = 0
	animate(math.max(duration, 0.05), function()
		local now = os.clock()
		if now < nextAt or body.Parent == nil then
			return
		end
		nextAt = now + 0.06
		local delta = body.Position - last
		last = body.Position
		local flat = Vector3.new(delta.X, 0, delta.Z)
		local back = if flat.Magnitude > 0.01 then -flat.Unit else -body.CFrame.LookVector
		local base = feet()
		Fx.play("slideStep", base + back * 1.1, nil)
		local side = Vector3.new(-back.Z, 0, back.X) * ((math.random() - 0.5) * 2.4)
		local from = base + side + Vector3.new(0, 0.8 + math.random() * 1.8, 0)
		playBar("streak", from, from + back * 3.4, WHITE, 0.6)
	end, function() end)
end

function Fx.clear()
	for _, a in anims do
		a.finish()
	end
	table.clear(anims)
	for _, s in stars do
		s.gen += 1
		s.gui.Enabled = false
	end
	for _, n in numbers do
		n.gen += 1
		n.gui.Enabled = false
	end
	for _, b in banners do
		b.gen += 1
		b.gui.Enabled = false
	end
	for _, r in rings do
		r.gen += 1
		hideRing(r)
	end
	for _, t in tracers do
		t.gen += 1
		hideTracer(t)
	end
	for _, h in highlights do
		h.Enabled = false
		h.Adornee = nil
	end
	table.clear(warns)
	Budget.clear(budget)
	Shake.reset()
	local frame = flashFrame
	if frame ~= nil then
		frame.BackgroundTransparency = 1
	end
end

-- Builds every pool once, so nothing is created in the middle of a fight.
function Fx.start()
	if started then
		return
	end
	started = true
	effectsFolder()
	for _ = 1, STAR_POOL do
		table.insert(stars, makeStar())
	end
	for i = 1, caps.numbers do
		table.insert(numbers, makeLabel("Fx_Number" .. i))
	end
	for i = 1, caps.banners do
		table.insert(banners, makeLabel("Fx_Word" .. i))
	end
	for _ = 1, caps.rings do
		table.insert(rings, makeRing())
	end
	for _ = 1, TRACER_POOL do
		table.insert(tracers, makeTracer())
	end
	for _ = 1, HIGHLIGHT_POOL do
		table.insert(highlights, makeHighlight())
	end
	for _, name in Recipes.names() do
		if name == "containerHit" or name == "containerBreak" then
			for _, tier in Config.Containers.tierOrder do
				holderPool(name, tierHex(tier))
			end
		else
			holderPool(name, nil)
		end
	end
	task.spawn(makeFlashGui)
	RunService.RenderStepped:Connect(stepAnims)
end

return Fx
