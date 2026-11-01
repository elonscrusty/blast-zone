--!strict
-- One gate arch per zone 2..5 (the picked Toy Pop gate model in the zone's colours), standing across
-- the ring boundary on the hub direction line, drawn at WorldPlan's gate scale (1.5 on the big
-- island). Gates never block movement (only the pillar feet are solid, the walk-through opening is
-- 18 x scale studs wide): the glowing floor plate is the
-- VSGate part that carries the "Open gate" prompt; the server decides what opening does and refuses
-- sweeping in locked zones.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)
local Zones = require(Shared.Catalog.Zones)

local Build = require(script.Parent.Models.Build)
local Registry = require(script.Parent.Models.Registry)
local Wiring = require(script.Parent.Models.Wiring)
local WorldUtil = require(script.Parent.WorldUtil)

local Gates = {}

local P = WorldUtil.Palette
local V = Vector3.new

local function buildSign(beam: BasePart, zone: Zones.Zone, accent: string, k: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "GateSign"
	gui.Size = UDim2.fromScale(15 * k, 4.2 * k)
	gui.StudsOffset = V(0, 4.2 * k, 0)
	gui.MaxDistance = 260 * k
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromHex(P.navy)
	back.BackgroundTransparency = 0.08
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex(accent)
	stroke.Thickness = 3
	stroke.Parent = back

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.04, 0.06)
	title.Size = UDim2.fromScale(0.92, 0.55)
	title.Text = `{zone.name} — gate`
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = Color3.fromHex(P.white)
	title.Parent = back

	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.BackgroundTransparency = 1
	price.Position = UDim2.fromScale(0.04, 0.63)
	price.Size = UDim2.fromScale(0.92, 0.3)
	price.Text = if zone.unlockPrice <= 0
		then "Free"
		else `{WorldUtil.commas(zone.unlockPrice)} coins`
	price.TextScaled = true
	price.Font = Enum.Font.FredokaOne
	price.TextColor3 = Color3.fromHex(accent)
	price.Parent = back

	back.Parent = gui
	gui.Parent = beam
end

local function buildGate(folder: Folder, g: WorldPlan.Gate)
	local zone = Zones.byId[g.zoneId]
	local accent = WorldUtil.zoneAccent[g.zoneId] or P.gold
	local k = g.scale -- the whole arch grows with the island (1 = the first, small island's gate)
	local origin = V(g.x, 0, g.z)
	-- the model's front (-Z, pennants) looks out to sea, at the kids walking up to the gate
	local frame = CFrame.lookAt(origin, origin + V(g.ux, 0, g.uz))
	local spec =
		Registry.spec("Gate", { style = Wiring.STYLE, accent = accent, ground = zone.ground })
	local model = Build.into(folder, spec, frame, k)
	model.Name = `Gate{g.zoneId}`

	-- the glowing floor plate = the tagged gate part (never solid: the opening stays walk-through)
	local plate = model:FindFirstChild(Wiring.PART.gatePlate)
	if plate == nil or not plate:IsA("BasePart") then
		error("the gate model has no GatePlate part")
	end
	local beam = model:FindFirstChild(Wiring.PART.gateBeam)
	if beam ~= nil and beam:IsA("BasePart") then
		buildSign(beam, zone, accent, k)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GatePrompt"
	prompt.ActionText = "Open gate"
	prompt.ObjectText = zone.name
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 16 * k
	prompt.RequiresLineOfSight = false
	-- E is "sweep" and ButtonX is "sell" (client Controls): the gate gets its own keys
	prompt.KeyboardKeyCode = Enum.KeyCode.G
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Parent = plate

	plate:SetAttribute("ZoneId", g.zoneId)
	CollectionService:AddTag(plate, "VSGate")
end

function Gates.build(root: Instance, plan: WorldPlan.Plan)
	local folder = Instance.new("Folder")
	folder.Name = "Gates"
	folder.Parent = root -- first: a gate that fails to build never hides the others

	for _, g in plan.gates do
		local ok, err = pcall(buildGate, folder, g)
		if not ok then
			warn(`[Gates] gate {g.zoneId} failed: {err}`)
		end
	end
end

return Gates
