--!strict
-- Street props that burst (piece 43, carter picked "A Chunk Burst"). Cars, dumpsters, planters,
-- benches and barriers are solids of the arena. Shots and blasts hurt them (the server owns the
-- health); when one breaks:
--   * its solid stops being solid: nobody collides with it and shots fly through (no tags, no query),
--   * the art parts that dress it are taken off the street (kept, so the next match can put them back),
--   * a scorch mark and a few small blocks stay on the ground until the arena is rebuilt or reset,
--   * every client gets `PropBroken` so it can throw the chunks (cosmetic only).
--
-- Whoever lands a shot or blast calls (after THEY checked range, walls and ammo):
--   BreakSystem.damage(hitPart, amount, sourceId, matchId) -> true when hitPart is a street prop
-- `amount` is the weapon's own number, never anything from a client. Nothing happens unless a combat
-- phase is running, the match is current and the source is alive. Props come back at the next Spawning.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BreakRules = require(Shared.Breakables.BreakRules)

local Net = require(script.Parent.Parent.Core.Net)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)
local Participants = require(script.Parent.Parent.Core.Participants)
local StreetArt = require(script.Parent.Parent.Arena.StreetArt)

local BreakSystem = {}
BreakSystem.order = 125

local tags = Config.Tags

type Held = { part: Instance, parent: Instance }
type Record = {
	id: string,
	kind: string,
	body: BasePart,
	art: { Held },
	canCollide: boolean,
	hadShots: boolean,
	hadLow: boolean,
	rubble: { Instance },
}

local book: BreakRules.Book = BreakRules.new(Config.Breakables.kinds)
local byBody: { [Instance]: Record } = {}
local registeredFor: Instance? = nil

local function arenaFolder(): Folder?
	local f = Workspace:FindFirstChild(Config.Workspace.ArenaFolder)
	return if f and f:IsA("Folder") then f else nil
end

-- Puts one prop back the way the arena built it.
local function restore(rec: Record)
	local body = rec.body
	if body.Parent == nil then
		return
	end
	body.CanCollide = rec.canCollide
	body.CanQuery = true
	if rec.hadShots then
		CollectionService:AddTag(body, tags.BlocksShots)
	end
	if rec.hadLow then
		CollectionService:AddTag(body, tags.LowCover)
	end
	CollectionService:AddTag(body, tags.Breakable)
	body:SetAttribute("Broken", nil)
	for _, h in rec.art do
		h.part.Parent = h.parent
	end
	for _, r in rec.rubble do
		r:Destroy()
	end
	table.clear(rec.rubble)
end

local function restoreAll()
	for _, rec in byBody do
		if BreakRules.isBroken(book, rec.id) then
			restore(rec)
		end
	end
	BreakRules.reset(book)
end

local function clear()
	for body in byBody do
		CollectionService:RemoveTag(body, tags.Breakable)
	end
	table.clear(byBody)
	book = BreakRules.new(Config.Breakables.kinds)
	registeredFor = nil
end

-- Finds every prop in the arena that was built. Called at Spawning, after the map is chosen.
local function register()
	local folder = arenaFolder()
	if folder == nil or not Config.Breakables.enabled then
		clear()
		return
	end
	if registeredFor == folder then
		restoreAll() -- the same arena plays again: everything comes back
		return
	end
	clear()
	registeredFor = folder
	local solids = folder:FindFirstChild("Solids")
	if solids == nil then
		return
	end
	-- the art parts of each solid, found once
	local artOf: { [string]: { Held } } = {}
	local art = folder:FindFirstChild("Art")
	if art ~= nil then
		for _, inst in art:GetDescendants() do
			local owner = inst:GetAttribute("ArtOwner")
			if typeof(owner) == "string" and inst.Parent ~= nil then
				local list = artOf[owner]
				if list == nil then
					list = {}
					artOf[owner] = list
				end
				table.insert(list :: { Held }, { part = inst, parent = inst.Parent })
			end
		end
	end
	for _, inst in solids:GetChildren() do
		if not inst:IsA("BasePart") then
			continue
		end
		local kind = StreetArt.classify(inst.Name)
		-- buildings and big masses never burst, whatever their name says
		if
			kind == nil
			or Config.Breakables.kinds[kind] == nil
			or inst:GetAttribute("OccluderKind") ~= nil
		then
			continue
		end
		-- only solids the art redraws (the gray box is invisible): a visible gray box would just vanish
		if artOf[inst.Name] == nil and inst.Transparency < 1 then
			continue
		end
		if BreakRules.register(book, inst.Name, kind) then
			byBody[inst] = {
				id = inst.Name,
				kind = kind,
				body = inst,
				art = artOf[inst.Name] or {},
				canCollide = inst.CanCollide,
				hadShots = CollectionService:HasTag(inst, tags.BlocksShots),
				hadLow = CollectionService:HasTag(inst, tags.LowCover),
				rubble = {},
			}
			CollectionService:AddTag(inst, tags.Breakable)
		end
	end
end

local function rubbleFolder(): Folder?
	local folder = arenaFolder()
	if folder == nil then
		return nil
	end
	local r = folder:FindFirstChild("Rubble")
	if r ~= nil and r:IsA("Folder") then
		return r
	end
	local made = Instance.new("Folder")
	made.Name = "Rubble"
	made.Parent = folder
	return made
end

local function dominantColor(rec: Record): Color3
	for _, h in rec.art do
		local part = h.part
		if
			part:IsA("BasePart")
			and part.Transparency < 0.5
			and part.Material ~= Enum.Material.Rubber
		then
			return part.Color
		end
	end
	return Color3.fromHex("#8794A6")
end

local function paintOnly(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

local function leaveRubble(rec: Record, color: Color3)
	local parent = rubbleFolder()
	if parent == nil then
		return
	end
	local body = rec.body
	local pos, size = body.Position, body.Size
	local cfg = Config.Breakables.rubble
	local box: BreakRules.Box = {
		x0 = pos.X - size.X / 2,
		z0 = pos.Z - size.Z / 2,
		x1 = pos.X + size.X / 2,
		z1 = pos.Z + size.Z / 2,
		h = size.Y,
	}
	local floorY = pos.Y - size.Y / 2
	local scorch = Instance.new("Part")
	scorch.Name = "Scorch"
	scorch.Shape = Enum.PartType.Cylinder
	local diameter = math.max(size.X, size.Z) * 0.9
	scorch.Size = Vector3.new(0.06, diameter, diameter)
	scorch.CFrame = CFrame.new(pos.X, floorY + 0.12, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	scorch.Color = Color3.fromHex(cfg.scorchColor)
	scorch.Transparency = 1 - cfg.scorchAlpha
	scorch.Material = Enum.Material.SmoothPlastic
	scorch.CastShadow = false
	paintOnly(scorch)
	scorch.Parent = parent
	table.insert(rec.rubble, scorch)

	local palette =
		{ color, color:Lerp(Color3.new(0, 0, 0), 0.55), color:Lerp(Color3.new(1, 1, 1), 0.3) }
	for _, piece in
		BreakRules.rubble(box, BreakRules.seedOf(rec.id), cfg.pieces, cfg.minSize, cfg.maxSize)
	do
		local p = Instance.new("Part")
		p.Name = "Rubble"
		p.Size = Vector3.new(piece.sx, piece.sy, piece.sz)
		p.CFrame = CFrame.new(pos.X + piece.dx, floorY + piece.sy / 2 + 0.1, pos.Z + piece.dz)
			* CFrame.Angles(0, math.rad(piece.ry), 0)
		p.Color = palette[1 + math.floor(piece.pick * #palette) % #palette]
		p.Material = Enum.Material.SmoothPlastic
		p.CastShadow = false
		paintOnly(p)
		p.Parent = parent
		table.insert(rec.rubble, p)
	end
end

local function breakProp(rec: Record)
	local body = rec.body
	local color = dominantColor(rec)
	local pos, size = body.Position, body.Size
	-- not a solid any more
	body.CanCollide = false
	body.CanQuery = false
	body:SetAttribute("Broken", true)
	CollectionService:RemoveTag(body, tags.BlocksShots)
	CollectionService:RemoveTag(body, tags.LowCover)
	CollectionService:RemoveTag(body, tags.Breakable)
	for _, h in rec.art do
		h.part.Parent = nil
	end
	leaveRubble(rec, color)
	Net.fireAll("PropBroken", {
		id = rec.id,
		kind = rec.kind,
		x = pos.X,
		y = pos.Y,
		z = pos.Z,
		sx = size.X,
		sy = size.Y,
		sz = size.Z,
		color = color:ToHex(),
	})
end

function BreakSystem.damage(
	hit: Instance,
	amount: number,
	sourceId: string?,
	matchId: number?
): boolean
	local rec = byBody[hit]
	if rec == nil then
		return false
	end
	-- It IS a street prop, so the shot stops here. Whether it hurts is decided below.
	local current = MatchContext:getMatchId()
	if
		not MatchContext:isCombat()
		or (matchId ~= nil and matchId ~= current)
		or sourceId == nil
		or not Participants:isAlive(sourceId)
	then
		return true
	end
	if BreakRules.damage(book, rec.id, amount) then
		breakProp(rec)
	end
	return true
end

-- A blast at `center` (flat, y ignored) of `radius` studs. Every prop whose edge is inside the
-- radius takes `damage` scaled by how near it is. `lineClear(part)` says whether the blast can see it.
function BreakSystem.blast(
	center: Vector3,
	radius: number,
	damage: number,
	sourceId: string?,
	matchId: number?,
	lineClear: (part: BasePart) -> boolean
)
	local minFactor = Config.Breakables.blastMinFactor
	for _, inst in CollectionService:GetTagged(tags.Breakable) do
		local rec = byBody[inst]
		if rec == nil then
			continue
		end
		local body = rec.body
		local p, s = body.Position, body.Size
		local d = BreakRules.edgeDistance(center.X, center.Z, {
			x0 = p.X - s.X / 2,
			z0 = p.Z - s.Z / 2,
			x1 = p.X + s.X / 2,
			z1 = p.Z + s.Z / 2,
			h = s.Y,
		})
		local factor = BreakRules.blastFactor(d, radius, minFactor)
		if factor > 0 and lineClear(body) then
			BreakSystem.damage(body, damage * factor, sourceId, matchId)
		end
	end
end

function BreakSystem.start()
	MatchContext.PhaseChanged:connect(function(phase: string)
		if phase == "Spawning" then
			register()
		end
	end)
	-- The arena of the first match is built before any phase change reaches us.
	register()
end

return BreakSystem
