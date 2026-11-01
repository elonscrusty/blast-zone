--!strict
-- The hub on the beach: eight spawn pads, the Trade Hut (counter, awning, sign, sell prompt), glowing
-- sell pads, a gate signpost and the "Sweep the ash!" tutorial sign. Everything is laid out by
-- WorldPlan in the hub's own (a, b) frame and stays inside Config.World.hub.clearRadius, which the
-- ash grid keeps empty.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)

local WorldUtil = require(script.Parent.WorldUtil)

local Hub = {}

local P = WorldUtil.Palette
local V = Vector3.new

local function billboard(part: BasePart, text: string, offsetY: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 46)
	gui.StudsOffset = V(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromHex(P.gold)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromHex("#7A3E12")
	label.Parent = gui
	gui.Parent = part
end

local function buildSpawns(folder: Folder, hub: WorldPlan.Hub)
	local lookAt = V(hub.x, 0.3, hub.z)
	for i, s in hub.spawns do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = `Spawn{i}`
		spawn.Anchored = true
		spawn.CanCollide = true
		spawn.Neutral = true
		spawn.AllowTeamChangeOnTouch = false
		spawn.Duration = 0
		spawn.Enabled = true
		spawn.Size = V(4.8, 0.6, 4.8)
		spawn.Material = Enum.Material.SmoothPlastic
		spawn.Color = Color3.fromHex("#2EC4B6")
		spawn.TopSurface = Enum.SurfaceType.Smooth
		spawn.BottomSurface = Enum.SurfaceType.Smooth
		spawn.CFrame = CFrame.lookAt(V(s.x, 0.3, s.z), lookAt)
		spawn.Parent = folder
		CollectionService:AddTag(spawn, "VSSpawn")
		WorldUtil.block(
			folder,
			"SpawnGlow",
			CFrame.new(s.x, 0.64, s.z) * (spawn.CFrame - spawn.CFrame.Position),
			V(3.2, 0.08, 3.2),
			"#B8FFF2",
			{ material = Enum.Material.Neon }
		)
	end
end

local function buildPads(folder: Folder, hub: WorldPlan.Hub)
	for _, p in hub.pads do
		WorldUtil.disc(folder, "SellPadBase", p.x, 0.25, p.z, 5.6, 0.25, "#FF9F1C")
		local pad = WorldUtil.disc(folder, "SellPad", p.x, 0.4, p.z, 5, 0.2, P.gold, {
			material = Enum.Material.Neon,
		})
		WorldUtil.tag(pad, "VSSellPad")
		billboard(pad, "SELL", 3.4)
	end
end

local function buildHut(folder: Folder, hub: WorldPlan.Hub, u: Vector3)
	local hx, hz = WorldPlan.toWorld(hub, hub.hutA, 0)
	local origin = V(hx, 0, hz)
	local frame = CFrame.lookAt(origin, origin - u) -- looks inland; local +Z is the back of the hut
	local function H(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local hut = Instance.new("Model")
	hut.Name = "TradeHut"

	local solid = { collide = true, shadow = true }
	WorldUtil.block(hut, "Floor", H(0, 0.2, 0), V(14, 0.4, 10), P.wood)
	WorldUtil.block(hut, "BackWall", H(0, 3.9, 4.7), V(14, 7, 0.6), P.cream, solid)
	for _, side in { -1, 1 } do
		WorldUtil.block(hut, "SideWall", H(side * 6.7, 3.9, 0), V(0.6, 7, 10), P.cream, solid)
		WorldUtil.block(hut, "FrontPost", H(side * 6.8, 3.9, -4.9), V(0.8, 7, 0.8), P.cream, solid)
		WorldUtil.cylinder(
			hut,
			"AwningPost",
			H(side * 6.5, 3.1, -7.2).Position,
			0.5,
			6.2,
			P.woodDark,
			{
				collide = true,
			}
		)
	end
	WorldUtil.block(hut, "CounterBody", H(0, 2.1, -4.1), V(14, 3.4, 1.8), P.coral, solid)
	local counter =
		WorldUtil.block(hut, "Counter", H(0, 3.95, -4.3), V(14.6, 0.3, 2.6), P.woodLight, {
			collide = true,
		})
	WorldUtil.block(hut, "Roof", H(0, 7.8, 0), V(15.6, 0.8, 11.6), P.teal, { shadow = true })

	-- striped awning over the counter, tilted down towards the customers
	for i = 0, 7 do
		local color = if i % 2 == 0 then P.red else P.white
		WorldUtil.block(
			hut,
			"Awning",
			H(-6.125 + i * 1.75, 6.65, -6.3) * CFrame.Angles(-math.rad(20), 0, 0),
			V(1.75, 0.3, 3),
			color,
			{ shadow = true }
		)
	end
	-- bunting along the roof edge
	local bunting = { P.red, P.sun, P.cyan, P.pink }
	for i = 0, 8 do
		WorldUtil.ball(
			hut,
			"Bunting",
			H(-7 + i * 1.75, 8.5, -5.6).Position,
			0.7,
			bunting[i % 4 + 1]
		)
	end

	-- the big sign
	WorldUtil.block(
		hut,
		"SignFrame",
		H(0, 10.7, -4.6),
		V(12.8, 3.8, 0.4),
		"#E0752D",
		{ shadow = true }
	)
	local board = WorldUtil.block(
		hut,
		"SignBoard",
		H(0, 10.7, -4.8),
		V(12, 3.4, 0.6),
		P.sun,
		{ shadow = true }
	)
	WorldUtil.faceText(board, Enum.NormalId.Front, { text = "TRADE HUT", textColor = "#7A3E12" })
	for _, side in { -1, 1 } do
		WorldUtil.block(hut, "SignPost", H(side * 4.5, 8.7, -4.7), V(0.5, 1, 0.5), P.woodDark)
		WorldUtil.part(hut, {
			name = "SignCoin",
			size = V(0.5, 2.8, 2.8),
			cf = H(side * 7.5, 10.7, -4.8) * CFrame.Angles(0, math.pi / 2, 0),
			color = P.gold,
			material = Enum.Material.Neon,
			shape = Enum.PartType.Cylinder,
		})
	end

	-- the shopkeeper blob, peeking over the counter
	local keeper = H(-2.5, 0, -1.8).Position
	WorldUtil.ball(hut, "KeeperBody", keeper + V(0, 2.3, 0), 3.4, "#FF9F1C")
	WorldUtil.ball(hut, "KeeperHead", keeper + V(0, 4.9, 0), 2.4, "#FFE0B2")
	for _, side in { -1, 1 } do
		local eye = frame * CFrame.new(-2.5 + side * 0.5, 5.1, -1.8 - 1.1)
		WorldUtil.ball(hut, "KeeperEye", eye.Position, 0.35, "#2B2230")
	end
	WorldUtil.cylinder(hut, "KeeperHat", keeper + V(0, 6.3, 0), 2.2, 0.5, P.teal)

	-- shelf with jars
	WorldUtil.block(hut, "Shelf", H(0, 4.6, 4.2), V(10, 0.3, 1.2), P.wood)
	local jars = { P.coral, P.cyan, P.pink, P.sun }
	for i = 0, 3 do
		WorldUtil.ball(hut, "Jar", H(-3.6 + i * 2.4, 5.25, 4.2).Position, 0.9, jars[i + 1])
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SellPrompt"
	prompt.ActionText = "Sell ash"
	prompt.ObjectText = "Trade Hut"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	CollectionService:AddTag(prompt, "VSSellPrompt")
	prompt.Parent = counter

	hut.Parent = folder
end

local function buildSignpost(
	folder: Folder,
	u: Vector3,
	at: WorldPlan.HubPt,
	text: string,
	arrowColor: string
)
	local origin = V(at.x, 0, at.z)
	local frame = CFrame.lookAt(origin, origin - u)
	WorldUtil.cylinder(
		folder,
		"SignPole",
		origin + V(0, 2.8, 0),
		0.6,
		5.6,
		P.woodDark,
		{ collide = true }
	)
	WorldUtil.signBoard(
		folder,
		"SignBoard",
		frame * CFrame.new(0, 4.4, -0.45),
		V(7, 2.1, 0.35),
		P.cream,
		"#D9480F",
		text
	)
	WorldUtil.arrow(folder, frame * CFrame.new(0, 7.2, 0.4), arrowColor)
end

function Hub.build(root: Instance, plan: WorldPlan.Plan)
	local hub = plan.hub
	local folder = Instance.new("Folder")
	folder.Name = "Hub"
	local u = V(hub.ux, 0, hub.uz)
	-- parented first and each piece on its own: one broken piece never hides the spawns or the hut
	folder.Parent = root

	local function step(name: string, fn: () -> ())
		local ok, err = pcall(fn)
		if not ok then
			warn(`[Hub] {name} failed: {err}`)
		end
	end
	step("spawns", function()
		buildSpawns(folder, hub)
	end)
	step("sell pads", function()
		buildPads(folder, hub)
	end)
	step("hut", function()
		buildHut(folder, hub, u)
	end)
	step("gate signpost", function()
		buildSignpost(folder, u, hub.signpost, "Gates this way!", "#FFE14D")
	end)
	step("tutorial sign", function()
		buildSignpost(folder, u, hub.tutorial, "Sweep the ash!", "#7CFF8A")
	end)
end

return Hub
