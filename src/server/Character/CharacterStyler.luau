--!strict
-- Dresses an R15 body in one of the fighter looks (src/shared/Character/Looks.luau): body colors, a bigger
-- head, and welded parts for the helmet, shoulders, backpack and so on. Server side so every client sees the
-- same fighter. The parts cannot collide, be hit by shots, or be touched. Safe to run again (it replaces
-- what it built before), which the appearance loader needs.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Looks = require(Shared.Character.Looks)
local BotTuning = require(script.Parent.Parent.Bots.BotTuning)

local CharacterStyler = {}

local FOLDER = "LookParts"
local MISSING = Color3.fromRGB(255, 0, 255) -- a role missing from a palette shows as loud magenta, never as nothing

local function hex(text: string?): Color3
	if text == nil then
		return MISSING
	end
	local ok, color = pcall(Color3.fromHex, text)
	return if ok then color else MISSING
end

local function lookNameFor(model: Model): string?
	local attribute = Config.Character.lookAttribute
	local own = model:GetAttribute(attribute)
	if type(own) == "string" then
		return own
	end
	local player = Players:GetPlayerFromCharacter(model)
	local fromPlayer = if player ~= nil then player:GetAttribute(attribute) else nil
	if type(fromPlayer) == "string" then
		return fromPlayer
	end
	return Config.Character.defaultLook
end

-- The stock avatar's clothes, hats and face would fight the look.
local function stripAvatar(model: Model, humanoid: Humanoid)
	humanoid:RemoveAccessories()
	for _, child in model:GetChildren() do
		if
			child:IsA("Shirt")
			or child:IsA("Pants")
			or child:IsA("ShirtGraphic")
			or child:IsA("CharacterMesh")
			or child:IsA("BodyColors")
		then
			child:Destroy()
		end
	end
	local head = model:FindFirstChild("Head")
	if head ~= nil then
		for _, child in head:GetChildren() do
			if child:IsA("Decal") then
				child:Destroy()
			end
		end
	end
end

local function build(host: BasePart, def: Looks.PartDef, palette: { [string]: string }): Part
	local unit = Looks.UNIT[def.on] or 1
	local originY = Looks.ORIGIN_Y[def.on] or 0
	local piece = Instance.new("Part")
	piece.Name = def.on .. "_" .. def.role
	piece.Size = Vector3.new(def.size[1] * unit, def.size[2] * unit, def.size[3] * unit)
	piece.Color = hex(palette[def.role])
	piece.Material = if def.role == "glow" then Enum.Material.Neon else Enum.Material.SmoothPlastic
	piece.Massless = true
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	if def.shape == "Cylinder" then
		piece.Shape = Enum.PartType.Cylinder
	elseif def.shape == "Ball" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = piece
	end
	-- The drawings face +Z with +X on the left; Roblox bodies face -Z, so X and Z flip.
	local offset =
		Vector3.new(-def.pos[1] * unit, (def.pos[2] - originY) * unit, -def.pos[3] * unit)
	local rot = def.rot
	local turn = if rot ~= nil
		then CFrame.Angles(math.rad(-rot[1]), math.rad(rot[2]), math.rad(-rot[3]))
		else CFrame.identity
	local weld = Instance.new("Weld")
	weld.Part0 = host
	weld.Part1 = piece
	weld.C0 = CFrame.new(offset) * turn
	weld.Parent = piece
	return piece
end

function CharacterStyler.apply(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	local isBot = model:GetAttribute(Config.Attributes.IsBot) == true
	local def = Looks.get(lookNameFor(model))
	local palette = Looks.paletteFor(def, if isBot then BotTuning.LOOK else nil)

	stripAvatar(model, humanoid)
	for partName, role in Looks.BODY_ROLES do
		local part = model:FindFirstChild(partName)
		if part ~= nil and part:IsA("BasePart") then
			part.Color = hex(palette[role])
		end
	end
	local head = model:FindFirstChild("Head")
	if head ~= nil and head:IsA("BasePart") then
		head.Transparency = if def.hideHead == true then 1 else 0
	end
	local headScale = humanoid:FindFirstChild("HeadScale")
	if headScale ~= nil and headScale:IsA("NumberValue") then
		headScale.Value = def.headScale
	end

	local old = model:FindFirstChild(FOLDER)
	if old ~= nil then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	for _, partDef in Looks.partsFor(def, isBot) do
		local host = model:FindFirstChild(partDef.on)
		if host ~= nil and host:IsA("BasePart") then
			build(host, partDef, palette).Parent = folder
		end
	end
	folder.Parent = model
	model:SetAttribute("LookName", def.name)
end

return CharacterStyler
