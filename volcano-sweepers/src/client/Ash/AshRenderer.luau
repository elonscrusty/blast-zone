--!strict
-- Draws the ash. Client only: the cells are NOT replicated parts. The layout (which cells exist and
-- where) is computed from Shared/Ash/Layout, so only the levels travel the network:
--   AshSnapshot  string, one char per cell ('0'..'9')       -> every level
--   AshDelta     { idx, level, idx, level, ... }            -> changed levels
--
-- Speed rules:
--   * only cells within RADIUS studs of the player get a Part (CullLogic keeps the in-range set, with
--     a margin so the edge does not flicker); Parts are pooled and recycled (Parent = nil when away)
--   * level changes and range changes go into a queue; at most MAX_UPDATES_PER_FRAME cells (and
--     FRAME_BUDGET seconds of work) are refreshed per frame
--   * a level going DOWN shrinks the slab over ANIM_TIME seconds (at most MAX_ANIMS at once; the
--     rest just snap); a cell at level 0 has no Part, which reveals the ground
-- Golden cells: the `Golden` remote ({ cells, endsAt }) lists the golden cell indices (worth 5x). They
-- glow gold (Neon, gentle pulse) while their level is > 0 and before endsAt (server time). A cell
-- stops being golden when it reaches level 0. `cells = {}` clears all gold.
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
local Signal = require(Shared.Signal)
local Net = require(script.Parent.Parent.Core.Net)

-- 140 studs covers the default max camera zoom (128) with room to spare: about 650 Parts at the
-- beach spawn and ~920 at the island centre (was 200: up to 1932 Parts, too many for old phones).
local RADIUS = 140 -- studs around the player that get Parts
local MARGIN = 16 -- extra studs before an active cell is given up
local PART_CAP = 1100 -- hard ceiling on live ash Parts, whatever happens
local MIN_MOVE = 6 -- studs the player must move before the range is recomputed
local MAX_UPDATES_PER_FRAME = 600
local FRAME_BUDGET = 0.004 -- seconds of cell work per frame
local MAX_ANIMS = 100
local ANIM_TIME = 0.12
local POOL_MAX = 900
local MIN_HEIGHT = 0.03 -- slab height at the end of the "cleared" shrink
local FOLDER_NAME = "VSAshClient"

local N: number = Layout.N
local MAX_LEVEL: number = Config.World.maxUnitsPerCell
local GROUND_Y: number = Config.World.groundY
local SIZE: number = CullLogic.slabSize(Config.World.cellSize)

type Anim = { part: Part, from: number, to: number, cur: number, t: number }

local AshRenderer = {}
AshRenderer.loaded = false
AshRenderer.cleared = Signal.new()

local levels: { number } = table.create(N, 0)
local range = CullLogic.newRange()
local queue = CullLogic.newQueue()
local partOf: { [number]: Part } = {}
local heightOf: { [number]: number } = {} -- target height of the cell's Part
local shrinkHint: { [number]: boolean } = {} -- the pending refresh came from a level DROP
local anims: { [number]: Anim } = {}
local animCount = 0
local golden: { [number]: boolean } = {}
local goldenCount = 0
local goldenEndsAt = 0
local goldLook: { [number]: boolean } = {} -- the Part currently wears the gold look
local pool: { Part } = {}
local liveParts = 0
local starved: { number } = {} -- cells that wanted a Part while over PART_CAP

local zoneAsh: { [number]: string } = {}
for _, zone in Zones.list do
	zoneAsh[zone.id] = zone.ash
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

local function newPart(): Part
	local p = Instance.new("Part")
	p.Name = "Ash"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function setHeight(i: number, part: Part, h: number)
	part.Size = Vector3.new(SIZE, h, SIZE)
	part.CFrame = CFrame.new(Layout.cx[i], GROUND_Y + h * 0.5, Layout.cz[i])
end

local GOLD_A = Color3.fromRGB(255, 196, 36)
local GOLD_B = Color3.fromRGB(255, 240, 150)

-- Ash colour (or gold) and material for cell i's Part.
local function applyLook(i: number, part: Part)
	local isGold = golden[i] == true
	goldLook[i] = isGold
	if isGold then
		part.Material = Enum.Material.Neon
		part.Color = GOLD_A
	else
		part.Material = Enum.Material.SmoothPlastic
		local base = zoneAsh[Layout.zone[i]] or "#B8B2AA"
		local r, g, b = CullLogic.shade(base, CullLogic.variation(i) * 0.07)
		part.Color = Color3.fromRGB(r, g, b)
	end
end

local function acquire(i: number): Part
	local part = table.remove(pool)
	if part == nil then
		part = newPart()
	end
	liveParts += 1
	return part :: Part
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
	goldLook[i] = nil
	dropAnim(i)
	if part ~= nil then
		liveParts -= 1
		part.Parent = nil
		if #pool < POOL_MAX then
			table.insert(pool, part)
		else
			part:Destroy()
		end
		-- a Part is free again: give it to a cell that was waiting (if it still wants one)
		local waiting = table.remove(starved)
		if waiting ~= nil and range.active[waiting] and levels[waiting] > 0 then
			queue.push(waiting)
		end
	end
end

-- Start (or retarget) a shrink/settle animation to height `to`. False when too many are running.
local function startAnim(i: number, part: Part, to: number): boolean
	local a = anims[i]
	if a ~= nil then
		a.from = a.cur
		a.to = to
		a.t = 0
		return true
	end
	if animCount >= MAX_ANIMS then
		return false
	end
	local from = heightOf[i] or to
	anims[i] = { part = part, from = from, to = to, cur = from, t = 0 }
	animCount += 1
	return true
end

-- Bring one cell's Part in line with levels[i] and the range.
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
			if hint and startAnim(i, part, MIN_HEIGHT) then
				heightOf[i] = MIN_HEIGHT
			else
				release(i)
			end
		end
		return
	end

	local h = CullLogic.slabHeight(level)
	if part == nil then
		if liveParts >= PART_CAP then
			-- over budget: this (far) cell waits until another Part is given up
			table.insert(starved, i)
			return
		end
		local fresh = acquire(i)
		applyLook(i, fresh)
		partOf[i] = fresh
		heightOf[i] = h
		setHeight(i, fresh, h)
		fresh.Parent = folder
		return
	end
	if (golden[i] == true) ~= (goldLook[i] == true) then
		applyLook(i, part)
	end
	if heightOf[i] == h then
		return
	end
	if hint and h < (heightOf[i] or h) and startAnim(i, part, h) then
		heightOf[i] = h
	else
		dropAnim(i)
		heightOf[i] = h
		setHeight(i, part, h)
	end
end

local function stepAnims(dt: number)
	if animCount == 0 then
		return
	end
	for i, a in anims do
		a.t += dt / ANIM_TIME
		local k = math.min(a.t, 1)
		a.cur = a.from + (a.to - a.from) * (k * (2 - k)) -- ease out
		setHeight(i, a.part, math.max(a.cur, MIN_HEIGHT))
		if k >= 1 then
			anims[i] = nil
			animCount -= 1
			if levels[i] <= 0 or not range.active[i] then
				release(i)
			end
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
	local active = range.active
	for i = 1, N do
		local v = decoded[i]
		if v == 0 then
			setGolden(i, false)
		end
		if levels[i] ~= v then
			levels[i] = v
			if active[i] then
				queue.push(i)
			end
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
		if range.active[i] then
			if now < was then
				shrinkHint[i] = true
			end
			queue.push(i)
			if now == 0 then
				AshRenderer.cleared:fire(Layout.cx[i], Layout.cz[i], Layout.zone[i])
			end
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

-- Parts currently drawn (for debugging).
function AshRenderer.partCount(): number
	return liveParts
end

return AshRenderer
