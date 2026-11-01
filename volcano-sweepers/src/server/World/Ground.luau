--!strict
-- Ground, sea, foam, zone rings, glowing boundary ropes and the invisible wall.
--
-- Walking is on ONE big invisible disc whose top is exactly y = groundY (few big parts, cheap
-- physics). The pretty zone colours are flat non-colliding blocks laid on top of it, also with
-- their top at groundY, so the ash cells sit on a perfectly flat surface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local WorldPlan = require(Shared.WorldPlan)
local Zones = require(Shared.Catalog.Zones)

local WorldUtil = require(script.Parent.WorldUtil)

local Ground = {}

export type Refs = {
	foam: BasePart,
	foamOuter: BasePart,
}

local GROUND_MATERIAL: { [number]: Enum.Material } = {
	[1] = Enum.Material.Sand,
	[2] = Enum.Material.Grass,
	[3] = Enum.Material.SmoothPlastic,
	[4] = Enum.Material.Concrete,
	[5] = Enum.Material.Slate,
}

local function segCF(seg: WorldPlan.Seg, y: number): CFrame
	local p = Vector3.new(seg.x, y, seg.z)
	return CFrame.lookAt(p, p + Vector3.new(seg.dx, 0, seg.dz))
end

function Ground.build(root: Instance, plan: WorldPlan.Plan): Refs
	local gy = Config.World.groundY
	local folder = Instance.new("Folder")
	folder.Name = "Ground"
	local sea = Instance.new("Folder")
	sea.Name = "Sea"
	local ropes = Instance.new("Folder")
	ropes.Name = "BoundaryRopes"
	local wall = Instance.new("Folder")
	wall.Name = "Bounds"

	local zones = Config.World.zones
	local lastZone = zones[#zones]
	local islandRadius = plan.outerRadius

	-- ===== sea =====
	-- about 520 studs of sea past the beach (a Part can be at most 2048 studs across)
	local seaR = math.min(1016, islandRadius + 520)
	WorldUtil.disc(sea, "SeaFloor", 0, gy - 7, 0, seaR + 4, 2, "#58C7D6", { collide = true })
	WorldUtil.disc(
		sea,
		"Water",
		0,
		gy - 1.2,
		0,
		seaR,
		0.5,
		"#3FB6F2",
		{ transparency = 0.4, reflectance = 0.12 }
	)
	local foamOuter = WorldUtil.disc(
		sea,
		"FoamOuter",
		0,
		gy - 1.0,
		0,
		islandRadius + 16,
		0.3,
		"#F4FBFF",
		{ transparency = 0.55 }
	)
	local foam = WorldUtil.disc(
		sea,
		"Foam",
		0,
		gy - 0.85,
		0,
		islandRadius + 9,
		0.3,
		"#F4FBFF",
		{ transparency = 0.15 }
	)
	WorldUtil.disc(sea, "WetSand", 0, gy - 0.55, 0, islandRadius + 3.5, 4, "#DCC08A")
	WorldUtil.disc(sea, "SandUnder", 0, gy - 0.25, 0, islandRadius + 0.8, 4, Zones.byId[1].ground)

	-- ===== walking surface (invisible, solid) =====
	WorldUtil.disc(folder, "GroundCollision", 0, gy, 0, islandRadius + 2.5, 4, "#FFFFFF", {
		collide = true,
		transparency = 1,
	})

	-- ===== zone colours =====
	for _, ring in plan.rings do
		local zone = Zones.byId[ring.zoneId]
		local width = ring.outer - ring.inner
		local material = GROUND_MATERIAL[ring.zoneId] or Enum.Material.SmoothPlastic
		for _, seg in ring.segs do
			WorldUtil.block(
				folder,
				`Zone{ring.zoneId}Ground`,
				segCF(seg, gy - 0.25),
				Vector3.new(width, 0.5, seg.len + 0.5),
				zone.ground,
				{ material = material }
			)
		end
	end
	-- the Lava Heart is one dark glossy disc
	local heart = Zones.byId[lastZone.id]
	WorldUtil.disc(folder, "Zone5Ground", 0, gy, 0, lastZone.outer, 0.5, heart.ground, {
		material = GROUND_MATERIAL[5],
		reflectance = 0.15,
	})

	-- ===== glowing lines on every ring boundary =====
	for _, rope in plan.ropes do
		local color = WorldUtil.zoneAccent[rope.zoneId] or "#FFFFFF"
		for _, seg in rope.segs do
			WorldUtil.block(
				ropes,
				`Rope{rope.zoneId}`,
				segCF(seg, gy + 0.09),
				Vector3.new(1.5, 0.18, seg.len + 0.3),
				color,
				{ material = Enum.Material.Neon }
			)
		end
	end

	-- ===== invisible wall so nobody leaves the island =====
	for _, seg in plan.wall do
		WorldUtil.block(
			wall,
			"Wall",
			segCF(seg, gy + 40),
			Vector3.new(4, 80, seg.len + 4),
			"#FFFFFF",
			{
				collide = true,
				transparency = 1,
			}
		)
	end

	sea.Parent = root
	folder.Parent = root
	ropes.Parent = root
	wall.Parent = root
	return { foam = foam, foamOuter = foamOuter }
end

return Ground
