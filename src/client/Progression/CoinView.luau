--!strict
-- A small spinning 3D coin in a ViewportFrame, built from plain parts (no art assets). The look comes from
-- CoinLooks (Config.Progression.look). Cheap: about a dozen parts, one CFrame update each per frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoinLooks = require(Shared.Progression.CoinLooks)

local CoinView = {}

type Piece = { part: BasePart, offset: Vector3, turn: CFrame }

local EDGE_RIDGES = 24 -- little blocks around the side; more looks nicer but costs parts
local FACE_TURN = CFrame.Angles(0, math.pi / 2, 0) -- a cylinder's axis is X; this points it at the camera (Z)

local function add(
	pieces: { Piece },
	model: Model,
	isCylinder: boolean,
	size: Vector3, -- (width, height, thickness) for blocks; (diameter, diameter, thickness) for cylinders
	offsetZ: number,
	hex: string,
	neon: boolean?,
	spinZ: number?,
	offsetXY: Vector2?
)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Color = Color3.fromHex(hex)
	part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local turn = CFrame.Angles(0, 0, spinZ or 0)
	if isCylinder then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(size.Z, size.X, size.X) -- thickness runs along the cylinder axis
		turn = turn * FACE_TURN
	else
		part.Size = size
	end
	part.Parent = model
	local xy = offsetXY or Vector2.zero
	table.insert(pieces, { part = part, offset = Vector3.new(xy.X, xy.Y, offsetZ), turn = turn })
end

-- Returns the ViewportFrame; it stops updating by itself when destroyed.
function CoinView.create(parent: Instance, lookKey: string): ViewportFrame
	local look = CoinLooks.get(lookKey)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Coin"
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(170, 170, 170)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-0.4, -0.7, -1)
	vp.Parent = parent

	local camera = Instance.new("Camera")
	camera.FieldOfView = 28
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.5, 8), Vector3.zero)
	camera.Parent = vp
	vp.CurrentCamera = camera

	local model = Instance.new("Model")
	model.Parent = vp
	local pieces: { Piece } = {}

	-- Body (thickness runs along Z, so a face points at the camera). Everything is on both sides for the spin.
	local rimDisc = Vector3.new(2.0, 2.0, 0.3)
	add(pieces, model, true, rimDisc, 0, look.rim) -- raised rim: a full disc underneath
	add(pieces, model, true, Vector3.new(1.6, 1.6, 0.325), 0, look.face) -- the face, a hair proud of the rim
	for k = 0, EDGE_RIDGES - 1 do -- reeded edge
		local theta = k / EDGE_RIDGES * math.pi * 2
		add(
			pieces,
			model,
			false,
			Vector3.new(0.07, 0.12, 0.3),
			0,
			look.edge,
			false,
			theta,
			Vector2.new(math.cos(theta), math.sin(theta))
		)
	end
	for _, side in { 1, -1 } do
		local z = side * 0.2
		if look.glyph == "bolt" then
			add(
				pieces,
				model,
				false,
				Vector3.new(0.26, 0.7, 0.1),
				z,
				look.ink,
				false,
				-0.5,
				Vector2.new(0.1, 0.34)
			)
			add(pieces, model, false, Vector3.new(0.7, 0.2, 0.1), z, look.ink)
			add(
				pieces,
				model,
				false,
				Vector3.new(0.26, 0.7, 0.1),
				z,
				look.ink,
				false,
				-0.5,
				Vector2.new(-0.1, -0.34)
			)
		elseif look.glyph == "gear" then
			add(pieces, model, true, Vector3.new(0.8, 0.8, 0.1), z, look.ink)
			for k = 0, 7 do
				local theta = k / 8 * math.pi * 2
				add(
					pieces,
					model,
					false,
					Vector3.new(0.2, 0.2, 0.1),
					z,
					look.ink,
					false,
					theta,
					Vector2.new(math.cos(theta) * 0.48, math.sin(theta) * 0.48)
				)
			end
			add(pieces, model, true, Vector3.new(0.34, 0.34, 0.12), z, look.face)
		else -- diamond
			add(pieces, model, false, Vector3.new(0.78, 0.78, 0.1), z, look.ink, false, math.pi / 4)
			add(pieces, model, false, Vector3.new(0.4, 0.4, 0.12), z, look.rim, false, math.pi / 4)
		end
	end

	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if vp.Parent == nil then
			conn:Disconnect()
			return
		end
		local pivot = CFrame.Angles(0, os.clock() * 1.6, 0)
		for _, piece in pieces do
			piece.part.CFrame = pivot * CFrame.new(piece.offset) * piece.turn
		end
	end)
	return vp
end

return CoinView
