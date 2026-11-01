--!strict
-- The tool in every character's hand (and the vac backpack / wings / tank on their back), built on
-- THIS client from Parts (Shared/Client/HeldToolLogic has the eight looks), plus a quick swing.
-- Purely cosmetic: nothing here is replicated or trusted.
--
-- Which tool: the character attribute `VSTool` (string tool id, set by the server). If it is missing,
-- my own character uses the Store's equipped `tool`, and other players use the `tool` field of their
-- last SweepFx. Unknown ids show the Twig Broom.
-- When it swings:
--   * mine: at once on every swing sent (Controls.swept)
--   * others: on every SweepFx for them, and while their attribute `VSSweeping` is true
-- Speed: others' tools are built only within HeldToolLogic.BUILD_RADIUS (dropped beyond DROP_RADIUS),
-- at most MAX_MODELS at once, and only animated within ANIM_RADIUS. The model lives inside the
-- character, so it goes away with it; everything else is cleaned on CharacterRemoving / leave.
--
--   HeldTool.swing(player)   play one swing on that player's tool (if it is built)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CullLogic = require(Shared.Client.CullLogic)
local HeldToolLogic = require(Shared.Client.HeldToolLogic)
local Tools = require(Shared.Catalog.Tools)
local Net = require(script.Parent.Parent.Core.Net)
local Store = require(script.Parent.Parent.Core.Store)

local function softRequire(folderName: string, moduleName: string): any?
	local folder = script.Parent.Parent:FindFirstChild(folderName)
	local mod = if folder ~= nil then folder:FindFirstChild(moduleName) else nil
	if mod == nil or not mod:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn(`[HeldTool] could not load {moduleName}: {result}`)
		return nil
	end
	return result
end

local Controls: any = softRequire("Core", "Controls")
local Vfx: any = softRequire("Vfx", "Vfx")

local HeldTool = {}

local LocalPlayer = Players.LocalPlayer
local MODEL_NAME = "VSHeldTool"
local SCAN_GAP = 0.5 -- seconds between distance / attribute checks

type Rec = {
	player: Player,
	character: Model?,
	model: Model?,
	toolId: string?,
	weld: Weld?,
	backWeld: Weld?,
	base: CFrame, -- the weld's resting C0
	blueprint: HeldToolLogic.Blueprint?,
	shoulder: Motor6D?,
	written: CFrame?, -- the shoulder Transform we wrote last frame
	writtenBase: CFrame?, -- the animation's Transform under it
	swingT: number, -- 0..1 while swinging, -1 at rest
	swingDur: number,
	near: boolean, -- close enough to animate
	sweeping: boolean, -- VSSweeping attribute
	nextAutoSwing: number,
	fxTool: string?, -- tool id from their last SweepFx
	charConns: { RBXScriptConnection },
	conns: { RBXScriptConnection },
}

local recs: { [Player]: Rec } = {}
local built = 0

-- ===== building =====

local SHAPES: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Cylinder = Enum.PartType.Cylinder,
	Ball = Enum.PartType.Ball,
}

local MATERIALS: { [string]: Enum.Material } = {
	Wood = Enum.Material.Wood,
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Neon = Enum.Material.Neon,
	Metal = Enum.Material.Metal,
	Fabric = Enum.Material.Fabric,
	Glass = Enum.Material.Glass,
}

local function color3(hex: string): Color3
	local r, g, b = CullLogic.parseHex(hex)
	return Color3.fromRGB(r, g, b)
end

local function quiet(p: BasePart)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Locked = true
end

local function offset(v: { number }, r: { number }): CFrame
	return CFrame.new(v[1], v[2], v[3])
		* CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
end

-- R15 RightHand / R6 Right Arm, and where the grip sits on it.
local function handOf(character: Model): (BasePart?, CFrame)
	local hand = character:FindFirstChild("RightHand")
	if hand ~= nil and hand:IsA("BasePart") then
		return hand, CFrame.new(0, -0.1, 0)
	end
	local arm = character:FindFirstChild("Right Arm")
	if arm ~= nil and arm:IsA("BasePart") then
		return arm, CFrame.new(0, -0.9, 0)
	end
	return nil, CFrame.identity
end

local function torsoOf(character: Model): BasePart?
	local t = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if t ~= nil and t:IsA("BasePart") then
		return t
	end
	return nil
end

local function shoulderOf(character: Model): Motor6D?
	-- R15 only: the R6 shoulder uses another axis, so R6 gets the grip swing alone
	local arm = character:FindFirstChild("RightUpperArm")
	local m = if arm ~= nil then arm:FindFirstChild("RightShoulder") else nil
	if m ~= nil and m:IsA("Motor6D") then
		return m
	end
	return nil
end

local function makePart(spec: HeldToolLogic.PartSpec, at: CFrame, parent: Instance): BasePart
	local p: BasePart
	if spec.shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		part.Shape = SHAPES[spec.shape] or Enum.PartType.Block
		p = part
	end
	p.Name = spec.name
	p.Size = Vector3.new(spec.size[1], spec.size[2], spec.size[3])
	p.Color = color3(spec.color)
	p.Material = MATERIALS[spec.material] or Enum.Material.SmoothPlastic
	p.Transparency = spec.transparency
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	quiet(p)
	p.CFrame = at * offset(spec.pos, spec.rot)
	p.Parent = parent
	return p
end

local function rootPart(name: string, cf: CFrame, parent: Instance): Part
	local root = Instance.new("Part")
	root.Name = name
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	quiet(root)
	root.CFrame = cf
	root.Parent = parent
	return root
end

local function weldAll(root: BasePart, parts: { BasePart })
	for _, p in parts do
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
	end
end

local function releaseShoulder(rec: Rec)
	local m = rec.shoulder
	if m ~= nil and rec.written ~= nil and m.Parent ~= nil and m.Transform == rec.written then
		m.Transform = rec.writtenBase or CFrame.identity
	end
	rec.written = nil
	rec.writtenBase = nil
end

local function destroyModel(rec: Rec)
	releaseShoulder(rec)
	if rec.model ~= nil then
		rec.model:Destroy()
		built -= 1
	end
	rec.model = nil
	rec.weld = nil
	rec.backWeld = nil
	rec.toolId = nil
	rec.blueprint = nil
	rec.shoulder = nil
	rec.swingT = -1
end

local function build(rec: Rec, character: Model, toolId: string): boolean
	local hand, gripOffset = handOf(character)
	if hand == nil then
		return false
	end
	local bp = HeldToolLogic.blueprint(toolId)
	local model = Instance.new("Model")
	model.Name = MODEL_NAME

	-- the grip: tilted forward and a little outward so the tool clears the leg
	local base = gripOffset * CFrame.Angles(math.rad(bp.tilt), 0, math.rad(8))
	local gripCf = hand.CFrame * base
	local grip = rootPart("Grip", gripCf, model)
	local handParts: { BasePart } = {}
	local backSpecs: { HeldToolLogic.PartSpec } = {}
	for _, spec in bp.parts do
		if spec.anchor == "back" then
			table.insert(backSpecs, spec)
		else
			table.insert(handParts, makePart(spec, gripCf, model))
		end
	end
	weldAll(grip, handParts)
	local weld = Instance.new("Weld")
	weld.Name = "GripWeld"
	weld.Part0 = hand
	weld.Part1 = grip
	weld.C0 = base
	weld.Parent = grip

	local torso = torsoOf(character)
	local backWeld: Weld? = nil
	if torso ~= nil and #backSpecs > 0 then
		local backRoot = rootPart("Back", torso.CFrame, model)
		local backParts: { BasePart } = {}
		for _, spec in backSpecs do
			table.insert(backParts, makePart(spec, torso.CFrame, model))
		end
		weldAll(backRoot, backParts)
		local bw = Instance.new("Weld")
		bw.Name = "BackWeld"
		bw.Part0 = torso
		bw.Part1 = backRoot
		bw.C0 = CFrame.identity
		bw.Parent = backRoot
		backWeld = bw
	end

	model.Parent = character
	rec.model = model
	rec.weld = weld
	rec.backWeld = backWeld
	rec.base = base
	rec.toolId = toolId
	rec.blueprint = bp
	rec.shoulder = shoulderOf(character)
	rec.swingT = -1
	built += 1
	return true
end

-- Still properly attached? Avatar loading can swap body parts after spawn, which leaves the welds
-- pointing at a destroyed hand: then the model must be rebuilt on the new one.
local function attached(rec: Rec, character: Model): boolean
	local model, weld = rec.model, rec.weld
	if model == nil or model.Parent ~= character or weld == nil or weld.Parent == nil then
		return false
	end
	local hand = weld.Part0
	if hand == nil or hand.Parent ~= character then
		return false
	end
	local bw = rec.backWeld
	if
		bw ~= nil
		and (bw.Parent == nil or bw.Part0 == nil or (bw.Part0 :: BasePart).Parent ~= character)
	then
		return false
	end
	return true
end

-- ===== which tool =====

local function wantedTool(rec: Rec): string
	local character = rec.character
	local attr = if character ~= nil then character:GetAttribute("VSTool") else nil
	local fallback: any = rec.fxTool
	if rec.player == LocalPlayer then
		fallback = Store.get("tool")
	end
	return HeldToolLogic.resolve(attr, fallback)
end

-- Seconds between swings: my real (upgraded) interval from the Store, others' from the catalog.
local function interval(rec: Rec): number
	if rec.player == LocalPlayer then
		local derived = Store.get("derived")
		local v = if type(derived) == "table" then derived.interval else nil
		if type(v) == "number" and v == v and v > 0 then
			return v
		end
	end
	local tool = if rec.toolId ~= nil then Tools.byId[rec.toolId] else nil
	return if tool ~= nil then tool.interval else 0.34
end

-- ===== swing =====

function HeldTool.swing(player: Player)
	local rec = recs[player]
	if rec == nil or rec.weld == nil or not rec.near then
		return
	end
	-- restart only once the last swing is mostly done (fast tools would otherwise only twitch)
	if rec.swingT >= 0 and rec.swingT < 0.6 then
		return
	end
	rec.swingT = 0
	rec.swingDur = HeldToolLogic.swingTime(interval(rec))
end

local function stepSwings(dt: number)
	for _, rec in recs do
		local weld = rec.weld
		local bp = rec.blueprint
		if weld ~= nil and bp ~= nil then
			if rec.swingT >= 0 then
				rec.swingT += dt / math.max(rec.swingDur, 0.05)
				if rec.swingT >= 1 then
					rec.swingT = -1
					weld.C0 = rec.base
					releaseShoulder(rec)
				else
					local pitch, roll, arm = HeldToolLogic.pose(bp.style, rec.swingT, bp.amp)
					weld.C0 = rec.base * CFrame.Angles(math.rad(pitch), 0, math.rad(roll))
					local m = rec.shoulder
					if m ~= nil and m.Parent ~= nil then
						-- the Animator rewrites Transform each frame; if it did not this frame, build on
						-- the value under our last write so the arm can never wind up
						local current = m.Transform
						local under = if rec.written ~= nil and current == rec.written
							then rec.writtenBase or current
							else current
						local out = under * CFrame.Angles(math.rad(arm), 0, 0)
						m.Transform = out
						rec.written = out
						rec.writtenBase = under
					end
				end
			end
		end
	end
end

-- ===== characters =====

local function disconnectAll(list: { RBXScriptConnection })
	for _, c in list do
		c:Disconnect()
	end
	table.clear(list)
end

local function myPosition(): Vector3?
	local character = LocalPlayer.Character
	local hrp = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if hrp ~= nil and hrp:IsA("BasePart") then
		return hrp.Position
	end
	local cam = workspace.CurrentCamera
	return if cam ~= nil then cam.Focus.Position else nil
end

local function distanceTo(rec: Rec, from: Vector3?): number
	if rec.player == LocalPlayer then
		return 0
	end
	local character = rec.character
	local hrp = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if from == nil or hrp == nil or not hrp:IsA("BasePart") then
		return math.huge
	end
	return (hrp.Position - from).Magnitude
end

-- Bring one player's model in line with distance + wanted tool.
local function sync(rec: Rec, from: Vector3?)
	local character = rec.character
	if character == nil or character.Parent == nil then
		if rec.model ~= nil then
			destroyModel(rec)
		end
		return
	end
	local dist = distanceTo(rec, from)
	rec.near = rec.player == LocalPlayer or HeldToolLogic.canAnimate(dist)
	local has = rec.model ~= nil and attached(rec, character)
	if rec.model ~= nil and not has then
		destroyModel(rec) -- removed, or the hand it held was swapped: rebuild below
	end
	local want = rec.player == LocalPlayer or HeldToolLogic.wantModel(dist, has)
	if not want then
		if has then
			destroyModel(rec)
		end
		return
	end
	local toolId = wantedTool(rec)
	if has and rec.toolId == toolId then
		return
	end
	local changed = has and rec.toolId ~= nil
	if has then
		destroyModel(rec)
	elseif built >= HeldToolLogic.MAX_MODELS and rec.player ~= LocalPlayer then
		return
	end
	if build(rec, character, toolId) and changed and rec.player == LocalPlayer and Vfx ~= nil then
		-- a little sparkle when you switch tools
		local hand = handOf(character)
		if hand ~= nil then
			local tool = Tools.byId[toolId]
			pcall(Vfx.puff, hand.Position, if tool ~= nil then tool.color else "#FFFFFF", 10)
		end
	end
end

local function attachCharacter(rec: Rec, character: Model)
	disconnectAll(rec.charConns)
	destroyModel(rec)
	rec.character = character
	rec.sweeping = character:GetAttribute("VSSweeping") == true
	table.insert(
		rec.charConns,
		character:GetAttributeChangedSignal("VSTool"):Connect(function()
			sync(rec, myPosition())
		end)
	)
	table.insert(
		rec.charConns,
		character:GetAttributeChangedSignal("VSSweeping"):Connect(function()
			local on = character:GetAttribute("VSSweeping") == true
			if on and not rec.sweeping and rec.player ~= LocalPlayer then
				HeldTool.swing(rec.player)
				rec.nextAutoSwing = os.clock() + interval(rec)
			end
			rec.sweeping = on
		end)
	)
	-- the hand may stream in a moment after the model
	task.delay(0.5, function()
		if rec.character == character then
			sync(rec, myPosition())
		end
	end)
end

local function detachCharacter(rec: Rec)
	disconnectAll(rec.charConns)
	destroyModel(rec)
	rec.character = nil
	rec.sweeping = false
end

local function track(player: Player)
	if recs[player] ~= nil then
		return
	end
	local rec: Rec = {
		player = player,
		character = nil,
		model = nil,
		toolId = nil,
		weld = nil,
		backWeld = nil,
		base = CFrame.identity,
		blueprint = nil,
		shoulder = nil,
		written = nil,
		writtenBase = nil,
		swingT = -1,
		swingDur = 0.28,
		near = player == LocalPlayer,
		sweeping = false,
		nextAutoSwing = 0,
		fxTool = nil,
		charConns = {},
		conns = {},
	}
	recs[player] = rec
	table.insert(
		rec.conns,
		player.CharacterAdded:Connect(function(character: Model)
			attachCharacter(rec, character)
		end)
	)
	table.insert(
		rec.conns,
		player.CharacterRemoving:Connect(function()
			detachCharacter(rec)
		end)
	)
	if player.Character ~= nil then
		attachCharacter(rec, player.Character)
	end
end

local function untrack(player: Player)
	local rec = recs[player]
	if rec == nil then
		return
	end
	recs[player] = nil
	disconnectAll(rec.conns)
	detachCharacter(rec)
end

-- ===== wiring =====

for _, p in Players:GetPlayers() do
	track(p)
end
Players.PlayerAdded:Connect(track)
Players.PlayerRemoving:Connect(untrack)

-- my own swings: at once, no round trip
if Controls ~= nil and Controls.swept ~= nil then
	Controls.swept:connect(function()
		HeldTool.swing(LocalPlayer)
	end)
end

-- my equipped tool (fallback when the server attribute is missing)
Store.subscribe("tool", function()
	local rec = recs[LocalPlayer]
	if rec ~= nil then
		sync(rec, myPosition())
	end
end)

-- others' swings
Net.on("SweepFx", function(info: any)
	if type(info) ~= "table" or type(info.userId) ~= "number" then
		return
	end
	local player = Players:GetPlayerByUserId(info.userId)
	if player == nil or player == LocalPlayer then
		return
	end
	local rec = recs[player]
	if rec == nil then
		return
	end
	if type(info.tool) == "string" and Tools.byId[info.tool] ~= nil and rec.fxTool ~= info.tool then
		rec.fxTool = info.tool
		sync(rec, myPosition())
	end
	HeldTool.swing(player)
	rec.nextAutoSwing = os.clock() + interval(rec) -- the attribute loop must not double this swing
end)

local scanAcc = 0
RunService.Heartbeat:Connect(function(dt: number)
	scanAcc += dt
	if scanAcc >= SCAN_GAP then
		scanAcc = 0
		local from = myPosition()
		for _, rec in recs do
			local ok, err = pcall(sync, rec, from)
			if not ok then
				warn(`[HeldTool] {err}`)
			end
		end
	end
	-- keep swinging others while the server says they are sweeping
	local now = os.clock()
	for player, rec in recs do
		if rec.sweeping and player ~= LocalPlayer and rec.near and now >= rec.nextAutoSwing then
			rec.nextAutoSwing = now + interval(rec)
			HeldTool.swing(player)
		end
	end
end)

-- after the Animator wrote this frame's pose, before physics: our offsets go on top
RunService.PreSimulation:Connect(stepSwings)

return HeldTool
