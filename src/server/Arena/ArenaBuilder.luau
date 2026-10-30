--!strict
-- Turns a compiled layout into graybox parts in Workspace.Arena, with the tags the other pieces
-- read (see Config.Tags): BlocksShots, LowCover, Roof, Interior, ArenaSpawn, ContainerSpot,
-- FinalZoneRegion. Collision geometry is simple boxes; roofs never collide or get hit by rays.
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Layout = require("./Layout")

local Tags = Config.Tags
local Pal = Config.Palette

-- Which solids a fighter can hop over, if they are low enough (Config.Vault.maxHeight).
local VAULT_KINDS: { [string]: boolean } = { cover = true, rail = true, fence = true }

local ArenaBuilder = {}

export type Built = { folder: Folder, layout: Layout.Layout }

local GROUND = {
	sidewalk = Pal.Pavement,
	road = "#2E3B4E",
	park = Pal.ParkGreen,
	alley = "#566175",
	lot = "#A49476",
	floor = "#66728A",
}
-- Visual layers sit a hair above each other so flat tops never fight.
local LAYER = { sidewalk = 0, lot = 0.05, park = 0.05, alley = 0.08, road = 0.1, floor = 0.12 }

local SOLID = {
	mass = "#3F5878",
	wall = "#E3E8EF",
	partition = "#CBD3DE",
	cover = "#B98558",
	prop = "#4E7A3A",
	water = "#4E9BC9",
	fence = "#DCE3EA",
	boundary = Pal.Navy,
}

local function part(
	parent: Instance,
	name: string,
	x0: number,
	z0: number,
	x1: number,
	z1: number
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = true
	p.Size = Vector3.new(x1 - x0, 1, z1 - z0)
	p.Position = Vector3.new((x0 + x1) / 2, 0.5, (z0 + z1) / 2)
	p.Parent = parent
	return p
end

local function setY(p: Part, bottom: number, height: number)
	p.Size = Vector3.new(p.Size.X, height, p.Size.Z)
	p.Position = Vector3.new(p.Position.X, bottom + height / 2, p.Position.Z)
end

local function visualOnly(p: Part)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end

local function solidColor(s: Layout.Solid): string
	if s.kind == "cover" then
		if string.sub(s.id, 1, 5) == "hedge" then
			return "#5E8244"
		elseif s.h >= 5 then
			return "#D8714B"
		end
	end
	return SOLID[s.kind] or "#8794A6"
end

function ArenaBuilder.destroyExisting()
	local old = Workspace:FindFirstChild(Config.Workspace.ArenaFolder)
	if old then
		old:Destroy()
	end
end

function ArenaBuilder.build(layout: Layout.Layout): Built
	ArenaBuilder.destroyExisting()
	local root = Instance.new("Folder")
	root.Name = Config.Workspace.ArenaFolder
	root:SetAttribute("LayoutId", layout.id)

	local function folder(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		return f
	end
	local groundF, solidsF, roofsF, markersF =
		folder("Ground"), folder("Solids"), folder("Roofs"), folder("Markers")

	-- ground: one thick walkable slab, then thin visual layers on top
	local half = layout.half
	local base = part(groundF, "Base", -half - 4, -half - 4, half + 4, half + 4)
	setY(base, -4, 4)
	base.Color = Color3.fromHex(Pal.Pavement)
	for _, g in layout.ground do
		if g.kind == "sidewalk" then
			continue
		end
		local p = part(groundF, g.id, g.x0, g.z0, g.x1, g.z1)
		setY(p, 0, LAYER[g.kind] or 0.05)
		p.Color = Color3.fromHex(GROUND[g.kind] or "#888888")
		visualOnly(p)
		if g.kind == "floor" then
			CollectionService:AddTag(p, Tags.Interior)
			p:SetAttribute("Building", string.sub(g.id, 1, -7)) -- "<id>-floor"
		end
	end

	-- walls, cover, fences, boundary
	for _, s in layout.solids do
		local p = part(solidsF, s.id, s.x0, s.z0, s.x1, s.z1)
		setY(p, 0, s.h)
		p.Color = Color3.fromHex(solidColor(s))
		p.CanCollide = s.blocksMove
		if s.kind == "boundary" then
			p.Transparency = 1
		elseif s.kind == "fence" then
			p.Transparency = 0.35
		end
		if s.blocksShots then
			CollectionService:AddTag(p, Tags.BlocksShots)
		elseif s.blocksMove then
			CollectionService:AddTag(p, Tags.LowCover)
		end
		if VAULT_KINDS[s.kind] and s.h <= Config.Vault.maxHeight then
			CollectionService:AddTag(p, Tags.Vaultable) -- low enough to hop over (piece 45)
		end
		if s.occluder then
			CollectionService:AddTag(p, Config.Arena.occluderTag)
			p:SetAttribute("OccluderKind", if s.kind == "mass" then "mass" else "wall")
			p:SetAttribute("Building", s.building)
		end
	end

	-- roofs: visual only (CanQuery off keeps rays and shots from ever touching them)
	for _, r in layout.roofs do
		local p = part(roofsF, r.id, r.x0, r.z0, r.x1, r.z1)
		setY(p, r.h, 1)
		p.Color = Color3.fromHex("#2A3F5C")
		visualOnly(p)
		CollectionService:AddTag(p, Tags.Roof)
		CollectionService:AddTag(p, Config.Arena.occluderTag)
		p:SetAttribute("OccluderKind", "roof")
		p:SetAttribute("Building", r.building)
	end

	-- markers other pieces read: spawn pads, crate spots (bottom face on the floor), last ring
	for _, sp in layout.spawns do
		local p = part(markersF, sp.id, sp.x - 2, sp.z - 2, sp.x + 2, sp.z + 2)
		setY(p, 0.12, 0.2)
		p.Color = Color3.fromHex(Pal.Cyan)
		p.Transparency = 0.5
		visualOnly(p)
		CollectionService:AddTag(p, Tags.Spawn)
	end
	for _, c in layout.containers do
		local p = part(markersF, c.id, c.x - 2, c.z - 2, c.x + 2, c.z + 2)
		setY(p, 0.12, 0.2)
		p.Color = Color3.fromHex(Pal.RewardGold)
		p.Transparency = 0.6
		visualOnly(p)
		CollectionService:AddTag(p, Tags.ContainerSpot)
	end
	local lastRadius = Config.Zone.stages[#Config.Zone.stages].targetRadius
	local ring = Instance.new("Part")
	ring.Name = "FinalZoneRegion"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.Orientation = Vector3.new(0, 0, 90)
	ring.Size = Vector3.new(0.2, lastRadius * 2, lastRadius * 2)
	ring.Position = Vector3.new(Config.Zone.centerX, 0.15, Config.Zone.centerZ)
	ring.Transparency = 1
	visualOnly(ring)
	ring:SetAttribute("Radius", lastRadius)
	ring.Parent = markersF
	CollectionService:AddTag(ring, Tags.FinalZoneRegion)

	root.Parent = Workspace
	return { folder = root, layout = layout }
end

return ArenaBuilder
