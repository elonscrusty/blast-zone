--!strict
-- A small spinning 3D coin in a ViewportFrame, built from plain parts (no art assets). The look comes from
-- CoinLooks (Config.Progression.look). Cheap: about a dozen parts, one CFrame update each per frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoinLooks = require(Shared.Progression.CoinLooks)

local CoinView = {}

type Piece = { part: BasePart, offset: Vector3, turn: CFrame }

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

	-- Body: rim underneath, then the face. Everything is repeated on the back so the spin looks right.
	if look.shape == "octagon" then
		add(pieces, model, false, Vector3.new(2.2, 2.2, 0.28), 0, look.rim)
		add(pieces, model, false, Vector3.new(2.2, 2.2, 0.28), 0, look.rim, false, math.pi / 4)
		add(pieces, model, false, Vector3.new(2.0, 2.0, 0.34), 0, look.face)
		add(pieces, model, false, Vector3.new(2.0, 2.0, 0.34), 0, look.face, false, math.pi / 4)
	else
		add(pieces, model, true, Vector3.new(2.3, 2.3, 0.28), 0, look.rim)
		add(pieces, model, true, Vector3.new(2.2, 2.2, 0.34), 0, look.face)
		add(pieces, model, true, Vector3.new(1.8, 1.8, 0.38), 0, look.rim)
		add(pieces, model, true, Vector3.new(1.64, 1.64, 0.4), 0, look.face)
	end
	if look.glyph ~= nil then
		-- Only "V" is drawn (two bars). A new glyph needs its own shapes here.
		add(
			pieces,
			model,
			false,
			Vector3.new(0.3, 1.25, 0.46),
			0,
			look.ink,
			false,
			0.36,
			Vector2.new(-0.27, 0)
		)
		add(
			pieces,
			model,
			false,
			Vector3.new(0.3, 1.25, 0.46),
			0,
			look.ink,
			false,
			-0.36,
			Vector2.new(0.27, 0)
		)
	end
	if look.dot ~= nil then
		add(pieces, model, true, Vector3.new(1.0, 1.0, 0.44), 0, look.dot)
		add(pieces, model, true, Vector3.new(0.3, 0.3, 0.48), 0, look.ink)
	end
	if look.hole then
		add(pieces, model, true, Vector3.new(0.95, 0.95, 0.44), 0, look.rim)
		add(pieces, model, true, Vector3.new(0.75, 0.75, 0.48), 0, look.ink)
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
