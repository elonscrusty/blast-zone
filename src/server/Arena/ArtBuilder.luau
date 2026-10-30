--!strict
-- Makes the real parts for the city art plan (piece 14). Every part is paint only: anchored, no
-- collision, no queries (rays and shots pass through), no touch. Parts live in Arena.Art, one
-- folder per group. Glowing parts get the ArtNeon tag and their colors as attributes, so the
-- client can follow the time of day; parts that fade with a roof or wall get the ArtFollower tag
-- and a FadeWith attribute naming that wall.
local CollectionService = game:GetService("CollectionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local ArtKit = require("./ArtKit")
local ArtPlan = require("./ArtPlan")

local ArtBuilder = {}

local Tags = Config.Tags

local function color(hex: string): Color3
	local r, g, b = ArtKit.rgb(hex)
	return Color3.new(r, g, b)
end

local function material(name: string): Enum.Material
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	if ok and typeof(value) == "EnumItem" then
		return value :: Enum.Material
	end
	return Enum.Material.SmoothPlastic
end

local function makePart(spec: ArtKit.Spec): Part
	local p: Part
	if spec.shape == "Wedge" then
		p = Instance.new("WedgePart") :: any
	else
		p = Instance.new("Part")
		if spec.shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif spec.shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		end
	end
	p.Name = spec.name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = spec.shadow
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material(spec.material)
	p.Color = color(spec.color)
	p.Transparency = spec.transparency
	p.Reflectance = spec.reflectance
	p.Size = Vector3.new(spec.sx, spec.sy, spec.sz)
	p.CFrame = CFrame.new(spec.x, spec.y, spec.z)
		* CFrame.fromOrientation(math.rad(spec.rx), math.rad(spec.ry), math.rad(spec.rz))
	return p
end

local function addSign(p: Part, sign: ArtKit.Sign)
	local gui = Instance.new("SurfaceGui")
	gui.Face = (Enum.NormalId :: any)[sign.face]
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = color(sign.background or "#10203A")
	label.BorderSizePixel = 0
	label.Text = sign.text
	label.TextColor3 = color(sign.color)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui
end

local function decorate(p: Part, spec: ArtKit.Spec)
	local neon = spec.neon
	if neon then
		p:SetAttribute("NeonOn", neon.on)
		p:SetAttribute("NeonOff", neon.off)
		p:SetAttribute("NeonLitAt", neon.litAt)
		p:SetAttribute("NeonSoft", neon.soft)
		CollectionService:AddTag(p, Tags.ArtNeon)
	end
	local light = spec.light
	if light then
		local l = Instance.new("PointLight")
		l.Color = color(light.color)
		l.Range = light.range
		l.Brightness = light.brightness
		l.Shadows = false
		l.Parent = p
		p:SetAttribute("LightBase", light.brightness)
		CollectionService:AddTag(p, Tags.ArtNeon)
	end
	if spec.sign then
		addSign(p, spec.sign)
	end
	if spec.owner then
		p:SetAttribute("ArtOwner", spec.owner)
	end
	if spec.fadeWith then
		p:SetAttribute("FadeWith", spec.fadeWith)
		CollectionService:AddTag(p, Tags.ArtFollower)
	end
end

-- Builds the plan under `arena` as Arena.Art and returns that folder. Stops at the phone budget
-- (Config.Art.maxParts) and the light budget; tests keep the real plan under both.
function ArtBuilder.build(result: ArtPlan.Result, arena: Instance): Folder
	local root = Instance.new("Folder")
	root.Name = "Art"
	local groups: { [string]: Folder } = {}
	local made, lights = 0, 0
	for _, spec in result.parts do
		if made >= Config.Art.maxParts then
			warn(`[art] stopped at {made} parts (Config.Art.maxParts)`)
			break
		end
		local g = groups[spec.group]
		if g == nil then
			g = Instance.new("Folder")
			g.Name = spec.group
			g.Parent = root
			groups[spec.group] = g
		end
		local capped = spec
		if spec.light and lights >= Config.Art.maxLights then
			capped = table.clone(spec)
			capped.light = nil
		end
		if capped.light then
			lights += 1
		end
		local p = makePart(capped)
		decorate(p, capped)
		p.Parent = g
		made += 1
	end
	root:SetAttribute("Parts", made)
	root.Parent = arena
	return root
end

return ArtBuilder
