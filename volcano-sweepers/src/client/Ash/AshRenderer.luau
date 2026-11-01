--!strict
-- Draws the ash. Client only: the cells are NOT replicated parts. The layout (which cells exist and
-- where) is computed from Shared/Ash/Layout, so only the levels travel the network:
--   AshSnapshot  string, one char per cell ('0'..'9')       -> every level
--   AshDelta     { idx, level, idx, level, ... }            -> changed levels
--
-- Look: the island is under ONE flat, continuous blanket of ash with a real thickness, and every
-- swing carves a clean trench through it down to the bright zone ground (the trench wall shows how
-- deep the layer is; a part-swept cell is a thinner, slightly darker layer). Trench edges follow
-- marching squares on the cell centres (straight or 45 degrees, chamfered ends), never a staircase
-- of squares. A full cell is one flat block; cells on an edge add a 45-degree diamond and flat
-- WedgeParts. All the maths (pieces, heights, z-fight offsets, colours) lives in
-- Shared/Client/AshShape and is unit tested. Matte Sand material, no shadows.
-- Deep zones (Crater Rim, Lava Heart): a few full cells carry a tiny glowing ember speck (capped).
--
-- Speed rules (the island is ~12,000 cells; only a ring around the player is drawn):
--   * the island is cut into chunks of CHUNK x CHUNK cells (Shared/Client/AshChunks)
--   * NEAR chunks (centre within NEAR_RADIUS studs) draw every cell in detail
--   * FAR chunks (within FAR_RADIUS, not near) draw one flat tile (1-4 blocks) at the chunk's mean
--     level, its colour leaning to the ground as it gets swept, so the blanket reaches the haze
--   * both sets have a hysteresis margin (CullLogic.update), Parts are pooled and recycled
--   * level and range changes go into queues; at most MAX_UPDATES_PER_FRAME cells (and
--     FRAME_BUDGET seconds) and MAX_FAR_PER_FRAME chunks are refreshed per frame; a cell whose
--     level and neighbours did not change is skipped (signature)
--   * a cell getting LOWER sinks smoothly over ANIM_TIME (at most MAX_ANIMS at once; the rest snap);
--     a swept cell sinks to the ground, then only its corner fillets stay
--   * at most PART_CAP Parts: NEAR_CAP detail + FAR_CAP tiles + EMBER_CAP embers
-- Golden cells: the `Golden` remote ({ cells, endsAt }) lists the golden cell indices (worth 5x). They
-- glow gold (Neon, a hair above the layer, gentle pulse) while their level is > 0 and before endsAt
-- (server time). A cell stops being golden when it reaches level 0. `cells = {}` clears all gold.
-- A golden cell may be bare ground when `Golden` arrives (the server tops it up, and that level comes
-- in the NEXT AshDelta): it is flagged anyway and lights up as soon as the delta raises it.
--
-- Exports: levelAt(i), cellAt(x, z), ashAhead(...), partCount(), cleared (Signal: x, z, zone),
-- loaded (true after the first snapshot), layerHex(x, z) (the layer colour there, for dust puffs).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Layout = require(Shared.Ash.Layout)
local Zones = require(Shared.Catalog.Zones)
local CullLogic = require(Shared.Client.CullLogic)
local AshShape = require(Shared.Client.AshShape)
local AshChunks = require(Shared.Client.AshChunks)
local Signal = require(Shared.Signal)
local Net = require(script.Parent.Parent.Core.Net)

-- Budget (mid phone), measured on the 12,000-cell island (tests/ash_shape covers the maths):
--   near detail: 560-860 cells -> ~580-870 Parts on a fresh layer, up to ~1050 on a heavily
--   scraped patchwork (every level step adds a diamond or a wedge); far tiles: 150-285 Parts;
--   embers: 20. Hard ceilings below add up to 1400.
local CHUNK = 4 -- cells per chunk side (32 studs)
local NEAR_RADIUS = 112 -- studs: chunks whose centre is this close are drawn in detail
local NEAR_MARGIN = 12
local FAR_RADIUS = 300 -- studs: chunks out to here get a flat far tile
local FAR_MARGIN = 24
local MIN_MOVE = 6 -- studs the player must move before the ranges are recomputed
local NEAR_CAP = 1080 -- detail Parts at most
local FAR_CAP = 300 -- far tile Parts at most
local EMBER_CAP = 20 -- ember specks at most
local PART_CAP = NEAR_CAP + FAR_CAP + EMBER_CAP -- 1400
local MAX_UPDATES_PER_FRAME = 500
local MAX_FAR_PER_FRAME = 60
local FRAME_BUDGET = 0.004 -- seconds of cell work per frame
local MAX_ANIMS = 140
local ANIM_TIME = 0.14
local POOL_MAX = 500 -- spare Parts kept per kind
local MIN_TOP = 0.02 -- studs: a swept cell sinks to this, then goes
local FAR_PARITY = 0.02 -- far tiles: checkerboard height offset
local FAR_DROP = 0.04 -- far tiles sit a hair lower than the detail layer
local EMBER_SIZE = 0.45
local FOLDER_NAME = "VSAshClient"
local ASH_MATERIAL = Enum.Material.Sand -- matte and grainy: reads as soft powder, no glare

local N: number = Layout.N
local MAX_LEVEL: number = Config.World.maxUnitsPerCell
local GROUND_Y: number = Config.World.groundY
local CELL: number = Config.World.cellSize
local BURY: number = AshShape.BURY
local STRIDE: number = AshShape.STRIDE
local KIND_WEDGE: number = AshShape.KIND_WEDGE
local KIND_DIAMOND: number = AshShape.KIND_DIAMOND
local ROT45 = CFrame.Angles(0, math.rad(45), 0)

-- ===== static tables (built once) =====

local DIR = AshShape.dirTable(N, Layout.cellOf, Layout.cx, Layout.cz, CELL)
local CH = AshChunks.build(Layout, CHUNK)
local chunkOf = CH.chunkOf

local parity: { number } = table.create(N, 0)
local baseR: { number } = table.create(N, 0)
local baseG: { number } = table.create(N, 0)
local baseB: { number } = table.create(N, 0)
do
	local rings: { AshShape.Ring } = {}
	for _, zc in Config.World.zones do
		local zone = Zones.byId[zc.id]
		local r, g, b = CullLogic.parseHex(if zone ~= nil then zone.ash else "#B8B2AA")
		table.insert(rings, { inner = zc.inner, outer = zc.outer, r = r, g = g, b = b })
	end
	for i = 1, N do
		local x, z = Layout.cx[i], Layout.cz[i]
		parity[i] = AshShape.parity(x, z, CELL)
		baseR[i], baseG[i], baseB[i] = AshShape.baseColour(x, z, rings)
	end
end

-- far tile colours per chunk: mean layer colour and the zone ground under it
local chunkR: { number } = table.create(CH.count, 0)
local chunkG: { number } = table.create(CH.count, 0)
local chunkB: { number } = table.create(CH.count, 0)
local groundR: { number } = table.create(CH.count, 0)
local groundG: { number } = table.create(CH.count, 0)
local groundB: { number } = table.create(CH.count, 0)
for c = 1, CH.count do
	local sr, sg, sb = 0, 0, 0
	local list = CH.cells[c]
	for _, i in list do
		sr += baseR[i]
		sg += baseG[i]
		sb += baseB[i]
	end
	local n = math.max(#list, 1)
	chunkR[c], chunkG[c], chunkB[c] = sr / n, sg / n, sb / n
	local zone = Zones.byId[CH.zone[c]]
	groundR[c], groundG[c], groundB[c] =
		CullLogic.parseHex(if zone ~= nil then zone.ground else "#F2D9A0")
end

type Anim = {
	t: number,
	from: number, -- height scale at the start
	to: number,
	clearing: boolean, -- the cell was swept: all its old pieces sink, then they go
}

local AshRenderer = {}
AshRenderer.loaded = false
AshRenderer.cleared = Signal.new()

local levels: { number } = table.create(N, 0)
local nearRange = CullLogic.newRange()
local farRange = CullLogic.newRange()
local queue = CullLogic.newQueue()
local farQueue = CullLogic.newQueue()

local blocksOf: { [number]: { Part } } = {} -- cell -> its blocks and diamond
local wedgesOf: { [number]: { WedgePart } } = {} -- cell -> its flat wedges
local sigOf: { [number]: number } = {} -- cell -> signature of what is drawn
local shownLevel: { [number]: number } = {} -- cell -> level its pieces were built for
local partTop: { [BasePart]: number } = {} -- built top of each live piece (studs above ground)
local partGold: { [BasePart]: boolean } = {} -- piece wears the gold look
local shrinkHint: { [number]: boolean } = {} -- the pending refresh came from the cell's own DROP
local anims: { [number]: Anim } = {}
local animCount = 0
local golden: { [number]: boolean } = {}
local goldenCount = 0
local goldenEndsAt = 0
local blockPool: { Part } = {}
local wedgePool: { WedgePart } = {}
local nearParts = 0
local starved: { number } = {}
local isStarved: { [number]: boolean } = {}
local emberOf: { [number]: Part } = {}
local emberPool: { Part } = {}
local emberCount = 0

-- far tiles
local tilesOf: { [number]: { Part } } = {}
local tileSig: { [number]: number } = {}
local farParts = 0
local chAsh: { number } = table.create(CH.count, 0) -- cells with ash per chunk
local chSum: { number } = table.create(CH.count, 0) -- sum of levels per chunk

local pieceBuf: { number } = table.create(AshShape.MAX_PIECES * STRIDE, 0)

-- ===== folder =====

local old = workspace:FindFirstChild(FOLDER_NAME)
if old ~= nil then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = workspace

-- ===== parts =====

local function quietPart(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = ASH_MATERIAL
end

local function takeBlock(): Part
	local p = table.remove(blockPool)
	if p == nil then
		local fresh = Instance.new("Part")
		fresh.Name = "Ash"
		quietPart(fresh)
		return fresh
	end
	return p
end

local function takeWedge(): WedgePart
	local w = table.remove(wedgePool)
	if w == nil then
		local fresh = Instance.new("WedgePart")
		fresh.Name = "AshEdge"
		quietPart(fresh)
		return fresh
	end
	return w
end

local function giveBlock(p: Part)
	p.Parent = nil
	partTop[p] = nil
	if partGold[p] then
		partGold[p] = nil
		p.Material = ASH_MATERIAL
	end
	if #blockPool < POOL_MAX then
		table.insert(blockPool, p)
	else
		p:Destroy()
	end
end

local function giveWedge(w: WedgePart)
	w.Parent = nil
	partTop[w] = nil
	if #wedgePool < POOL_MAX then
		table.insert(wedgePool, w)
	else
		w:Destroy()
	end
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

-- A flat block (or a 45-degree diamond) from the ground up to `top`.
local function placeBlock(
	p: BasePart,
	x: number,
	z: number,
	sx: number,
	sz: number,
	top: number,
	turn: boolean
)
	local hgt = math.max(top, MIN_TOP) + BURY
	p.Size = Vector3.new(sx, hgt, sz)
	local cf = CFrame.new(x, GROUND_Y - BURY + hgt / 2, z)
	p.CFrame = if turn then cf * ROT45 else cf
end

-- A flat wedge (horizontal right triangle, see AshShape.wedgeFrame) from the ground up to `top`.
local function placeWedge(
	w: WedgePart,
	cx: number,
	cz: number,
	sx: number,
	sz: number,
	leg: number,
	top: number
)
	local mx, mz, upY, yx, zz = AshShape.wedgeFrame(cx, cz, sx, sz, leg)
	local hgt = math.max(top, MIN_TOP) + BURY
	w.Size = Vector3.new(hgt, leg, leg)
	w.CFrame = CFrame.fromMatrix(
		Vector3.new(mx, GROUND_Y - BURY + hgt / 2, mz),
		Vector3.new(0, upY, 0),
		Vector3.new(yx, 0, 0),
		Vector3.new(0, 0, zz)
	)
end

-- Re-height a live piece to `scale` x its built top, keeping its footprint (animations).
local function scaleHeight(p: BasePart, scale: number, isWedge: boolean)
	local top = partTop[p]
	if top == nil then
		return
	end
	local hgt = math.max(top * scale, MIN_TOP) + BURY
	local size = p.Size
	p.Size = if isWedge then Vector3.new(hgt, size.Y, size.Z) else Vector3.new(size.X, hgt, size.Z)
	local pos = p.Position
	p.CFrame = p.CFrame.Rotation + Vector3.new(pos.X, GROUND_Y - BURY + hgt / 2, pos.Z)
end

local GOLD_A = Color3.fromRGB(255, 196, 36)
local GOLD_B = Color3.fromRGB(255, 240, 150)

local function ashColor(i: number, level: number): Color3
	local r, g, b = AshShape.depthShade(baseR[i], baseG[i], baseB[i], level, MAX_LEVEL)
	return Color3.fromRGB(r, g, b)
end

-- ===== embers =====

local function dropEmber(i: number)
	local e = emberOf[i]
	if e ~= nil then
		emberOf[i] = nil
		emberCount -= 1
		e.Parent = nil
		table.insert(emberPool, e)
	end
end

local function updateEmber(i: number)
	local level = levels[i]
	if golden[i] or not AshShape.hasEmber(i, Layout.zone[i], level) then
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
	local dx, dz = AshShape.emberSpot(i, CELL)
	local top = AshShape.thickness(level, MAX_LEVEL) + parity[i] * AshShape.PARITY
	ember.CFrame =
		CFrame.new(Layout.cx[i] + dx, GROUND_Y + top - EMBER_SIZE * 0.2, Layout.cz[i] + dz)
	ember.Parent = folder
end

-- ===== cells =====

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

local function partsOf(i: number): number
	local b, w = blocksOf[i], wedgesOf[i]
	return (if b ~= nil then #b else 0) + (if w ~= nil then #w else 0)
end

local function isActive(i: number): boolean
	return nearRange.active[chunkOf[i]] == true
end

-- Give every piece of cell i back to the pools (and hand freed room to a cell that waited).
local function releaseCell(i: number)
	local b, w = blocksOf[i], wedgesOf[i]
	local freed = 0
	if b ~= nil then
		for _, p in b do
			giveBlock(p)
		end
		freed += #b
		blocksOf[i] = nil
	end
	if w ~= nil then
		for _, p in w do
			giveWedge(p)
		end
		freed += #w
		wedgesOf[i] = nil
	end
	nearParts -= freed
	sigOf[i] = nil
	shownLevel[i] = nil
	dropAnim(i)
	dropEmber(i)
	if freed > 0 then
		-- room again: wake a cell that waited (skip ones that left the range)
		while #starved > 0 do
			local waiting = table.remove(starved) :: number
			isStarved[waiting] = nil
			if isActive(waiting) then
				queue.push(waiting)
				break
			end
		end
	end
end

-- Wake up to `count` waiting cells while there is room (pieces also come back when cells get
-- simpler, not only when they are released).
local function wakeStarved(count: number)
	local woken = 0
	while woken < count and #starved > 0 and nearParts < NEAR_CAP - AshShape.MAX_PIECES do
		local waiting = table.remove(starved) :: number
		isStarved[waiting] = nil
		if isActive(waiting) then
			queue.push(waiting)
			woken += 1
		end
	end
end

local function starve(i: number)
	if not isStarved[i] then
		isStarved[i] = true
		table.insert(starved, i)
	end
end

-- Start (or retarget) cell i's height animation. False when too many are running.
local function startAnim(i: number, from: number, to: number, clearing: boolean): boolean
	local a = anims[i]
	if a == nil then
		if animCount >= MAX_ANIMS then
			return false
		end
		a = { t = 0, from = from, to = to, clearing = clearing }
		anims[i] = a
		animCount += 1
	end
	local anim = a :: Anim
	anim.t, anim.from, anim.to, anim.clearing = 0, from, to, clearing
	return true
end

-- Re-height cell i's pieces (blocks and diamond only, unless `all`).
local function scaleCell(i: number, scale: number, all: boolean)
	local b = blocksOf[i]
	if b ~= nil then
		for _, p in b do
			scaleHeight(p, scale, false)
		end
	end
	local w = wedgesOf[i]
	if all and w ~= nil then
		for _, p in w do
			scaleHeight(p, scale, true)
		end
	end
end

-- Bring cell i's pieces in line with the levels around it and the range.
local function refresh(i: number)
	if not isActive(i) then
		shrinkHint[i] = nil
		if blocksOf[i] ~= nil or wedgesOf[i] ~= nil then
			releaseCell(i)
		end
		return
	end
	local a = anims[i]
	if a ~= nil and a.clearing then
		return -- sinking away; refreshed again when the sink ends
	end
	local hint = shrinkHint[i] == true
	shrinkHint[i] = nil
	local level = levels[i]
	local isGold = golden[i] == true and level > 0
	local sig = AshShape.signature(i, levels, DIR, MAX_LEVEL, isGold)
	if sigOf[i] == sig then
		return
	end
	local was = shownLevel[i] or 0

	-- swept: the old pieces sink into the ground first, the corner fillets come after
	if level == 0 and hint and was > 0 and partsOf(i) > 0 and startAnim(i, 1, 0, true) then
		sigOf[i] = nil
		dropEmber(i)
		return
	end

	local n = AshShape.pieces(
		pieceBuf,
		i,
		levels,
		DIR,
		Layout.cx[i],
		Layout.cz[i],
		CELL,
		MAX_LEVEL,
		parity[i],
		isGold
	)
	local needW = 0
	for k = 0, n - 1 do
		if pieceBuf[k * STRIDE + 1] == KIND_WEDGE then
			needW += 1
		end
	end
	local needB = n - needW
	local have = partsOf(i)
	if nearParts - have + n > NEAR_CAP then
		-- over budget: this (far) cell keeps what it has and waits until another cell gives
		-- Parts back
		starve(i)
		return
	end
	dropAnim(i)

	local blocks = blocksOf[i] or {}
	local wedges = wedgesOf[i] or {}
	while #blocks < needB do
		table.insert(blocks, takeBlock())
		nearParts += 1
	end
	while #blocks > needB do
		giveBlock(table.remove(blocks) :: Part)
		nearParts -= 1
	end
	while #wedges < needW do
		table.insert(wedges, takeWedge())
		nearParts += 1
	end
	while #wedges > needW do
		giveWedge(table.remove(wedges) :: WedgePart)
		nearParts -= 1
	end
	blocksOf[i] = if needB > 0 then blocks else nil
	wedgesOf[i] = if needW > 0 then wedges else nil

	local bi, wi = 0, 0
	for k = 0, n - 1 do
		local o = k * STRIDE
		local kind = pieceBuf[o + 1]
		local x, z, pa, pb = pieceBuf[o + 2], pieceBuf[o + 3], pieceBuf[o + 4], pieceBuf[o + 5]
		local top, plevel = pieceBuf[o + 6], pieceBuf[o + 7]
		if kind == KIND_WEDGE then
			wi += 1
			local w = wedges[wi]
			placeWedge(w, x, z, pa, pb, pieceBuf[o + 8], top)
			w.Color = ashColor(i, plevel)
			partTop[w] = top
			w.Parent = folder
		else
			bi += 1
			local p = blocks[bi]
			placeBlock(p, x, z, pa, pb, top, kind == KIND_DIAMOND)
			if isGold then
				if not partGold[p] then
					partGold[p] = true
					p.Material = Enum.Material.Neon
					p.Color = GOLD_A
				end
			else
				if partGold[p] then
					partGold[p] = nil
					p.Material = ASH_MATERIAL
				end
				p.Color = ashColor(i, plevel)
			end
			partTop[p] = top
			p.Parent = folder
		end
	end
	sigOf[i] = sig
	shownLevel[i] = level

	-- scraped thinner: the layer sinks from the old height instead of snapping
	if hint and level > 0 and was > level and needB > 0 then
		local from = AshShape.thickness(was, MAX_LEVEL) / AshShape.thickness(level, MAX_LEVEL)
		if startAnim(i, from, 1, false) then
			scaleCell(i, from, false)
		end
	end
	updateEmber(i)
end

local function stepAnims(dt: number)
	if animCount == 0 then
		return
	end
	local done: { number }? = nil
	for i, a in anims do
		a.t += dt / ANIM_TIME
		local k = math.min(a.t, 1)
		local e = k * (2 - k) -- ease out
		scaleCell(i, a.from + (a.to - a.from) * e, a.clearing)
		if k >= 1 then
			done = done or {}
			table.insert(done :: { number }, i)
		end
	end
	if done ~= nil then
		for _, i in done do
			local a = anims[i]
			dropAnim(i)
			if a ~= nil and a.clearing then
				-- the sunk pieces go; the cell is rebuilt from its current level (fillets only)
				releaseCell(i)
				queue.push(i)
			end
		end
	end
end

-- Queue cell i and its in-range neighbours (their corners depend on i's level).
-- `drop`: i's level went down, so i sinks smoothly instead of snapping.
local function pushAround(i: number, drop: boolean)
	if isActive(i) then
		if drop then
			shrinkHint[i] = true
		end
		queue.push(i)
	end
	local base = (i - 1) * 8
	for s = 1, 8 do
		local j = DIR[base + s]
		if j ~= 0 and isActive(j) then
			queue.push(j)
		end
	end
end

-- ===== far tiles =====

local function releaseTiles(c: number)
	local list = tilesOf[c]
	if list ~= nil then
		for _, p in list do
			giveBlock(p)
		end
		farParts -= #list
		tilesOf[c] = nil
	end
	tileSig[c] = nil
end

local function refreshFar(c: number)
	local show = farRange.active[c] == true and not nearRange.active[c]
	local level, lean = 0, 1
	if show then
		show, level, lean = AshShape.farLook(chAsh[c], #CH.cells[c], chSum[c], MAX_LEVEL)
	end
	if not show then
		releaseTiles(c)
		return
	end
	local sig = level * 1000 + math.floor(lean * 100 + 0.5)
	if tileSig[c] == sig then
		return
	end
	local runs = CH.runs[c]
	local need = #runs // 4
	local list = tilesOf[c] or {}
	if farParts - #list + need > FAR_CAP then
		releaseTiles(c)
		return
	end
	while #list < need do
		table.insert(list, takeBlock())
		farParts += 1
	end
	tilesOf[c] = list
	local top = AshShape.thickness(level, MAX_LEVEL) + CH.parity[c] * FAR_PARITY - FAR_DROP
	local r, g, b =
		AshShape.mix(chunkR[c], chunkG[c], chunkB[c], groundR[c], groundG[c], groundB[c], lean)
	r, g, b = AshShape.depthShade(r, g, b, level, MAX_LEVEL)
	local color = Color3.fromRGB(r, g, b)
	local ov = AshShape.OVERLAP
	for k = 1, need do
		local o = (k - 1) * 4
		local p = list[k]
		placeBlock(
			p,
			runs[o + 1],
			runs[o + 2],
			runs[o + 3] + 2 * ov,
			runs[o + 4] + 2 * ov,
			top,
			false
		)
		p.Color = color
		p.Parent = folder
	end
	tileSig[c] = sig
end

-- Keep the per-chunk totals in step with a level change.
local function noteLevel(i: number, was: number, now: number)
	local c = chunkOf[i]
	if was > 0 then
		chAsh[c] -= 1
	end
	if now > 0 then
		chAsh[c] += 1
	end
	chSum[c] += now - was
	if farRange.active[c] and not nearRange.active[c] then
		farQueue.push(c)
	end
end

local function pushChunkCells(c: number)
	for _, i in CH.cells[c] do
		queue.push(i)
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
			local was = levels[i]
			levels[i] = v
			noteLevel(i, was, v)
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
		if isActive(i) then
			queue.push(i)
		end
	end
end)

Net.on("AshDelta", function(flat: any)
	CullLogic.applyDelta(levels, flat, N, MAX_LEVEL, function(i: number, was: number, now: number)
		if now == 0 then
			setGolden(i, false) -- gold ends when the cell is empty (the look is fixed by refresh)
		end
		noteLevel(i, was, now)
		pushAround(i, now < was)
		if now == 0 and isActive(i) then
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
			if isActive(i) then
				queue.push(i)
			end
		end
		return
	end
	local t = os.clock() * 4
	for i in golden do
		local b = blocksOf[i]
		if b ~= nil then
			local color = GOLD_A:Lerp(GOLD_B, 0.5 + 0.5 * math.sin(t + i * 0.7))
			for _, p in b do
				if partGold[p] then
					p.Color = color
				end
			end
		end
	end
end

-- ===== frame loop =====

RunService.Heartbeat:Connect(function(dt: number)
	local x, z = centre()
	if x ~= nil and z ~= nil then
		local inNear, outNear =
			CullLogic.update(CH, nearRange, x, z, NEAR_RADIUS, NEAR_MARGIN, MIN_MOVE)
		local inFar, outFar = CullLogic.update(CH, farRange, x, z, FAR_RADIUS, FAR_MARGIN, MIN_MOVE)
		for _, c in outNear do
			pushChunkCells(c)
			farQueue.push(c)
		end
		for _, c in inNear do
			pushChunkCells(c)
			farQueue.push(c)
		end
		for _, c in outFar do
			farQueue.push(c)
		end
		for _, c in inFar do
			farQueue.push(c)
		end
	end
	if #starved > 0 then
		wakeStarved(8)
	end
	if queue.size() > 0 then
		local t0 = os.clock()
		CullLogic.drain(queue, MAX_UPDATES_PER_FRAME, function(i: number): boolean?
			refresh(i)
			return os.clock() - t0 < FRAME_BUDGET
		end)
	end
	if farQueue.size() > 0 then
		CullLogic.drain(farQueue, MAX_FAR_PER_FRAME, function(c: number): boolean?
			refreshFar(c)
			return true
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

-- The layer's colour at a world point ("#RRGGBB"), for dust that should match it; nil off the ash.
function AshRenderer.layerHex(x: number, z: number): string?
	local i = Layout.cellOf(x, z)
	if i == nil then
		return nil
	end
	return string.format("#%02X%02X%02X", baseR[i], baseG[i], baseB[i])
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

-- Parts currently drawn: detail pieces + far tiles + ember specks (for debugging; <= PART_CAP).
function AshRenderer.partCount(): number
	return nearParts + farParts + emberCount
end

AshRenderer.PART_CAP = PART_CAP

return AshRenderer
