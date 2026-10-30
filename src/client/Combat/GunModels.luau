--!strict
-- The gun you see in every fighter's hand, and on the ground when a gun drops. Part lists live in
-- WeaponModels (the Volt Pistol is carter's "A++" pick; Breaker, Hornet and Longline match it).
-- Local only: every client builds its own copy. The held gun follows the fighter's WeaponId attribute
-- (set by the server) and is rebuilt when it changes; it is always a Model named "CombatGun" with
-- parts named "Slide" and "Grip".

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local WeaponModels = require("./WeaponModels")

local GunModels = {}

local SCALE = 0.75
local DROP_SCALE = 0.6
local CYAN = Color3.fromHex(Config.Palette.Cyan)
local CORAL = Color3.fromHex(Config.Palette.DangerCoral)

type Look = { color: Color3, material: Enum.Material, transparency: number }

local LOOK: { [string]: Look } = {
	poly = {
		color = Color3.fromHex("303640"),
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
	},
	gun = { color = Color3.fromHex("5A6676"), material = Enum.Material.Metal, transparency = 0 },
	steel = { color = Color3.fromHex("9AA5B3"), material = Enum.Material.Metal, transparency = 0 },
	blued = { color = Color3.fromHex("68778F"), material = Enum.Material.Metal, transparency = 0 },
	brass = { color = Color3.fromHex("C9A24A"), material = Enum.Material.Metal, transparency = 0 },
	dark = {
		color = Color3.fromHex("07090C"),
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
	},
	hull = {
		color = Color3.fromHex("C9454D"),
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
	},
	rubber = {
		color = Color3.fromHex("15171B"),
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
	},
	tan = {
		color = Color3.fromHex("8C7656"),
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
	},
	glass = { color = CYAN, material = Enum.Material.Glass, transparency = 0.45 },
	cyan = { color = CYAN, material = Enum.Material.Neon, transparency = 0 },
	coral = { color = CORAL, material = Enum.Material.Neon, transparency = 0 },
}

GunModels.LOOKS = LOOK

local function shapeTurn(shape: WeaponModels.Shape): CFrame
	if shape == "cylY" then
		return CFrame.Angles(0, 0, math.rad(90))
	elseif shape == "cylZ" then
		return CFrame.Angles(0, math.rad(90), 0)
	end
	return CFrame.identity
end

-- Builds gun `weaponId` with its centre at `base` (gun +X along base's X). Parts are unanchored,
-- massless and touch nothing; `weldTo` (if given) holds every part, else they are anchored.
function GunModels.build(weaponId: string, base: CFrame, scale: number, weldTo: BasePart?): Model
	local def = WeaponModels.get(weaponId)
	local gun = Instance.new("Model")
	gun.Name = "CombatGun"
	gun:SetAttribute("WeaponId", def.id)
	gun.WorldPivot = base
	local frames: { [string]: CFrame } = {}
	for name, f in def.frames do
		frames[name] = base * CFrame.new(f.x * scale, f.y * scale, 0) * CFrame.Angles(0, 0, f.tilt)
	end
	for _, p in def.parts do
		local look = LOOK[p.look] or LOOK.poly
		local piece = Instance.new("Part")
		piece.Name = p.name
		piece.Material = look.material
		piece.Color = look.color
		piece.Transparency = look.transparency
		if p.shape == "ball" then
			piece.Shape = Enum.PartType.Ball
		elseif p.shape ~= "box" then
			piece.Shape = Enum.PartType.Cylinder
		end
		piece.Size = Vector3.new(p.w, p.h, p.d) * scale
		local frame = if p.frame ~= nil then frames[p.frame] or base else base
		piece.CFrame = frame
			* CFrame.new(p.x * scale, p.y * scale, p.z * scale)
			* CFrame.Angles(p.pitch, 0, p.roll)
			* shapeTurn(p.shape)
		piece.Massless = true
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.CastShadow = false
		if weldTo ~= nil then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = weldTo
			weld.Part1 = piece
			weld.Parent = piece
		else
			piece.Anchored = true
		end
		piece.Parent = gun
	end
	return gun
end

-- ===== held guns =====

local function equip(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") or model:GetAttribute("Alive") == false then
		return
	end
	local want = model:GetAttribute("WeaponId")
	local weaponId = if type(want) == "string" then want else Config.Weapons.Firearm.id
	local old = model:FindFirstChild("CombatGun")
	if old ~= nil then
		if old:GetAttribute("WeaponId") == WeaponModels.get(weaponId).id then
			return
		end
		old:Destroy()
	end
	local hold = WeaponModels.get(weaponId).hold
	-- Gun +X becomes the character's forward (-Z); held low on the right side.
	local base = root.CFrame
		* CFrame.new(hold.x, hold.y, hold.z)
		* CFrame.Angles(0, math.rad(90), 0)
	GunModels.build(weaponId, base, SCALE, root).Parent = model
end

local watched: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function attach(model: Model)
	if watched[model] then
		return
	end
	watched[model] = true
	equip(model)
	model:GetAttributeChangedSignal("WeaponId"):Connect(function()
		equip(model)
	end)
	-- Gone when the fighter is out.
	model:GetAttributeChangedSignal("Alive"):Connect(function()
		if model:GetAttribute("Alive") == false then
			local gun = model:FindFirstChild("CombatGun")
			if gun ~= nil then
				gun:Destroy()
			end
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

-- ===== guns on the ground =====

type Shown = { gun: Model, ring: Part }
local shown: { [BasePart]: Shown } = {}

local function showDrop(anchor: Instance)
	if not anchor:IsA("BasePart") or shown[anchor] ~= nil then
		return
	end
	local weaponId = anchor:GetAttribute("WeaponId")
	if type(weaponId) ~= "string" then
		return
	end
	local gun = GunModels.build(weaponId, CFrame.identity, DROP_SCALE, nil)
	gun.Name = "DroppedGun"
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = CYAN
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.08, 4.2, 4.2)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.CFrame = CFrame.new(
		anchor.Position - Vector3.new(0, Config.Weapons.Drops.height - 0.05, 0)
	) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = anchor
	gun.Parent = anchor
	shown[anchor] = { gun = gun, ring = ring }
end

local function hideDrop(anchor: Instance)
	if anchor:IsA("BasePart") then
		local s = shown[anchor]
		if s ~= nil then
			s.gun:Destroy()
			s.ring:Destroy()
			shown[anchor] = nil
		end
	end
end

local function watchDrops(folder: Instance)
	for _, child in folder:GetChildren() do
		showDrop(child)
	end
	folder.ChildAdded:Connect(showDrop)
	folder.ChildRemoved:Connect(hideDrop)
end

-- Slow spin and bob, so a gun on the ground reads as "pick me up".
local function animateDrops()
	local t = os.clock()
	for anchor, s in shown do
		if anchor.Parent == nil then
			s.gun:Destroy()
			s.ring:Destroy()
			shown[anchor] = nil
		else
			local spin = CFrame.Angles(0, t * 1.4, 0)
			local bob = math.sin(t * 2.5) * 0.15
			s.gun:PivotTo(
				CFrame.new(anchor.Position + Vector3.new(0, bob, 0))
					* spin
					* CFrame.Angles(0, 0, 0.12)
			)
		end
	end
end

function GunModels.start()
	for _, d in Workspace:GetDescendants() do
		consider(d)
	end
	Workspace.DescendantAdded:Connect(consider)

	local name = Config.Weapons.Drops.folder
	local existing = Workspace:FindFirstChild(name)
	if existing ~= nil then
		watchDrops(existing)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == name then
			watchDrops(child)
		end
	end)
	RunService.RenderStepped:Connect(animateDrops)
end

return GunModels
