--!strict
-- The island. World.init() builds everything under ONE folder, workspace.VSWorld (ground, sea,
-- volcano, hub, Trade Hut, gates, Trade Posts, lighthouse, decor) and sets the lighting. The layout
-- comes from the pure Shared/WorldPlan, so it is deterministic from Config.World.seed. Huts, gates,
-- the volcano and most scenery are carter's picked Toy models (World/Models, see Models/Wiring).
--
-- Build order: the ESSENTIAL parts (ground, the volcano's solid core, hub + spawns + Trade Hut,
-- gates, Trade Posts, every tag and prompt) are built at once and attached in one go; the volcano
-- mountain, the lighthouse and the scenery follow in a background task, a chunk per frame, each
-- model under its own pcall (one broken model warns once and the rest still builds).
--
--   World.init()                    build (safe to call again: the old VSWorld is removed first)
--   World.applyLighting()           bright afternoon look (also called by init)
--   World.hubPosition: Vector3      centre of the hub, on the ground
--   World.spawnPositions            { Vector3 } the 8 spawn pads (pad centres)
--   World.sellPadPositions()        { Vector3 } centres of the glowing sell pads (the hut's AND
--                                   one per Trade Post in zones 2..5)
--   World.gatePosition(zoneId)      Vector3? on the ring boundary (nil for zone 1 / unknown)
--   World.ventPositions             { Vector3 } geyser vents in zones 3..5 (for gem geysers)
--   World.decorReady()              true once the volcano and the scenery finished building (they
--                                   build in a background task)
--   World.partCount()               number of parts under VSWorld right now (debug / tests in Studio)
--
-- Tags: VSSellPad (pad parts), VSSellPrompt (the ProximityPrompt on each counter), VSGate (gate floor
-- plate, attribute ZoneId, child ProximityPrompt "GatePrompt"), VSSpawn (SpawnLocations).
-- The folder carries a number attribute "Glow" (0..1, pulses about every 7 s) that the client may
-- read to match the crater glow. Lava here is decor only: nothing in this folder hurts anyone.
--
-- Positions are computed at require time (pure maths) so other services can read them before init().

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local WorldPlan = require(Shared.WorldPlan)

local Decor = require(script.Parent.Decor)
local Gates = require(script.Parent.Gates)
local Ground = require(script.Parent.Ground)
local Hub = require(script.Parent.Hub)
local TradePosts = require(script.Parent.TradePosts)
local Volcano = require(script.Parent.Volcano)

type Live = { volcano: Volcano.Refs? }

local World = {}

local plan = WorldPlan.default()
local GY = Config.World.groundY

World.hubPosition = Vector3.new(plan.hub.x, GY, plan.hub.z)

World.spawnPositions = {} :: { Vector3 }
for _, s in plan.hub.spawns do
	table.insert(World.spawnPositions, Vector3.new(s.x, GY + 0.3, s.z))
end

World.ventPositions = {} :: { Vector3 }
for _, v in plan.vents do
	table.insert(World.ventPositions, Vector3.new(v.x, GY, v.z))
end

local padPositions: { Vector3 } = {}
for _, p in plan.hub.pads do
	table.insert(padPositions, Vector3.new(p.x, GY, p.z))
end
for _, post in plan.posts do
	table.insert(padPositions, Vector3.new(post.x, GY, post.z))
end

local gatePositions: { [number]: Vector3 } = {}
for _, g in plan.gates do
	gatePositions[g.zoneId] = Vector3.new(g.x, GY, g.z)
end

local buildId = 0
local rootFolder: Folder? = nil
local decorDone = false

function World.sellPadPositions(): { Vector3 }
	return table.clone(padPositions)
end

function World.gatePosition(zoneId: number): Vector3?
	return gatePositions[zoneId]
end

function World.decorReady(): boolean
	return decorDone
end

function World.partCount(): number
	local root = rootFolder
	if root == nil then
		return 0
	end
	local n = 0
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- ===== lighting =====

local function fresh(className: string, name: string): Instance
	local old = Lighting:FindFirstChild(name)
	if old ~= nil then
		old:Destroy()
	end
	local inst = Instance.new(className)
	inst.Name = name
	return inst
end

function World.applyLighting()
	Lighting.ClockTime = 15
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(140, 125, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(160, 150, 140)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 238, 210)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0

	local atmosphere = fresh("Atmosphere", "VSAtmosphere") :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(255, 214, 170)
	atmosphere.Decay = Color3.fromRGB(255, 190, 130)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting

	local bloom = fresh("BloomEffect", "VSBloom") :: BloomEffect
	bloom.Intensity = 0.4
	bloom.Size = 26
	bloom.Threshold = 0.95
	bloom.Parent = Lighting

	local color = fresh("ColorCorrectionEffect", "VSColorCorrection") :: ColorCorrectionEffect
	color.Saturation = 0.18
	color.Contrast = 0.06
	color.Brightness = 0
	color.TintColor = Color3.fromRGB(255, 248, 238)
	color.Parent = Lighting

	local rays = fresh("SunRaysEffect", "VSSunRays") :: SunRaysEffect
	rays.Intensity = 0.05
	rays.Spread = 0.6
	rays.Parent = Lighting
end

-- ===== helpers =====

-- Run one build step; a broken step is logged and the rest of the island still gets built.
local function stage<T>(name: string, fn: () -> T): T?
	local ok, result = pcall(fn)
	if not ok then
		warn(`[World] {name} failed: {result}`)
		return nil
	end
	return result
end

local function run(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(`[World] {name} failed: {err}`)
	end
end

-- If the hub's spawn pads failed to build, Roblox would drop everyone at the origin, which is inside
-- the volcano: put one plain pad on the first spawn spot instead.
local function ensureSpawn(root: Folder)
	for _, d in root:GetDescendants() do
		if d:IsA("SpawnLocation") then
			return
		end
	end
	local spot = World.spawnPositions[1]
	if spot == nil then
		return
	end
	local pad = Instance.new("SpawnLocation")
	pad.Name = "FallbackSpawn"
	pad.Anchored = true
	pad.Neutral = true
	pad.Duration = 0
	pad.Size = Vector3.new(6, 0.6, 6)
	pad.Color = Color3.fromHex("#2EC4B6")
	pad.CFrame = CFrame.new(spot)
	pad.Parent = root
	warn("[World] no spawn pads were built: using a fallback spawn at the hub")
end

-- Anybody who spawned before the world existed starts at the origin, which is inside the volcano.
local function rescuePlayers()
	local count = #World.spawnPositions
	if count == 0 then
		return
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp ~= nil and hrp:IsA("BasePart") then
				local p = hrp.Position
				local fromCentre = math.sqrt(p.X * p.X + p.Z * p.Z)
				if fromCentre < plan.coneRadius + 4 or p.Y < -20 then
					local spot = World.spawnPositions[player.UserId % count + 1]
					character:PivotTo(CFrame.new(spot + Vector3.new(0, 4, 0)))
					-- the server moved this body itself: the movement check must trust the new spot
					-- (otherwise a ready player could be snapped straight back into the volcano)
					local mw = script.Parent.Parent:FindFirstChild("Core")
					local mod = if mw ~= nil then mw:FindFirstChild("MoveWatch") else nil
					if mod ~= nil and mod:IsA("ModuleScript") then
						pcall(function()
							(require(mod) :: any).teleported(player)
						end)
					end
				end
			end
		end
	end
end

-- Gentle glow pulse: sets the "Glow" attribute and nudges the crater light, lava colour and foam.
-- The volcano arrives a moment after init (it builds with the scenery), so it is read from `live`.
local function startPulse(myId: number, root: Folder, ground: Ground.Refs?, live: Live)
	local lavaA = Color3.fromHex("#FF6A1F")
	local lavaB = Color3.fromHex("#FFA03A")
	local started = os.clock()
	task.spawn(function()
		while buildId == myId and root.Parent ~= nil do
			local t = os.clock() - started
			local glow = 0.5 + 0.5 * math.sin(t * 0.9)
			root:SetAttribute("Glow", glow)
			local volcano = live.volcano
			if volcano ~= nil then
				volcano.light.Brightness = 2.5 + 2.5 * glow
				volcano.lava.Color = lavaA:Lerp(lavaB, glow)
			end
			if ground ~= nil then
				ground.foam.Transparency = 0.1 + 0.25 * (0.5 + 0.5 * math.sin(t * 0.6))
			end
			task.wait(0.5)
		end
	end)
end

-- The lighthouse beam turns slowly (10 steps a second: a few hundred bytes a second per player).
local BEAM_SPEED = 0.35 -- radians per second
local BEAM_STEP = 0.1 -- seconds

local function startBeam(myId: number, root: Folder, beam: Model)
	task.spawn(function()
		while buildId == myId and root.Parent ~= nil and beam.Parent ~= nil do
			local dt = task.wait(BEAM_STEP)
			local ok = pcall(function()
				beam:PivotTo(beam:GetPivot() * CFrame.Angles(0, dt * BEAM_SPEED, 0))
			end)
			if not ok then
				return
			end
		end
	end)
end

-- ===== init =====

function World.init()
	buildId += 1
	local myId = buildId
	decorDone = false

	local old = Workspace:FindFirstChild("VSWorld")
	if old ~= nil then
		old:Destroy()
	end
	rootFolder = nil

	if GY ~= 0 then
		warn("[World] Config.World.groundY is not 0: the island is built for ground level 0")
	end

	local okLight, errLight = pcall(World.applyLighting)
	if not okLight then
		warn(`[World] lighting failed: {errLight}`)
	end

	local root = Instance.new("Folder")
	root.Name = "VSWorld"
	root:SetAttribute("Glow", 0.5)

	-- ===== essentials (one replication burst) =====
	local ground = stage("ground", function()
		return Ground.build(root, plan)
	end)
	local volcanoFolder = stage("volcano core", function()
		return Volcano.buildCore(root, plan)
	end)
	run("hub", function()
		Hub.build(root, plan)
	end)
	run("gates", function()
		Gates.build(root, plan)
	end)
	run("trade posts", function()
		TradePosts.build(root, plan)
	end)
	run("spawn fallback", function()
		ensureSpawn(root)
	end)

	root.Parent = Workspace
	rootFolder = root
	rescuePlayers()
	local live: Live = {}
	startPulse(myId, root, ground, live)

	-- ===== the volcano mountain, lighthouse and scenery: in the background, a chunk per frame =====
	local function alive(): boolean
		return buildId == myId and root.Parent ~= nil
	end
	task.spawn(function()
		task.wait()
		if alive() then
			live.volcano = stage("volcano", function()
				return Volcano.build(volcanoFolder or root, plan)
			end)
			task.wait()
		end
		if alive() then
			local ok, err = pcall(Decor.build, root, plan, alive, function(beam: Model)
				startBeam(myId, root, beam)
			end)
			if not ok then
				warn(`[World] decor failed: {err}`)
			end
		end
		if buildId == myId then
			decorDone = true
		end
	end)
end

return World
