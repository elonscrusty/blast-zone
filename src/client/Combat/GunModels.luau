--!strict
-- The Volt Pistol you see in every fighter's hand: the realistic "A++" look carter picked on the preview
-- page, built from parts and welded to the body so it turns with it. Local only (every client builds its
-- own copy). Fine engraving and stippling from the preview are left out: about 45 parts per gun is enough
-- at game distance and keeps eight fighters cheap.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local GunModels = {}

local SCALE = 0.75
local CYAN = Color3.fromHex(Config.Palette.Cyan)
local CORAL = Color3.fromHex(Config.Palette.DangerCoral)

type Look = { color: Color3, material: Enum.Material, neon: boolean }

local LOOK: { [string]: Look } = {
	poly = {
		color = Color3.fromHex("303640"),
		material = Enum.Material.SmoothPlastic,
		neon = false,
	},
	gun = { color = Color3.fromHex("5A6676"), material = Enum.Material.Metal, neon = false },
	steel = { color = Color3.fromHex("9AA5B3"), material = Enum.Material.Metal, neon = false },
	blued = { color = Color3.fromHex("68778F"), material = Enum.Material.Metal, neon = false },
	brass = { color = Color3.fromHex("C9A24A"), material = Enum.Material.Metal, neon = false },
	dark = {
		color = Color3.fromHex("07090C"),
		material = Enum.Material.SmoothPlastic,
		neon = false,
	},
	cyan = { color = CYAN, material = Enum.Material.Neon, neon = true },
	coral = { color = CORAL, material = Enum.Material.Neon, neon = true },
}

type PartDef = {
	name: string,
	shape: "box" | "cylX" | "cylZ",
	size: Vector3, -- box: width, height, depth. cylinders: length, diameter
	offset: Vector3, -- from the gun centre (the gun points along +X), or from the grip centre
	look: string,
	pitch: number, -- roll about X (bevels)
	roll: number, -- roll about Z
	onGrip: boolean,
}

-- The grip is tilted back this much; the magazine and grip texture live in the grip's own space.
local GRIP_CENTRE = Vector3.new(-1.05, -0.78, 0)
local GRIP_TILT = 0.2

local function box(
	name: string,
	w: number,
	h: number,
	d: number,
	look: string,
	x: number,
	y: number,
	z: number,
	pitch: number?,
	roll: number?
): PartDef
	return {
		name = name,
		shape = "box",
		size = Vector3.new(w, h, d),
		offset = Vector3.new(x, y, z),
		look = look,
		pitch = pitch or 0,
		roll = roll or 0,
		onGrip = false,
	}
end

local function cyl(
	name: string,
	length: number,
	diameter: number,
	look: string,
	x: number,
	y: number,
	z: number,
	alongZ: boolean?
): PartDef
	return {
		name = name,
		shape = if alongZ then "cylZ" else "cylX",
		size = Vector3.new(length, diameter, diameter),
		offset = Vector3.new(x, y, z),
		look = look,
		pitch = 0,
		roll = 0,
		onGrip = false,
	}
end

local function inGrip(def: PartDef): PartDef
	def.onGrip = true
	return def
end

local PARTS: { PartDef } = {
	-- slide: body, bevelled top edges, front block, barrel, bore, compensator cuts
	box("Slide", 3.3, 0.58, 0.5, "gun", 0.15, 0.42, 0),
	box("BevelR", 3.3, 0.1, 0.12, "gun", 0.15, 0.72, 0.17, 0.8),
	box("BevelL", 3.3, 0.1, 0.12, "gun", 0.15, 0.72, -0.17, -0.8),
	box("FrontBlock", 0.5, 0.42, 0.4, "gun", 1.95, 0.35, 0),
	cyl("Barrel", 0.4, 0.3, "steel", 2.2, 0.38, 0),
	cyl("Bore", 0.05, 0.17, "dark", 2.41, 0.38, 0),
	box("Cut1", 0.1, 0.05, 0.2, "dark", 1.25, 0.76, 0),
	box("Cut2", 0.1, 0.05, 0.2, "dark", 1.47, 0.76, 0),
	box("Cut3", 0.1, 0.05, 0.2, "dark", 1.69, 0.76, 0),
	-- serrations (rear and front, both sides), ejection port, brass, extractor, striker
	box("SerRearR", 0.7, 0.46, 0.03, "dark", -1.15, 0.42, 0.255),
	box("SerRearL", 0.7, 0.46, 0.03, "dark", -1.15, 0.42, -0.255),
	box("SerFrontR", 0.45, 0.46, 0.03, "dark", 1.15, 0.42, 0.255),
	box("SerFrontL", 0.45, 0.46, 0.03, "dark", 1.15, 0.42, -0.255),
	box("Port", 0.78, 0.22, 0.04, "dark", 0.35, 0.55, 0.255),
	box("Brass", 0.32, 0.1, 0.03, "brass", 0.3, 0.52, 0.262),
	box("Extractor", 0.1, 0.22, 0.04, "steel", 0.85, 0.64, 0.262),
	box("Striker", 0.18, 0.3, 0.3, "gun", -1.68, 0.5, 0, 0, 0.35),
	-- sights
	box("RearSightBase", 0.28, 0.06, 0.4, "gun", -1.45, 0.76, 0),
	box("RearSightR", 0.12, 0.17, 0.1, "gun", -1.45, 0.86, 0.12),
	box("RearSightL", 0.12, 0.17, 0.1, "gun", -1.45, 0.86, -0.12),
	box("FrontSight", 0.1, 0.2, 0.08, "gun", 1.68, 0.84, 0),
	box("FrontDot", 0.05, 0.05, 0.1, "cyan", 1.68, 0.92, 0),
	-- frame, bevels, rail with slots, rail light, takedown pin, slide stop, spring guide
	box("Frame", 2.6, 0.28, 0.44, "poly", -0.05, 0, 0),
	box("FrameBevelR", 2.6, 0.07, 0.07, "poly", -0.05, 0.13, 0.2, 0.7),
	box("FrameBevelL", 2.6, 0.07, 0.07, "poly", -0.05, 0.13, -0.2, -0.7),
	box("Beavertail", 0.5, 0.1, 0.44, "poly", -1.4, 0.14, 0, 0, -0.15),
	box("RailBlock", 0.9, 0.22, 0.46, "poly", 1.4, -0.02, 0),
	box("Slot1", 0.07, 0.2, 0.48, "dark", 1.1, -0.02, 0),
	box("Slot2", 0.07, 0.2, 0.48, "dark", 1.35, -0.02, 0),
	box("Slot3", 0.07, 0.2, 0.48, "dark", 1.6, -0.02, 0),
	box("Light", 0.62, 0.24, 0.34, "gun", 1.56, -0.28, 0),
	box("LightLens", 0.05, 0.13, 0.13, "cyan", 1.88, -0.28, 0),
	box("LightDot", 0.04, 0.04, 0.04, "coral", 1.88, -0.17, 0),
	cyl("TakedownPin", 0.5, 0.14, "steel", 0.75, -0.05, 0, true),
	box("SlideStop", 0.55, 0.08, 0.06, "steel", -0.2, 0.17, 0.255),
	cyl("SpringGuide", 0.55, 0.13, "steel", 2.1, 0.12, 0),
	box("CellBar1", 0.1, 0.04, 0.02, "cyan", -0.3, 0.04, -0.222),
	box("CellBar2", 0.1, 0.04, 0.02, "cyan", -0.14, 0.04, -0.222),
	box("CellBar3", 0.1, 0.04, 0.02, "cyan", 0.02, 0.04, -0.222),
	-- trigger and guard
	box("GuardBottom", 0.95, 0.07, 0.34, "poly", 0.05, -0.58, 0),
	box("GuardFront", 0.07, 0.42, 0.34, "poly", 0.5, -0.36, 0),
	box("Trigger", 0.07, 0.32, 0.1, "steel", -0.02, -0.38, 0, 0, 0.25),
	-- grip: body, backstrap, finger grooves, magwell, panel texture, lanyard
	inGrip(box("Grip", 0.72, 1.5, 0.46, "poly", 0, 0, 0)),
	inGrip(box("Backstrap", 0.14, 1.3, 0.4, "poly", -0.42, -0.05, 0)),
	inGrip(cyl("Groove1", 0.5, 0.18, "dark", 0.37, 0.3, 0, true)),
	inGrip(cyl("Groove2", 0.5, 0.18, "dark", 0.37, 0, 0, true)),
	inGrip(cyl("Groove3", 0.5, 0.18, "dark", 0.37, -0.3, 0, true)),
	inGrip(box("TextureR", 0.5, 1.0, 0.04, "dark", -0.02, -0.05, 0.235)),
	inGrip(box("TextureL", 0.5, 1.0, 0.04, "dark", -0.02, -0.05, -0.235)),
	inGrip(box("Magwell", 0.86, 0.1, 0.54, "poly", 0, -0.76, 0)),
	inGrip(box("Lanyard", 0.1, 0.22, 0.08, "steel", -0.4, -0.78, 0)),
	-- magazine: blued steel, brass rounds in the window, floorplate with a cyan line
	inGrip(box("Magazine", 0.52, 0.95, 0.38, "blued", 0.03, -0.55, 0)),
	inGrip(box("Rounds", 0.22, 0.5, 0.4, "brass", 0.03, -0.55, 0)),
	inGrip(box("Floorplate", 0.6, 0.1, 0.46, "poly", 0.03, -1.05, 0)),
	inGrip(box("FloorLine", 0.4, 0.03, 0.48, "cyan", 0.03, -1.1, 0)),
}

local function attach(model: Model)
	if model:FindFirstChild("CombatGun") ~= nil then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local gun = Instance.new("Model")
	gun.Name = "CombatGun"
	-- Gun +X becomes the character's forward (-Z); held low on the right side.
	local base = root.CFrame * CFrame.new(1.3, -0.1, -1.0) * CFrame.Angles(0, math.rad(90), 0)
	local gripBase = base * CFrame.new(GRIP_CENTRE * SCALE) * CFrame.Angles(0, 0, GRIP_TILT)
	for _, def in PARTS do
		local look = LOOK[def.look]
		local piece = Instance.new("Part")
		piece.Name = def.name
		piece.Material = look.material
		piece.Color = look.color
		local frame = if def.onGrip then gripBase else base
		local local_ = CFrame.new(def.offset * SCALE) * CFrame.Angles(def.pitch, 0, def.roll)
		if def.shape == "box" then
			piece.Size = def.size * SCALE
		else
			piece.Shape = Enum.PartType.Cylinder
			piece.Size = def.size * SCALE
			if def.shape == "cylZ" then
				local_ = local_ * CFrame.Angles(0, math.rad(90), 0)
			end
		end
		piece.CFrame = frame * local_
		piece.Massless = true
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.CastShadow = false
		piece.Parent = gun
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = piece
		weld.Parent = piece
	end
	gun.Parent = model
	-- Gone when the fighter is out.
	model:GetAttributeChangedSignal("Alive"):Connect(function()
		if model:GetAttribute("Alive") == false then
			gun:Destroy()
		end
	end)
end

local function consider(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	if inst:GetAttribute(Config.Attributes.ParticipantId) ~= nil then
		attach(inst)
	else
		inst:GetAttributeChangedSignal(Config.Attributes.ParticipantId):Once(function()
			attach(inst)
		end)
	end
end

function GunModels.start()
	for _, d in Workspace:GetDescendants() do
		consider(d)
	end
	Workspace.DescendantAdded:Connect(consider)
end

return GunModels
