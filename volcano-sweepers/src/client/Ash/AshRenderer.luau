--!strict
-- Draws the ash. Client only: the cells are NOT replicated parts. The layout (which cells exist and
-- where) is computed from Shared/Ash/Layout, so only the levels travel the network:
--   AshSnapshot  string, one char per cell ('0'..'9')       -> every level
--   AshDelta     { idx, level, idx, level, ... }            -> changed levels
--
-- Look: every cell with ash is ONE soft mound: a Part with a SpecialMesh sphere (an ellipsoid sunk
-- into the ground so only a low dome shows), wider than the cell so neighbours melt into continuous
-- drifts. The maths (smoothed height from the 8 neighbours, footprint, per-cell jitter, colour) lives
-- in Shared/Client/AshShape and is unit tested. A level change refreshes the cell AND its neighbours
-- (their smoothed heights relax too, so swept paths get soft edges). Matte Sand material, no shadows.
-- Deep zones (Crater Rim, Lava Heart): a few tall mounds carry a tiny glowing ember speck (capped).
--
-- Speed rules:
--   * only cells within RADIUS studs of the player get a Part (CullLogic keeps the in-range set, with
--     a margin so the edge does not flicker); Parts are pooled and recycled (Parent = nil when away)
--   * level changes and range changes go into a queue; at most MAX_UPDATES_PER_FRAME cells (and
--     FRAME_BUDGET seconds of work) are refreshed per frame
--   * a mound getting LOWER (its own level or a neighbour's dropped) shrinks over ANIM_TIME seconds
--     (at most MAX_ANIMS at once; the rest just snap); a cell at level 0 has no Part, which reveals
--     the ground
--   * at most PART_CAP Parts in total: MOUND_CAP mounds + EMBER_CAP embers
-- Golden cells: the `Golden` remote ({ cells, endsAt }) lists the golden cell indices (worth 5x). They
-- glow gold (Neon dome, centred on the cell, gentle pulse) while their level is > 0 and before endsAt
-- (server time). A cell stops being golden when it reaches level 0. `cells = {}` clears all gold.
-- A golden cell may be bare ground when `Golden` arrives (the server tops it up, and that level comes
-- in the NEXT AshDelta): it is flagged anyway and lights up as soon as the delta raises it.
--
-- Exports: levelAt(i), cellAt(x, z), ashAhead(...), partCount(), cleared (Signal: x, z, zone),
-- loaded (true after the first snapshot).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Layout = require(Shared.Ash.Layout)
local Zones = require(Shared.Catalog.Zones)
local CullLogic = require(Shared.Client.CullLogic)
local AshShape = require(Shared.Client.AshShape)
local Signal = require(Shared.Signal)
local Net = require(script.Parent.Parent.Core.Net)

-- 140 studs covers the default max camera zoom (128) with room to spare: about 650 Parts at the
-- beach spawn and ~920 at the island centre (was 200: up to 1932 Parts, too many for old phones).
local RADIUS = 140 -- studs around the player that get Parts
local MARGIN = 16 -- extra studs before an active cell is given up
local PART_CAP = 1100 -- hard ceiling on live ash Parts (mounds + embers), whatever happens
local EMBER_CAP = 40 -- ember specks at most (taken out of PART_CAP)
local MOUND_CAP = PART_CAP - EMBER_CAP
local MIN_MOVE = 6 -- studs the player must move before the range is recomputed
local MAX_UPDATES_PER_FRAME = 600
local FRAME_BUDGET = 0.004 -- seconds of cell work per frame
local MAX_ANIMS = 140
local ANIM_TIME = 0.12
local POOL_MAX = 900
local MIN_HEIGHT = 0.03 -- mound height at the end of the "cleared" shrink
local CLEARED_RADIUS = 0.6 -- the footprint shrinks to this share while a cleared mound sinks away
local EMBER_SIZE = 0.5
local FOLDER_NAME = "VSAshClient"
local ASH_MATERIAL = Enum.Material.Sand -- matte and grainy: reads as soft powder, no glare

local N: number = Layout.N
local MAX_LEVEL: number = Config.World.maxUnitsPerCell
local GROUND_Y: number = Config.World.groundY
local CELL: number = Config.World.cellSize
local MAX_PEAK: number = AshShape.maxPeak(MAX_LEVEL)

-- neighbour table, built once: NB[(i - 1) * 8 + k], k = 1..NB_COUNT[i]
local NB, NB_COUNT = AshShape.neighbourTable(N, Layout.neighbours)

type Anim = {
	part: Part,
	fromH: number,
	toH: number,
	fromR: number,
	toR: number,
	curH: number,
	curR: number,
	t: number,
}

local AshRenderer = {}
AshRenderer.loaded = false
AshRenderer.cleared = Signal.new()

local levels: { number } = table.create(N, 0)
local range = CullLogic.newRange()
local queue = CullLogic.newQueue()
local partOf: { [number]: Part } = {}
local heightOf: { [number]: number } = {} -- target peak height of the cell's mound
local radiusOf: { [number]: number } = {} -- target footprint radius of the cell's mound
local shrinkHint: { [number]: boolean } = {} -- the pending refresh came from a level DROP
local anims: { [number]: Anim } = {}
local animCount = 0
local golden: { [number]: boolean } = {}
local goldenCount = 0
local goldenEndsAt = 0
local goldLook: { [number]: boolean } = {} -- the Part currently wears the gold look
local pool: { Part } = {}
local liveParts = 0 -- live mounds
local starved: { number } = {} -- cells that wanted a Part while over MOUND_CAP
local isStarved: { [number]: boolean } = {} -- each cell waits in `starved` at most once
local emberOf: { [number]: Part } = {}
local emberPool: { Part } = {}
local emberCount = 0

-- zone ash tints as numbers (parsed once)
local zoneR: { [number]: number } = {}
local zoneG: { [number]: number } = {}
local zoneB: { [number]: number } = {}
for _, zone in Zones.list do
	local r, g, b = CullLogic.parseHex(zone.ash)
	zoneR[zone.id], zoneG[zone.id], zoneB[zone.id] = r, g, b
end

-- ===== folder =====

local old = workspace:FindFirstChild(FOLDER_NAME)
if old ~= nil then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = workspace

-- ===== parts =====

local function quietPart(p: Part)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

local function newPart(): Part
	local p = Instance.new("Part")
	p.Name = "Ash"
	quietPart(p)
	p.Material = ASH_MATERIAL
	-- a Sphere SpecialMesh stretches to the Part's Size, so the Part becomes an ellipsoid
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function newEmber(): Part
	local p = Instance.new("Part")
	p.Name = "Ember"
	quietPart(p)
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(EMBER_SIZE, EMBER_SIZE, EMBER_SIZE)
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 122, 40)
	p.Transparency = 0.3
	return p
end

-- Size and place cell i's mound for peak height h and footprint radius r.
local function setShape(i: number, part: Part, h: number, r: number)
	local ox, oz, yaw, fx, fz = AshShape.jitter(i, goldLook[i] == true)
	local a, b, cy = AshShape.ellipsoid(h, r)
	part.Size = Vector3.new(2 * a * fx, 2 * b, 2 * a * fz)
	part.CFrame = CFrame.new(Layout.cx[i] + ox, GROUND_Y + cy, Layout.cz[i] + oz)
		* CFrame.Angles(0, yaw, 0)
end

local GOLD_A = Color3.fromRGB(255, 196, 36)
local GOLD_B = Color3.fromRGB(255, 240, 150)

-- Ash colour (or gold) and material for cell i's mound at peak height h.
local function applyLook(i: number, part: Part, h: number)
	local isGold = golden[i] == true
	local was = goldLook[i]
	goldLook[i] = isGold
	if isGold then
		if was ~= true then
			part.Material = Enum.Material.Neon
			part.Color = GOLD_A
		end
		return
	end
	if was ~= false then
		part.Material = ASH_MATERIAL
	end
	local zone = Layout.zone[i]
	local _, _, _, _, _, _, light = AshShape.jitter(i, false)
	local r, g, b = AshShape.tint(
		zoneR[zone] or 184,
		zoneG[zone] or 178,
		zoneB[zone] or 170,
		light,
		h / MAX_PEAK
	)
	part.Color = Color3.fromRGB(r, g, b)
end

local function acquire(): Part
	local part = table.remove(pool)
	if part == nil then
		part = newPart()
	end
	liveParts += 1
	return part :: Part
end

local function dropEmber(i: number)
	local e = emberOf[i]
	if e ~= nil then
		emberOf[i] = nil
		emberCount -= 1
		e.Parent = nil
		table.insert(emberPool, e)
	end
end

-- Give cell i its ember speck (deep zones, tall mounds, some cells only) or take it away.
local function updateEmber(i: number, h: number, r: number)
	if goldLook[i] or not AshShape.hasEmber(i, Layout.zone[i], levels[i]) then
		dropEmber(i)
		return
	end
	local e = emberOf[i]
	if e == nil then
		if emberCount >= EMBER_CAP then
			return
		end
		e = table.remove(emberPool) or newEmber()
		emberOf[i] = e :: Part
		emberCount += 1
	end
	local ember = e :: Part
	local ox, oz, _, fx, fz = AshShape.jitter(i, false)
	local rr = r * math.min(fx, fz)
	local dx, dz, d = AshShape.emberSpot(i, rr)
	local y = AshShape.surfaceAt(h, rr, d)
	ember.CFrame =
		CFrame.new(Layout.cx[i] + ox + dx, GROUND_Y + y - EMBER_SIZE * 0.2, Layout.cz[i] + oz + dz)
	ember.Parent = folder
end

local function setGolden(i: number, on: boolean)
	if on then
		if not golden[i] then
			golden[i] = true
			goldenCount += 1
		end
	elseif golden[i] then
		golden[i] = nil
		goldenCount -= 1
	end
end

local function dropAnim(i: number)
	if anims[i] ~= nil then
		anims[i] = nil
		animCount -= 1
	end
end

local function release(i: number)
	local part = partOf[i]
	partOf[i] = nil
	heightOf[i] = nil
	radiusOf[i] = nil
	goldLook[i] = nil
	dropAnim(i)
	dropEmber(i)
	if part ~= nil then
		liveParts -= 1
		part.Parent = nil
		if #pool < POOL_MAX then
			table.insert(pool, part)
		else
			part:Destroy()
		end
		-- a Part is free again: give it to a cell that was waiting (if it still wants one)
		-- (skip ones that left the range or emptied while they waited)
		while #starved > 0 do
			local waiting = table.remove(starved) :: number
			isStarved[waiting] = nil
			if range.active[waiting] and levels[waiting] > 0 and partOf[waiting] == nil then
				queue.push(waiting)
				break
			end
		end
	end
end

-- Start (or retarget) a shrink animation to (toH, toR). False when too many are running.
local function startAnim(i: number, part: Part, toH: number, toR: number): boolean
	local a = anims[i]
	if a ~= nil then
		a.fromH, a.fromR = a.curH, a.curR
		a.toH, a.toR = toH, toR
		a.t = 0
		return true
	end
	if animCount >= MAX_ANIMS then
		return false
	end
	local fromH = heightOf[i] or toH
	local fromR = radiusOf[i] or toR
	anims[i] = {
		part = part,
		fromH = fromH,
		toH = toH,
		fromR = fromR,
		toR = toR,
		curH = fromH,
		curR = fromR,
		t = 0,
	}
	animCount += 1
	return true
end

-- Bring one cell's mound in line with levels[i] (and its neighbours') and the range.
local function refresh(i: number)
	local level = levels[i]
	local part = partOf[i]
	local hint = shrinkHint[i]
	shrinkHint[i] = nil

	if not range.active[i] then
		if part ~= nil then
			release(i)
		end
		return
	end

	if level <= 0 then
		if part ~= nil then
			dropEmber(i)
			if anims[i] ~= nil and heightOf[i] == MIN_HEIGHT then
				return -- already sinking away; it is released when the shrink ends
			end
			local toR = (radiusOf[i] or CELL * 0.5) * CLEARED_RADIUS
			if hint and startAnim(i, part, MIN_HEIGHT, toR) then
				heightOf[i] = MIN_HEIGHT
				radiusOf[i] = toR
			else
				release(i)
			end
		end
		return
	end

	local h, r = AshShape.target(i, levels, NB, NB_COUNT, CELL, MAX_LEVEL, golden[i] == true)
	if part == nil then
		if liveParts >= MOUND_CAP then
			-- over budget: this (far) cell waits until another Part is given up
			if not isStarved[i] then
				isStarved[i] = true
				table.insert(starved, i)
			end
			return
		end
		local fresh = acquire()
		partOf[i] = fresh
		heightOf[i] = h
		radiusOf[i] = r
		applyLook(i, fresh, h)
		setShape(i, fresh, h, r)
		fresh.Parent = folder
		updateEmber(i, h, r)
		return
	end
	local lookChanged = (golden[i] == true) ~= (goldLook[i] == true)
	if not lookChanged and heightOf[i] == h and radiusOf[i] == r then
		return
	end
	applyLook(i, part, h)
	if hint and h < (heightOf[i] or h) and startAnim(i, part, h, r) then
		heightOf[i] = h
		radiusOf[i] = r
	else
		dropAnim(i)
		heightOf[i] = h
		radiusOf[i] = r
		setShape(i, part, h, r)
	end
	updateEmber(i, h, r)
end

local function stepAnims(dt: number)
	if animCount == 0 then
		return
	end
	for i, a in anims do
		a.t += dt / ANIM_TIME
		local k = math.min(a.t, 1)
		local e = k * (2 - k) -- ease out
		a.curH = a.fromH + (a.toH - a.fromH) * e
		a.curR = a.fromR + (a.toR - a.fromR) * e
		setShape(i, a.part, math.max(a.curH, MIN_HEIGHT), a.curR)
		if k >= 1 then
			anims[i] = nil
			animCount -= 1
			if levels[i] <= 0 or not range.active[i] then
				release(i)
			end
		end
	end
end

-- Queue cell i and its in-range neighbours (their smoothed heights depend on i's level).
-- `drop`: the level went down, so the mounds may shrink smoothly instead of snapping.
local function pushAround(i: number, drop: boolean)
	local active = range.active
	if active[i] then
		if drop then
			shrinkHint[i] = true
		end
		queue.push(i)
	end
	local base = (i - 1) * 8
	for k = 1, NB_COUNT[i] do
		local j = NB[base + k]
		if active[j] then
			if drop then
				shrinkHint[j] = true
			end
			queue.push(j)
		end
	end
end

-- ===== where the player is =====

-- Only the character counts: before it exists the camera sits at the world origin, and building
-- the cells around (0, 0) only to throw them away a moment later wastes the first seconds.
local function centre(): (number?, number?)
	local character = Players.LocalPlayer.Character
	if character ~= nil then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp ~= nil and hrp:IsA("BasePart") then
			return hrp.Position.X, hrp.Position.Z
		end
	end
	return nil, nil
end

-- ===== network =====

Net.on("AshSnapshot", function(s: any)
	local decoded = CullLogic.decodeSnapshot(s, N, MAX_LEVEL)
	if decoded == nil then
		warn("[AshRenderer] bad AshSnapshot ignored")
		return
	end
	for i = 1, N do
		local v = decoded[i]
		if v == 0 then
			setGolden(i, false)
		end
		if levels[i] ~= v then
			levels[i] = v
			pushAround(i, false)
		end
	end
	AshRenderer.loaded = true
end)

-- { cells = { idx, ... }, endsAt = serverTime }: the whole golden set replaces the old one.
Net.on("Golden", function(info: any)
	if type(info) ~= "table" or type(info.cells) ~= "table" then
		return
	end
	local touched: { number } = {}
	for i in golden do
		table.insert(touched, i)
	end
	table.clear(golden)
	goldenCount = 0
	local endsAt = if type(info.endsAt) == "number" and info.endsAt == info.endsAt
		then info.endsAt
		else 0
	goldenEndsAt = endsAt
	if endsAt > 0 then
		for _, i in info.cells do
			if type(i) == "number" and i == math.floor(i) and i >= 1 and i <= N then
				setGolden(i, true)
				table.insert(touched, i)
			end
		end
	end
	for _, i in touched do
		if range.active[i] then
			queue.push(i)
		end
	end
end)

Net.on("AshDelta", function(flat: any)
	CullLogic.applyDelta(levels, flat, N, MAX_LEVEL, function(i: number, was: number, now: number)
		if now == 0 then
			setGolden(i, false) -- gold ends when the cell is empty (the Part's look is fixed by refresh)
		end
		pushAround(i, now < was)
		if now == 0 and range.active[i] then
			AshRenderer.cleared:fire(Layout.cx[i], Layout.cz[i], Layout.zone[i])
		end
	end)
end)

-- ===== gold pulse and expiry =====

local function stepGolden()
	if goldenCount == 0 then
		return
	end
	if goldenEndsAt > 0 and workspace:GetServerTimeNow() >= goldenEndsAt then
		local ended: { number } = {}
		for i in golden do
			table.insert(ended, i)
		end
		table.clear(golden)
		goldenCount = 0
		for _, i in ended do
			if range.active[i] then
				queue.push(i)
			end
		end
		return
	end
	local t = os.clock() * 4
	for i in golden do
		local part = partOf[i]
		if part ~= nil and goldLook[i] then
			local k = 0.5 + 0.5 * math.sin(t + i * 0.7)
			part.Color = GOLD_A:Lerp(GOLD_B, k)
		end
	end
end

-- ===== frame loop =====

RunService.Heartbeat:Connect(function(dt: number)
	local x, z = centre()
	if x ~= nil and z ~= nil then
		local entered, left = CullLogic.update(Layout, range, x, z, RADIUS, MARGIN, MIN_MOVE)
		for _, i in left do
			queue.push(i)
		end
		for _, i in entered do
			queue.push(i)
		end
	end
	if queue.size() > 0 then
		local t0 = os.clock()
		CullLogic.drain(queue, MAX_UPDATES_PER_FRAME, function(i: number): boolean?
			refresh(i)
			return os.clock() - t0 < FRAME_BUDGET
		end)
	end
	stepAnims(dt)
	stepGolden()
end)

-- ===== API =====

function AshRenderer.levelAt(i: number): number
	return levels[i] or 0
end

function AshRenderer.cellAt(x: number, z: number): number?
	return Layout.cellOf(x, z)
end

-- Is there ash (level > 0, in an allowed zone) in the fan in front of (px, pz)? See CullLogic.ashAhead.
function AshRenderer.ashAhead(
	px: number,
	pz: number,
	dx: number,
	dz: number,
	reach: number,
	arcDeg: number,
	allowed: { [number]: boolean }
): boolean
	return CullLogic.ashAhead(Layout, levels, px, pz, dx, dz, reach, arcDeg, allowed)
end

-- Parts currently drawn: mounds + ember specks (for debugging).
function AshRenderer.partCount(): number
	return liveParts + emberCount
end

return AshRenderer
