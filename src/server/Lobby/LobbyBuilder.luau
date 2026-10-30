--!strict
-- Builds the lobby plaza (graybox) in Workspace.Lobby from shared/LobbyLayout. Nothing here is gameplay:
-- no damage, no shooting. The tags other pieces look for:
--   LobbySpawn      the one part where waiting players stand (piece 05 uses it, and results land here)
--   LobbyStation    each pad; attribute "Station" = loadout | play | settings | rewards
--   LeaderboardSpot where the top-wins board stands (leaderboard piece)
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local LobbyLayout = require(Shared.LobbyLayout)
local GridLines = require(Shared.GridLines)

local LobbyBuilder = {}

LobbyBuilder.folderName = "Lobby"
LobbyBuilder.tags = {
	spawn = "LobbySpawn",
	station = "LobbyStation",
	leaderboard = "LeaderboardSpot",
}

local PAL = Config.Palette
local CREAM = "#FFF4D6"
local WALL = "#28486B"
local WALL2 = "#335A85"
local FONT = Enum.Font.FredokaOne

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local function block(
	parent: Instance,
	name: string,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	collide: boolean?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(sx, sy, sz)
	p.Position = Vector3.new(cx, cy, cz)
	p.Color = hex(color)
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = collide ~= false
	p.Parent = parent
	return p
end

-- A box from a layout Box ({ x, z, w, d, h }, top-left corner) standing on the ground.
local function layoutBlock(parent: Instance, name: string, box: { number }, color: string): Part
	local x, z, w, d, h = box[1], box[2], box[3], box[4], box[5]
	local wx, wz = LobbyLayout.toWorld(x + w / 2, z + d / 2)
	return block(parent, name, wx, h / 2, wz, w, h, d, color)
end

-- Words on the face the camera sees (+Z is toward the camera, so that is the part's Back face).
local function sign(
	parent: Instance,
	text: string,
	cx: number,
	cy: number,
	zFace: number,
	w: number,
	h: number,
	fill: string,
	ink: string
): Part
	local plate = block(parent, "Sign_" .. text, cx, cy, zFace + 0.25, w, h, 0.5, fill, false)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.Parent = plate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = FONT
	label.TextScaled = true
	label.TextColor3 = hex(ink)
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = label
	return plate
end

local function disc(
	parent: Instance,
	name: string,
	cx: number,
	cy: number,
	cz: number,
	diameter: number,
	thickness: number,
	color: string
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.Size = Vector3.new(thickness, diameter, diameter) -- a cylinder's axis is X, so it is turned to stand on the floor
	p.CFrame = CFrame.new(cx, cy, cz) * CFrame.Angles(0, 0, math.rad(90))
	p.Color = hex(color)
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.Parent = parent
	return p
end

local function ball(
	parent: Instance,
	name: string,
	cx: number,
	cy: number,
	cz: number,
	d: number,
	color: string
): Part
	local p = block(parent, name, cx, cy, cz, d, d, d, color, false)
	p.Shape = Enum.PartType.Ball
	return p
end

local function buildGround(root: Folder)
	local w, d = LobbyLayout.width, LobbyLayout.depth
	local ox, oz = LobbyLayout.origin.x, LobbyLayout.origin.z
	block(root, "Ground", ox, -1, oz, w, 2, d, PAL.Pavement)

	-- Crosswalk stripes, just for the look.
	local count = math.floor(w / 13)
	for i = 0, count - 1 do
		local x, z = LobbyLayout.toWorld(10 + i * 13, LobbyLayout.depth * 0.5)
		local stripe = block(root, "Stripe", x, 0.05, z, 7, 0.1, 1.6, CREAM, false)
		stripe.Transparency = 0.6
	end

	-- Invisible walls keep everyone on the plaza.
	local t, wallH = 6, 60
	local function wall(name: string, cx: number, cz: number, sx: number, sz: number)
		local p = block(root, name, cx, wallH / 2, cz, sx, wallH, sz, WALL, true)
		p.Transparency = 1
		p.CanQuery = false
		p.CastShadow = false
	end
	wall("WallNorth", ox, oz - d / 2 - t / 2, w + 2 * t, t)
	wall("WallSouth", ox, oz + d / 2 + t / 2, w + 2 * t, t)
	wall("WallWest", ox - w / 2 - t / 2, oz, t, d)
	wall("WallEast", ox + w / 2 + t / 2, oz, t, d)
end

-- Glowing cyan grid lines lying on the plaza floor (the synthwave floor from video 3). Paint only:
-- no collision, no queries, no shadows. Pads and the spawn block sit above them.
local function buildGrid(root: Folder)
	local g = Config.Art.lobbyGrid
	if not g.enabled then
		return
	end
	local w, d = LobbyLayout.width, LobbyLayout.depth
	local ox, oz = LobbyLayout.origin.x, LobbyLayout.origin.z
	local folder = Instance.new("Folder")
	folder.Name = "Grid"
	folder.Parent = root
	local function line(name: string, cx: number, cz: number, sx: number, sz: number)
		local p = block(folder, name, cx, 0.03, cz, sx, 0.06, sz, g.color, false)
		p.Material = Enum.Material.Neon
		p.Transparency = g.transparency
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	end
	for _, dx in GridLines.offsets(w, g.spacing) do
		line("GridV", ox + dx, oz, g.line, d)
	end
	for _, dz in GridLines.offsets(d, g.spacing) do
		line("GridH", ox, oz + dz, w, g.line)
	end
end

local function buildSpawn(root: Folder)
	local s = LobbyLayout.spawn
	local x, z = LobbyLayout.toWorld(s.x, s.z)
	-- A flat block, not a cylinder: piece 05 stands people at its top plus 3 studs.
	local p = block(root, "LobbySpawnPad", x, 0.25, z, 12, 0.5, 12, CREAM, true)
	p.Transparency = 0.45
	CollectionService:AddTag(p, LobbyBuilder.tags.spawn)
end

local function buildPad(root: Folder, id: string, color: string, pad: LobbyLayout.Pad)
	local x, z = LobbyLayout.toWorld(pad.x, pad.z)
	local p = disc(root, "Pad_" .. id, x, 0.2, z, pad.radius * 2, 0.3, color)
	p.Material = Enum.Material.Neon
	p.Transparency = 0.4
	p:SetAttribute("Station", id)
	CollectionService:AddTag(p, LobbyBuilder.tags.station)
	local ring = disc(root, "PadRing_" .. id, x, 0.25, z, pad.radius * 2 + 1.2, 0.2, CREAM)
	ring.Transparency = 0.2
	local inner = disc(root, "PadInner_" .. id, x, 0.3, z, pad.radius * 2 - 1.2, 0.2, color)
	inner.Transparency = 0.4
end

local function buildStations(root: Folder)
	for _, st in LobbyLayout.stations do
		buildPad(root, st.id, st.color, st.pad)

		if st.id == "loadout" and st.box then
			local b = st.box
			local body = layoutBlock(root, "LoadoutGarage", b, WALL)
			local cx, cz = body.Position.X, body.Position.Z + b[4] / 2
			-- door, awning and sign face the camera
			block(root, "GarageDoor", cx, 9, cz + 0.1, 20, 18, 0.4, "#10202F", false)
			block(root, "GarageAwning", cx, 20, cz + 3, 26, 1.4, 6, st.color, false)
			sign(root, st.label, cx, b[5] - 5, cz, math.min(b[3] - 8, 36), 8, st.color, PAL.Navy)
		elseif st.id == "settings" and st.box then
			local b = st.box
			local body = layoutBlock(root, "SettingsKiosk", b, st.color)
			sign(
				root,
				st.label,
				body.Position.X,
				b[5] - 4.5,
				body.Position.Z + b[4] / 2,
				b[3] - 4,
				6,
				CREAM,
				PAL.Navy
			)
		elseif st.id == "rewards" and st.box then
			local b = st.box
			local body = layoutBlock(root, "RewardsBoard", b, st.color)
			sign(
				root,
				st.label,
				body.Position.X,
				b[5] - 5,
				body.Position.Z + b[4] / 2,
				b[3] - 8,
				8,
				CREAM,
				PAL.Navy
			)
		elseif st.id == "play" and st.pillars and st.beam then
			for i, box in st.pillars do
				layoutBlock(root, "GatePillar" .. i, box, st.color)
				local x, z = LobbyLayout.toWorld(box[1] + box[3] / 2, box[2] + box[4] / 2)
				block(root, "GateBase" .. i, x, 2, z, box[3] + 1.6, 4, box[4] + 1.6, PAL.Navy)
			end
			local beam = st.beam
			local top, thick = beam[5], beam[6]
			local cx, cz = LobbyLayout.toWorld(beam[1] + beam[3] / 2, beam[2] + beam[4] / 2)
			block(root, "GateBeam", cx, top - thick / 2, cz, beam[3], thick, beam[4], PAL.Navy)
			sign(
				root,
				st.label,
				cx,
				top - thick / 2,
				cz + beam[4] / 2,
				beam[3] * 0.5,
				thick - 2,
				st.color,
				PAL.Navy
			)
		end
	end
end

local function buildDecor(root: Folder)
	for _, dc in LobbyLayout.decor do
		if dc.kind == "planter" and dc.box then
			layoutBlock(root, "Planter", dc.box, PAL.ParkGreen)
		elseif dc.kind == "crate" and dc.box then
			layoutBlock(root, "Crate", dc.box, "#8B5FBF")
		elseif dc.kind == "wall" and dc.box then
			layoutBlock(root, "SideBuilding", dc.box, WALL)
		elseif dc.kind == "tower" and dc.box then
			layoutBlock(root, "SideTower", dc.box, WALL2)
		elseif dc.kind == "fountain" and dc.x and dc.z then
			local x, z = LobbyLayout.toWorld(dc.x, dc.z)
			local basin = disc(root, "FountainBasin", x, 2, z, 26, 4, WALL)
			basin.CanCollide = true
			disc(root, "FountainWater", x, 4.1, z, 22, 0.4, PAL.Cyan)
			block(root, "FountainSpout", x, 6, z, 2.4, 8, 2.4, WALL, false)
			ball(root, "FountainDrop", x, 10.5, z, 5, "#9FF1F7")
		elseif dc.kind == "tree" and dc.x and dc.z then
			local x, z = LobbyLayout.toWorld(dc.x, dc.z)
			block(root, "TreeTrunk", x, 3, z, 2.4, 6, 2.4, "#6B4A2E")
			ball(root, "TreeLeaves", x, 10, z, 12, PAL.ParkGreen)
		elseif dc.kind == "lamp" and dc.x and dc.z then
			local x, z = LobbyLayout.toWorld(dc.x, dc.z)
			block(root, "LampPole", x, 7, z, 1, 14, 1, PAL.Navy)
			local bulb = ball(root, "LampBulb", x, 14.5, z, 3, PAL.RewardGold)
			bulb.Material = Enum.Material.Neon
			local light = Instance.new("PointLight")
			light.Color = hex(PAL.RewardGold)
			light.Range = 28
			light.Brightness = 0.8
			light.Parent = bulb
		end
	end
end

local function buildLeaderboardSpot(root: Folder)
	local spot = LobbyLayout.leaderboardSpot
	local x, z = LobbyLayout.toWorld(spot.x, spot.z)
	-- A placeholder plate; the leaderboard piece finds it by tag and puts its board here.
	local plate = block(
		root,
		"LeaderboardSpot",
		x,
		spot.height / 2 + 2,
		z,
		spot.width,
		spot.height,
		1,
		PAL.Navy,
		false
	)
	CollectionService:AddTag(plate, LobbyBuilder.tags.leaderboard)
	sign(root, "TOP WINS", x, spot.height - 2, z + 0.5, spot.width - 6, 6, PAL.RewardGold, PAL.Navy)
end

-- City skyline outside the walls, so the plaza feels like part of a district. No collision.
local function buildSkyline(root: Folder)
	local rng = Random.new(19)
	local w, d = LobbyLayout.width, LobbyLayout.depth
	local ox, oz = LobbyLayout.origin.x, LobbyLayout.origin.z
	for i = 1, 40 do
		local angle = (i / 40) * math.pi * 2
		local sx, sz = math.cos(angle), math.sin(angle)
		local reach = math.max(w / 2 / math.max(math.abs(sx), 0.01), 0) -- distance to the plaza edge along this ray
		local edge = math.min(reach, d / 2 / math.max(math.abs(sz), 0.01))
		local dist = edge + 30 + rng:NextNumber() * 50
		local h = 40 + rng:NextNumber() * 90
		local size = 24 + rng:NextNumber() * 20
		local shade = 0.12 + rng:NextNumber() * 0.1
		local p = block(
			root,
			"Skyline",
			ox + sx * dist,
			h / 2 - 2,
			oz + sz * dist,
			size,
			h,
			size,
			"#000000",
			false
		)
		p.Color = Color3.fromHSV(0.6, 0.45, shade + 0.1)
		p.CanQuery = false
	end
end

function LobbyBuilder.build(): Folder
	local old = Workspace:FindFirstChild(LobbyBuilder.folderName)
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = LobbyBuilder.folderName
	buildGround(root)
	buildGrid(root)
	buildSpawn(root)
	buildStations(root)
	buildDecor(root)
	buildLeaderboardSpot(root)
	buildSkyline(root)
	root.Parent = Workspace
	return root
end

return LobbyBuilder
