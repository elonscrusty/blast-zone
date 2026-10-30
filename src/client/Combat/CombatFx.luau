--!strict
-- What shots and blasts look like. Cosmetic only: nothing here decides a hit. Everything is a short-lived
-- part that cleans itself up, and the number of live effects is capped (Config.Perf).

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local CYAN = Color3.fromHex(Config.Palette.Cyan)
local GOLD = Color3.fromHex(Config.Palette.RewardGold)
local CORAL = Color3.fromHex(Config.Palette.DangerCoral)

local CombatFx = {}

local folder: Folder? = nil
local live = 0
local numbers: { BillboardGui } = {}
local shells: { [string]: BasePart? } = {}
local rings: { [string]: BasePart? } = {}

local function effects(): Folder
	if folder ~= nil and folder.Parent ~= nil then
		return folder
	end
	local found = Workspace:FindFirstChild(Config.Workspace.EffectsFolder)
	if found ~= nil and found:IsA("Folder") then
		folder = found
		return found
	end
	local made = Instance.new("Folder")
	made.Name = Config.Workspace.EffectsFolder
	made.Parent = Workspace
	folder = made
	return made
end

local function newPart(shape: Enum.PartType, color: Color3, size: Vector3, cf: CFrame): BasePart
	local p = Instance.new("Part")
	p.Shape = shape
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = effects()
	return p
end

-- Makes a part fade out over `seconds` then removes it. Returns false (and does nothing) when too many effects are live.
local function fade(p: BasePart, seconds: number, goal: { [string]: any }?)
	live += 1
	local props: { [string]: any } = goal or {}
	props.Transparency = 1
	TweenService
		:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
		:Play()
	Debris:AddItem(p, seconds + 0.05)
	task.delay(seconds + 0.05, function()
		live -= 1
	end)
end

local function atCap(): boolean
	return live >= Config.Perf.maxLiveEffects
end

function CombatFx.tracer(from: Vector3, to: Vector3, weaponId: string)
	local len = (to - from).Magnitude
	if len < 0.2 or atCap() then
		return
	end
	local mortar = weaponId == Config.Weapons.Explosive.id
	local color = if mortar then GOLD else CYAN
	local width = if mortar then 0.4 else 0.14
	local p = newPart(
		Enum.PartType.Block,
		color,
		Vector3.new(width, width, len),
		CFrame.lookAt((from + to) / 2, to)
	)
	fade(p, 0.14, { Size = Vector3.new(width * 0.3, width * 0.3, len) })
end

function CombatFx.muzzleFlash(at: Vector3)
	if atCap() then
		return
	end
	local p = newPart(Enum.PartType.Ball, GOLD, Vector3.new(1.1, 1.1, 1.1), CFrame.new(at))
	fade(p, 0.08, { Size = Vector3.new(1.9, 1.9, 1.9) })
end

-- A small spark where a shot ended.
function CombatFx.impact(at: Vector3, hitKind: string)
	if atCap() then
		return
	end
	local color = if hitKind == "target" then CORAL else GOLD
	local p = newPart(Enum.PartType.Ball, color, Vector3.new(0.5, 0.5, 0.5), CFrame.new(at))
	fade(p, 0.15, { Size = Vector3.new(1.4, 1.4, 1.4) })
end

-- A floating "-10". Capped: the oldest number goes first.
function CombatFx.damageNumber(at: Vector3, amount: number, killed: boolean, mine: boolean)
	while #numbers >= Config.Perf.maxDamageNumbers do
		local old = table.remove(numbers, 1)
		if old ~= nil then
			old:Destroy()
		end
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = at + Vector3.new(0, 3, 0)
	anchor.Parent = effects()

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(if killed then 110 else 80, 36)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = (if killed then "KO " else "") .. "-" .. tostring(math.floor(amount + 0.5))
	label.TextColor3 = if mine then CORAL else (if killed then GOLD else Color3.new(1, 1, 1))
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	table.insert(numbers, gui)

	TweenService
		:Create(anchor, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = anchor.Position + Vector3.new(0, 3, 0),
		})
		:Play()
	TweenService
		:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 })
		:Play()
	Debris:AddItem(anchor, 0.7)
	task.delay(0.7, function()
		local i = table.find(numbers, gui)
		if i ~= nil then
			table.remove(numbers, i)
		end
	end)
end

-- A shell in the air, drawn from its start to where it is expected to land.
function CombatFx.shell(shooterId: string, from: Vector3, to: Vector3, speed: number)
	local old = shells[shooterId]
	if old ~= nil then
		old:Destroy()
	end
	local ball = newPart(Enum.PartType.Ball, GOLD, Vector3.new(1.4, 1.4, 1.4), CFrame.new(from))
	shells[shooterId] = ball
	local seconds = math.max(0.05, (to - from).Magnitude / math.max(speed, 1))
	TweenService:Create(ball, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Position = to })
		:Play()
	Debris:AddItem(ball, seconds + 1.5) -- a burst on a body ends it sooner (see burst)
end

-- The warning ring: where the blast will be and how big it is.
function CombatFx.warnRing(shooterId: string, at: Vector3, radius: number, secondsToLand: number)
	local old = rings[shooterId]
	if old ~= nil then
		old:Destroy()
	end
	local ring = newPart(
		Enum.PartType.Cylinder,
		CORAL,
		Vector3.new(0.2, radius * 2, radius * 2),
		CFrame.new(at.X, at.Y - 2.8, at.Z) * CFrame.Angles(0, 0, math.rad(90))
	)
	ring.Transparency = 0.7
	rings[shooterId] = ring
	TweenService
		:Create(ring, TweenInfo.new(math.max(0.1, secondsToLand), Enum.EasingStyle.Linear), {
			Transparency = 0.35,
		})
		:Play()
	Debris:AddItem(ring, math.max(secondsToLand, 0) + 2)
end

-- The blast itself. Also removes that shooter's shell and warning ring.
function CombatFx.burst(shooterId: string?, at: Vector3, radius: number)
	if shooterId ~= nil then
		local s = shells[shooterId]
		if s ~= nil then
			s:Destroy()
			shells[shooterId] = nil
		end
		local r = rings[shooterId]
		if r ~= nil then
			r:Destroy()
			rings[shooterId] = nil
		end
	end
	if atCap() then
		return
	end
	local ball = newPart(Enum.PartType.Ball, GOLD, Vector3.new(2, 2, 2), CFrame.new(at))
	ball.Transparency = 0.2
	fade(ball, 0.3, { Size = Vector3.new(radius * 1.6, radius * 1.6, radius * 1.6) })
	if not atCap() then
		local flat = newPart(
			Enum.PartType.Cylinder,
			CORAL,
			Vector3.new(0.2, 2, 2),
			CFrame.new(at.X, at.Y - 2.8, at.Z) * CFrame.Angles(0, 0, math.rad(90))
		)
		flat.Transparency = 0.3
		fade(flat, 0.4, { Size = Vector3.new(0.2, radius * 2, radius * 2) })
	end
end

function CombatFx.clear()
	for _, s in shells do
		if s ~= nil then
			s:Destroy()
		end
	end
	for _, r in rings do
		if r ~= nil then
			r:Destroy()
		end
	end
	table.clear(shells)
	table.clear(rings)
	for _, n in numbers do
		n:Destroy()
	end
	table.clear(numbers)
end

return CombatFx
