--!strict
-- The Volt Pistol you see in every fighter's hand: the "sleek, more detail" look carter picked, built from
-- parts and welded to the body so it turns with it. Local only (every client builds its own copy).

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local GunModels = {}

local NAVY = Color3.fromHex(Config.Palette.Navy)
local CYAN = Color3.fromHex(Config.Palette.Cyan)
local GOLD = Color3.fromHex(Config.Palette.RewardGold)
local STEEL = Color3.fromRGB(86, 103, 124)
local DEEP = Color3.fromRGB(29, 58, 92)
local SCALE = 0.75

type PartDef = {
	name: string,
	size: Vector3,
	offset: Vector3,
	roll: number,
	color: Color3,
	neon: boolean,
}

-- name, size, offset from the gun centre (the gun points along +X), roll, color, neon
local function part(
	name: string,
	size: Vector3,
	offset: Vector3,
	roll: number,
	color: Color3,
	neon: boolean
): PartDef
	return { name = name, size = size, offset = offset, roll = roll, color = color, neon = neon }
end

local PARTS: { PartDef } = {
	part("Slide", Vector3.new(3.4, 0.62, 0.52), Vector3.new(0.1, 0.4, 0), 0, NAVY, false),
	part("Frame", Vector3.new(2.6, 0.3, 0.46), Vector3.new(-0.1, 0, 0), 0, DEEP, false),
	part("Barrel", Vector3.new(0.9, 0.34, 0.34), Vector3.new(2.05, 0.38, 0), 0, STEEL, false),
	part("MuzzleRing", Vector3.new(0.1, 0.5, 0.5), Vector3.new(2.5, 0.38, 0), 0, CYAN, true),
	part("TopGlow", Vector3.new(2.2, 0.07, 0.18), Vector3.new(0.1, 0.74, 0), 0, CYAN, true),
	part("CellWindow", Vector3.new(1.0, 0.1, 0.56), Vector3.new(-0.35, 0.26, 0), 0, CYAN, true),
	part("RearSight", Vector3.new(0.18, 0.16, 0.34), Vector3.new(-1.4, 0.8, 0), 0, NAVY, false),
	part("FrontSight", Vector3.new(0.12, 0.18, 0.1), Vector3.new(1.65, 0.8, 0), 0, NAVY, false),
	part("Grip", Vector3.new(0.7, 1.5, 0.5), Vector3.new(-1.0, -0.78, 0), 0.18, DEEP, false),
	part("Magazine", Vector3.new(0.5, 0.95, 0.4), Vector3.new(-0.9, -1.15, 0), 0.18, STEEL, false),
	part("MagBase", Vector3.new(0.58, 0.1, 0.46), Vector3.new(-0.82, -1.62, 0), 0.18, GOLD, true),
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
	for _, def in PARTS do
		local piece = Instance.new("Part")
		piece.Name = def.name
		piece.Size = def.size * SCALE
		piece.Color = def.color
		piece.Material = if def.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		piece.CFrame = base * CFrame.new(def.offset * SCALE) * CFrame.Angles(0, 0, def.roll)
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
