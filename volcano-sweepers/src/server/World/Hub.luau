--!strict
-- The hub on the beach: eight spawn pads, the Trade Hut (the picked Toy Pop model: counter, awning,
-- sign, sell prompt), glowing sell pads, a gate signpost and the "Sweep the ash!" tutorial sign. Everything is laid out by
-- WorldPlan in the hub's own (a, b) frame and stays inside Config.World.hub.clearRadius, which the
-- ash grid keeps empty.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)

local Build = require(script.Parent.Models.Build)
local Wiring = require(script.Parent.Models.Wiring)
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

-- The Trade Hut: the picked Toy Pop model, its counter (sell prompt) facing inland at the pads.
local function buildHut(folder: Folder, hub: WorldPlan.Hub, u: Vector3)
	local hx, hz = WorldPlan.toWorld(hub, hub.hutA, 0)
	local origin = V(hx, 0, hz)
	-- the model's front (-Z) looks inland, at the sell pads and the spawns
	local frame = CFrame.lookAt(origin, origin - u)
	local spec = Wiring.kitSpec("TradeHut", 1, "TRADE HUT")
	local hut = Build.into(folder, spec, frame, Wiring.HUT_SCALE)
	hut.Name = "TradeHut"

	local counter = hut:FindFirstChild(Wiring.PART.counter)
	if counter == nil or not counter:IsA("BasePart") then
		error("the Trade Hut model has no Counter part")
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
end

-- A Toy Pop signpost facing the spawns, text on both sides, with a glowing arrow over it pointing
-- inland (towards the gates). Walk-through: it stands between the spawn pads.
local function buildSignpost(
	folder: Folder,
	u: Vector3,
	at: WorldPlan.HubPt,
	text: string,
	arrowColor: string
)
	local origin = V(at.x, 0, at.z)
	local frame = CFrame.lookAt(origin, origin - u)
	local sign = Build.into(folder, Wiring.kitSpec("Sign", 1, text), frame, 1, false)
	sign.Name = "Signpost"
	local board = sign:FindFirstChild(Wiring.PART.signBoard)
	if board ~= nil and board:IsA("BasePart") then
		WorldUtil.faceText(board, Enum.NormalId.Back, { text = text, textColor = "#FF4D4D" })
	end
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
