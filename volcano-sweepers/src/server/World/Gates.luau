--!strict
-- One gate arch per zone 2..5, standing across the ring boundary on the hub direction line. Gates
-- never block movement (the walk-through opening is 18 studs wide): the glowing floor plate is the
-- VSGate part that carries the "Open gate" prompt; the server decides what opening does and refuses
-- sweeping in locked zones.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)
local Zones = require(Shared.Catalog.Zones)

local WorldUtil = require(script.Parent.WorldUtil)

local Gates = {}

local P = WorldUtil.Palette
local V = Vector3.new

local function buildSign(beam: BasePart, zone: Zones.Zone, accent: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "GateSign"
	gui.Size = UDim2.fromScale(15, 4.2)
	gui.StudsOffset = V(0, 4.2, 0)
	gui.MaxDistance = 260
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

function Gates.build(root: Instance, plan: WorldPlan.Plan)
	local folder = Instance.new("Folder")
	folder.Name = "Gates"

	for _, g in plan.gates do
		local zone = Zones.byId[g.zoneId]
		local accent = WorldUtil.zoneAccent[g.zoneId] or P.gold
		local origin = V(g.x, 0, g.z)
		local frame = CFrame.lookAt(origin, origin - V(g.ux, 0, g.uz)) -- walking inland is local -Z
		local function G(x: number, y: number, z: number): CFrame
			return frame * CFrame.new(x, y, z)
		end
		local model = Instance.new("Model")
		model.Name = `Gate{g.zoneId}`

		-- the glowing floor plate = the tagged gate part
		local plate = WorldUtil.block(model, "GatePlate", G(0, 0.15, 0), V(16, 0.3, 5), accent, {
			material = Enum.Material.Neon,
			transparency = 0.35,
		})

		for _, side in { -1, 1 } do
			local x = side * 9.2
			WorldUtil.block(
				model,
				"PillarBase",
				G(x, 0.5, 0),
				V(3.6, 1, 3.6),
				P.stone,
				{ collide = true, shadow = true }
			)
			WorldUtil.cylinder(model, "Pillar", G(x, 6.5, 0).Position, 2.6, 11, zone.ground, {
				collide = true,
				shadow = true,
			})
			WorldUtil.cylinder(model, "PillarBandLow", G(x, 3, 0).Position, 2.9, 0.4, accent, {
				material = Enum.Material.Neon,
			})
			WorldUtil.cylinder(model, "PillarBandHigh", G(x, 9.5, 0).Position, 2.9, 0.4, accent, {
				material = Enum.Material.Neon,
			})
			WorldUtil.ball(model, "PillarCap", G(x, 12.4, 0).Position, 3.4, accent, {
				material = Enum.Material.Neon,
			})
		end

		local beam = WorldUtil.block(
			model,
			"Beam",
			G(0, 13.2, 0),
			V(22.4, 2.2, 3),
			zone.ground,
			{ shadow = true }
		)
		WorldUtil.block(model, "BeamStrip", G(0, 11.95, -1.4), V(21, 0.3, 0.3), accent, {
			material = Enum.Material.Neon,
		})
		for i = 0, 4 do
			WorldUtil.ball(model, "BeamLight", G(-8 + i * 4, 13.2, -1.6).Position, 0.6, accent, {
				material = Enum.Material.Neon,
			})
		end
		buildSign(beam, zone, accent)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "GatePrompt"
		prompt.ActionText = "Open gate"
		prompt.ObjectText = zone.name
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 16
		prompt.RequiresLineOfSight = false
		prompt.Parent = plate

		plate:SetAttribute("ZoneId", g.zoneId)
		CollectionService:AddTag(plate, "VSGate")
		model.Parent = folder
	end

	folder.Parent = root
end

return Gates
